import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/features/update/data/update_manifest_client.dart';
import 'package:starflow/features/update/data/update_manifest_parser.dart';
import 'package:starflow/features/update/domain/app_update.dart';

final _uri = Uri.parse('https://updates.example/manifest.json');
final _hash = List.filled(64, 'a').join();

Map<String, dynamic> _manifest() => {
      'schemaVersion': 1,
      'appId': 'com.example.starflow',
      'channel': 'stable',
      'version': '1.9.250',
      'versionCode': 250,
      'publishedAt': '2026-09-26T09:12:30.123456Z',
      'releaseNotes': ['Playback fixes', 'Improved update checks'],
      'artifacts': <dynamic>[
        <String, dynamic>{
          'platform': 'android',
          'variant': 'tv',
          'fileName': 'starflow-tv-1.9.250.apk',
          'url': 'https://cdn.example/starflow-tv-1.9.250.apk',
          'size': 12345,
          'sha256': _hash,
          'minSdk': 23,
          'certificateSha256': _hash.toUpperCase(),
        },
      ],
    };

Map<String, dynamic> _artifact(Map<String, dynamic> manifest) =>
    (manifest['artifacts'] as List).single as Map<String, dynamic>;

TypeMatcher<UpdateFailure> _failure([String? code]) =>
    isA<UpdateFailure>().having(
      (failure) => failure.code,
      'code',
      code == null ? isNotEmpty : equals(code),
    );

class _Client extends http.BaseClient {
  _Client(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  final requests = <http.BaseRequest>[];
  int closeCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    return handler(request);
  }

  @override
  void close() => closeCount++;
}

http.StreamedResponse _response(List<int> body, {int status = 200}) =>
    http.StreamedResponse(Stream.value(body), status);

void main() {
  group('parseUpdateManifest', () {
    test('parses the stable TV payload and returns immutable collections', () {
      final update = parseUpdateManifest(_manifest());
      expect(update.appId, 'com.example.starflow');
      expect(update.channel, 'stable');
      expect(update.version, '1.9.250');
      expect(update.versionCode, 250);
      expect(
          update.publishedAt, DateTime.utc(2026, 9, 26, 9, 12, 30, 123, 456));
      expect(update.releaseNotes, hasLength(2));
      expect(update.artifacts.single.certificateSha256, _hash);
      expect(update.artifacts.single.minSdk, 23);
      expect(() => update.releaseNotes.add('x'), throwsUnsupportedError);
      expect(() => update.artifacts.clear(), throwsUnsupportedError);
    });

    final invalidFields = <String, List<Object?>>{
      'schemaVersion': [null, true, '1', 1.0, 2],
      'appId': [null, '', 'other.app', 'com.example.starflow '],
      'channel': [null, '', 'beta', 'Stable'],
      'version': [
        null,
        1,
        '',
        '../1.9.250',
        '1.9',
        '01.9.250',
        '1.9.250+1',
        '1.9.250\n',
        '100.9.250',
        '1.0.250',
        '1.13.250',
        '1.9.10000'
      ],
      'versionCode': [null, 0, -1, 1.0, '250', true, 2100000001],
      'publishedAt': [
        null,
        0,
        '',
        '2026-09-26',
        '2026-09-26T12:00:00',
        '2026-09-26T12:00:00+08:00',
        '2026-02-30T12:00:00Z',
        '2026-09-26T24:00:00Z',
        '2026-09-26T12:60:00Z',
        '2026-09-26T12:00:60Z'
      ],
      'releaseNotes': [
        null,
        'text',
        [1],
        [null],
        [''],
        ['\u0000'],
        List.filled(101, 'note'),
        [List.filled(4097, 'a').join()]
      ],
      'artifacts': [
        null,
        {},
        [],
        [null],
        ['artifact'],
        List.filled(17, {})
      ],
    };
    for (final field in invalidFields.entries) {
      for (var i = 0; i < field.value.length; i++) {
        test('rejects ${field.key} malformed case $i', () {
          final json = _manifest()..[field.key] = field.value[i];
          expect(() => parseUpdateManifest(json),
              throwsA(_failure('invalid_manifest')));
        });
      }
    }
    final invalidArtifactFields = <String, List<Object?>>{
      'platform': [null, 'ios', 'Android'],
      'variant': [null, 'mobile', 'config'],
      'fileName': [
        null,
        'app-release.apk',
        'starflow-tv-config-1.9.250.apk',
        'starflow-tv-1.9.249.apk',
        '../starflow-tv-1.9.250.apk'
      ],
      'url': [
        null,
        'http://cdn.example/app.apk',
        '/app.apk',
        'https://user:secret@cdn.example/app.apk',
        'https://@cdn.example/app.apk',
        'https://cdn.example/app.apk#fragment',
        'https://cdn.example/app.apk#',
        'https:///app.apk',
        'https://cdn.example:0/app.apk',
        'https://cdn.example:65536/app.apk',
        'https://cdn.example/a b.apk',
        'https://cdn.example/starflow-tv-config-1.9.250.apk',
        'https://cdn.example/starflow-tv-%63onfig-1.9.250.apk'
      ],
      'size': [null, 0, -1, 1.0, '123', true, 512 * 1024 * 1024 + 1],
      'sha256': [
        null,
        '',
        List.filled(64, 'g').join(),
        List.filled(63, 'a').join()
      ],
      'certificateSha256': [
        null,
        '',
        List.filled(65, 'a').join(),
        'sha256:$_hash'
      ],
      'minSdk': [null, 22, 24, '23', 23.0],
    };
    for (final field in invalidArtifactFields.entries) {
      for (var i = 0; i < field.value.length; i++) {
        test('rejects artifact ${field.key} malformed case $i', () {
          final json = _manifest();
          _artifact(json)[field.key] = field.value[i];
          expect(() => parseUpdateManifest(json),
              throwsA(_failure('invalid_manifest')));
        });
      }
    }
    test('accepts inclusive APK size boundary and explicit UTC offset', () {
      final json = _manifest()..['publishedAt'] = '2026-09-26T12:00:00+00:00';
      _artifact(json)['size'] = 512 * 1024 * 1024;
      expect(
          parseUpdateManifest(json).artifacts.single.size, 512 * 1024 * 1024);
    });
    test('accepts version boundaries without deriving versionCode', () {
      for (final version in ['0.1.0', '99.12.9999']) {
        final json = _manifest()
          ..['version'] = version
          ..['versionCode'] = 7;
        _artifact(json)['fileName'] = 'starflow-tv-$version.apk';
        expect(parseUpdateManifest(json).versionCode, 7);
      }
    });
    test('rejects duplicate artifact identities even with different URLs', () {
      final json = _manifest();
      (json['artifacts'] as List)
          .add({..._artifact(json), 'url': 'https://other.example/app.apk'});
      expect(() => parseUpdateManifest(json),
          throwsA(_failure('invalid_manifest')));
    });
    test('rejects unknown and missing fields', () {
      for (final json in [
        _manifest()..['extra'] = true,
        _manifest()..remove('releaseNotes'),
        _manifest()
          ..['artifacts'] = [
            {..._artifact(_manifest()), 'extra': true}
          ],
      ]) {
        expect(() => parseUpdateManifest(json),
            throwsA(_failure('invalid_manifest')));
      }
    });
    test('bounds total UTF8 payload bytes, not just character count', () {
      final json = _manifest()
        ..['releaseNotes'] =
            List.filled(100, List.filled(1000, '\u4e2d').join());
      expect(() => parseUpdateManifest(json),
          throwsA(_failure('invalid_manifest')));
    });
  });

  group('UpdateManifestClient', () {
    final manifestBody = utf8.encode(jsonEncode(_manifest()));

    test('accepts plain JSON without any manifest signing key', () async {
      final body = utf8.encode(
          ' \n${const JsonEncoder.withIndent('  ').convert(_manifest())}\n');
      final transport = _Client((_) async => _response(body));
      final client = UpdateManifestClient(client: transport);
      addTearDown(client.close);
      expect((await client.fetch(_uri)).version, '1.9.250');
      final request = transport.requests.single;
      expect(request.method, 'GET');
      expect(request.followRedirects, isFalse);
      expect(request.maxRedirects, 0);
      expect(request.headers, isEmpty);
    });

    for (final text in [
      'http://updates.example/a',
      'https://user:secret@updates.example/a',
      'https://updates.example/a#',
      '/relative'
    ]) {
      test('rejects unsafe initial URI $text', () async {
        final transport = _Client((_) async => _response(manifestBody));
        final client = UpdateManifestClient(client: transport);
        addTearDown(client.close);
        await expectLater(
            client.fetch(Uri.parse(text)), throwsA(_failure('invalid_url')));
        expect(transport.requests, isEmpty);
      });
    }

    for (final location in [
      'http://other.example/a',
      'https://user:secret@other.example/a',
      'https://@other.example/a',
      '/a#fragment',
      '/a#',
      ''
    ]) {
      test('rejects unsafe redirect $location', () async {
        var cancelled = false;
        final transport = _Client((_) async => http.StreamedResponse(
              StreamController<List<int>>(onCancel: () => cancelled = true)
                  .stream,
              302,
              headers: {'location': location},
            ));
        final client = UpdateManifestClient(client: transport);
        addTearDown(client.close);
        await expectLater(client.fetch(_uri), throwsA(_failure()));
        expect(transport.requests, hasLength(1));
        expect(cancelled, isTrue);
      });
    }

    test('permits three manual HTTPS redirects without forwarding headers',
        () async {
      var count = 0;
      final transport = _Client((_) async {
        count++;
        return count <= 3
            ? http.StreamedResponse(
                const Stream.empty(), [301, 303, 307][count - 1], headers: {
                'location':
                    count == 1 ? '/next' : 'https://other.example/hop$count'
              })
            : _response(manifestBody);
      });
      final client = UpdateManifestClient(client: transport);
      addTearDown(client.close);
      await client.fetch(_uri);
      expect(transport.requests, hasLength(4));
      expect(
          transport.requests[1].url, Uri.parse('https://updates.example/next'));
      for (final request in transport.requests) {
        expect(request.followRedirects, isFalse);
        expect(request.headers, isEmpty);
      }
    });

    test('rejects a fourth redirect', () async {
      final transport = _Client((_) async => http.StreamedResponse(
          const Stream.empty(), 308,
          headers: {'location': '/again'}));
      final client = UpdateManifestClient(client: transport);
      addTearDown(client.close);
      await expectLater(
          client.fetch(_uri), throwsA(_failure('invalid_redirect')));
      expect(transport.requests, hasLength(4));
    });

    for (final status in [204, 206, 302, 304, 401, 500]) {
      test('rejects HTTP status $status without reading its body', () async {
        var cancelled = false;
        final transport = _Client((_) async => http.StreamedResponse(
            StreamController<List<int>>(onCancel: () => cancelled = true)
                .stream,
            status));
        final client = UpdateManifestClient(client: transport);
        addTearDown(client.close);
        await expectLater(client.fetch(_uri), throwsA(_failure()));
        expect(cancelled, isTrue);
      });
    }

    test('rejects oversized declared Content-Length immediately', () async {
      var cancelled = false;
      final client = UpdateManifestClient(
          client: _Client((_) async => http.StreamedResponse(
              StreamController<List<int>>(onCancel: () => cancelled = true)
                  .stream,
              200,
              contentLength: 256 * 1024 + 1)));
      addTearDown(client.close);
      await expectLater(
          client.fetch(_uri), throwsA(_failure('manifest_too_large')));
      expect(cancelled, isTrue);
    });

    test('bounds chunked body despite a misleading Content-Length', () async {
      var cancelled = false;
      final controller =
          StreamController<List<int>>(onCancel: () => cancelled = true);
      final client = UpdateManifestClient(
          client: _Client((_) async =>
              http.StreamedResponse(controller.stream, 200, contentLength: 1)));
      addTearDown(client.close);
      final result = expectLater(
          client.fetch(_uri), throwsA(_failure('manifest_too_large')));
      controller.add(List.filled(128 * 1024, 32));
      controller.add(List.filled(128 * 1024 + 1, 32));
      await result;
      expect(cancelled, isTrue);
      await controller.close();
    });

    test('accepts a manifest of exactly 256 KiB', () async {
      final body = [
        ...manifestBody,
        ...List.filled(256 * 1024 - manifestBody.length, 32)
      ];
      final client =
          UpdateManifestClient(client: _Client((_) async => _response(body)));
      addTearDown(client.close);
      expect((await client.fetch(_uri)).versionCode, 250);
    });

    test('has one total deadline for headers and a continuously active body',
        () {
      fakeAsync((async) {
        var cancelled = false;
        var aborted = false;
        Object? failure;
        final controller =
            StreamController<List<int>>(onCancel: () => cancelled = true);
        final transport = _Client((request) async {
          unawaited((request as http.AbortableRequest)
              .abortTrigger!
              .then((_) => aborted = true));
          await Future<void>.delayed(const Duration(seconds: 10));
          return http.StreamedResponse(controller.stream, 200);
        });
        final client = UpdateManifestClient(client: transport);
        unawaited(client.fetch(_uri).then<void>((_) => fail('Expected timeout'),
            onError: (Object e) => failure = e));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 10));
        for (var i = 0; i < 9; i++) {
          controller.add([32]);
          async.elapse(const Duration(seconds: 1));
        }
        expect(failure, isNull);
        async.elapse(const Duration(seconds: 1));
        expect(failure, _failure('update_timeout'));
        expect(cancelled, isTrue);
        expect(aborted, isTrue);
        expect(transport.closeCount, 0);
        client.close();
        unawaited(controller.close());
        async.flushMicrotasks();
      });
    });

    test(
        'discards headers arriving after timeout from an uncooperative transport',
        () {
      fakeAsync((async) {
        var cancelled = false;
        Object? failure;
        final pending = Completer<http.StreamedResponse>();
        final transport = _Client((_) => pending.future);
        final client = UpdateManifestClient(client: transport);
        unawaited(client.fetch(_uri).then<void>((_) => fail('Expected timeout'),
            onError: (Object e) => failure = e));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 20));
        expect(failure, _failure('update_timeout'));
        final controller =
            StreamController<List<int>>(onCancel: () => cancelled = true);
        pending.complete(http.StreamedResponse(controller.stream, 200));
        async.flushMicrotasks();
        expect(cancelled, isTrue);
        client.close();
        unawaited(controller.close());
        async.flushMicrotasks();
      });
    });

    test('sanitizes transport errors containing secrets', () async {
      final client = UpdateManifestClient(
          client: _Client((_) async => throw http.ClientException(
              'secret-body token=secret',
              Uri.parse('https://x.example/?secret'))));
      addTearDown(client.close);
      await expectLater(
          client.fetch(_uri),
          throwsA(
            _failure('update_failed').having(
                (e) => e.toString(), 'message', isNot(contains('secret'))),
          ));
    });

    test(
        'handles synchronous transport failures without unhandled abort errors',
        () async {
      final client = UpdateManifestClient(
          client: _Client(
              (_) => throw StateError('secret synchronous transport failure')));
      addTearDown(client.close);
      await expectLater(client.fetch(_uri), throwsA(_failure('update_failed')));
      await Future<void>.delayed(Duration.zero);
    });

    test('sanitizes body stream failures and cancels the subscription',
        () async {
      var cancelled = false;
      final controller =
          StreamController<List<int>>(onCancel: () => cancelled = true);
      final client = UpdateManifestClient(
          client: _Client(
              (_) async => http.StreamedResponse(controller.stream, 200)));
      addTearDown(client.close);
      final result =
          expectLater(client.fetch(_uri), throwsA(_failure('update_failed')));
      controller.addError(StateError('secret body and token'));
      await result;
      expect(cancelled, isTrue);
      await controller.close();
    });

    test('redirects share the same deadline instead of resetting it', () {
      fakeAsync((async) {
        Object? failure;
        final transport = _Client((_) async {
          await Future<void>.delayed(const Duration(seconds: 8));
          return http.StreamedResponse(const Stream.empty(), 302,
              headers: {'location': '/next'});
        });
        final client = UpdateManifestClient(client: transport);
        unawaited(client.fetch(_uri).then<void>((_) => fail('Expected timeout'),
            onError: (Object e) => failure = e));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 20));
        expect(failure, _failure('update_timeout'));
        expect(transport.requests, hasLength(3));
        async.elapse(const Duration(seconds: 8));
        expect(transport.requests, hasLength(3));
        client.close();
      });
    });

    test('rejects malformed JSON, UTF8, schema and legacy signed envelopes',
        () async {
      final bodies = <List<int>>[
        [255],
        utf8.encode('{secret'),
        utf8.encode('[]'),
        utf8.encode('null'),
        for (final json in [
          {..._manifest(), 'extra': true},
          {..._manifest(), 'versionCode': -1},
          {..._manifest(), 'artifacts': []},
          {
            'payload': base64.encode(manifestBody),
            'signature': base64.encode(List.filled(64, 0))
          },
        ])
          utf8.encode(jsonEncode(json)),
      ];
      for (final body in bodies) {
        final client =
            UpdateManifestClient(client: _Client((_) async => _response(body)));
        await expectLater(client.fetch(_uri), throwsA(_failure()));
        client.close();
      }
    });

    test(
        'close cancels active reads, is idempotent, and leaves injected client reusable',
        () async {
      var cancelled = false;
      final controller =
          StreamController<List<int>>(onCancel: () => cancelled = true);
      var calls = 0;
      final started = Completer<void>();
      final transport = _Client((_) async {
        if (calls++ == 0) {
          started.complete();
          return http.StreamedResponse(controller.stream, 200);
        }
        return _response(manifestBody);
      });
      final client = UpdateManifestClient(client: transport);
      final result =
          expectLater(client.fetch(_uri), throwsA(_failure('cancelled')));
      await started.future;
      await Future<void>.delayed(Duration.zero);
      client.close();
      client.close();
      await result;
      expect(cancelled, isTrue);
      expect(transport.closeCount, 0);
      await expectLater(client.fetch(_uri), throwsA(_failure('closed')));
      final second = UpdateManifestClient(client: transport);
      expect((await second.fetch(_uri)).versionCode, 250);
      second.close();
      await controller.close();
    });
  });
}
