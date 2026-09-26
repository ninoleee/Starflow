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

const _mib = 1024 * 1024;
const _wait = Duration(seconds: 5);
const _foregroundWait = Duration(seconds: 2);

enum _Invalidation { seek, clear }

void main() {
  test('disk prefetch needs a fresh high-water permission', () async {
    final f = await _Fixture.create(autoReady: false);
    addTearDown(f.close);
    _expectComplete(await f.read(0, 511), 512);
    final before = f.requests.length;
    await Future<void>.delayed(const Duration(milliseconds: 650));
    expect(f.requests.length, before);
    final first = f.holdNext(start: 512);
    f.reportReady();
    await first.entered.future.timeout(_wait);
    (f.relay as PlaybackRelayBufferControl)
        .updateBufferState(memoryReady: false);
    first.release();
    await Future<void>.delayed(const Duration(milliseconds: 650));
    final stopped = f.requests.length;
    await Future<void>.delayed(const Duration(milliseconds: 650));
    expect(f.requests.length, stopped);
    _expectComplete(await f.read(4 * _mib, 4 * _mib + 511), 512);
  });

  test('expired buffer permission cancels active speculation', () async {
    final f = await _Fixture.create(autoReady: false);
    addTearDown(f.close);
    _expectComplete(await f.read(0, 511), 512);
    final first = f.holdNext(start: 512);
    f.reportReady();
    await first.entered.future.timeout(_wait);
    await Future<void>.delayed(const Duration(milliseconds: 4100));
    first.release();
    _expectComplete(await f.read(4 * _mib, 4 * _mib + 511), 512);
    final stopped = f.requests.length;
    await Future<void>.delayed(const Duration(milliseconds: 650));
    expect(f.requests.length, stopped);
  });

  test('foreground adopts an in-flight range before it finishes or writes',
      () async {
    final f = await _Fixture.create(autoReady: false);
    addTearDown(f.close);
    final bodyGate = f.holdBodyAfter(64 * 1024);
    _expectComplete(await f.read(0, 511), 512);
    f.reportReady();
    await bodyGate.entered.future.timeout(_wait);
    final delivered = Completer<void>();
    final read = f.read(512, 2 * _mib + 511, onBytes: (_) {
      if (!delivered.isCompleted) delivered.complete();
    });
    try {
      await delivered.future.timeout(const Duration(milliseconds: 700),
          onTimeout: () => fail('In-flight bytes must feed the player before '
              'the remaining origin body or disk block is ready.'));
      expect(f.requests.where((r) => r.start == 512), hasLength(1));
      (f.relay as PlaybackRelayBufferControl)
          .updateBufferState(memoryReady: false);
    } finally {
      bodyGate.release();
    }
    _expectComplete(await read.timeout(_wait), 2 * _mib);
    expect(f.requests.where((r) => r.start == 512), hasLength(1));
    expect(f.requests.where((r) => r.start > 512), isEmpty);
  });

  test('partial adoption finishes without waiting for unused origin bytes',
      () async {
    final f = await _Fixture.create(autoReady: false);
    addTearDown(f.close);
    final bodyGate = f.holdBodyAfter(64 * 1024);
    _expectComplete(await f.read(0, 511), 512);
    f.reportReady();
    await bodyGate.entered.future.timeout(_wait);
    try {
      _expectComplete(await f.read(512, 1023).timeout(_foregroundWait), 512);
      expect(bodyGate.released, isFalse);
      expect(f.requests.where((r) => r.start == 512), hasLength(1));
    } finally {
      (f.relay as PlaybackRelayBufferControl)
          .updateBufferState(memoryReady: false);
      bodyGate.release();
    }
  });

  test('foreground receives bytes before a slow 2 MiB range finishes',
      () async {
    final f = await _Fixture.create();
    addTearDown(f.close);
    f.control.setPlaybackActive(false);
    final bodyGate = f.holdBodyAfter(64 * 1024);
    final firstByte = Completer<void>();
    final read = f.read(0, 2 * _mib - 1, onBytes: (_) {
      if (!firstByte.isCompleted) firstByte.complete();
    });
    try {
      await bodyGate.entered.future.timeout(_wait);
      await firstByte.future.timeout(const Duration(milliseconds: 500),
          onTimeout: () => fail('Available origin bytes were held until the '
              'whole cache block completed.'));
      expect(bodyGate.released, isFalse);
    } finally {
      bodyGate.release();
      _expectComplete(await read.timeout(_wait), 2 * _mib);
    }
  });

  test('cached continuation does not wait for unrelated read ahead', () async {
    final f = await _Fixture.create(capacityBytes: 32 * _mib);
    addTearDown(f.close);
    await f.seed(0, 6 * _mib);
    final localGate = _Gate();
    f.cache.readGate = (2 * _mib, localGate);
    final originGate = f.holdNext(start: 6 * _mib);
    final read = f.read(0, 6 * _mib - 1);
    try {
      await localGate.entered.future.timeout(_wait,
          onTimeout: () => fail('Local gate not reached: '
              '${f.cache.storedBytes}, ${f.cache.hitBytes}'));
      await originGate.entered.future.timeout(_wait,
          onTimeout: () => fail('Read ahead not started: '
              '${f.requests.map((r) => (r.start, r.end)).toList()}'));
      localGate.release();
      _expectComplete(
          await read.timeout(const Duration(milliseconds: 700),
              onTimeout: () => fail('Cached bytes waited behind speculative '
                  'origin work beyond the requested range.')),
          6 * _mib);
      expect(originGate.released, isFalse);
      expect(f.cache.hitBytes, 6 * _mib);
    } finally {
      f.control.setPlaybackActive(false);
      localGate.release();
      originGate.release();
      await read.timeout(_wait);
    }
  });

  test('disconnected open range stops fetching subsequent origin ranges',
      () async {
    final f = await _Fixture.create(total: 16 * _mib);
    addTearDown(f.close);
    f.control.setPlaybackActive(false);
    final bodyGate = f.holdBodyAfter(64 * 1024);
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.getUrl(f.relayUri);
    request.headers.set('range', 'bytes=0-');
    final response = await request.close();
    final first = Completer<void>();
    final subscription = response.listen((_) {
      if (!first.isCompleted) first.complete();
    }, onError: (Object _) {});
    addTearDown(subscription.cancel);
    await first.future.timeout(_wait);
    await bodyGate.entered.future.timeout(_wait);
    client.close(force: true);
    await subscription.cancel();
    bodyGate.release();
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(f.requests.where((r) => r.start >= 2 * _mib), isEmpty,
        reason: 'A disconnected player must not keep downloading the movie.');
    final resumed = f.holdNext(start: 8 * _mib + 512);
    f.control.setPlaybackActive(true);
    _expectComplete(await f.read(8 * _mib, 8 * _mib + 511), 512);
    await resumed.entered.future.timeout(_foregroundWait,
        onTimeout: () => fail('Disconnected reader still blocks read ahead.'));
    f.control.setPlaybackActive(false);
    resumed.release();
  });

  test('cancelling prefetch blocked on directory does not block foreground',
      () async {
    final disk = _Gate();
    final f = await _Fixture.create(directoryGate: disk);
    addTearDown(f.close);
    final prefetchGate = f.holdNext(start: 512);
    _expectComplete(await f.read(0, 511), 512);
    await disk.entered.future.timeout(_wait);

    await prefetchGate.entered.future.timeout(_wait);
    final prefetched = prefetchGate.request!;
    expect(prefetched.start, 512);
    expect(prefetched.end - prefetched.start + 1, 2 * _mib);
    prefetchGate.release();
    await prefetched.sent.future.timeout(_wait);
    // Observe the real flush call without replacing its future. This proves
    // cancellation interrupts disk waiting, not an unfinished origin download.
    await f.cache.flushEntered.future.timeout(_wait);
    expect(f.cache.queuedBytes, greaterThanOrEqualTo(512 + 2 * _mib));
    expect(f.cache.storedBytes, 0);
    final foregroundGate = f.holdNext(start: 6 * _mib);
    final foreground = f.read(6 * _mib, 6 * _mib + 511);
    try {
      await foregroundGate.entered.future.timeout(_foregroundWait,
          onTimeout: () =>
              fail('New foreground did not reach origin while the directory '
                  'provider was held; cancelled prefetch still blocks it.'));
      foregroundGate.release();
      _expectComplete(await foreground.timeout(_foregroundWait), 512);
      expect(disk.released, isFalse,
          reason: 'Foreground must finish before the disk gate is released.');
    } finally {
      f.control.setPlaybackActive(false);
      foregroundGate.release();
      disk.release();
    }
  });

  for (final changeOrigin in [true, false]) {
    test(
        'probe without validator cannot produce a mixed foreground body, '
        'changeOrigin=$changeOrigin', () async {
      final f =
          await _Fixture.create(total: 4 * _mib, omitProbeValidator: true);
      addTearDown(f.close);
      f.control.setPlaybackActive(false);
      // A single full-range origin response stays version A. If the relay
      // splits it, the next origin request sees same-size version B instead.
      f.replaceFrom = changeOrigin ? 2 * _mib : null;
      final result = await f.read(0, f.total - 1).timeout(_wait);

      expect(result.status, HttpStatus.partialContent);
      expect(result.advertisedLength, f.total);
      expect(result.firstMismatch, isNull,
          reason: 'The client must receive no version B bytes after A. '
              'Received ${result.bytes} bytes; error: ${result.error}');
      if (changeOrigin) {
        if (result.error == null) {
          _expectComplete(result, f.total);
        } else {
          expect(result.error, isA<HttpException>(),
              reason: 'Reject the splice as an incomplete HTTP response.');
          expect(result.bytes, greaterThan(0));
          expect(result.bytes, lessThan(f.total));
        }
      } else {
        _expectComplete(result, f.total);
      }
      final second = f.requests.where((request) => request.start >= 2 * _mib);
      if (second.isNotEmpty) {
        expect(second.first.ifRange, '"A"',
            reason: 'A split response must retain its first foreground ETag.');
      }
    });
  }

  for (final invalidation in _Invalidation.values) {
    test('old foreground cannot restart prefetch after ${invalidation.name}',
        () async {
      final f = await _Fixture.create();
      addTearDown(f.close);
      final oldGate = f.holdNext(start: 0);
      final oldRead = f.read(0, 511);
      await oldGate.entered.future.timeout(_wait);
      await f.invalidate(invalidation);
      final before = f.requests.length;
      oldGate.release();
      final result = await oldRead.timeout(_wait);
      expect(result.error, isNot(isA<TimeoutException>()));

      // This bounded quiet window tests the real 500 ms scheduling timer.
      // The old request and invalidation themselves are synchronized by HTTP.
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(f.requests.skip(before), isEmpty,
          reason: 'No new foreground request authorized more read ahead.');
    });

    test(
        'old foreground cannot replace newer cursor after ${invalidation.name}',
        () async {
      final f = await _Fixture.create();
      addTearDown(f.close);
      final oldGate = f.holdNext(start: 0);
      final oldRead = f.read(0, 511);
      await oldGate.entered.future.timeout(_wait);
      await f.invalidate(invalidation);
      f.control.setPlaybackActive(false);

      const newerStart = 4 * _mib;
      const newerCursor = newerStart + 512;
      const markerBytes = 1024;
      _expectComplete(await f.read(newerStart, newerCursor - 1), 512);
      // A unique contiguous span exposes the cursor through the public cache
      // snapshot, without inspecting private scheduler state.
      await f.seed(newerCursor, markerBytes);
      expect(f.control.cacheSnapshot()?.forwardBytes, markerBytes);
      oldGate.release();
      final result = await oldRead.timeout(_wait);
      expect(result.error, isNot(isA<TimeoutException>()));
      expect(f.control.cacheSnapshot()?.forwardBytes, markerBytes,
          reason: 'Late old foreground completion must not rewind the cursor.');

      final resumed = f.holdNext();
      f.control.setPlaybackActive(true);
      await resumed.entered.future.timeout(_wait);
      expect(resumed.request!.start, newerCursor + markerBytes,
          reason: 'Resume must continue after the newer cached span.');
      f.control.setPlaybackActive(false);
      resumed.release();
    });
  }
}

void _expectComplete(_ReadResult result, int length) {
  expect(result.error, isNull);
  expect(result.status, HttpStatus.partialContent);
  expect(result.advertisedLength, length);
  expect(result.bytes, length);
  expect(result.firstMismatch, isNull);
}

int _byteAt(int offset, {bool changed = false}) {
  if (offset >= 4 && offset < 8) return const [102, 116, 121, 112][offset - 4];
  return (offset * 17 + offset ~/ 251 + (changed ? 113 : 0)) % 256;
}

class _ReadResult {
  int? status;
  int? advertisedLength;
  int bytes = 0;
  int? firstMismatch;
  Object? error;
}

class _Gate {
  final entered = Completer<void>();
  final _release = Completer<void>();

  bool get released => _release.isCompleted;

  Future<void> hold() async {
    if (!entered.isCompleted) entered.complete();
    await _release.future;
  }

  void release() {
    if (!_release.isCompleted) _release.complete();
  }
}

class _OriginRequest {
  _OriginRequest(this.start, this.end, this.ifRange);

  final int start;
  final int end;
  final String? ifRange;
  final sent = Completer<void>();
}

class _OriginGate extends _Gate {
  _OriginGate(this.start);

  final int? start;
  _OriginRequest? request;
}

class _ObservedCache extends PlaybackRelayDiskCache {
  _ObservedCache(
      Future<Directory> Function() directoryProvider, int capacityBytes)
      : super(
          capacityBytes: capacityBytes,
          directoryProvider: directoryProvider,
          freeBytes: () async => 4 * 1024 * _mib,
        );

  final flushEntered = Completer<void>();
  (int, _Gate)? readGate;

  @override
  Future<PlaybackCachedResponse?> read(String key, String? range) async {
    final gate = readGate;
    if (gate != null && range?.startsWith('bytes=${gate.$1}-') == true) {
      await gate.$2.hold();
    }
    return super.read(key, range);
  }

  @override
  Future<void> flushWrites() {
    final pending = super.flushWrites();
    if (!flushEntered.isCompleted) flushEntered.complete();
    return pending;
  }
}

class _Fixture {
  _Fixture(this.root, this.server, this.total, this.omitProbeValidator,
      this.directoryGate, int capacityBytes)
      : cache = _ObservedCache(() async {
          await directoryGate?.hold();
          return root.createTemp('session-');
        }, capacityBytes);

  final Directory root;
  final HttpServer server;
  final int total;
  final bool omitProbeValidator;
  final _Gate? directoryGate;
  final _ObservedCache cache;
  final client = HttpClient();
  final requests = <_OriginRequest>[];
  final _gates = <_OriginGate>[];
  final _bodyGates = <int, _Gate>{};
  final _handlers = <Future<void>>{};
  final _errors = <Object>[];
  late final PlaybackStreamRelayService relay;
  late final Uri relayUri;
  Timer? bufferReporting;
  int? replaceFrom;
  bool _preparing = true;

  PlaybackRelayCacheControl get control => relay as PlaybackRelayCacheControl;

  static Future<_Fixture> create({
    int total = 8 * _mib,
    bool omitProbeValidator = false,
    _Gate? directoryGate,
    int capacityBytes = 8 * _mib,
    bool autoReady = true,
  }) async {
    final root = await Directory.systemTemp.createTemp('read-ahead-race-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final f = _Fixture(
        root, server, total, omitProbeValidator, directoryGate, capacityBytes);
    server.listen((request) {
      final task = f._serve(request);
      f._handlers.add(task);
      unawaited(task.then<void>((_) => f._handlers.remove(task),
          onError: (Object error, StackTrace _) {
        f._handlers.remove(task);
        f._errors.add(error);
      }));
    });
    f.relay = createPlaybackStreamRelayService(diskCache: f.cache);
    final target = await f.relay.prepareTarget(PlaybackTarget(
      title: 'Read ahead races',
      sourceId: 'race',
      sourceName: 'race',
      sourceKind: MediaSourceKind.nas,
      streamUrl: 'http://127.0.0.1:${server.port}/video',
    ));
    f.relayUri = Uri.parse(target.streamUrl);
    expect(f.relayUri.port, isNot(server.port));
    f._preparing = false;
    if (autoReady) {
      f.reportReady();
      f.bufferReporting = Timer.periodic(
          const Duration(milliseconds: 500), (_) => f.reportReady());
    }
    return f;
  }

  void reportReady() => (relay as PlaybackRelayBufferControl)
      .updateBufferState(memoryReady: true, url: relayUri.toString());

  _OriginGate holdNext({int? start}) {
    final gate = _OriginGate(start);
    _gates.add(gate);
    return gate;
  }

  _Gate holdBodyAfter(int bytes) => _bodyGates[bytes] = _Gate();

  Future<void> invalidate(_Invalidation invalidation) async {
    if (invalidation == _Invalidation.seek) {
      control.cancelReadAhead();
    } else {
      await cache.clear().timeout(_wait);
    }
  }

  Future<void> _serve(HttpRequest request) async {
    final parsed = RegExp(r'^bytes=(\d+)-(\d*)$')
        .firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
    final start = parsed == null ? 0 : int.parse(parsed[1]!);
    final end = parsed == null || parsed[2]!.isEmpty
        ? total - 1
        : min(total - 1, int.parse(parsed[2]!));
    final origin = _OriginRequest(
        start, end, request.headers.value(HttpHeaders.ifRangeHeader));
    final probe = _preparing;
    if (request.uri.path == '/video') {
      requests.add(origin);
      for (final gate in _gates) {
        if (gate.request == null &&
            (gate.start == null || gate.start == start)) {
          gate.request = origin;
          await gate.hold();
          break;
        }
      }
    }

    final response = request.response;
    response.statusCode =
        parsed == null ? HttpStatus.ok : HttpStatus.partialContent;
    response.contentLength = end - start + 1;
    response.headers.contentType = ContentType('video', 'mp4');
    final version = replaceFrom != null && start >= replaceFrom!;
    if (!(probe && omitProbeValidator)) {
      response.headers.set(HttpHeaders.etagHeader, version ? '"B"' : '"A"');
    }
    if (parsed != null) {
      response.headers
          .set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$total');
    }
    try {
      for (var at = start; at <= end; at += 64 * 1024) {
        final count = min(64 * 1024, end - at + 1);
        final bytes = Uint8List(count);
        for (var i = 0; i < count; i++) {
          bytes[i] = _byteAt(at + i, changed: version);
        }
        response.add(bytes);
        await response.flush();
        if (request.uri.path == '/video' && !probe) {
          await _bodyGates[at + count - start]?.hold();
        }
      }
      await response.close();
    } on SocketException {
      // Cancellation and validator rejection intentionally close origin reads.
    } on HttpException {
      // The media probe may also stop reading before the origin finishes.
    } finally {
      if (!origin.sent.isCompleted) origin.sent.complete();
      try {
        await response.close();
      } on SocketException {
        // Closing an already cancelled connection is harmless.
      } on HttpException {
        // Closing an already cancelled connection is harmless.
      }
    }
  }

  Future<_ReadResult> read(int start, int end,
      {void Function(int)? onBytes}) async {
    final result = _ReadResult();
    try {
      final request = await client.getUrl(relayUri);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
      final response = await request.close();
      result.status = response.statusCode;
      result.advertisedLength = response.contentLength;
      await for (final chunk in response.timeout(_wait)) {
        for (var i = 0; i < chunk.length; i++) {
          final offset = start + result.bytes + i;
          if (chunk[i] != _byteAt(offset)) result.firstMismatch ??= offset;
        }
        result.bytes += chunk.length;
        onBytes?.call(result.bytes);
      }
    } catch (error) {
      result.error = error;
    }
    return result;
  }

  Future<void> seed(int start, int length) async {
    final request =
        await client.getUrl(Uri.parse('http://127.0.0.1:${server.port}/seed'));
    request.headers
        .set(HttpHeaders.rangeHeader, 'bytes=$start-${start + length - 1}');
    final response = await request.close();
    expect(response.statusCode, HttpStatus.partialContent);
    final writer =
        cache.writer(relayUri.path, response.statusCode, response.headers)!;
    try {
      await for (final chunk in response) {
        await writer.add(chunk);
      }
    } finally {
      writer.close();
    }
    await cache.flushWrites().timeout(_wait);
  }

  Future<void> close() async {
    bufferReporting?.cancel();
    control.setPlaybackActive(false);
    directoryGate?.release();
    cache.readGate?.$2.release();
    for (final gate in _bodyGates.values) {
      gate.release();
    }
    for (final gate in _gates) {
      gate.release();
    }
    client.close(force: true);
    await relay.close().timeout(_wait);
    await server.close(force: true);
    await Future.wait(_handlers.toList()).timeout(_wait);
    if (await root.exists()) await root.delete(recursive: true);
    expect(_errors, isEmpty);
  }
}
