import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/application/playback_relay_disk_cache.dart';

const _mib = 1024 * 1024;

void main() {
  late Directory root;
  late PlaybackRelayDiskCache cache;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('forward-retention-');
  });
  tearDown(() async {
    await cache.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  void create({int capacity = 32, Future<int?> Function()? freeBytes}) {
    cache = PlaybackRelayDiskCache(
      capacityBytes: capacity,
      directoryProvider: () => root.createTemp('session-'),
      freeBytes: freeBytes ?? () async => 4 * 1024 * _mib,
    );
  }

  Future<void> write(int start,
      {String key = 'a', int length = 8, int value = 42}) async {
    final writer = cache.writer(key, 206, _Headers(start, length))!;
    await writer.add(Uint8List(length)..fillRange(0, length, value));
    await cache.flushWrites();
    expect(cache.disabled, false);
    expect(cache.queuedBytes, 0);
    expect(cache.storedBytes, lessThanOrEqualTo(cache.capacityBytes));
    var diskBytes = 0;
    await for (final entry in root.list(recursive: true)) {
      if (entry is File) diskBytes += await entry.length();
    }
    expect(diskBytes, cache.storedBytes);
  }

  Future<void> hit(int start, {String key = 'a', bool exists = true}) async {
    final response = await cache.read(key, 'bytes=$start-${start + 7}');
    expect(response, exists ? isNotNull : isNull);
    if (response != null) {
      expect(await response.handles.single.$1.read(8), List.filled(8, 42));
      await response.close();
    }
  }

  test('recently touched consumed blocks go before backtrack and forward data',
      () async {
    create();
    for (final start in [0, 8, 16, 24]) {
      await write(start);
    }
    await hit(0);
    cache.setReadCursor('a', 16); // Eight-byte bounded backtrack window.
    await write(32);
    await hit(0, exists: false);
    for (final start in [8, 16, 24, 32]) {
      await hit(start);
    }
  });

  test('nearest upcoming wins including incoming admission and backward seek',
      () async {
    create();
    cache.setReadCursor('a', 0);
    for (final start in [0, 16, 24, 32]) {
      await write(start);
    }
    await write(48);
    await hit(48, exists: false);
    await write(8);
    await hit(32, exists: false);
    await hit(8);
    cache.clearReadCursor('a');
    cache.setReadCursor('a', 48);
    await write(48);
    await hit(0, exists: false);
    cache.clearReadCursor('a');
    cache.setReadCursor('a', 0);
    await write(0);
    await hit(48, exists: false);
    await hit(0);
  });

  test('clearing cursor restores LRU instead of rejecting distant writes',
      () async {
    create(capacity: 16);
    cache.setReadCursor('a', 0);
    await write(0);
    await write(8);
    cache.clearReadCursor('a');
    await write(100);
    await hit(0, exists: false);
    await hit(100);
  });

  test('consumed ranges yield to other keys without global distance ranking',
      () async {
    create(capacity: 24);
    await write(0, key: 'b');
    await write(0);
    await write(8);
    cache.setReadCursor('a', 16);
    await hit(0);
    await write(1000, key: 'b');
    await hit(0, exists: false);
    await hit(0, key: 'b');
    await hit(1000, key: 'b');
    await write(16);
    await hit(8, exists: false);
    await hit(16);
  });

  test('LRU across keys prevents a cursor key monopolizing capacity', () async {
    create(capacity: 16);
    cache.setReadCursor('a', 0);
    await write(0);
    await write(8);
    await write(0, key: 'b');
    await hit(0);
    await hit(8, exists: false);
    await hit(0, key: 'b');
  });

  test('opening and active handles stay pinned; full pinned cache drops writes',
      () async {
    create(capacity: 16);
    await write(0);
    await write(8);
    final opening = cache.read('a', 'bytes=0-15');
    cache.setReadCursor('a', 100);
    await write(16);
    final reader = (await opening)!;
    await write(24);
    await hit(16, exists: false);
    await hit(24, exists: false);
    for (final (handle, count) in reader.handles) {
      expect(await handle.read(count), List.filled(count, 42));
    }
    await reader.close();
    await write(24);
    await hit(0, exists: false);
    await hit(24);
  });

  test('backtrack is capped at 8MiB even with a large capacity', () async {
    create(capacity: 40 * _mib);
    cache.setReadCursor('a', 20 * _mib);
    for (var start = 10 * _mib; start < 50 * _mib; start += 2 * _mib) {
      await write(start, length: 2 * _mib);
    }
    await hit(10 * _mib);
    await write(50 * _mib, length: 2 * _mib);
    await hit(10 * _mib, exists: false);
    await hit(12 * _mib);
    await hit(20 * _mib);
  });

  test('rejected large admission does not partially evict smaller blocks',
      () async {
    create(capacity: 24);
    cache.setReadCursor('a', 16);
    for (final start in [0, 8, 16]) {
      await write(start);
    }
    await write(100, length: 24);
    for (final start in [0, 8, 16]) {
      await hit(start);
    }
    await write(200, length: 25);
    expect(cache.storedBytes, 24);
  });

  test('prefix removal and clear discard cursors for reused keys', () async {
    create(capacity: 16);
    for (final removePrefix in [true, false]) {
      cache.setReadCursor('a', 0);
      await write(0);
      if (removePrefix) {
        await cache.removePrefix('a');
      } else {
        await cache.clear();
      }
      await write(0);
      await write(8);
      await write(100);
      await hit(100);
      await cache.clear();
    }
  });

  test('negative cursor clamps to zero and disabled capacity stores no files',
      () async {
    create(capacity: 8);
    cache.setReadCursor('a', -100);
    await write(0);
    await write(8);
    await hit(0);
    await hit(8, exists: false);
    await cache.close();
    create(capacity: 0);
    expect(cache.writer('a', 206, _Headers(0, 8)), isNull);
    expect(cache.storedBytes, 0);
  });

  for (final typed in [false, true]) {
    test('caller mutation cannot change pending or queued bytes, typed=$typed',
        () async {
      final gate = Completer<int?>();
      create(capacity: 32, freeBytes: () => gate.future);
      final backing = Uint8List.fromList([99, 1, 2, 3, 4, 99]);
      final List<int> first =
          typed ? Uint8List.sublistView(backing, 1, 5) : [1, 2, 3, 4];
      final List<int> second =
          typed ? Uint8List.fromList([5, 6, 7, 8]) : [5, 6, 7, 8];
      final writer = cache.writer('a', 206, _Headers(0, 8))!;
      final pending = writer.add(first);
      first.fillRange(0, 4, 77);
      await pending;
      expect(cache.queuedBytes, 4);
      final queued = writer.add(second);
      second.fillRange(0, 4, 88);
      await queued;
      gate.complete(4 * 1024 * _mib);
      await cache.flushWrites();
      final reader = (await cache.read('a', 'bytes=0-7'))!;
      expect(await reader.handles.single.$1.read(8), [1, 2, 3, 4, 5, 6, 7, 8]);
      await reader.close();
      expect(cache.queuedBytes, 0);
    });
  }

  test(
      'multi-block allocation keeps queue bounded and accepted copies isolated',
      () async {
    final gate = Completer<int?>();
    create(capacity: 16 * _mib, freeBytes: () => gate.future);
    final bytes = Uint8List(10 * _mib)..fillRange(0, 10 * _mib, 42);
    final writer = cache.writer('a', 206, _Headers(0, bytes.length))!;
    final adding = writer.add(bytes);
    bytes.fillRange(0, bytes.length, 99);
    await adding;
    expect(writer.accepting, false);
    expect(cache.queuedBytes, PlaybackRelayDiskCache.maxWriteQueueBytes);
    expect(cache.droppedBytes, 2 * _mib);
    gate.complete(4 * 1024 * _mib);
    await cache.flushWrites();
    expect(cache.storedBytes, 8 * _mib);
    expect(cache.queuedBytes, 0);
    for (var start = 0; start < 8 * _mib; start += 2 * _mib) {
      await hit(start);
    }
    await hit(8 * _mib, exists: false);
  });
}

class _Headers extends Fake implements HttpHeaders {
  _Headers(this.start, this.contentLength);
  final int start;
  @override
  final int contentLength;
  @override
  ContentType get contentType => ContentType.binary;
  @override
  String? value(String name) => switch (name) {
        HttpHeaders.contentRangeHeader =>
          'bytes $start-${start + contentLength - 1}/${128 * _mib}',
        HttpHeaders.etagHeader => '"stable"',
        _ => null,
      };
}
