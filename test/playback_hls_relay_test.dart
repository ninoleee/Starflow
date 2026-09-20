import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_hls_rewriter.dart';
import 'package:starflow/features/playback/application/playback_stream_relay_contract.dart';
import 'package:starflow/features/playback/application/playback_stream_relay_service_io.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

const _secret = 'Basic c3ludGhldGljOnNlY3JldA==';

Future<HttpServer> _server(FutureOr<void> Function(HttpRequest) handler) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    try {
      await handler(request);
    } catch (_) {/* Cancellation is expected. */}
  });
  addTearDown(() => server.close(force: true));
  return server;
}

String _url(HttpServer server, String path) =>
    'http://127.0.0.1:${server.port}$path';

PlaybackTarget _target(String url) => PlaybackTarget(
    title: 'Synthetic',
    sourceId: 'nas',
    sourceName: 'NAS',
    sourceKind: MediaSourceKind.nas,
    streamUrl: url,
    headers: const {'Authorization': _secret, 'Cookie': 'sid=synthetic'});

Future<(int, List<int>, HttpHeaders)> _get(String url,
    {String method = 'GET', String? range}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, Uri.parse(url));
    if (range != null) request.headers.set('range', range);
    final response = await request.close();
    return (
      response.statusCode,
      await response.fold<List<int>>([], (a, b) => a..addAll(b)),
      response.headers
    );
  } finally {
    client.close(force: true);
  }
}

List<String> _uris(String text) {
  final result = <String>[];
  rewritePlaybackHls(text, (uri, _) {
    result.add(uri);
    return uri;
  });
  return result;
}

void main() {
  test(
      'live refresh keeps stable capabilities and expires old segments without reuse',
      () async {
    var sequence = 1;
    var invalid = false;
    final origin = await _server((request) async {
      request.response.headers.contentType = ContentType.binary;
      if (request.uri.path.endsWith('.m3u8')) {
        request.response.write('#EXTM3U\n#EXT-X-TARGETDURATION:6\n'
            '#EXT-X-MEDIA-SEQUENCE:$sequence\n#EXTINF:6,\n$sequence.ts\n'
            '${invalid ? '#EXT-X-UNKNOWN:URI="external"\n' : ''}');
      } else {
        request.response
            .add([0, 0, 0, 16, ...ascii.encode('stypisom'), 0, 0, 0, 0]);
      }
      await request.response.close();
    });
    var now = DateTime.utc(2026, 9, 20);
    final relay = createPlaybackStreamRelayService(clock: () => now);
    addTearDown(relay.close);
    final target =
        await relay.prepareTarget(_target(_url(origin, '/live.m3u8')));
    final first = await _get(target.streamUrl);
    expect(first.$3.value('cache-control'), 'no-store');
    final old = _uris(utf8.decode(first.$2)).single;
    expect(_uris(utf8.decode((await _get(target.streamUrl)).$2)).single, old);
    sequence++;
    final fresh = _uris(utf8.decode((await _get(target.streamUrl)).$2)).single;
    expect(fresh, isNot(old));
    expect((await _get(old)).$1, 200);
    now = now.add(const Duration(minutes: 3));
    invalid = true;
    expect((await _get(target.streamUrl)).$1, 502);
    // Failed refresh cannot revoke capabilities used by the current player.
    expect((await _get(old)).$1, 200);
    invalid = false;
    await _get(target.streamUrl);
    expect((await _get(old)).$1, 404);
    expect((await _get(fresh)).$1, 200);
    sequence = 1;
    final reintroduced =
        _uris(utf8.decode((await _get(target.streamUrl)).$2)).single;
    expect(reintroduced, isNot(old));
    expect((await _get(old)).$1, 404);
    expect((await _get('${target.streamUrl}?_HLS_msn=2')).$1, 404);
  });

  test(
      'LL-HLS fallback exposes full segments only and rejects delta and part-only responses',
      () {
    const partial = '#EXTM3U\n#EXT-X-TARGETDURATION:6\n'
        '#EXT-X-SERVER-CONTROL:CAN-BLOCK-RELOAD=YES,CAN-SKIP-UNTIL=12,PART-HOLD-BACK=1\n'
        '#EXT-X-PART-INF:PART-TARGET=0.5\n'
        '#EXT-X-PART:DURATION=0.5,URI="https://foreign.test/part",INDEPENDENT=YES\n'
        '#EXT-X-PRELOAD-HINT:TYPE=PART,URI="https://foreign.test/next"\n'
        '#EXT-X-RENDITION-REPORT:URI="other.m3u8",LAST-MSN=12,LAST-PART=1\n';
    final registered = <String>[];
    final result =
        rewritePlaybackHls('$partial#EXTINF:6,\nfull.ts\n', (uri, _) {
      registered.add(uri);
      return 'https://relay.test/resource';
    });
    expect(registered, ['full.ts']);
    expect(result, isNot(contains('foreign.test')));
    expect(result, isNot(contains('PART')));
    expect(result, isNot(contains('CAN-BLOCK')));
    for (final manifest in [
      partial,
      '$partial#EXT-X-SKIP:SKIPPED-SEGMENTS=2\n#EXTINF:6,\nfull.ts\n',
      '#EXTM3U\n#EXT-X-TARGETDURATION:0\n#EXTINF:6,\nfull.ts\n'
    ]) {
      expect(() => rewritePlaybackHls(manifest, (uri, _) => uri),
          throwsA(same(unsupportedRelayMedia)));
    }
  });

  test(
      'AES-128 ciphertext bypasses clear-container sniffing and key ranges are removed',
      () async {
    final ciphertext = List<int>.generate(1024, (i) => (i * 37 + 11) % 256);
    final origin = await _server((request) async {
      request.response.headers.contentType = ContentType.binary;
      if (request.uri.path == '/media.m3u8') {
        request.response.write('#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key"\n'
            '#EXT-X-MAP:URI="init",BYTERANGE="1024@0"\n#EXTINF:5,\nsegment\n#EXT-X-ENDLIST\n');
      } else if (request.uri.path == '/key') {
        expect(request.headers.value('range'), isNull);
        request.response.add(List.filled(16, 7));
      } else {
        request.response.add(ciphertext);
      }
      await request.response.close();
    });
    final relay = createPlaybackStreamRelayService();
    addTearDown(relay.close);
    final target =
        await relay.prepareTarget(_target(_url(origin, '/media.m3u8')));
    final resources = _uris(utf8.decode((await _get(target.streamUrl)).$2));
    expect(
        (await _get(resources[0], range: 'bytes=0-1')).$2, List.filled(16, 7));
    expect((await _get(resources[1])).$2, ciphertext);
    expect((await _get(resources[2])).$2, ciphertext);
  });

  test('quoted commas, keys, maps, renditions and signed query bytes survive',
      () {
    const master =
        '#EXTM3U\n#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="s",NAME="English, CC",URI="sub.m3u8?x=a%2Fb&x=2"\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=12,CODECS="avc1.640029,mp4a.40.2",SUBTITLES="s"\nvideo.m3u8\n';
    final kinds = <HlsResourceKind>[];
    final rewritten = rewritePlaybackHls(master, (uri, kind) {
      kinds.add(kind);
      return 'https://relay.test/$uri';
    });
    expect(rewritten, contains('NAME="English, CC"'));
    expect(rewritten, contains('x=a%2Fb&x=2'));
    expect(kinds, [HlsResourceKind.playlist, HlsResourceKind.playlist]);
    final media = rewritePlaybackHls(
        '#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key"\n'
        '#EXT-X-MAP:URI="init.mp4",BYTERANGE="20@0"\n#EXTINF:5,\nseg.ts\n#EXT-X-ENDLIST\n',
        (uri, kind) {
      kinds.add(kind);
      return uri;
    });
    expect(media, contains('BYTERANGE="20@0"'));
    expect(kinds.skip(2), [
      HlsResourceKind.key,
      HlsResourceKind.encryptedSegment,
      HlsResourceKind.encryptedSegment
    ]);
  });

  for (final invalid in [
    '#EXTM3U\n#EXTINF:5,\nseg.ts\n',
    '#EXTM3U\n#EXT-X-DEFINE:NAME="x",VALUE="secret"\n#EXTINF:5,\nseg.ts\n#EXT-X-ENDLIST',
    '#EXTM3U\n#EXT-X-CONTENT-STEERING:SERVER-URI="https://evil.test"\n',
    '#EXTM3U\n#EXT-X-KEY:METHOD=SAMPLE-AES,URI="key"\nseg.ts\n#EXT-X-ENDLIST',
    '#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key",KEYFORMAT="com.apple.streamingkeydelivery"\nseg.ts\n#EXT-X-ENDLIST',
    '#EXTM3U\n#EXT-X-MAP:URI="a",URI="b"\nseg.ts\n#EXT-X-ENDLIST',
    '#EXTM3U\n#EXT-X-MAP:URI="a",\nseg.ts\n#EXT-X-ENDLIST',
    '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=12\n',
    '#EXTM3U\n#EXTINF:5,\n{variable}.ts\n#EXT-X-ENDLIST',
  ]) {
    test('unsupported or malformed HLS fails closed: $invalid', () {
      expect(() => rewritePlaybackHls(invalid, (uri, _) => uri),
          throwsA(same(unsupportedRelayMedia)));
    });
  }

  test(
      'nested HLS rewrites every URL and isolates credentials across origins and redirects',
      () async {
    final external = <Map<String, String?>>[];
    final cdn = await _server((request) async {
      external.add({
        'auth': request.headers.value('authorization'),
        'cookie': request.headers.value('cookie'),
        'query': request.uri.query
      });
      request.response.headers.contentType = ContentType.binary;
      request.response.add(request.uri.path == '/key'
          ? List.filled(16, 7)
          : [0, 0, 0, 16, ...ascii.encode('stypisom'), 0, 0, 0, 0]);
      await request.response.close();
    });
    final originRequests = <String>[];
    final origin = await _server((request) async {
      expect(request.headers.value('authorization'), _secret);
      expect(request.headers.value('cookie'), contains('sid=synthetic'));
      originRequests.add(request.uri.path);
      if (request.uri.path == '/entry.m3u8') {
        request.response.statusCode = 302;
        request.response.headers.set('location', '/dir/master.m3u8');
      } else if (request.uri.path == '/dir/master.m3u8') {
        request.response.write(
            '#EXTM3U\n#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="s",NAME="CC",URI="sub.m3u8"\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=12,SUBTITLES="s"\nvideo.m3u8\n');
      } else if (request.uri.path == '/dir/video.m3u8') {
        request.response.write(
            '#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="${_url(cdn, '/key?sig=a%2Fb&sig=2')}"\n'
            '#EXT-X-MAP:URI="init.mp4"\n#EXTINF:5,\nsegment.ts\n#EXT-X-ENDLIST\n');
      } else if (request.uri.path == '/dir/sub.m3u8') {
        request.response
            .write('#EXTM3U\n#EXTINF:5,\nsub.vtt\n#EXT-X-ENDLIST\n');
      } else if (request.uri.path == '/dir/sub.vtt') {
        request.response.headers.contentType = ContentType('text', 'vtt');
        request.response
            .write('WEBVTT\n\n00:00.000 --> 00:01.000\nSynthetic\n');
      } else if (request.uri.path == '/dir/segment.ts') {
        request.response.statusCode = 302;
        request.response.headers.set('location', _url(cdn, '/segment'));
      } else {
        request.response.headers.contentType = ContentType.binary;
        request.response.statusCode = 206;
        request.response.headers.set('content-range', 'bytes 4-7/20');
        request.response.add([1, 2, 3, 4]);
      }
      await request.response.close();
    });
    final relay = createPlaybackStreamRelayService();
    addTearDown(relay.close);
    final target =
        await relay.prepareTarget(_target(_url(origin, '/entry.m3u8')));
    expect(target.headers, isEmpty);
    final master = await _get(target.streamUrl);
    expect(master.$1, 200);
    final children = _uris(utf8.decode(master.$2));
    expect(children, hasLength(2));
    expect(
        children.every(
            (u) => Uri.parse(u).port == Uri.parse(target.streamUrl).port),
        isTrue);
    final subtitle = _uris(utf8.decode((await _get(children[0])).$2)).single;
    expect(utf8.decode((await _get(subtitle)).$2), startsWith('WEBVTT'));
    final video = _uris(utf8.decode((await _get(children[1])).$2));
    expect((await _get(video[0])).$2, List.filled(16, 7));
    final ranged = await _get(video[1], range: 'bytes=4-7');
    expect(ranged.$1, 206);
    expect(ranged.$3.value('content-range'), 'bytes 4-7/20');
    expect((await _get(video[2])).$1, 200);
    expect(external.every((r) => r['auth'] == null && r['cookie'] == null),
        isTrue);
    expect(external.first['query'], 'sig=a%2Fb&sig=2');
    expect(originRequests, contains('/dir/video.m3u8'));
    expect((await _get('${video[0]}?url=https://evil.test')).$1, 404);
    final head = await _get(target.streamUrl, method: 'HEAD');
    expect(head.$1, 200);
    expect(head.$2, isEmpty);
    await relay.clear();
    expect((await _get(video[0])).$1, 404);
  });

  test(
      'extensionless manifest range probe is refetched, oversized and unsafe URIs rejected',
      () async {
    var manifest = '#EXTM3U\n#EXTINF:5,\nsegment.ts\n#EXT-X-ENDLIST\n';
    final ranges = <String?>[];
    final origin = await _server((request) async {
      ranges.add(request.headers.value('range'));
      request.response.write(manifest);
      await request.response.close();
    });
    final relay = createPlaybackStreamRelayService();
    addTearDown(relay.close);
    await relay.prepareTarget(_target(_url(origin, '/opaque')));
    expect(ranges, ['bytes=0-511', null]);
    for (final uri in [
      'file:///etc/passwd',
      'http://user:pass@evil.test/a',
      'data:text/plain,x'
    ]) {
      manifest = '#EXTM3U\n#EXTINF:5,\n$uri\n#EXT-X-ENDLIST\n';
      await expectLater(
          relay.prepareTarget(_target(_url(origin, '/media.m3u8'))),
          throwsA(same(unsupportedRelayMedia)));
    }
    manifest = '#EXTM3U\n#${'x' * (1024 * 1024)}\n';
    await expectLater(relay.prepareTarget(_target(_url(origin, '/media.m3u8'))),
        throwsA(same(unsupportedRelayMedia)));
  });

  test(
      'cyclic manifests are depth bounded and unknown segment payloads rejected',
      () async {
    var body = '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=12\ncycle.m3u8\n';
    final origin = await _server((request) async {
      request.response.headers.contentType = ContentType.binary;
      request.response.write(body);
      await request.response.close();
    });
    final relay = createPlaybackStreamRelayService();
    addTearDown(relay.close);
    final target =
        await relay.prepareTarget(_target(_url(origin, '/cycle.m3u8')));
    var url = target.streamUrl;
    var rejected = false;
    for (var i = 0; i < 8; i++) {
      final response = await _get(url);
      if (response.$1 == 502) {
        rejected = true;
        break;
      }
      url = _uris(utf8.decode(response.$2)).single;
    }
    expect(rejected, isTrue);
    body =
        '#EXTM3U\n#EXT-X-SESSION-KEY:METHOD=AES-128,URI="key"\n#EXTINF:5,\nsegment.ts\n#EXT-X-ENDLIST\n';
    final media =
        await relay.prepareTarget(_target(_url(origin, '/video.m3u8')));
    final resources = _uris(utf8.decode((await _get(media.streamUrl)).$2));
    body = '[Reference]\nRef1=https://foreign.test/video\n';
    expect((await _get(resources[0])).$1, 502);
    expect((await _get(resources[1])).$1, 502);
  });
}
