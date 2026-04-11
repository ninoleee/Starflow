import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_stream_relay_contract.dart';
import 'package:starflow/features/playback/application/playback_stream_relay_service.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

const String _originHeaderName = 'origin';

void main() {
  test('playback relay forwards quark auth state and reuses redirected target',
      () async {
    final upstreamRequests = <_RecordedUpstreamRequest>[];
    final upstreamServer =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final upstreamSubscription = upstreamServer.listen((request) async {
      upstreamRequests.add(
        _RecordedUpstreamRequest(
          path: request.uri.path,
          cookie: request.headers.value(HttpHeaders.cookieHeader) ?? '',
          range: request.headers.value(HttpHeaders.rangeHeader) ?? '',
          userAgent: request.headers.value(HttpHeaders.userAgentHeader) ?? '',
          referer: request.headers.value(HttpHeaders.refererHeader) ?? '',
          origin: request.headers.value(_originHeaderName) ?? '',
        ),
      );

      if (request.uri.path == '/start') {
        request.response.statusCode = HttpStatus.found;
        request.response.headers
          ..set(HttpHeaders.locationHeader, '/cdn/video.mkv')
          ..add(HttpHeaders.setCookieHeader, 'vip=1; Path=/');
        await request.response.close();
        return;
      }

      if (request.uri.path == '/cdn/video.mkv') {
        final body = utf8.encode('relay-ok');
        final requestedRange =
            request.headers.value(HttpHeaders.rangeHeader) ?? '';
        request.response.statusCode =
            requestedRange.isNotEmpty ? HttpStatus.partialContent : 200;
        request.response.headers
          ..set(HttpHeaders.acceptRangesHeader, 'bytes')
          ..set(HttpHeaders.contentTypeHeader, 'video/mp4')
          ..contentLength = body.length;
        if (requestedRange.isNotEmpty) {
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes 0-${body.length - 1}/${body.length}',
          );
        }
        request.response.add(body);
        await request.response.close();
        return;
      }

      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });
    addTearDown(() async {
      await upstreamSubscription.cancel();
      await upstreamServer.close(force: true);
    });

    final container = ProviderContainer();
    addTearDown(() async {
      await container.read(playbackStreamRelayServiceProvider).close();
      container.dispose();
    });

    final service = container.read(playbackStreamRelayServiceProvider);
    final prepared = await service.prepareTarget(
      PlaybackTarget(
        title: 'Quark Relay',
        sourceId: 'quark-main',
        sourceName: 'Quark',
        sourceKind: MediaSourceKind.quark,
        streamUrl: 'http://127.0.0.1:${upstreamServer.port}/start',
        headers: const <String, String>{
          'Cookie': 'kps=base; sign=keep',
          'User-Agent': 'StarflowTestUA/1.0',
          'Referer': 'https://drive-pc.quark.cn',
          'Origin': 'https://drive-pc.quark.cn',
        },
      ),
    );

    expect(isLoopbackPlaybackRelayUrl(prepared.streamUrl), isTrue);
    expect(prepared.headers, isEmpty);
    expect(
      prepared.actualAddress,
      'http://127.0.0.1:${upstreamServer.port}/start',
    );

    final client = HttpClient()..autoUncompress = false;
    addTearDown(() {
      client.close(force: true);
    });

    final relayRequest = await client.getUrl(Uri.parse(prepared.streamUrl));
    relayRequest.headers.set(HttpHeaders.rangeHeader, 'bytes=100-199');
    final relayResponse = await relayRequest.close();
    final bytes = await relayResponse.fold<List<int>>(
      <int>[],
      (buffer, chunk) {
        buffer.addAll(chunk);
        return buffer;
      },
    );

    expect(relayResponse.statusCode, HttpStatus.partialContent);
    expect(utf8.decode(bytes), 'relay-ok');
    expect(
      upstreamRequests.map((item) => item.path).toList(),
      ['/start', '/cdn/video.mkv', '/cdn/video.mkv'],
    );
    expect(upstreamRequests[0].range, 'bytes=0-0');
    expect(upstreamRequests[0].cookie, contains('kps=base'));
    expect(upstreamRequests[1].cookie, contains('vip=1'));
    expect(upstreamRequests[2].cookie, contains('vip=1'));
    expect(upstreamRequests[2].range, 'bytes=100-199');
    expect(upstreamRequests[2].userAgent, 'StarflowTestUA/1.0');
    expect(upstreamRequests[2].referer, 'https://drive-pc.quark.cn');
    expect(upstreamRequests[2].origin, 'https://drive-pc.quark.cn');
  });
}

class _RecordedUpstreamRequest {
  const _RecordedUpstreamRequest({
    required this.path,
    required this.cookie,
    required this.range,
    required this.userAgent,
    required this.referer,
    required this.origin,
  });

  final String path;
  final String cookie;
  final String range;
  final String userAgent;
  final String referer;
  final String origin;
}
