import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/storage/local_storage_models.dart';
import 'package:starflow/features/playback/application/playback_relay_disk_cache.dart';

const _mib = 1024 * 1024;
const _blockSize = 2 * _mib;
const _payloadSize = 8;
final _payload = List<int>.filled(_payloadSize, 42);

void main() {
  test('inspect summary includes active blocks and cleanup removes them',
      () async {
    final root = await Directory.systemTemp.createTemp('playback-summary-');
    addTearDown(() => root.delete(recursive: true));
    final cache = PlaybackRelayDiskCache(
      capacityBytes: 8 * 1024 * 1024,
      directoryProvider: () => root.createTemp('session-'),
      freeBytes: () async => 2 * 1024 * 1024 * 1024,
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.statusCode = HttpStatus.partialContent;
      request.response.contentLength = 2 * 1024 * 1024;
      request.response.headers.set(
        'content-range',
        'bytes 0-${2 * 1024 * 1024 - 1}/${2 * 1024 * 1024}',
      );
      request.response.headers.set('etag', '"summary"');
      request.response.add(List<int>.filled(2 * 1024 * 1024, 7));
      await request.response.close();
    });
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/summary'),
    );
    final response = await request.close();
    final headers = response.headers;
    final writer = cache.writer(
      'session/media',
      HttpStatus.partialContent,
      headers,
    );
    expect(writer, isNotNull);
    await writer!.add(List<int>.filled(2 * 1024 * 1024, 7));
    await cache.flushWrites();
    final summary = await PlaybackRelayDiskCache.inspectSummary();
    expect(summary.type, LocalStorageCacheType.playbackDiskCache);
    expect(summary.entryCount, greaterThanOrEqualTo(1));
    expect(summary.totalBytes, greaterThanOrEqualTo(2 * 1024 * 1024));
    await cache.clear();
    final cleared = await PlaybackRelayDiskCache.inspectSummary();
    expect(cleared.totalBytes, lessThan(summary.totalBytes));
    await cache.close();
  });

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('disk-cache-reserve-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  PlaybackRelayDiskCache createCache({
    int capacityBytes = 256 * _mib,
    Future<int?> Function()? freeBytes,
    Future<Directory> Function()? directoryProvider,
  }) {
    final cache = PlaybackRelayDiskCache(
      capacityBytes: capacityBytes,
      directoryProvider: directoryProvider ?? () => root.createTemp('session-'),
      freeBytes: freeBytes ?? () async => 4 * 1024 * _mib,
    );
    addTearDown(cache.close);
    return cache;
  }

  for (final (capacityMiB, reserveMiB) in [
    (256, 512),
    (1024, 512),
    (2048, 512),
    (4096, 1024),
    (8192, 2048),
  ]) {
    for (final delta in [-1, 0, 1]) {
      test(
          '${capacityMiB}MiB capacity reserves ${reserveMiB}MiB '
          'plus write headroom, boundary delta=$delta', () async {
        final cache = createCache(
          capacityBytes: capacityMiB * _mib,
          freeBytes: () async =>
              reserveMiB * _mib + _blockSize + _payloadSize + delta,
        );
        await _write(cache, 'owner/media');

        final allowed = delta >= 0;
        expect(cache.disabled, !allowed);
        expect(cache.disabledReason, allowed ? isNull : 'low_space');
        expect(cache.storedBytes, allowed ? _payloadSize : 0);
        expect(
            cache.storedBytesForPrefix('owner/'), allowed ? _payloadSize : 0);
        expect(cache.writtenBytes, allowed ? _payloadSize : 0);
        expect(await _fileBytes(root), cache.storedBytes);
        expect(cache.queuedBytes, 0);
        final hit = await cache.read('owner/media', null);
        expect(hit, allowed ? isNotNull : isNull);
        await hit?.close();
        if (!allowed) {
          expect(cache.writer('owner/next', 200, _CacheHeaders()), isNull);
        }
      });
    }
  }

  for (final freeMiB in [511, 512]) {
    test('${freeMiB}MiB free cannot consume the minimum reserve', () async {
      final cache = createCache(freeBytes: () async => freeMiB * _mib);
      await _write(cache, 'owner/media');
      expect(cache.disabledReason, 'low_space');
      expect(cache.storedBytesForPrefix('owner/'), 0);
      expect(await cache.read('owner/media', null), isNull);
      expect(await _fileBytes(root), 0);
    });
  }

  test('low space disables caching and removes earlier committed bytes',
      () async {
    final cache = createCache(
      freeBytes: () async => 512 * _mib + _blockSize + _payloadSize,
    );
    await _write(cache, 'owner/first');
    expect(cache.storedBytesForPrefix('owner/'), _payloadSize);
    await _write(cache, 'owner/second');
    expect(cache.disabled, true);
    expect(cache.disabledReason, 'low_space');
    expect(cache.storedBytes, 0);
    expect(cache.storedBytesForPrefix('owner/'), 0);
    expect(cache.writtenBytes, _payloadSize);
    expect(await cache.read('owner/first', null), isNull);
    expect(await _fileBytes(root), 0);
  });

  test('unknown space falls back without writing or returning stale hits',
      () async {
    final cache = createCache(freeBytes: () async => null);
    await _write(cache, 'owner/media');
    expect(cache.disabled, true);
    expect(cache.disabledReason, 'space_unknown');
    expect(cache.storedBytesForPrefix('owner/'), 0);
    expect(await cache.read('owner/media', null), isNull);
    expect(cache.writer('owner/next', 200, _CacheHeaders()), isNull);
    expect(await _fileBytes(root), 0);
  });

  test('file write failure falls back and clear permits a fresh write',
      () async {
    final missing = Directory('${root.path}/missing/session');
    final cache = createCache(directoryProvider: () async => missing);
    await _write(cache, 'owner/media');
    expect(cache.disabled, true);
    expect(cache.disabledReason, 'write_failure');
    expect(cache.storedBytesForPrefix('owner/'), 0);
    expect(await _fileBytes(root), 0);
    expect(cache.queuedBytes, 0);
    expect(await cache.read('owner/media', null), isNull);
    expect(cache.writer('owner/next', 200, _CacheHeaders()), isNull);

    await cache.clear();
    await missing.create(recursive: true);
    await _write(cache, 'owner/media');
    expect(cache.disabled, false);
    expect(cache.disabledReason, isNull);
    expect(cache.storedBytesForPrefix('owner/'), _payloadSize);
    expect(await _fileBytes(root), _payloadSize);
  });

  test('prefix bytes exclude pending and queued writes until commit', () async {
    final gate = Completer<int?>();
    final cache = createCache(freeBytes: () => gate.future);
    addTearDown(() {
      if (!gate.isCompleted) gate.complete(4 * 1024 * _mib);
    });
    final writer = cache.writer('owner/media', 200, _CacheHeaders())!;
    await writer.add(_payload.sublist(0, 4));
    expect(cache.queuedBytes, 4);
    expect(cache.storedBytesForPrefix('owner/'), 0);
    await writer.add(_payload.sublist(4));
    expect(cache.queuedBytes, _payloadSize);
    expect(cache.storedBytesForPrefix('owner/'), 0);

    gate.complete(4 * 1024 * _mib);
    await cache.flushWrites();
    expect(cache.storedBytesForPrefix('owner/'), _payloadSize);
    expect(await _fileBytes(root), _payloadSize);
    expect(cache.queuedBytes, 0);
  });

  test('prefix bytes isolate owners and do not accumulate duplicate writes',
      () async {
    final cache = createCache();
    expect(cache.storedBytesForPrefix(''), 0);
    await _write(cache, 'owner/1/video');
    await _write(cache, 'owner/1/subtitle');
    await _write(cache, 'owner/10/video');
    await _write(cache, 'owner/1/video');

    expect(cache.storedBytesForPrefix('owner/1/'), 2 * _payloadSize);
    expect(cache.storedBytesForPrefix('owner/10/'), _payloadSize);
    expect(cache.storedBytesForPrefix('missing/'), 0);
    expect(cache.storedBytesForPrefix(''), 3 * _payloadSize);
    expect(cache.storedBytesForPrefix(''), cache.storedBytes);
    expect(cache.writtenBytes, 3 * _payloadSize);
    expect(await _fileBytes(root), cache.storedBytes);
  });

  test('prefix bytes sum disjoint blocks of the same resource', () async {
    final cache = createCache();
    for (final start in [0, 16]) {
      await _write(cache, 'owner/media',
          status: 206,
          headers: _CacheHeaders(contentRange: 'bytes $start-${start + 7}/24'));
    }
    expect(cache.storedBytesForPrefix('owner/'), 2 * _payloadSize);
    expect(await _fileBytes(root), 2 * _payloadSize);
    expect(await cache.read('owner/media', null), isNull);
  });

  test('prefix bytes shrink on LRU eviction instead of tracking total writes',
      () async {
    final cache = createCache(capacityBytes: 2 * _payloadSize);
    await _write(cache, 'owner/1/old');
    await _write(cache, 'owner/2/video');
    await _write(cache, 'owner/1/new');

    expect(cache.writtenBytes, 3 * _payloadSize);
    expect(cache.storedBytesForPrefix('owner/1/'), _payloadSize);
    expect(cache.storedBytesForPrefix('owner/2/'), _payloadSize);
    expect(cache.storedBytesForPrefix(''), 2 * _payloadSize);
    expect(await cache.read('owner/1/old', null), isNull);
    expect(await _fileBytes(root), cache.storedBytes);
  });

  test('resource replacement reports retained bytes rather than write history',
      () async {
    final cache = createCache();
    await _write(cache, 'owner/media');
    await _write(cache, 'owner/media', headers: _CacheHeaders(etag: '"v2"'));
    expect(cache.writtenBytes, 2 * _payloadSize);
    expect(cache.storedBytesForPrefix('owner/'), _payloadSize);
    expect(await _fileBytes(root), _payloadSize);
  });

  test('removePrefix removes only matching files and pending writers',
      () async {
    final cache = createCache();
    await _write(cache, 'owner/1/video');
    await _write(cache, 'owner/1/subtitle');
    await _write(cache, 'owner/10/video');
    final removedReader = await cache.read('owner/1/video', null);
    final keptReader = await cache.read('owner/10/video', null);
    expect(removedReader, isNotNull);
    expect(keptReader, isNotNull);
    final removedWriter =
        cache.writer('owner/1/pending', 200, _CacheHeaders())!;
    final keptWriter = cache.writer('owner/10/pending', 200, _CacheHeaders())!;
    await removedWriter.add(_payload.sublist(0, 4));
    await keptWriter.add(_payload.sublist(0, 4));

    await cache.removePrefix('owner/1/');
    expect(cache.disabled, false);
    expect(removedWriter.accepting, false);
    expect(keptWriter.accepting, true);
    expect(cache.queuedBytes, 4);
    expect(cache.storedBytesForPrefix('owner/1/'), 0);
    expect(cache.storedBytesForPrefix('owner/10/'), _payloadSize);
    expect(await cache.read('owner/1/video', null), isNull);
    await expectLater(removedReader!.handles.single.$1.length(),
        throwsA(isA<FileSystemException>()));
    expect(await keptReader!.handles.single.$1.length(), _payloadSize);
    await keptReader.close();
    expect(await _fileBytes(root), _payloadSize);

    await removedWriter.add(_payload.sublist(4));
    await keptWriter.add(_payload.sublist(4));
    await cache.flushWrites();
    expect(cache.storedBytesForPrefix('owner/1/'), 0);
    expect(cache.storedBytesForPrefix('owner/10/'), 2 * _payloadSize);
    await cache.removePrefix('owner/1/');
    await cache.removePrefix('missing/');
    expect(cache.storedBytes, 2 * _payloadSize);
    await _write(cache, 'owner/1/fresh');
    expect(cache.storedBytesForPrefix('owner/1/'), _payloadSize);
    expect(await _fileBytes(root), cache.storedBytes);
  });

  test('clear zeroes every prefix and fresh writes start from current usage',
      () async {
    final cache = createCache();
    await _write(cache, 'owner/1/video');
    await _write(cache, 'owner/2/video');
    final pending = cache.writer('owner/1/pending', 200, _CacheHeaders())!;
    await pending.add(_payload.sublist(0, 4));

    await cache.clear();
    expect(pending.accepting, false);
    expect(cache.disabled, false);
    expect(cache.queuedBytes, 0);
    expect(cache.storedBytes, 0);
    expect(cache.storedBytesForPrefix('owner/1/'), 0);
    expect(cache.storedBytesForPrefix('owner/2/'), 0);
    expect(cache.storedBytesForPrefix(''), 0);
    expect(await _fileBytes(root), 0);
    await _write(cache, 'owner/1/video');
    expect(cache.writtenBytes, 3 * _payloadSize);
    expect(cache.storedBytesForPrefix('owner/1/'), _payloadSize);
    expect(cache.storedBytesForPrefix('owner/2/'), 0);
    expect(await _fileBytes(root), _payloadSize);

    await cache.close();
    expect(cache.disabled, true);
    expect(cache.storedBytesForPrefix(''), 0);
    expect(await _fileBytes(root), 0);
  });
}

Future<void> _write(PlaybackRelayDiskCache cache, String key,
    {int status = 200, HttpHeaders? headers}) async {
  final writer = cache.writer(key, status, headers ?? _CacheHeaders());
  expect(writer, isNotNull);
  await writer!.add(_payload);
  await cache.flushWrites();
}

Future<int> _fileBytes(Directory directory) async {
  var bytes = 0;
  await for (final entry
      in directory.list(recursive: true, followLinks: false)) {
    if (entry is File) bytes += await entry.length();
  }
  return bytes;
}

class _CacheHeaders extends Fake implements HttpHeaders {
  _CacheHeaders({this.etag = '"v1"', this.contentRange});

  final String etag;
  final String? contentRange;

  @override
  int get contentLength => _payloadSize;

  @override
  ContentType get contentType => ContentType.binary;

  @override
  String? value(String name) => switch (name) {
        HttpHeaders.etagHeader => etag,
        HttpHeaders.contentRangeHeader => contentRange,
        _ => null,
      };
}
