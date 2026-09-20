import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/network/http_origin_policy.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_stream_relay_contract.dart';
import 'package:starflow/features/playback/application/playback_stream_relay_service_io.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart'
    hide isLoopbackPlaybackRelayUrl;
import 'package:starflow/features/playback/domain/playback_models.dart';

final _mp4 = [0, 0, 0, 16, ...ascii.encode('ftypisom'), 0, 0, 0, 0];
const _secret = 'Basic c3ludGhldGljOnNlY3JldA==';

PlaybackTarget _target(String url,
        {Map<String, String> headers = const {'Authorization': _secret}}) =>
    PlaybackTarget(
        title: 'Synthetic',
        sourceId: 'nas',
        sourceName: 'NAS',
        sourceKind: MediaSourceKind.nas,
        streamUrl: url,
        actualAddress: url,
        headers: headers);

Future<HttpServer> _server(FutureOr<void> Function(HttpRequest) handler) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    try {
      request.response.headers.contentType = ContentType.binary;
      await handler(request);
    } catch (_) {/* Client cancellation is expected. */}
  });
  addTearDown(() => server.close(force: true));
  return server;
}

String _url(HttpServer server, [String path = '/video']) =>
    'http://127.0.0.1:${server.port}$path';

Future<void> _media(HttpRequest request) async {
  request.response.headers.contentType = ContentType('video', 'mp4');
  request.response.contentLength = _mp4.length;
  if (request.method != 'HEAD') request.response.add(_mp4);
  await request.response.close();
}

PlaybackStreamRelayService _relay() {
  final relay = createPlaybackStreamRelayService();
  addTearDown(relay.close);
  return relay;
}

Future<(int, List<int>, HttpHeaders)> _get(String url,
    {String method = 'GET', Map<String, String> headers = const {}}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, Uri.parse(url));
    headers.forEach(request.headers.set);
    final response = await request.close();
    final bytes =
        await response.fold<List<int>>([], (all, chunk) => all..addAll(chunk));
    return (response.statusCode, bytes, response.headers);
  } finally {
    client.close(force: true);
  }
}

void main() {
  test('ordinary NAS HLS headers bypass relay; credential aliases require it',
      () async {
    final relay = _relay();
    final ordinary = _target('https://a.test/live.m3u8',
        headers: {'User-Agent': 'UA', 'Referer': 'https://a.test'});
    expect(identical(await relay.prepareTarget(ordinary), ordinary), isTrue);
    for (final kind in MediaSourceKind.values) {
      final target = ordinary.copyWith(
          sourceKind: kind, headers: const {'Authorization': _secret});
      expect(requiresPlaybackStreamRelay(target),
          kind == MediaSourceKind.nas || kind == MediaSourceKind.quark);
      final publicTarget = ordinary.copyWith(sourceKind: kind);
      expect(identical(await relay.prepareTarget(publicTarget), publicTarget),
          isTrue);
    }
    for (final name in [
      'authorization',
      'AUTHORIZATION',
      'Cookie',
      'X-Emby-Token',
      'AuthX',
      'X-Api-Key'
    ]) {
      expect(
          requiresPlaybackStreamRelay(
              _target('https://a.test/live', headers: {name: 'synthetic'})),
          isTrue);
    }
    expect(
        isSameHttpOrigin(
            Uri.parse('https://a.test'), Uri.parse('https://a.test:443')),
        isTrue);
    expect(
        isSameHttpOrigin(
            Uri.parse('http://a.test'), Uri.parse('https://a.test')),
        isFalse);
    expect(
        isSameHttpOrigin(
            Uri.parse('https://a.test'), Uri.parse('https://a.test:444')),
        isFalse);
  });

  test(
      'same-host different-port redirect strips all origin auth and cookies on every range',
      () async {
    final observed = <Map<String, String?>>[];
    final cdn = await _server((request) async {
      observed.add({
        for (final name in [
          'authorization',
          'cookie',
          'x-custom-secret',
          'referer',
          'origin',
          'range',
          'user-agent'
        ])
          name: request.headers.value(name)
      });
      request.response.cookies.add(Cookie('cdn', 'own')..path = '/');
      await _media(request);
    });
    final origin = await _server((request) async {
      expect(request.headers.value('authorization'), _secret);
      expect(request.headers.value('cookie'), contains('nas=own'));
      request.response.statusCode = 302;
      request.response.headers.set('location', _url(cdn));
      request.response.cookies
          .add(Cookie('nas-response', 'secret')..path = '/');
      await request.response.close();
    });
    final original = _target(_url(origin), headers: {
      'Authorization': _secret,
      'Cookie': 'nas=own',
      'X-Custom-Secret': 'private',
      'Referer': '${_url(origin)}/private',
      'Origin': _url(origin),
      'User-Agent': 'TestUA',
    });
    final prepared = await _relay().prepareTarget(original);
    expect(prepared.headers, isEmpty);
    expect(prepared.actualAddress, original.actualAddress);
    expect(buildPlaybackItemKey(prepared), buildPlaybackItemKey(original));
    expect(original.headers['Authorization'], _secret);
    expect(original.streamUrl, _url(origin));
    final result =
        await _get(prepared.streamUrl, headers: {'Range': 'bytes=0-15'});
    expect(result.$1, 200);
    expect(result.$2, _mp4);
    expect(result.$3.value('set-cookie'), isNull);
    expect(result.$3.value('location'), isNull);
    expect(observed, hasLength(2));
    for (final request in observed) {
      for (final name in [
        'authorization',
        'x-custom-secret',
        'referer',
        'origin'
      ]) {
        expect(request[name], isNull, reason: name);
      }
      expect(request['user-agent'], 'TestUA');
      expect(request['cookie'] ?? '', isNot(contains('nas')));
    }
    expect(observed.first['cookie'], isNull);
    expect(observed.last['cookie'], 'cdn=own');
    expect(observed.last['range'], 'bytes=0-15');
  });

  test('A-B-A redirect only restores A credentials and never imports B cookies',
      () async {
    late HttpServer a;
    final b = await _server((request) async {
      expect(request.headers.value('authorization'), isNull);
      expect(request.headers.value('cookie'), isNull);
      request.response.cookies.add(Cookie('evil', 'value')
        ..domain = '127.0.0.1'
        ..path = '/');
      request.response.statusCode = 307;
      request.response.headers.set('location', _url(a, '/final'));
      await request.response.close();
    });
    a = await _server((request) async {
      expect(request.headers.value('authorization'), _secret);
      expect(request.headers.value('cookie'), isNot(contains('evil')));
      if (request.uri.path == '/video') {
        request.response.statusCode = 301;
        request.response.cookies.add(Cookie('a', 'own')..path = '/');
        request.response.headers.set('location', _url(b));
        await request.response.close();
      } else {
        expect(request.headers.value('cookie'), contains('a=own'));
        await _media(request);
      }
    });
    final prepared = await _relay().prepareTarget(_target(_url(a)));
    expect((await _get(prepared.streamUrl)).$2, _mp4);
  });

  test(
      'redirects bounded, invalid locations rejected, errors contain no URL or credential',
      () async {
    var count = 0;
    var location = '/loop';
    final origin = await _server((request) async {
      count++;
      request.response.statusCode = 302;
      request.response.headers.set('location', location);
      await request.response.close();
    });
    final relay = _relay();
    await expectLater(relay.prepareTarget(_target(_url(origin))),
        throwsA(isA<PlaybackRelayException>()));
    expect(count, 6);
    for (final invalid in [
      'file:///private/secret',
      'http://user:secret@127.0.0.1/video'
    ]) {
      location = invalid;
      await expectLater(
          relay.prepareTarget(_target(_url(origin))),
          throwsA(isA<PlaybackRelayException>().having(
              (e) => e.toString(),
              'redacted',
              allOf(isNot(contains('secret')), isNot(contains('127.0.0.1'))))));
    }
  });

  test('unsupported manifests, MIME mismatch and runtime switch fail closed',
      () async {
    var type = 'application/octet-stream';
    List<int> body = utf8.encode('#EXTM3U\nsegment.ts\n');
    var hits = 0;
    final origin = await _server((request) async {
      hits++;
      request.response.headers.set('content-type', type);
      request.response.add(body);
      await request.response.close();
    });
    final relay = _relay();
    for (final path in ['/live.m3u8', '/live.mpd', '/disc.iso']) {
      await expectLater(relay.prepareTarget(_target(_url(origin, path))),
          throwsA(same(unsupportedRelayMedia)));
    }
    expect(hits, 1);
    await expectLater(relay.prepareTarget(_target(_url(origin))),
        throwsA(same(unsupportedRelayMedia)));
    type = 'application/vnd.apple.mpegurl';
    body = _mp4;
    await expectLater(relay.prepareTarget(_target(_url(origin))),
        throwsA(same(unsupportedRelayMedia)));
    type = 'application/octet-stream';
    final prepared = await relay.prepareTarget(_target(_url(origin)));
    body = utf8.encode('#EXTM3U\nsegment.ts\n');
    final result = await _get(prepared.streamUrl);
    expect(result.$1, 502);
    expect(utf8.decode(result.$2), isNot(contains('segment.ts')));
    expect(hits, 7);
  });

  test('random exact capabilities, HEAD, clearing, and independent sessions',
      () async {
    final origin = await _server(_media);
    final relay = _relay();
    final first = await relay.prepareTarget(_target(_url(origin)));
    final second = await relay.prepareTarget(_target(_url(origin)));
    final a = Uri.parse(first.streamUrl), b = Uri.parse(second.streamUrl);
    expect(a.pathSegments[1], matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    expect(a.pathSegments[1], isNot(b.pathSegments[1]));
    expect((await _get(first.streamUrl, method: 'HEAD')).$1, 200);
    expect((await _get('${first.streamUrl}/segment.ts')).$1, 404);
    expect((await _get('${first.streamUrl}?url=https://other.test')).$1, 404);
    expect((await _get(second.streamUrl)).$2, _mp4);
    await relay.clear();
    expect((await _get(first.streamUrl)).$1, 404);
    expect((await _get(second.streamUrl)).$1, 404);
  });

  test(
      'closing pending preparation aborts request and cannot publish late session',
      () async {
    final started = Completer<void>();
    final origin = await _server((request) {
      started.complete();
    });
    final relay = _relay();
    final pending = relay.prepareTarget(_target(_url(origin)));
    final failed = expectLater(pending, throwsA(isA<PlaybackRelayException>()));
    await started.future;
    await relay.close();
    await failed.timeout(const Duration(seconds: 2));
  });

  test('slow prefix and redirect chain share a total deadline', () async {
    for (final redirects in [false, true]) {
      var count = 0;
      final origin = await _server((request) async {
        count++;
        if (redirects) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          request.response.statusCode = 302;
          request.response.headers.set('location', '/hop$count');
          await request.response.close();
        } else {
          request.response.add(_mp4);
          await request.response.flush();
          for (var i = 0; i < 20; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            request.response.add([0]);
            await request.response.flush();
          }
          await request.response.close();
        }
      });
      final relay = createPlaybackStreamRelayService(
          requestTimeout: const Duration(milliseconds: 250));
      addTearDown(relay.close);
      final clock = Stopwatch()..start();
      await expectLater(relay.prepareTarget(_target(_url(origin))),
          throwsA(isA<PlaybackRelayException>()));
      expect(clock.elapsed, lessThan(const Duration(seconds: 1)));
      if (redirects) expect(count, lessThan(6));
    }
  });

  test('ignored Range with unending large body is sampled not drained',
      () async {
    final disconnected = Completer<void>();
    final origin = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(origin.close);
    origin.listen((socket) {
      addTearDown(socket.destroy);
      var sent = false;
      socket.listen((_) {
        if (sent) return;
        sent = true;
        socket.add(ascii.encode('HTTP/1.1 200 OK\r\n'
            'Content-Type: video/mp4\r\nContent-Length: 100000000\r\n\r\n'));
        socket.add([..._mp4, ...List.filled(64 * 1024, 0)]);
      }, onDone: () {
        if (!disconnected.isCompleted) disconnected.complete();
      }, onError: (Object _) {
        if (!disconnected.isCompleted) disconnected.complete();
      });
    });
    final relay = _relay();
    final prepared = await relay
        .prepareTarget(_target('http://127.0.0.1:${origin.port}/video'))
        .timeout(const Duration(seconds: 2));
    expect(prepared.headers, isEmpty);
    await disconnected.future.timeout(const Duration(seconds: 2));
  });

  test(
      'clear aborts late prepare; preparing replacement leaves playing session valid',
      () async {
    final started = Completer<void>();
    final origin = await _server((request) async {
      if (request.uri.path == '/pending') {
        started.complete();
        return;
      }
      await _media(request);
    });
    final relay = _relay();
    final old = await relay.prepareTarget(_target(_url(origin)));
    final pending = relay.prepareTarget(_target(_url(origin, '/pending')));
    final failed = expectLater(pending, throwsA(isA<PlaybackRelayException>()));
    await started.future;
    expect((await _get(old.streamUrl)).$2, _mp4);
    await relay.clear();
    await failed.timeout(const Duration(seconds: 2));
    expect((await _get(old.streamUrl)).$1, 404);
    final fresh = await relay.prepareTarget(_target(_url(origin)));
    expect((await _get(fresh.streamUrl)).$2, _mp4);
  });

  test(
      'nonzero range may start with hash or angle byte; complete manifests still rejected',
      () async {
    List<int> data = [0x23, 1, 2, 3];
    final origin = await _server((request) async {
      if (request.headers.value('range') == 'bytes=100-103') {
        request.response.statusCode = 206;
        request.response.headers.set('content-range', 'bytes 100-103/1000');
        request.response.add(data);
        await request.response.close();
      } else {
        await _media(request);
      }
    });
    final prepared = await _relay().prepareTarget(_target(_url(origin)));
    for (final byte in [0x23, 0x3c]) {
      data = [byte, 1, 2, 3];
      final response =
          await _get(prepared.streamUrl, headers: {'Range': 'bytes=100-103'});
      expect(response.$1, 206);
      expect(response.$2, data);
    }
    data = ascii.encode('#EXTM3U\nsegment.ts');
    expect(
        (await _get(prepared.streamUrl, headers: {'Range': 'bytes=100-103'}))
            .$1,
        502);
  });

  test('ASF and 192-byte M2TS signatures are accepted', () async {
    List<int> data = [
      0x30,
      0x26,
      0xb2,
      0x75,
      0x8e,
      0x66,
      0xcf,
      0x11,
      0xa6,
      0xd9,
      0,
      0xaa,
      0,
      0x62,
      0xce,
      0x6c
    ];
    final origin = await _server((request) async {
      request.response.add(data);
      await request.response.close();
    });
    final relay = _relay();
    final asf = await relay.prepareTarget(_target(_url(origin)));
    expect((await _get(asf.streamUrl)).$2, data);
    data = List.filled(512, 0)
      ..[4] = 0x47
      ..[196] = 0x47
      ..[388] = 0x47;
    final m2ts = await relay.prepareTarget(_target(_url(origin)));
    expect((await _get(m2ts.streamUrl)).$2, data);
  });

  test('short zero ranges match the validated prefix, not a changed manifest',
      () async {
    var manifest = false;
    final origin = await _server((request) async {
      final range = request.headers.value('range') ?? '';
      if (range == 'bytes=0-511') {
        await _media(request);
        return;
      }
      final end = int.parse(range.substring('bytes=0-'.length));
      final data = manifest ? ascii.encode('#EXTM3U\nsegment.ts') : _mp4;
      request.response.statusCode = 206;
      request.response.headers
          .set('content-range', 'bytes 0-$end/${data.length}');
      request.response.add(data.sublist(0, end + 1));
      await request.response.close();
    });
    final prepared = await _relay().prepareTarget(_target(_url(origin)));
    for (final end in [0, 1, 3, 6, 7, 15]) {
      final response =
          await _get(prepared.streamUrl, headers: {'Range': 'bytes=0-$end'});
      expect(response.$1, 206, reason: 'bytes=0-$end');
      expect(response.$2, _mp4.sublist(0, end + 1));
    }
    manifest = true;
    expect((await _get(prepared.streamUrl, headers: {'Range': 'bytes=0-1'})).$1,
        502);
  });

  test('redirect, response headers and prefix consume one combined deadline',
      () async {
    var completedBody = false;
    final origin = await _server((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (request.uri.path == '/video') {
        request.response.statusCode = 302;
        request.response.headers.set('location', '/final');
        await request.response.close();
        return;
      }
      request.response.add(_mp4);
      await request.response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      completedBody = true;
      await request.response.close();
    });
    final relay = createPlaybackStreamRelayService(
        requestTimeout: const Duration(milliseconds: 750));
    addTearDown(relay.close);
    await expectLater(relay.prepareTarget(_target(_url(origin))),
        throwsA(isA<PlaybackRelayException>()));
    expect(completedBody, isFalse);
  });

  test('close cancels a stalled prefix without waiting for its deadline',
      () async {
    final started = Completer<void>();
    final origin = await _server((request) async {
      request.response.add(_mp4);
      await request.response.flush();
      started.complete();
    });
    final relay = _relay();
    final pending = relay.prepareTarget(_target(_url(origin)));
    final failed = expectLater(pending, throwsA(isA<PlaybackRelayException>()));
    await started.future;
    await relay.close().timeout(const Duration(seconds: 2));
    await failed.timeout(const Duration(seconds: 2));
  });

  test('closing one owner aborts its stream and leaves another owner alive',
      () async {
    final started = Completer<void>();
    final origin = await _server((request) async {
      if (request.headers.value('range') == 'bytes=0-511' ||
          request.uri.path == '/other') {
        await _media(request);
        return;
      }
      request.response.add([..._mp4, ...List.filled(1024, 0)]);
      await request.response.flush();
      started.complete();
    });
    final relay = _relay();
    final other = _relay();
    final prepared = await relay.prepareTarget(_target(_url(origin)));
    final replacement =
        await other.prepareTarget(_target(_url(origin, '/other')));
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final response =
        await (await client.getUrl(Uri.parse(prepared.streamUrl))).close();
    final finished = response.drain<void>().then<void>((_) {}, onError: (_) {});
    await started.future;
    await relay.close().timeout(const Duration(seconds: 2));
    await finished.timeout(const Duration(seconds: 2));
    expect((await _get(replacement.streamUrl)).$2, _mp4);
  });
}
