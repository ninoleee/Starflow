import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/mpv_tuning_policy.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  group('MPV tuning policy aggressive downgrade', () {
    test('downgrades non-windows remote heavy HEVC quality-first to performance-first', () {
      const target = PlaybackTarget(
        title: 'Remote HEVC 4K',
        sourceId: 'emby-main',
        streamUrl: 'https://cdn.example.com/heavy.mkv',
        sourceName: 'Emby',
        sourceKind: MediaSourceKind.emby,
        container: 'mkv',
        videoCodec: 'hevc',
        width: 3840,
        height: 2160,
        bitrate: 28000000,
      );

      final preset = resolveEffectivePlaybackMpvQualityPreset(
        requestedPreset: PlaybackMpvQualityPreset.qualityFirst,
        target: target,
        isWindowsPlatform: false,
        isTelevision: false,
        isFullscreen: false,
        aggressiveTuningEnabled: false,
        decodeMode: PlaybackDecodeMode.auto,
      );

      expect(preset, PlaybackMpvQualityPreset.performanceFirst);
    });

    test('downgrades remote playback with low startup probe speed', () {
      const target = PlaybackTarget(
        title: 'Remote AVC',
        sourceId: 'emby-main',
        streamUrl: 'https://cdn.example.com/movie.mp4',
        sourceName: 'Emby',
        sourceKind: MediaSourceKind.emby,
        container: 'mp4',
        videoCodec: 'h264',
        width: 1920,
        height: 1080,
        bitrate: 7000000,
      );

      final preset = resolveEffectivePlaybackMpvQualityPreset(
        requestedPreset: PlaybackMpvQualityPreset.qualityFirst,
        target: target,
        isWindowsPlatform: false,
        isTelevision: false,
        isFullscreen: true,
        aggressiveTuningEnabled: false,
        decodeMode: PlaybackDecodeMode.auto,
        startupProbeMegabitsPerSecond: 8.5,
      );

      expect(preset, PlaybackMpvQualityPreset.balanced);
    });

    test('quark remote playback with low startup speed prefers performance-first and stronger buffering', () {
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

      final preset = resolveEffectivePlaybackMpvQualityPreset(
        requestedPreset: PlaybackMpvQualityPreset.qualityFirst,
        target: target,
        isWindowsPlatform: false,
        isTelevision: false,
        isFullscreen: true,
        aggressiveTuningEnabled: false,
        decodeMode: PlaybackDecodeMode.auto,
        startupProbeMegabitsPerSecond: 5.2,
      );

      final profile = resolveMpvRemotePlaybackTuningProfile(
        target: target,
        aggressiveTuning: false,
        heavyPlayback: true,
        startupProbeMegabitsPerSecond: 5.2,
      );

      expect(preset, PlaybackMpvQualityPreset.performanceFirst);
      expect(profile, isNotNull);
      expect(profile!.cachePauseInitial, 'yes');
      expect(profile.cacheSecs, '180');
      expect(profile.demuxerReadaheadSecs, '48');
      expect(profile.networkTimeoutSeconds, '35');
    });
  });
}
