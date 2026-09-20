import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/live_tv/data/live_playlist_parser.dart';
import 'package:starflow/features/live_tv/data/live_backup.dart';
import 'package:starflow/features/live_tv/data/live_playlist_transfer_service.dart';
import 'package:starflow/features/live_tv/data/live_playlist_transfer_service_io.dart';

void main() {
  Future<LivePlaylistTransferSession> start({
    Duration uploadTimeout = const Duration(seconds: 30),
    Duration sessionTimeout = const Duration(minutes: 10),
    LivePlaylistTransferMode mode = LivePlaylistTransferMode.file,
    Uint8List? backupBytes,
  }) async {
    final session = await IoLivePlaylistTransferService(
            uploadTimeout: uploadTimeout, sessionTimeout: sessionTimeout)
        .start(mode: mode, backupBytes: backupBytes);
    addTearDown(session.close);
    return session;
  }

  HttpClient client() {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    addTearDown(() => client.close(force: true));
    return client;
  }

  test(
      'LAN page is token scoped, local only and not an application config upload',
      () async {
    final session = await start();
    final http = client();
    final root = _root(session);
    final denied = await _request(http, root.replace(query: ''), method: 'GET');
    expect(denied.$1, HttpStatus.forbidden);
    final request = await http.getUrl(root);
    final response = await request.close();
    final html = await utf8.decoder.bind(response).join();
    expect(response.statusCode, HttpStatus.ok);
    expect(response.headers.value('cache-control'), 'no-store');
    expect(response.headers.value('referrer-policy'), 'no-referrer');
    expect(response.headers.value('content-security-policy'),
        contains("connect-src 'self'"));
    expect(html, contains('Starflow 直播文件传输'));
    expect(html, contains('accept=".m3u,.m3u8,.txt"'));
    expect(html, contains('body: file'));
    expect(html,
        isNot(contains('file.text()'))); // Preserve the original file encoding.
    expect(html, isNot(contains('src="https://')));
    expect(html, isNot(contains('覆盖配置')));
    expect(
        (await _request(http, _upload(root), origin: 'https://other.test')).$1,
        HttpStatus.forbidden);
    expect((await _request(http, _upload(root), host: 'other.test')).$1,
        HttpStatus.forbidden);
    expect(
        (await _request(http, root.replace(path: '/download'), method: 'GET'))
            .$1,
        HttpStatus.notFound);
  });

  test(
      'valid GBK bytes reach the editor unchanged and session accepts only once',
      () async {
    final session = await start();
    final bytes = gbk.encode('新闻,#genre#\n频道一,https://example.test/live\n');
    final response = await _request(
        client(), _upload(_root(session), '频道表.TXT'),
        bytes: bytes);
    expect(response.$1, HttpStatus.ok);
    expect(response.$2, contains('请在电视确认保存'));
    final upload = (await session.received)! as LivePlaylistUpload;
    expect(upload.name, '频道表.TXT');
    expect(upload.bytes, bytes);
    expect(
        parseLivePlaylist(decodeLiveText(upload.bytes), 's')
            .channels
            .single
            .name,
        '频道一');
    expect((await _request(client(), _upload(_root(session)), bytes: bytes)).$1,
        HttpStatus.gone);
    await session.close();
    await session.close();
  });

  test('invalid files can be retried and never expose content or credentials',
      () async {
    final session = await start();
    final root = _root(session);
    final errors = <String>[];
    final subscription = session.errors.listen(errors.add);
    addTearDown(subscription.cancel);
    for (final name in ['../private.txt', 'test.json', 'bad\nname.m3u']) {
      expect((await _request(client(), _upload(root, name))).$1,
          HttpStatus.badRequest);
    }
    for (final content in [
      '',
      'secret=https://account.test/password',
      '#EXTM3U\n#EXT-X-TARGETDURATION:10\nsecret.ts'
    ]) {
      final response =
          await _request(client(), _upload(root), bytes: utf8.encode(content));
      expect(response.$1, HttpStatus.badRequest);
      expect(response.$2, isNot(contains('password')));
      expect(response.$2, isNot(contains('secret')));
    }
    expect(
        (await _request(client(), _upload(root),
                contentType: 'application/json'))
            .$1,
        HttpStatus.unsupportedMediaType);
    expect((await _request(client(), _upload(root), bytes: _valid)).$1,
        HttpStatus.ok);
    expect(((await session.received)! as LivePlaylistUpload).bytes, _valid);
    expect(errors, hasLength(6));
    expect(errors.join(), isNot(contains('password')));
  });

  for (final declaredLength in [true, false]) {
    test(
        '8 MiB upload limit rejects ${declaredLength ? "declared" : "streamed"} bytes',
        () async {
      final session = await start();
      final response = await _request(client(), _upload(_root(session)),
          bytes: List.filled(livePlaylistMaxBytes + 1, 65),
          declaredLength: declaredLength);
      expect(response.$1, HttpStatus.requestEntityTooLarge);
      expect(
          (await _request(client(), _upload(_root(session)), bytes: _valid)).$1,
          HttpStatus.ok);
    });
  }

  test('stalled upload has a total deadline and does not block a later upload',
      () async {
    final session =
        await start(uploadTimeout: const Duration(milliseconds: 180));
    final root = _root(session);
    final errors = session.errors.first;
    final socket = await Socket.connect(root.host, root.port);
    addTearDown(socket.destroy);
    socket.listen((_) {});
    socket.write(
        'POST ${_upload(root).path}?${_upload(root).query} HTTP/1.1\r\n'
        'Host: ${root.authority}\r\nContent-Type: application/octet-stream\r\n'
        'Content-Length: 100\r\n\r\nx');
    await socket.flush();
    expect(await errors.timeout(const Duration(seconds: 2)), '上传超时，请重试');
    expect((await _request(client(), _upload(root), bytes: _valid)).$1,
        HttpStatus.ok);
  });

  test('cancel and expiry complete without data and invalidate the server',
      () async {
    final cancelled = await start();
    final root = _root(cancelled);
    await cancelled.close();
    await cancelled.close();
    expect(await cancelled.received, isNull);
    await expectLater(client().getUrl(root), throwsA(isA<SocketException>()));
    final expired =
        await start(sessionTimeout: const Duration(milliseconds: 40));
    expect(await expired.received.timeout(const Duration(seconds: 2)), isNull);
    await expired.close();
  });

  test('cancel during upload drops data and a second uploader cannot race it',
      () async {
    final session = await start();
    final root = _root(session);
    final socket = await Socket.connect(root.host, root.port);
    addTearDown(socket.destroy);
    socket.listen((_) {});
    socket.write(
        'POST ${_upload(root).path}?${_upload(root).query} HTTP/1.1\r\n'
        'Host: ${root.authority}\r\nContent-Type: application/octet-stream\r\n'
        'Content-Length: 100\r\n\r\nx');
    await socket.flush();
    // A GET round trip lets the first request enter its body reader.
    await _request(client(), root, method: 'GET');
    expect((await _request(client(), _upload(root), bytes: _valid)).$1,
        HttpStatus.conflict);
    await session.close();
    expect(await session.received, isNull);
  });

  test('backup export is token scoped, byte exact, one shot and has no upload',
      () async {
    final bytes =
        LiveBackup({for (final store in liveBackupStores) store: {}}).encode();
    final session = await start(
        mode: LivePlaylistTransferMode.backupExport, backupBytes: bytes);
    final root = _root(session);
    final page = await _request(client(), root, method: 'GET');
    expect(page.$2, contains('下载直播备份'));
    expect(page.$2, isNot(contains('type="file"')));
    final url = root.replace(path: '/download');
    expect((await _request(client(), url.replace(query: ''), method: 'GET')).$1,
        403);
    expect(
        (await _request(client(), url,
                method: 'GET', origin: 'https://other.test'))
            .$1,
        403);
    expect(
        (await _request(client(), _upload(root, 'backup.json'), bytes: bytes))
            .$1,
        404);
    final response = await (await client().getUrl(url)).close();
    expect(response.statusCode, 200);
    expect(response.headers.value('cache-control'), 'no-store');
    expect(response.headers.value('content-disposition'),
        contains('attachment; filename="starflow-live-tv-'));
    expect(await response.fold<List<int>>([], (a, b) => a..addAll(b)), bytes);
    expect(await session.received, isA<LiveBackupDownloaded>());
    expect((await _request(client(), url, method: 'GET')).$1, 410);
    await session.close();
    await expectLater(client().getUrl(root), throwsA(isA<SocketException>()));
  });

  test('backup export rejects invalid snapshots before opening a port',
      () async {
    await expectLater(start(mode: LivePlaylistTransferMode.backupExport),
        throwsFormatException);
    await expectLater(
        start(
            mode: LivePlaylistTransferMode.backupExport,
            backupBytes: Uint8List.fromList(utf8.encode('{}'))),
        throwsFormatException);
  });

  test('backup import validates JSON and returns a draft, not a restore action',
      () async {
    final session = await start(mode: LivePlaylistTransferMode.backupImport);
    final root = _root(session);
    final page = await _request(client(), root, method: 'GET');
    expect(page.$2, contains('accept=".json"'));
    expect(page.$2, contains('32 MiB'));
    expect(
        (await _request(client(), root.replace(path: '/download'),
                method: 'GET'))
            .$1,
        404);
    for (final payload in [
      '{"schemaVersion":2}',
      '{"password":"secret"}',
      'News,https://a.test/live'
    ]) {
      final response = await _request(client(), _upload(root, 'backup.json'),
          bytes: utf8.encode(payload));
      expect(response.$1, 400);
      expect(response.$2, '直播备份格式、版本或内容无效');
    }
    final bytes =
        LiveBackup({for (final store in liveBackupStores) store: {}}).encode();
    final response =
        await _request(client(), _upload(root, 'backup.json'), bytes: bytes);
    expect(response.$1, 200);
    expect(response.$2, contains('尚未恢复'));
    expect(((await session.received) as LivePlaylistUpload).bytes, bytes);
  });

  for (final declared in [true, false]) {
    test('backup upload enforces 32 MiB (declared: $declared)', () async {
      final session = await start(mode: LivePlaylistTransferMode.backupImport);
      final response = await _request(
          client(), _upload(_root(session), 'backup.json'),
          bytes: Uint8List(liveBackupMaxBytes + 1), declaredLength: declared);
      expect(response.$1, 413);
      expect(response.$2, '直播备份超过 32 MiB');
      await session.close();
      expect(await session.received, isNull);
    });
  }
}

final _valid = utf8.encode('News,https://example.test/live\n');
Uri _root(LivePlaylistTransferSession session) =>
    Uri.parse(session.urls.first).replace(host: '127.0.0.1');
Uri _upload(Uri root, [String name = 'channels.txt']) => root.replace(
    path: '/upload', queryParameters: {...root.queryParameters, 'name': name});

Future<(int, String)> _request(
  HttpClient client,
  Uri url, {
  String method = 'POST',
  List<int> bytes = const [],
  String? origin,
  String? host,
  String contentType = 'application/octet-stream',
  bool declaredLength = true,
}) async {
  final request = await client.openUrl(method, url);
  request.headers.set('Content-Type', contentType);
  if (origin != null) request.headers.set('Origin', origin);
  if (host != null) request.headers.set('Host', host);
  if (declaredLength) request.contentLength = bytes.length;
  if (bytes.isNotEmpty) request.add(bytes);
  final response = await request.close();
  return (response.statusCode, await utf8.decoder.bind(response).join());
}
