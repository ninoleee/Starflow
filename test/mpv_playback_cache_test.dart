import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/data/mpv_playback_cache.dart';

void main() {
  test('reads the full cache node on cores without subpath support', () async {
    final reads = <String>[];
    final bytes = await readMpvForwardCacheBytes((name) async {
      reads.add(name);
      if (name != 'demuxer-cache-state') return '';
      return '{"cache-duration":30.037333,"idle":true,'
          '"total-bytes":3280464,"fw-bytes":3255296,'
          '"seekable-ranges":[{"start":0,"end":30.165333}]}';
    });
    expect(bytes, 3255296);
    expect(reads, ['demuxer-cache-state']);
  });

  test('keeps zero forward bytes even with retained or disk bytes', () async {
    expect(
      await readMpvForwardCacheBytes((_) async =>
          '{"fw-bytes":0,"total-bytes":4096,"file-cache-bytes":8192}'),
      0,
    );
  });

  test('accepts bytes beyond 32 bits', () async {
    expect(
        await readMpvForwardCacheBytes((_) async => '{"fw-bytes":5368709120}'),
        5368709120);
  });

  for (final raw in [
    '',
    'not json',
    'null',
    '[]',
    '42',
    '{"total-bytes":4096,"file-cache-bytes":8192,"cache-duration":30}',
    '{"fw-bytes":null}',
    '{"fw-bytes":true}',
    '{"fw-bytes":"invalid"}',
    '{"fw-bytes":-1}',
    '{"fw-bytes":1e999}',
  ]) {
    test('unavailable or invalid forward bytes stay unknown: $raw', () async {
      expect(await readMpvForwardCacheBytes((_) async => raw), isNull);
    });
  }

  test('property read errors stay unknown', () async {
    expect(
      await readMpvForwardCacheBytes((_) async => throw StateError('disposed')),
      isNull,
    );
  });
}
