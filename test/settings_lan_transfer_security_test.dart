import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/settings/data/settings_lan_transfer_service_io.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  var imports = 0;
  setUp(() {
    imports = 0;
  });
  Future<SettingsLanTransferSession> start({
    int maxBytes = 8 * 1024 * 1024,
    Duration sessionTimeout = const Duration(minutes: 10),
    Duration uploadTimeout = const Duration(seconds: 30),
    SettingsLanTransferLoadSettings? load,
  }) async {
    final session = await SettingsLanTransferService.start(
      loadSettings: load ?? () => AppSettings.fromJson(const {}),
      importSettings: (_) async {
        imports++;
      },
      maxUploadBytes: maxBytes,
      sessionTimeout: sessionTimeout,
      uploadTimeout: uploadTimeout,
    );
    addTearDown(session.close);
    return session;
  }

  HttpClient client() {
    final c = HttpClient();
    addTearDown(() => c.close(force: true));
    return c;
  }

  test(
      'LAN validates token/Host/Origin/confirmation and protects response caching',
      () async {
    final session = await start();
    final root = _root(session);
    expect(session.accessCode.length, 24);
    for (final entry in [
      (root.replace(query: ''), <String, String>{}),
      (root, {'Host': 'other.test'}),
      (root, {'Origin': 'https://other.test'}),
    ]) {
      final response =
          await _request(client(), entry.$1, method: 'GET', headers: entry.$2);
      expect(response.$1, 403);
    }
    final request = await client().getUrl(root);
    final response = await request.close();
    expect(response.headers.value('cache-control'), 'no-store');
    expect(response.headers.value('referrer-policy'), 'no-referrer');
    final html = await utf8.decoder.bind(response).join();
    expect(html, contains('window.confirm'));
    expect(
        (await _request(client(), root.replace(path: '/upload'),
                confirm: false, bytes: _valid))
            .$1,
        415);
    expect(imports, 0);
    expect(
        (await _request(client(), root.replace(path: '/upload'), bytes: _valid))
            .$1,
        200);
    expect(imports, 1);
  });

  for (final declared in [true, false]) {
    test(
        'LAN rejects ${declared ? "declared" : "chunked"} oversize before import',
        () async {
      final session = await start(maxBytes: 16);
      final response = await _request(
          client(), _root(session).replace(path: '/upload'),
          bytes: List.filled(17, 65), declared: declared);
      expect(response.$1, 413);
      expect(imports, 0);
    });
  }

  test('LAN malformed JSON response/events never echo submitted secrets',
      () async {
    final session = await start();
    final event = session.events.first;
    final response = await _request(
        client(), _root(session).replace(path: '/upload'),
        bytes: utf8.encode('synthetic-password-not-json'));
    expect(response.$1, 400);
    expect(response.$2, isNot(contains('synthetic-password')));
    expect((await event).message, isNot(contains('synthetic-password')));
    expect(imports, 0);
  });

  test('LAN deadline stops stalled upload and permits retry', () async {
    final session =
        await start(uploadTimeout: const Duration(milliseconds: 100));
    final event = session.events.first;
    final socket = await _stall(session);
    addTearDown(socket.destroy);
    await event.timeout(const Duration(seconds: 2));
    expect(imports, 0);
    expect(
        (await _request(client(), _root(session).replace(path: '/upload'),
                bytes: _valid))
            .$1,
        200);
    expect(imports, 1);
  });

  test('LAN closes pending upload and excludes concurrent writers', () async {
    final session = await start();
    final socket = await _stall(session);
    addTearDown(socket.destroy);
    await _request(client(), _root(session), method: 'GET');
    expect(
        (await _request(client(), _root(session).replace(path: '/upload'),
                bytes: _valid))
            .$1,
        409);
    await session.close();
    await session.close();
    expect(imports, 0);
    await expectLater(
        client().getUrl(_root(session)), throwsA(isA<SocketException>()));
  });

  test('LAN expiry closes pending upload without import', () async {
    final session =
        await start(sessionTimeout: const Duration(milliseconds: 100));
    final socket = await _stall(session);
    addTearDown(socket.destroy);
    await session.events.drain<void>().timeout(const Duration(seconds: 2));
    expect(imports, 0);
    await expectLater(
        client().getUrl(_root(session)), throwsA(isA<SocketException>()));
  });

  test('LAN closed session never returns a late settings download', () async {
    final gate = Completer<AppSettings>();
    final started = Completer<void>();
    final session = await start(load: () {
      started.complete();
      return gate.future;
    });
    final response = _request(
        client(), _root(session).replace(path: '/download'),
        method: 'GET');
    final assertion = expectLater(response, throwsA(isA<HttpException>()));
    await started.future;
    await session.close();
    gate.complete(AppSettings.fromJson(const {}));
    await assertion;
    expect(imports, 0);
  });
}

final _valid = utf8.encode(jsonEncode(AppSettings.fromJson(const {}).toJson()));
Uri _root(SettingsLanTransferSession session) =>
    Uri.parse(session.urls.first).replace(host: '127.0.0.1');
Future<Socket> _stall(SettingsLanTransferSession session) async {
  final root = _root(session);
  final socket = await Socket.connect(root.host, root.port);
  socket.listen((_) {}, onError: (Object _) {});
  socket.write('POST /upload?${root.query} HTTP/1.1\r\n'
      'Host: ${root.authority}\r\nContent-Type: application/json\r\n'
      'X-Starflow-Confirm-Replace: true\r\nContent-Length: 100\r\n\r\nx');
  await socket.flush();
  return socket;
}

Future<(int, String)> _request(
  HttpClient client,
  Uri uri, {
  String method = 'POST',
  Map<String, String> headers = const {},
  List<int> bytes = const [],
  bool declared = true,
  bool confirm = true,
}) async {
  final request = await client.openUrl(method, uri);
  request.headers.contentType = ContentType.json;
  if (confirm) request.headers.set('X-Starflow-Confirm-Replace', 'true');
  headers.forEach(request.headers.set);
  if (method != 'GET') {
    request.contentLength = declared ? bytes.length : -1;
    request.add(bytes);
  }
  final response = await request.close();
  return (response.statusCode, await utf8.decoder.bind(response).join());
}
