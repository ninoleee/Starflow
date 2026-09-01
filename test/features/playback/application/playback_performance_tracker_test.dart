import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/application/playback_performance_tracker.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

void main() {
  test('summarizes first frame buffering bandwidth and recovery', () {
    var now = DateTime(2026, 9, 1, 12);
    final tracker = PlaybackPerformanceTracker(clock: () => now);
    tracker.begin(sourceBitrate: 8000000);
    tracker.onBufferingChanged(true);
    now = now.add(const Duration(milliseconds: 750));
    tracker.onBufferingChanged(false);
    now = now.add(const Duration(milliseconds: 250));
    expect(tracker.markFirstFrame(), 1000);
    tracker.recordNetworkBytesPerSecond(2000000);
    tracker.recordNetworkBytesPerSecond(1000000);
    tracker.recordRecovery();
    now = now.add(const Duration(seconds: 4));

    final summary = tracker.finish()!;

    expect(summary.firstFrameMs, 1000);
    expect(summary.bufferingCount, 1);
    expect(summary.bufferingDurationMs, 750);
    expect(summary.averageNetworkBytesPerSecond, 1500000);
    expect(summary.recoveryCount, 1);
    expect(summary.bandwidthToBitrateRatio, 1.5);
  });

  test('reuses recent bandwidth only for the same host', () {
    var now = DateTime(2026, 9, 1, 12);
    final cache = PlaybackHostBandwidthCache(
      ttl: const Duration(minutes: 10),
      clock: () => now,
    );
    const first = PlaybackTarget(
      title: 'Episode 1',
      sourceId: 'nas-main',
      streamUrl: 'https://media.example.com/episode-1.mkv',
      sourceName: 'NAS',
      sourceKind: MediaSourceKind.nas,
    );
    const second = PlaybackTarget(
      title: 'Episode 2',
      sourceId: 'nas-main',
      streamUrl: 'https://media.example.com/episode-2.mkv',
      sourceName: 'NAS',
      sourceKind: MediaSourceKind.nas,
    );

    cache.record(first, 2500000);
    expect(cache.resolve(second), 2500000);
    now = now.add(const Duration(minutes: 11));
    expect(cache.resolve(second), isNull);
  });
}
