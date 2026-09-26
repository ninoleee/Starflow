import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/domain/playback_network_speed.dart';

void main() {
  test('buffer duration and compact first line', () {
    expect(formatPlaybackMetrics(2048, 33554432, 18000),
        '2.0 KB/s · 32.0 MB · 18s');
    expect(
        formatPlaybackMetrics(2048, 33554432, 18000, diskCacheBytes: 100663296),
        '2.0 KB/s · 32.0 MB | 96.0 MB · 18s');
    expect(formatPlaybackMetrics(null, null, null), '-- · -- · --');
    expect(formatPlaybackBufferDuration(0), '0s');
    expect(formatPlaybackBufferDuration(59999), '60s');
    expect(formatPlaybackBufferDuration(90000), '90s');
    expect(formatPlaybackBufferDuration(120000), '120s');
    expect(formatPlaybackBufferDuration(3600000), '3600s');
    expect(formatPlaybackBufferDuration(null), '--');
    expect(formatPlaybackBufferDuration(-1), '--');
    expect(parsePlaybackDurationMilliseconds('18.5'), 18500);
    expect(parsePlaybackDurationMilliseconds('1e308'), isNull);
  });
  final fixture = jsonDecode(
    File('test/fixtures/playback_network_speed.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  test('speed format matches the native contract', () {
    for (final row in fixture['formats'] as List) {
      expect(formatPlaybackNetworkSpeed(row['bytes'] as int?), row['label']);
    }
  });

  test('cache uses the same units without a rate suffix', () {
    for (final row in fixture['formats'] as List) {
      expect(formatPlaybackCacheBytes(row['bytes'] as int?),
          (row['label'] as String).replaceFirst('/s', ''));
    }
  });

  test('native byte properties reject unavailable and invalid values', () {
    for (final raw in ['', 'unknown', 'NaN', 'Infinity', '-1']) {
      expect(parsePlaybackByteCount(raw), isNull);
    }
    expect(parsePlaybackByteCount('0'), 0);
    expect(parsePlaybackByteCount('1048576'), 1048576);
  });

  test('three samples smooth spikes and zero or unknown resets immediately',
      () {
    final window = PlaybackNetworkSpeedWindow();
    expect(
      (fixture['samples'] as List).map((value) => window.add(value as int?)),
      fixture['smoothed'],
    );
  });
}
