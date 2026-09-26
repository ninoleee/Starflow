import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:starflow/features/update/data/update_package_downloader.dart';
import 'package:starflow/features/update/data/update_package_downloader_stub.dart'
    as stub;
import 'package:starflow/features/update/domain/app_update.dart';

const _bytes = [80, 75, 3, 4, 1, 2, 3, 4];

UpdateArtifact _artifact({
  String url = 'https://downloads.example/starflow-tv-1.9.1.apk',
  String name = 'starflow-tv-1.9.1.apk',
  int size = 8,
  String? hash,
}) =>
    UpdateArtifact(
      platform: 'android-tv',
      variant: 'normal',
      url: Uri.parse(url),
      fileName: name,
      size: size,
      sha256: hash ?? sha256.convert(_bytes).toString(),
      minSdk: 23,
      certificateSha256: 'unused-by-downloader',
    );

Matcher _failure(String code) =>
    isA<UpdateFailure>().having((failure) => failure.code, 'code', code);

http.StreamedResponse _ok({
  List<List<int>> chunks = const [
    [80, 75, 3],
    [4, 1, 2, 3, 4],
  ],
  int? contentLength,
  Map<String, String> headers = const {},
}) =>
    http.StreamedResponse(Stream.fromIterable(chunks), 200,
        contentLength: contentLength, headers: headers);

class _Client extends http.BaseClient {
  _Client(this.handler);
  final FutureOr<http.StreamedResponse> Function(http.BaseRequest) handler;
  final requests = <http.BaseRequest>[];
  final sent = Completer<void>();
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    if (!sent.isCompleted) sent.complete();
    return handler(request);
  }

  @override
  void close() => closed = true;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  final downloaders = <UpdatePackageDownloader>[];

  setUp(() async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    root = await Directory.systemTemp.createTemp('update-downloader-test-');
  });

  tearDown(() async {
    for (final downloader in downloaders) {
      await downloader.dispose();
    }
    downloaders.clear();
    await root.delete(recursive: true);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  UpdatePackageDownloader create(_Client client) {
    final downloader = UpdatePackageDownloader(client: client, directory: root);
    downloaders.add(downloader);
    return downloader;
  }

  Future<String> download(UpdatePackageDownloader downloader,
          {UpdateArtifact? artifact,
          void Function(int)? progress,
          void Function()? verifying}) =>
      downloader.download(artifact ?? _artifact(),
          onProgress: progress ?? (_) {}, onVerifying: verifying ?? () {});

  Future<void> expectClean() async {
    final updates = Directory(p.join(root.path, 'updates'));
    if (await updates.exists()) expect(await updates.list().toList(), isEmpty);
  }

  test('streams bytes, verifies whole file, publishes only the safe basename',
      () async {
    final client = _Client((_) => _ok(contentLength: _bytes.length));
    final events = <Object>[];
    final path =
        await download(create(client), progress: events.add, verifying: () {
      events.add('verifying');
      expect(
          File(p.join(root.path, 'updates', _artifact().fileName)).existsSync(),
          isFalse);
      final partials = Directory(p.join(root.path, 'updates'))
          .listSync(recursive: true)
          .whereType<File>();
      expect(partials.single.readAsBytesSync(), _bytes);
    });
    expect(path, p.join(root.path, 'updates', _artifact().fileName));
    expect(await File(path).readAsBytes(), _bytes);
    expect(events, [0, 8, 'verifying']);
    expect(client.closed, isTrue);
    expect(await Directory(p.join(root.path, 'updates')).list().length, 1);
    final request = client.requests.single;
    expect(request.followRedirects, isFalse);
    expect(request.headers, {'Accept-Encoding': 'identity'});
    expect(request, isA<http.AbortableRequest>());
  });

  test('corruption deletes partial files', () async {
    await expectLater(
        download(create(_Client((_) => _ok())),
            artifact: _artifact(hash: '0' * 64)),
        throwsA(_failure('checksum')));
    await expectClean();
  });

  test('verification reads the stored file, not only the received stream',
      () async {
    await expectLater(
        download(create(_Client((_) => _ok())), verifying: () {
          final partial = Directory(p.join(root.path, 'updates'))
              .listSync(recursive: true)
              .whereType<File>()
              .single;
          partial.writeAsBytesSync(List.filled(_bytes.length, 0));
        }),
        throwsA(_failure('checksum')));
    await expectClean();
  });

  test('rejects advertised length mismatch before writing', () async {
    await expectLater(download(create(_Client((_) => _ok(contentLength: 7)))),
        throwsA(_failure('length')));
    await expectClean();
  });

  test('rejects truncated stream without content length', () async {
    await expectLater(
        download(create(_Client((_) => _ok(chunks: [
              [80, 75]
            ])))),
        throwsA(_failure('length')));
    await expectClean();
  });

  test('rejects overflow before reporting or writing excess bytes', () async {
    final progress = <int>[];
    await expectLater(
        download(
            create(_Client((_) => _ok(chunks: [
                  _bytes,
                  [9]
                ]))),
            progress: progress.add),
        throwsA(_failure('overflow')));
    expect(progress, [0]);
    await expectClean();
  });

  for (final size in [0, -1, UpdatePackageDownloader.maxPackageBytes + 1]) {
    test('rejects invalid manifest size $size without network or files',
        () async {
      final client = _Client((_) => _ok());
      await expectLater(
          download(create(client), artifact: _artifact(size: size)),
          throwsA(_failure('artifact')));
      expect(client.requests, isEmpty);
      await expectClean();
    });
  }

  for (final name in [
    '../starflow-tv-1.9.1.apk',
    '/starflow-tv-1.9.1.apk',
    r'folder\starflow-tv-1.9.1.apk',
    'starflow-tv-config-1.9.1.apk',
    'starflow-tv-1.9.1.apk\n',
    'starflow-tv-1.9.1.apk.exe',
  ]) {
    test('rejects unsafe or non-normal filename ${name.trim()}', () async {
      await expectLater(
          download(create(_Client((_) => _ok())),
              artifact: _artifact(name: name)),
          throwsA(_failure('artifact')));
      await expectClean();
    });
  }

  for (final url in [
    'http://downloads.example/file.apk',
    'https://user:secret@downloads.example/file.apk',
    'file:///file.apk',
    'https://downloads.example/file.apk#fragment',
    'https://downloads.example:0/file.apk',
    'https://downloads.example:65536/file.apk',
    'https://downloads.example/file%0a.apk',
  ]) {
    test('rejects insecure initial URL $url', () async {
      final client = _Client((_) => _ok());
      await expectLater(download(create(client), artifact: _artifact(url: url)),
          throwsA(_failure('url')));
      expect(client.requests, isEmpty);
      await expectClean();
    });
  }

  test('allows three HTTPS redirects with fresh credential-free requests',
      () async {
    var calls = 0;
    var cancelledBodies = 0;
    final bodies = <StreamController<List<int>>>[];
    addTearDown(() async {
      for (final body in bodies) {
        await body.close();
      }
    });
    final client = _Client((_) {
      if (calls++ == 3) return _ok();
      final body =
          StreamController<List<int>>(onCancel: () => cancelledBodies++);
      bodies.add(body);
      return http.StreamedResponse(body.stream, 302, headers: {
        'location': calls == 1 ? '/next.apk' : 'https://cdn.example/$calls.apk',
        'set-cookie': 'private=secret',
      });
    });
    await download(create(client));
    expect(client.requests, hasLength(4));
    expect(cancelledBodies, 3);
    expect(client.requests[1].url.toString(),
        'https://downloads.example/next.apk');
    for (final request in client.requests) {
      expect(request.headers, {'Accept-Encoding': 'identity'});
      expect(request.followRedirects, isFalse);
    }
  });

  test('rejects fourth redirect', () async {
    final client = _Client((_) => http.StreamedResponse(Stream.empty(), 307,
        headers: {'location': '/loop.apk'}));
    await expectLater(download(create(client)), throwsA(_failure('redirect')));
    expect(client.requests, hasLength(4));
    await expectClean();
  });

  for (final location in [
    'http://cdn.example/file.apk',
    'https://cdn.example/file.apk#fragment',
    'https://cdn.example:65536/file.apk',
  ]) {
    test('rejects unsafe redirect $location', () async {
      final client = _Client((_) => http.StreamedResponse(Stream.empty(), 308,
          headers: {'location': location}));
      await expectLater(download(create(client)), throwsA(_failure('url')));
      expect(client.requests, hasLength(1));
      await expectClean();
    });
  }

  test('rejects redirect without location', () async {
    await expectLater(
        download(
            create(_Client((_) => http.StreamedResponse(Stream.empty(), 301)))),
        throwsA(_failure('redirect')));
    await expectClean();
  });

  test('rejects raw and escaped control characters in redirects', () async {
    for (final location in [
      '/file\n.apk',
      '/file%0d.apk',
      '/file%7f.apk',
      'https://user:password@cdn.example/file.apk',
      '//user@cdn.example/file.apk',
      'https://@cdn.example/file.apk',
    ]) {
      await expectLater(
          download(create(_Client((_) => http.StreamedResponse(
              Stream.empty(), 302,
              headers: {'location': location})))),
          throwsA(_failure('redirect')));
      await expectClean();
    }
  });

  test('rejects partial HTTP responses and compressed responses', () async {
    await expectLater(
        download(
            create(_Client((_) => http.StreamedResponse(Stream.empty(), 206)))),
        throwsA(_failure('http')));
    await expectLater(
        download(
            create(_Client((_) => _ok(headers: {'content-encoding': 'gzip'})))),
        throwsA(_failure('encoding')));
    await expectClean();
  });

  test('cancel closes stalled request and keeps ownership through cleanup',
      () async {
    final response = Completer<http.StreamedResponse>();
    final client = _Client((_) => response.future);
    final downloader = create(client);
    final result = download(downloader);
    final rejected = expectLater(result, throwsA(_failure('cancelled')));
    await client.sent.future;
    downloader.cancel();
    expect(client.closed, isTrue);
    await expectLater(download(downloader), throwsA(_failure('busy')));
    await rejected.timeout(const Duration(seconds: 2));
    await expectClean();
    response.complete(_ok());
  });

  test('stream cancellation waits for cleanup; retry starts from zero',
      () async {
    final cleanup = Completer<void>();
    final cancelled = Completer<void>();
    final body = StreamController<List<int>>(onCancel: () {
      cancelled.complete();
      return cleanup.future;
    });
    final clients = <_Client>[];
    final firstChunk = Completer<void>();
    final downloader = UpdatePackageDownloader(
        directory: root,
        clientFactory: () {
          final client = _Client((_) => clients.length == 1
              ? http.StreamedResponse(body.stream.map((chunk) {
                  firstChunk.complete();
                  return chunk;
                }), 200)
              : _ok());
          clients.add(client);
          return client;
        });
    downloaders.add(downloader);
    final first = download(downloader);
    final rejected = expectLater(first, throwsA(_failure('cancelled')));
    body.add([80, 75]);
    await firstChunk.future;
    downloader.cancel();
    await cancelled.future;
    expect(clients.single.closed, isTrue);
    await expectLater(download(downloader), throwsA(_failure('busy')));
    cleanup.complete();
    await rejected;
    await body.close();
    await expectClean();
    final progress = <int>[];
    await download(downloader, progress: progress.add);
    expect(progress, [0, 8]);
    expect(clients, hasLength(2));
    expect(clients.last.requests.single.headers.containsKey('range'), isFalse);
  });

  test('cancel during verification never publishes APK', () async {
    final downloader = create(_Client((_) => _ok()));
    await expectLater(download(downloader, verifying: downloader.cancel),
        throwsA(_failure('cancelled')));
    await expectClean();
  });

  test('background cancels and prevents another download until foreground',
      () async {
    final body = StreamController<List<int>>();
    final client = _Client((_) => http.StreamedResponse(body.stream, 200));
    final downloader = create(client);
    final first = download(downloader);
    final rejected = expectLater(first, throwsA(_failure('cancelled')));
    await client.sent.future;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await rejected;
    expect(client.closed, isTrue);
    await expectLater(download(downloader), throwsA(_failure('background')));
    await body.close();
    await expectClean();
  });

  test('dispose cancels, waits for cleanup, is idempotent and blocks reuse',
      () async {
    final client = _Client((_) => Completer<http.StreamedResponse>().future);
    final downloader = create(client);
    final first = download(downloader);
    final rejected = expectLater(first, throwsA(_failure('cancelled')));
    await client.sent.future;
    final disposal = downloader.dispose();
    expect(downloader.dispose(), same(disposal));
    await disposal;
    await rejected;
    expect(client.closed, isTrue);
    await expectClean();
    await expectLater(download(downloader), throwsA(_failure('disposed')));
  });

  test('network failure preserves existing verified APK and unrelated files',
      () async {
    final updates = await Directory(p.join(root.path, 'updates')).create();
    final existing = File(p.join(updates.path, _artifact().fileName));
    await existing.writeAsBytes([1, 2, 3]);
    final unrelated = File(p.join(root.path, 'playback-cache'));
    await unrelated.writeAsString('untouched');
    final client = _Client((_) => http.StreamedResponse(
        Stream.error(const SocketException('network failed')), 200));
    await expectLater(download(create(client)), throwsA(_failure('download')));
    expect(await existing.readAsBytes(), [1, 2, 3]);
    expect(await unrelated.readAsString(), 'untouched');
    expect(await updates.list().length, 1);
    expect(client.closed, isTrue);
  });

  test('rejects symlink updates directory without touching its target',
      () async {
    final elsewhere = await Directory(p.join(root.path, 'elsewhere')).create();
    await Link(p.join(root.path, 'updates')).create(elsewhere.path);
    await expectLater(
        download(create(_Client((_) => _ok()))), throwsA(_failure('storage')));
    expect(await elsewhere.list().toList(), isEmpty);
  });

  test('cleans only stale downloader files, leaving native snapshots alone',
      () async {
    final updates = await Directory(p.join(root.path, 'updates')).create();
    final old = DateTime.now().subtract(const Duration(days: 2));
    final stale = File(p.join(updates.path, 'starflow-tv-1.8.0.apk'));
    await stale.writeAsBytes(_bytes);
    await stale.setLastModified(old);
    final staging =
        await Directory(p.join(updates.path, 'download-old123')).create();
    final partial = File(p.join(staging.path, 'package.part'));
    await partial.writeAsBytes([1]);
    await partial.setLastModified(old);
    final verified = await Directory(p.join(updates.path, 'verified')).create();
    final snapshot = File(p.join(verified.path, 'starflow-tv-1.8.0.apk'));
    await snapshot.writeAsBytes(_bytes);
    await snapshot.setLastModified(old);
    final recent = File(p.join(updates.path, 'starflow-tv-1.9.0.apk'));
    await recent.writeAsBytes(_bytes);
    await download(create(_Client((_) => _ok())));
    expect(await stale.exists(), isFalse);
    expect(await staging.exists(), isFalse);
    expect(await snapshot.readAsBytes(), _bytes);
    expect(await recent.exists(), isTrue);
  });

  test('stale cleanup removes at most 32 entries per download', () async {
    final updates = await Directory(p.join(root.path, 'updates')).create();
    final old = DateTime.now().subtract(const Duration(days: 2));
    for (var i = 0; i < 40; i++) {
      final file = File(p.join(updates.path, 'starflow-tv-1.8.$i.apk'));
      await file.writeAsBytes([1]);
      await file.setLastModified(old);
    }
    await download(create(_Client((_) => _ok())));
    expect(await updates.list().length, 9);
  });

  test('stalled headers time out, close owned client and clean staging',
      () async {
    final client = _Client((_) => Completer<http.StreamedResponse>().future);
    final downloader = create(client);
    await expectLater(download(downloader), throwsA(_failure('timeout')));
    expect(client.closed, isTrue);
    await expectClean();
  }, timeout: const Timeout(Duration(seconds: 40)));

  test(
      'progress throttles fast chunks and emits final length before verification',
      () async {
    final bytes = List<int>.filled(200, 1);
    final progress = <int>[];
    final client = _Client((_) => _ok(chunks: bytes.map((b) => [b]).toList()));
    await download(create(client),
        artifact: _artifact(
            size: bytes.length, hash: sha256.convert(bytes).toString()),
        progress: progress.add,
        verifying: () => expect(progress.last, bytes.length));
    expect(progress.first, 0);
    expect(progress.last, bytes.length);
    expect(progress.length, lessThan(20));
  });

  test('unsupported platform fails explicitly', () async {
    final downloader = stub.UpdatePackageDownloader();
    await expectLater(
        downloader.download(_artifact(),
            onProgress: (_) {}, onVerifying: () {}),
        throwsA(_failure('unsupported')));
    downloader.cancel();
    await downloader.dispose();
  });
}
