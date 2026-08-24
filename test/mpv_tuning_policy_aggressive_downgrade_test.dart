import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/mpv_tuning_policy.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

void main() {
  test('preflight speed estimate strengthens remote buffering without reroute',
      () {
    const target = PlaybackTarget(
      title: 'Quark Remote',
      sourceId: 'quark-main',
      streamUrl: 'https://download.example.com/media/episode01.mkv',
      sourceName: 'Quark',
      sourceKind: MediaSourceKind.quark,
      container: 'mkv',
      videoCodec: 'hevc',
      width: 1920,
      height: 1080,
      bitrate: 12000000,
    );

    final profile = resolveMpvRemotePlaybackTuningProfile(
      target: target,
      aggressiveTuning: false,
      heavyPlayback: true,
      preflightEstimatedMegabitsPerSecond: 5.2,
    );

    expect(profile, isNotNull);
    expect(profile!.cachePauseInitial, 'yes');
    expect(profile.cacheSecs, '150');
    expect(profile.demuxerReadaheadSecs, '42');
    expect(profile.networkTimeoutSeconds, '32');
  });
}
