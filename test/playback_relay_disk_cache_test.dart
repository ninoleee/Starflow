import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_relay_disk_cache.dart';
import 'package:starflow/features/playback/application/playback_stream_relay_service_io.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  test(
      'disk cache settings default off and round trip only supported capacities',
      () {
    final original = AppSettings.fromJson(const {});
    expect(original.playbackDiskCacheMiB, 0);
    for (final value in [0, 256, 512, 1024]) {
      expect(
          AppSettings.fromJson(
                  original.copyWith(playbackDiskCacheMiB: value).toJson())
              .playbackDiskCacheMiB,
          value);
    }
    expect(
        AppSettings.fromJson({...original.toJson(), 'playbackDiskCacheMiB': -1})
            .playbackDiskCacheMiB,
        0);
  });

  for (final lowSpace in [false, true]) {
    test(
        'unknown extension progressive bytes and range cache, lowSpace=$lowSpace',
        () async {
      final root = await Directory.systemTemp.createTemp('relay-cache-test-');
      addTearDown(() => root.delete(recursive: true));
      var reads = 0;
      final data = [
        0,
        0,
        0,
        16,
        ...ascii.encode('ftypisom'),
        0,
        0,
        0,
        0,
        ...List.generate(1024, (i) => i % 256)
      ];
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => origin.close(force: true));
      origin.listen((request) async {
        reads++;
        final match = RegExp(r'bytes=(\d+)-(\d*)')
            .firstMatch(request.headers.value('range') ?? '');
        final start = match == null ? 0 : int.parse(match[1]!);
        final end = match == null || match[2]!.isEmpty
            ? data.length - 1
            : int.parse(match[2]!).clamp(0, data.length - 1);
        request.response.statusCode = match == null ? 200 : 206;
        request.response.headers.contentType = ContentType.binary;
        request.response.headers.set('etag', '"stable"');
        request.response.contentLength = end - start + 1;
        if (match != null) {
          request.response.headers
              .set('content-range', 'bytes $start-$end/${data.length}');
        }
        request.response.add(data.sublist(start, end + 1));
        await request.response.close();
      });
      final cache = PlaybackRelayDiskCache(
          capacityBytes: 2048,
          directoryProvider: () => root.createTemp(),
          freeBytes: () async => lowSpace ? 0 : 1024 * 1024 * 1024);
      final relay = createPlaybackStreamRelayService(diskCache: cache);
      addTearDown(relay.close);
      final target = PlaybackTarget(
          title: 'test',
          sourceId: 'test',
          sourceName: 'test',
          sourceKind: MediaSourceKind.nas,
          streamUrl: 'http://127.0.0.1:${origin.port}/opaque');
      final prepared = await relay.prepareTarget(target);
      expect(prepared.streamUrl, isNot(target.streamUrl));
      expect(await get(prepared.streamUrl), data);
      await cache.flushWrites();
      final afterFirst = reads;
      expect(await get(prepared.streamUrl, range: 'bytes=16-31'),
          data.sublist(16, 32));
      expect(reads, lowSpace ? afterFirst + 1 : afterFirst);
      await cache.clear();
      expect(await get(prepared.streamUrl, range: 'bytes=16-31'),
          data.sublist(16, 32));
      expect(reads, lowSpace ? afterFirst + 2 : afterFirst + 1);
      await relay.close();
      expect(await root.list(recursive: true).where((e) => e is File).isEmpty,
          true);
    });
  }

  test(
      'HLS VOD segments and WebVTT use cache while manifests and keys stay live',
      () async {
    final root = await Directory.systemTemp.createTemp('relay-hls-cache-test-');
    addTearDown(() => root.delete(recursive: true));
    final requests = <String, int>{};
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => origin.close(force: true));
    origin.listen((request) async {
      final path = request.uri.path;
      requests.update(path, (n) => n + 1, ifAbsent: () => 1);
      final bytes = path == '/vod.m3u8'
          ? utf8.encode(
              '#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXTINF:6,\nsub.vtt\n#EXT-X-KEY:METHOD=AES-128,URI="key"\n#EXTINF:6,\nsegment.ts\n#EXT-X-ENDLIST\n')
          : path == '/sub.vtt'
              ? utf8.encode('WEBVTT\n\n00:00.000 --> 00:01.000\nHello\n')
              : List<int>.filled(16, 42);
      request.response.headers.contentType = path.endsWith('.vtt')
          ? ContentType('text', 'vtt')
          : ContentType.binary;
      request.response.contentLength = bytes.length;
      request.response.add(bytes);
      await request.response.close();
    });
    final cache = PlaybackRelayDiskCache(
        capacityBytes: 2048,
        directoryProvider: () => root.createTemp(),
        freeBytes: () async => 1024 * 1024 * 1024);
    final relay = createPlaybackStreamRelayService(diskCache: cache);
    addTearDown(relay.close);
    final prepared = await relay.prepareTarget(PlaybackTarget(
        title: 'test',
        sourceId: 'test',
        sourceName: 'test',
        sourceKind: MediaSourceKind.nas,
        streamUrl: 'http://127.0.0.1:${origin.port}/vod.m3u8'));
    final manifest = utf8.decode(await get(prepared.streamUrl));
    final urls = RegExp(r'http://[^\s"]+')
        .allMatches(manifest)
        .map((m) => m[0]!)
        .toList();
    expect(urls.length, 3);
    for (final url in urls) {
      await get(url);
      await cache.flushWrites();
      await get(url);
    }
    await get(prepared.streamUrl);
    expect(requests['/sub.vtt'], 1);
    expect(requests['/segment.ts'], 1);
    expect(requests['/key'], 2);
    expect(requests['/vod.m3u8'], 3);
  });

  test('local files bypass relay even when disk caching is enabled', () async {
    final relay = createPlaybackStreamRelayService(diskCacheMiB: 256);
    addTearDown(relay.close);
    final target = PlaybackTarget(
        title: 'test',
        sourceId: 'test',
        sourceName: 'test',
        sourceKind: MediaSourceKind.nas,
        streamUrl: 'file:///tmp/video.mkv',
        headers: const {'Authorization': 'local'});
    expect(identical(await relay.prepareTarget(target), target), true);
  });

  test(
      'LRU eviction, write failure and missing files fall back without stale hits',
      () async {
    final root = await Directory.systemTemp.createTemp('relay-cache-lru-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.contentLength = 8;
      request.response.add(List.filled(8, 7));
      await request.response.close();
    });
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final response = await (await client
            .getUrl(Uri.parse('http://127.0.0.1:${server.port}')))
        .close();
    await response.drain<void>();
    final cache = PlaybackRelayDiskCache(
        capacityBytes: 16,
        directoryProvider: () async => root,
        freeBytes: () async => 1024 * 1024 * 1024);
    Future<void> write(String key) async {
      final writer = cache.writer(key, 200, response.headers)!;
      await writer.add(List.filled(8, 7));
      await cache.flushWrites();
    }

    await write('a');
    await write('b');
    final a = await cache.read('a', null);
    expect(a, isNotNull);
    await a!.close();
    await write('c');
    expect(await cache.read('b', null), isNull);
    final hit = await cache.read('a', null);
    expect(hit, isNotNull);
    await hit!.close();
    final files = await root.list().where((entry) => entry is File).toList();
    for (final file in files) {
      await file.delete();
    }
    expect(await cache.read('a', null), isNull);
    expect(cache.disabled, true);
    await cache.close();

    final badCache = PlaybackRelayDiskCache(
        capacityBytes: 16,
        directoryProvider: () async =>
            throw const FileSystemException('unwritable'),
        freeBytes: () async => 1024 * 1024 * 1024);
    await badCache.writer('a', 200, response.headers)!.add(List.filled(8, 7));
    await badCache.flushWrites();
    expect(badCache.disabled, true);
    expect(await badCache.read('a', null), isNull);
    await badCache.close();
  });
}

Future<List<int>> get(String url, {String? range}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    if (range != null) request.headers.set('range', range);
    final response = await request.close();
    expect(response.statusCode, range == null ? 200 : 206);
    return await response.fold<List<int>>([], (a, b) => a..addAll(b));
  } finally {
    client.close(force: true);
  }
}
