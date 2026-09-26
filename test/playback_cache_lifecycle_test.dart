import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_relay_disk_cache.dart';
import 'package:starflow/features/playback/application/playback_stream_relay_contract.dart';
import 'package:starflow/features/playback/application/playback_stream_relay_service_io.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

void main() {
  for (final ignoreRange in [false, true]) {
    test('partial disk hit resumes open range, ignoreRange=$ignoreRange',
        () async {
      final fixture = await Fixture.create(ignoreRange: ignoreRange);
      addTearDown(fixture.close);
      final relay = createPlaybackStreamRelayService(diskCache: fixture.cache);
      addTearDown(relay.close);
      final target = await relay.prepareTarget(fixture.target);
      final key = Uri.parse(target.streamUrl).path;
      await fixture.seed(key, 0, 512);
      final before = fixture.ranges.length;
      expect(await fixture.get(target.streamUrl, 'bytes=0-'), fixture.data);
      expect(fixture.ranges.skip(before).first, 'bytes=512-4095');
      expect(fixture.cache.hitBytes, 512);
    });
  }

  test(
      'truncated cache falls back to a server ignoring Range without duplicate bytes',
      () async {
    final fixture = await Fixture.create(ignoreRange: true);
    addTearDown(fixture.close);
    final relay = createPlaybackStreamRelayService(diskCache: fixture.cache);
    addTearDown(relay.close);
    final target = await relay.prepareTarget(fixture.target);
    await fixture.seed(Uri.parse(target.streamUrl).path, 0, 4096);
    final file = (await fixture.root
            .list(recursive: true)
            .where((e) => e is File)
            .toList())
        .single as File;
    final handle = await file.open(mode: FileMode.writeOnlyAppend);
    await handle.truncate(128);
    await handle.close();
    expect(await fixture.get(target.streamUrl), fixture.data);
    expect(fixture.ranges.last, 'bytes=128-4095');
  });

  test('clear removes files, closes handles and allows fresh writes', () async {
    final fixture = await Fixture.create();
    addTearDown(fixture.close);
    await fixture.seed('media', 0, 4096);
    final read = await fixture.cache.read('media', null);
    expect(read, isNotNull);
    await fixture.cache.clear();
    expect(fixture.cache.disabled, false);
    expect(fixture.cache.storedBytes, 0);
    await fixture.seed('media', 0, 4096);
    final fresh = await fixture.cache.read('media', null);
    expect(fresh, isNotNull);
    await fresh!.close();
  });

  test(
      'changed resource validator cannot splice new bytes into an old response',
      () async {
    var etag = '"first"';
    final fixture = await Fixture.create(etag: () => etag);
    addTearDown(fixture.close);
    final relay = createPlaybackStreamRelayService(diskCache: fixture.cache);
    addTearDown(relay.close);
    final target = await relay.prepareTarget(fixture.target);
    await fixture.seed(Uri.parse(target.streamUrl).path, 0, 512);
    etag = '"second"';
    await expectLater(
        fixture.get(target.streamUrl), throwsA(isA<HttpException>()));
    expect(fixture.cache.disabled, true);
    expect(fixture.cache.disabledReason, 'resource_changed');
  });

  test('network fills only gaps between cached ranges', () async {
    final fixture = await Fixture.create();
    addTearDown(fixture.close);
    final relay = createPlaybackStreamRelayService(diskCache: fixture.cache);
    addTearDown(relay.close);
    final target = await relay.prepareTarget(fixture.target);
    final key = Uri.parse(target.streamUrl).path;
    await fixture.seed(key, 512, 512);
    await fixture.seed(key, 2048, 2048);
    final before = fixture.ranges.length;
    expect(await fixture.get(target.streamUrl, 'bytes=0-'), fixture.data);
    expect(fixture.ranges.skip(before), ['bytes=0-511', 'bytes=1024-2047']);
    expect(fixture.cache.hitBytes, 2560);
  });

  test('ignored Range responses fill gaps without overwriting later cache hits',
      () async {
    final fixture = await Fixture.create(ignoreRange: true);
    addTearDown(fixture.close);
    final relay = createPlaybackStreamRelayService(diskCache: fixture.cache);
    addTearDown(relay.close);
    final target = await relay.prepareTarget(fixture.target);
    final key = Uri.parse(target.streamUrl).path;
    await fixture.seed(key, 512, 512);
    await fixture.seed(key, 2048, 2048);
    final before = fixture.ranges.length;
    expect(await fixture.get(target.streamUrl, 'bytes=0-'), fixture.data);
    expect(fixture.ranges.skip(before), ['bytes=0-511', 'bytes=1024-2047']);
    expect(fixture.cache.hitBytes, 2560);
  });

  test('a cache containing only a later range reports a miss before gap fill',
      () async {
    final fixture = await Fixture.create();
    addTearDown(fixture.close);
    await fixture.seed('media', 512, 512);
    final miss = await fixture.cache.read('media', 'bytes=0-511');
    expect(miss, isNull);
  });

  test('overlapping range writes preserve the existing cached prefix',
      () async {
    final fixture = await Fixture.create();
    addTearDown(fixture.close);
    await fixture.seed('media', 0, 2048);
    await fixture.seed('media', 1024, 2048);
    final preserved = await fixture.cache.read('media', 'bytes=0-2047');
    expect(preserved, isNotNull);
    await preserved!.close();
    expect(fixture.cache.storedBytes, 2048);
  });

  test('large cached media is served in bounded file-handle slices', () async {
    final fixture = await Fixture.create(size: 34 * 1024 * 1024);
    addTearDown(fixture.close);
    final relay = createPlaybackStreamRelayService(diskCache: fixture.cache);
    addTearDown(relay.close);
    final target = await relay.prepareTarget(fixture.target);
    const blockSize = 2 * 1024 * 1024;
    for (var start = 0; start < fixture.data.length; start += blockSize) {
      await fixture.seed(Uri.parse(target.streamUrl).path, start,
          min(blockSize, fixture.data.length - start));
    }
    await fixture.cache.flushWrites();
    final before = fixture.ranges.length;
    expect(await fixture.get(target.streamUrl), fixture.data);
    expect(fixture.ranges.length, before);
  });

  test(
      'clearing during a cache read preserves the response and does not disable fresh caching',
      () async {
    final fixture = await Fixture.create(size: 4 * 1024 * 1024);
    addTearDown(fixture.close);
    final relay = createPlaybackStreamRelayService(diskCache: fixture.cache);
    addTearDown(relay.close);
    final target = await relay.prepareTarget(fixture.target);
    await fixture.seed(
        Uri.parse(target.streamUrl).path, 0, fixture.data.length);
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final response =
        await (await client.getUrl(Uri.parse(target.streamUrl))).close();
    final result = <int>[];
    var cleared = false;
    await for (final chunk in response) {
      result.addAll(chunk);
      if (!cleared) {
        cleared = true;
        await fixture.cache.clear();
      }
    }
    expect(result, fixture.data);
    expect(fixture.cache.disabled, false);
    await fixture.cache.flushWrites();
  });

  test(
      'many writers share one queue budget and free-space checks are throttled',
      () async {
    final gate = Completer<int?>();
    var spaceChecks = 0;
    final fixture = await Fixture.create(freeBytes: () {
      spaceChecks++;
      return gate.future;
    });
    addTearDown(fixture.close);
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final response =
        await (await client.getUrl(Uri.parse(fixture.target.streamUrl)))
            .close();
    await response.drain<void>();
    for (var i = 0; i < 3000; i++) {
      await fixture.cache
          .writer('media/$i', 200, response.headers)!
          .add(fixture.data);
    }
    expect(fixture.cache.queuedBytes,
        lessThanOrEqualTo(PlaybackRelayDiskCache.maxWriteQueueBytes));
    expect(fixture.cache.droppedBytes, greaterThan(0));
    final closing = fixture.cache.close();
    gate.complete(1024 * 1024 * 1024);
    await closing;
    expect(spaceChecks, lessThanOrEqualTo(1));
    expect(fixture.cache.queuedBytes, 0);
    expect(fixture.cache.storedBytes, 0);
  });

  test(
      'slow disk cannot block forwarding, queue stays bounded and close revokes queued writes',
      () async {
    final gate = Completer<int?>();
    final fixture = await Fixture.create(freeBytes: () => gate.future);
    addTearDown(fixture.close);
    final relay = createPlaybackStreamRelayService(diskCache: fixture.cache);
    final target = await relay.prepareTarget(fixture.target);
    expect(
        await fixture.get(target.streamUrl).timeout(const Duration(seconds: 1)),
        fixture.data);
    expect(fixture.cache.queuedBytes,
        lessThanOrEqualTo(PlaybackRelayDiskCache.maxWriteQueueBytes));
    final closing = relay.close();
    gate.complete(1024 * 1024 * 1024);
    await closing;
    expect(fixture.cache.storedBytes, 0);
    expect(
        await fixture.root
            .list(recursive: true)
            .where((e) => e is File)
            .isEmpty,
        true);
  });

  test(
      'shared owner exit removes only its blocks and final exit deletes every file',
      () async {
    final fixture = await Fixture.create();
    addTearDown(fixture.close);
    final first = createPlaybackStreamRelayService(diskCache: fixture.cache);
    final second = createPlaybackStreamRelayService(diskCache: fixture.cache);
    addTearDown(first.close);
    addTearDown(second.close);
    final a = await first.prepareTarget(fixture.target);
    final b = await second.prepareTarget(fixture.target);
    await fixture.seed(Uri.parse(a.streamUrl).path, 0, 4096);
    await fixture.seed(Uri.parse(b.streamUrl).path, 0, 4096);
    await first.close();
    expect(fixture.cache.storedBytes, 4096);
    expect(fixture.cache.disabled, false);
    final before = fixture.ranges.length;
    expect(await fixture.get(b.streamUrl), fixture.data);
    expect(fixture.ranges.length, before);
    await second.close();
    expect(fixture.cache.storedBytes, 0);
    expect(
        await fixture.root
            .list(recursive: true)
            .where((e) => e is File)
            .isEmpty,
        true);
  });

  test('idle bounded prefetch is cancelled by exit before it starts', () async {
    final fixture = await Fixture.create();
    addTearDown(fixture.close);
    final relay = createPlaybackStreamRelayService(diskCache: fixture.cache);
    final target = await relay.prepareTarget(fixture.target);
    await fixture.get(target.streamUrl, 'bytes=0-511');
    await relay.close();
    final before = fixture.ranges.length;
    await Future<void>.delayed(const Duration(milliseconds: 650));
    expect(fixture.ranges.length, before);
    expect(fixture.cache.storedBytes, 0);
  });

  test('finite request schedules bounded read ahead and next range hits disk',
      () async {
    final fixture = await Fixture.create();
    addTearDown(fixture.close);
    final relay = createPlaybackStreamRelayService(diskCache: fixture.cache);
    addTearDown(relay.close);
    final target = await relay.prepareTarget(fixture.target);
    await fixture.get(target.streamUrl, 'bytes=0-511');
    (relay as PlaybackRelayBufferControl).updateBufferState(memoryReady: true);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await fixture.cache.flushWrites();
    expect(fixture.ranges, contains('bytes=512-4095'));
    final before = fixture.ranges.length;
    expect(await fixture.get(target.streamUrl, 'bytes=512-1023'),
        fixture.data.sublist(512, 1024));
    expect(fixture.ranges.length, before);
  });

  test(
      'manual clear cancels scheduled prefetch but next playback request caches again',
      () async {
    final fixture = await Fixture.create();
    addTearDown(fixture.close);
    final relay = createPlaybackStreamRelayService(diskCache: fixture.cache);
    addTearDown(relay.close);
    final target = await relay.prepareTarget(fixture.target);
    await fixture.get(target.streamUrl, 'bytes=0-511');
    await clearPlaybackDiskCache();
    final before = fixture.ranges.length;
    await Future<void>.delayed(const Duration(milliseconds: 650));
    expect(fixture.ranges.length, before);
    await fixture.get(target.streamUrl);
    await fixture.cache.flushWrites();
    expect(fixture.cache.storedBytes, fixture.data.length);
  });

  test('HLS read ahead stops at two following VOD segments', () async {
    final root = await Directory.systemTemp.createTemp('cache-hls-prefetch-');
    final requests = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    addTearDown(() => root.delete(recursive: true));
    server.listen((request) async {
      requests.add(request.uri.path);
      final bytes = request.uri.path.endsWith('.m3u8')
          ? utf8.encode(
              '#EXTM3U\n#EXT-X-TARGETDURATION:5\n#EXTINF:5,\na.vtt\n#EXTINF:5,\nb.vtt\n#EXTINF:5,\nc.vtt\n#EXTINF:5,\nd.vtt\n#EXT-X-ENDLIST\n')
          : utf8.encode('WEBVTT\n\n00:00.000 --> 00:01.000\nHello\n');
      request.response.headers.contentType = ContentType.binary;
      request.response.contentLength = bytes.length;
      request.response.add(bytes);
      await request.response.close();
    });
    final cache = PlaybackRelayDiskCache(
        capacityBytes: 4096,
        directoryProvider: () => root.createTemp(),
        freeBytes: () async => 1024 * 1024 * 1024);
    final relay = createPlaybackStreamRelayService(diskCache: cache);
    addTearDown(relay.close);
    final target = await relay.prepareTarget(PlaybackTarget(
        title: 'test',
        sourceId: 'test',
        sourceName: 'test',
        sourceKind: MediaSourceKind.nas,
        streamUrl: 'http://127.0.0.1:${server.port}/vod.m3u8'));
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final manifestResponse =
        await (await client.getUrl(Uri.parse(target.streamUrl))).close();
    final manifest = await manifestResponse.transform(utf8.decoder).join();
    final first = RegExp(r'http://[^\s]+').firstMatch(manifest)![0]!;
    await (await (await client.getUrl(Uri.parse(first))).close()).drain<void>();
    (relay as PlaybackRelayBufferControl).updateBufferState(memoryReady: true);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await cache.flushWrites();
    expect(requests.where((p) => p.endsWith('.vtt')),
        ['/a.vtt', '/b.vtt', '/c.vtt']);
  });
}

class Fixture {
  Fixture(this.root, this.server, this.cache, this.data, this.ranges);
  final Directory root;
  final HttpServer server;
  final PlaybackRelayDiskCache cache;
  final List<int> data;
  final List<String?> ranges;
  PlaybackTarget get target => PlaybackTarget(
      title: 'test',
      sourceId: 'test',
      sourceName: 'test',
      sourceKind: MediaSourceKind.nas,
      streamUrl: 'http://127.0.0.1:${server.port}/video');

  static Future<Fixture> create(
      {bool ignoreRange = false,
      Future<int?> Function()? freeBytes,
      String? Function()? etag,
      int size = 4096}) async {
    final root = await Directory.systemTemp.createTemp('cache-lifecycle-');
    final data = List<int>.generate(size, (i) => i % 256)
      ..setRange(4, 8, ascii.encode('ftyp'));
    final ranges = <String?>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final range = request.headers.value('range');
      ranges.add(range);
      final parsed = !ignoreRange || request.uri.path == '/seed'
          ? RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range ?? '')
          : null;
      final start = parsed == null ? 0 : int.parse(parsed[1]!);
      final end = parsed == null || parsed[2]!.isEmpty
          ? data.length - 1
          : int.parse(parsed[2]!).clamp(0, data.length - 1);
      request.response.statusCode = parsed == null ? 200 : 206;
      request.response.headers.contentType = ContentType.binary;
      final tag = etag == null ? '"stable"' : etag();
      if (tag != null) request.response.headers.set('etag', tag);
      request.response.contentLength = end - start + 1;
      if (parsed != null) {
        request.response.headers
            .set('content-range', 'bytes $start-$end/${data.length}');
      }
      request.response.add(data.sublist(start, end + 1));
      await request.response.close();
    });
    return Fixture(
        root,
        server,
        PlaybackRelayDiskCache(
            capacityBytes: size > 16384 ? size * 2 : 16384,
            directoryProvider: () => root.createTemp('session-'),
            freeBytes: freeBytes ?? () async => 1024 * 1024 * 1024),
        data,
        ranges);
  }

  Future<void> seed(String key, int start, int length) async {
    final client = HttpClient();
    try {
      final request = await client
          .getUrl(Uri.parse('http://127.0.0.1:${server.port}/seed'));
      request.headers.set('range', 'bytes=$start-${start + length - 1}');
      final response = await request.close();
      final writer = cache.writer(key, response.statusCode, response.headers)!;
      await for (final chunk in response) {
        await writer.add(chunk);
      }
      writer.close();
      await cache.flushWrites();
    } finally {
      client.close(force: true);
    }
  }

  Future<List<int>> get(String url, [String? range]) async {
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

  Future<void> close() async {
    await cache.close();
    await server.close(force: true);
    if (await root.exists()) await root.delete(recursive: true);
  }
}
