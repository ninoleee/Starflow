import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_relay_disk_cache.dart';
import 'package:starflow/features/playback/application/playback_stream_relay_contract.dart';
import 'package:starflow/features/playback/application/playback_stream_relay_service_io.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

const mib = 1024 * 1024;

void main() {
  test('full player buffer can stop reading beyond the origin timeout',
      () async {
    final f =
        await RollingFixture.create(requestTimeout: const Duration(seconds: 2));
    addTearDown(f.close);
    final request = await f.client.getUrl(Uri.parse(f.url));
    request.headers.set('range', 'bytes=0-');
    final response = await request.close();
    final first = Completer<void>();
    final done = Completer<void>();
    var count = 0;
    Object? streamError;
    late StreamSubscription<List<int>> sub;
    sub = response.listen(
        (chunk) {
          count += chunk.length;
          if (!first.isCompleted) {
            sub.pause();
            first.complete();
          }
        },
        onDone: done.complete,
        onError: (Object error) {
          streamError = error;
        });
    addTearDown(sub.cancel);
    await first.future;
    await f
        .until(() => (f.control.cacheSnapshot()?.forwardBytes ?? 0) > 32 * mib);
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    sub.resume();
    await done.future.timeout(const Duration(seconds: 12));
    expect(streamError, isNull,
        reason: 'Player backpressure is not an origin read timeout.');
    expect(count, 180 * mib);
    expect(f.cache.hitBytes, greaterThan(32 * mib));
    expect(f.originBytes, lessThanOrEqualTo(180 * mib + 512));
  }, timeout: const Timeout(Duration(seconds: 35)));

  test('closing cancels a response blocked by full player memory', () async {
    final f = await RollingFixture.create();
    addTearDown(f.close);
    final response = await (await f.client.getUrl(Uri.parse(f.url))).close();
    final first = Completer<void>();
    late StreamSubscription<List<int>> sub;
    sub = response.listen((_) {
      if (!first.isCompleted) {
        sub.pause();
        first.complete();
      }
    }, onError: (Object _) {});
    addTearDown(sub.cancel);
    await first.future;
    await f
        .until(() => (f.control.cacheSnapshot()?.forwardBytes ?? 0) > 32 * mib);
    await f.relay.close().timeout(const Duration(seconds: 2));
    expect(f.cache.queuedBytes, 0);
    expect(f.cache.storedBytes, 0);
    expect(await f.root.list(recursive: true).where((e) => e is File).isEmpty,
        isTrue);
  });

  test(
      'one open-to-EOF response consumes background blocks without a second download',
      () async {
    final f = await RollingFixture.create();
    addTearDown(f.close);
    final request = await f.client.getUrl(Uri.parse(f.url));
    request.headers.set('range', 'bytes=0-');
    final response = await request.close();
    final first = Completer<void>();
    final done = Completer<void>();
    var count = 0;
    late StreamSubscription<List<int>> sub;
    sub = response.listen((chunk) {
      count += chunk.length;
      if (!first.isCompleted) {
        sub.pause();
        first.complete();
      }
    }, onDone: done.complete, onError: done.completeError);
    addTearDown(sub.cancel);
    await first.future;
    await f
        .until(() => (f.control.cacheSnapshot()?.forwardBytes ?? 0) > 32 * mib);
    sub.resume();
    await done.future;
    expect(count, 180 * mib);
    expect(f.originBytes, lessThanOrEqualTo(180 * mib + 512));
    expect(f.cache.hitBytes, greaterThan(32 * mib));
  }, timeout: const Timeout(Duration(seconds: 35)));

  test('rolling read ahead exceeds 32 MiB and replenishes a consumed window',
      () async {
    final f = await RollingFixture.create();
    addTearDown(f.close);
    await f.read(0, 511);
    await f.until(
        () => (f.control.cacheSnapshot()?.forwardBytes ?? 0) >= 128 * mib);
    expect(f.cache.storedBytes, 128 * mib + 512);
    final filled = f.requests.length;
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(f.requests.length, filled);
    final originBefore = f.originBytes;
    await f.read(512, 16 * mib + 511);
    expect(f.originBytes, originBefore,
        reason: 'Completed prefetched blocks must not be re-downloaded');
    await f.until(
        () => (f.control.cacheSnapshot()?.forwardBytes ?? 0) >= 128 * mib);
    expect(f.cache.storedBytes, 144 * mib + 512);
    expect(f.requests.skip(2).every((r) => r.$2 - r.$1 + 1 <= 2 * mib), isTrue);
  }, timeout: const Timeout(Duration(seconds: 35)));

  test('pause cancels scheduled and active prefetch; resume can refill',
      () async {
    final f =
        await RollingFixture.create(delay: const Duration(milliseconds: 50));
    addTearDown(f.close);
    await f.read(0, 511);
    f.control.setPlaybackActive(false);
    final paused = f.requests.length;
    await Future<void>.delayed(const Duration(milliseconds: 650));
    expect(f.requests.length, paused);
    f.control.setPlaybackActive(true);
    await f.until(() => f.requests.length > paused);
    f.control.setPlaybackActive(false);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final afterCancel = f.requests.length;
    await Future<void>.delayed(const Duration(milliseconds: 650));
    expect(f.requests.length, afterCancel);
    // Foreground reads remain available while speculative work is paused.
    await f.read(150 * mib, 150 * mib + 511);
  });

  test('seek invalidates pending prefetch; new read moves the cursor',
      () async {
    final f = await RollingFixture.create();
    addTearDown(f.close);
    await f.read(0, 511);
    f.control.cancelReadAhead();
    final before = f.requests.length;
    await Future<void>.delayed(const Duration(milliseconds: 650));
    expect(f.requests.length, before);
    await f.read(140 * mib, 140 * mib + 511);
    await f.until(() => f.requests.length > before + 1);
    expect(f.requests.skip(before).every((r) => r.$1 >= 140 * mib), isTrue);
  });

  test('close waits for read ahead and removes all files and connections',
      () async {
    final f =
        await RollingFixture.create(delay: const Duration(milliseconds: 40));
    addTearDown(f.close);
    await f.read(0, 511);
    await f.until(() => f.requests.length > 2);
    await f.relay.close();
    await f.until(() => f.active == 0);
    expect(f.cache.storedBytes, 0);
    expect(f.cache.queuedBytes, 0);
    expect(await f.root.list(recursive: true).where((e) => e is File).isEmpty,
        isTrue);
    final requests = f.requests.length;
    await Future<void>.delayed(const Duration(milliseconds: 650));
    expect(f.requests.length, requests);
  });

  test('measured slow origin does not expand the disk window', () async {
    final f = await RollingFixture.create(
        delay: const Duration(milliseconds: 40), bitrate: 2000000000);
    addTearDown(f.close);
    await f.read(0, 511);
    final requests = f.requests.length;
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(f.requests.length, requests);
  });
}

class RollingFixture {
  RollingFixture(this.root, this.server, this.cache, this.delay, this.bitrate);
  final Directory root;
  final HttpServer server;
  final PlaybackRelayDiskCache cache;
  final Duration delay;
  final int bitrate;
  final requests = <(int, int)>[];
  int originBytes = 0;
  int active = 0;
  final client = HttpClient();
  late final PlaybackStreamRelayService relay;
  late final String url;
  PlaybackRelayCacheControl get control => relay as PlaybackRelayCacheControl;
  void memoryReady() => (relay as PlaybackRelayBufferControl)
      .updateBufferState(memoryReady: true, url: url);
  Timer? bufferReporting;

  static Future<RollingFixture> create(
      {Duration delay = Duration.zero,
      int bitrate = 0,
      Duration requestTimeout = const Duration(seconds: 15)}) async {
    final root = await Directory.systemTemp.createTemp('rolling-cache-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final cache = PlaybackRelayDiskCache(
        capacityBytes: 256 * mib,
        directoryProvider: () => root.createTemp(),
        freeBytes: () async => 4 * 1024 * mib);
    final f = RollingFixture(root, server, cache, delay, bitrate);
    server.listen(f.serve);
    f.relay = createPlaybackStreamRelayService(
        diskCache: cache, requestTimeout: requestTimeout);
    final target = await f.relay.prepareTarget(PlaybackTarget(
        title: 'test',
        sourceId: 'test',
        sourceName: 'test',
        sourceKind: MediaSourceKind.nas,
        bitrate: bitrate,
        streamUrl: 'http://127.0.0.1:${server.port}/media'));
    f.url = target.streamUrl;
    f.memoryReady();
    f.bufferReporting = Timer.periodic(
        const Duration(milliseconds: 500), (_) => f.memoryReady());
    return f;
  }

  Future<void> serve(HttpRequest request) async {
    const total = 180 * mib;
    active++;
    try {
      final range = RegExp(r'^bytes=(\d+)-(\d*)$')
          .firstMatch(request.headers.value('range') ?? '');
      final start = range == null ? 0 : int.parse(range[1]!);
      final end = range == null || range[2]!.isEmpty
          ? total - 1
          : min(total - 1, int.parse(range[2]!));
      requests.add((start, end));
      request.response.statusCode = range == null ? 200 : 206;
      request.response.headers.contentType = ContentType.binary;
      request.response.headers.set('etag', '"stable"');
      request.response.contentLength = end - start + 1;
      if (range != null) {
        request.response.headers
            .set('content-range', 'bytes $start-$end/$total');
      }
      if (delay != Duration.zero) await Future<void>.delayed(delay);
      final chunk = Uint8List(64 * 1024);
      for (var at = start; at <= end; at += chunk.length) {
        final count = min(chunk.length, end - at + 1);
        final bytes =
            at == 0 ? Uint8List(count) : Uint8List.sublistView(chunk, 0, count);
        if (at == 0) bytes.setRange(4, 8, [102, 116, 121, 112]);
        request.response.add(bytes);
        originBytes += count;
        await request.response.flush();
      }
    } catch (_) {
      // The tests deliberately abort speculation at pause, seek and close.
    } finally {
      try {
        await request.response.close();
      } catch (_) {}
      active--;
    }
  }

  Future<void> read(int start, int end) async {
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set('range', 'bytes=$start-$end');
    final response = await request.close();
    expect(response.statusCode, 206);
    final length = await response.fold<int>(0, (n, c) => n + c.length);
    expect(length, end - start + 1);
    await cache.flushWrites();
  }

  Future<void> until(bool Function() ready) async {
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (!ready()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Timed out waiting for cache state');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<void> close() async {
    bufferReporting?.cancel();
    client.close(force: true);
    await relay.close();
    await server.close(force: true);
    if (await root.exists()) await root.delete(recursive: true);
  }
}
