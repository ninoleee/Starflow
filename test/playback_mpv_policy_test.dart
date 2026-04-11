import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/mpv_tuning_policy.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  group('MPV playback policy', () {
    test('detects remote and live playback urls', () {
      expect(
          isLikelyRemotePlaybackUrl('https://example.com/movie.mkv'), isTrue);
      expect(isLikelyRemotePlaybackUrl('rtsp://example.com/live'), isTrue);
      expect(isLikelyRemotePlaybackUrl(r'\\nas\movies\movie.mkv'), isFalse);
      expect(isLikelyRemotePlaybackUrl(r'D:\movies\movie.mkv'), isFalse);

      expect(
        isLikelyLiveRemotePlaybackUrl('rtsp://example.com/live'),
        isTrue,
      );
      expect(
        isLikelyLiveRemotePlaybackUrl('https://example.com/movie.mkv'),
        isFalse,
      );
    });

    test('detects heavy playback metadata', () {
      const heavyTarget = PlaybackTarget(
        title: '4K HEVC',
        sourceId: 'emby-main',
        streamUrl: 'https://example.com/movie.mkv',
        sourceName: 'Emby',
        sourceKind: MediaSourceKind.emby,
        width: 3840,
        height: 2160,
        bitrate: 18000000,
        videoCodec: 'hevc',
      );
      const lightTarget = PlaybackTarget(
        title: '1080p AVC',
        sourceId: 'emby-main',
        streamUrl: 'https://example.com/movie.mkv',
        sourceName: 'Emby',
        sourceKind: MediaSourceKind.emby,
        width: 1920,
        height: 1080,
        bitrate: 8000000,
        videoCodec: 'h264',
      );

      expect(isHeavyPlaybackTargetMetadata(heavyTarget), isTrue);
      expect(isHeavyPlaybackTargetMetadata(lightTarget), isFalse);
    });

    test('auto downgrades quality-first for heavy windowed windows playback',
        () {
      const target = PlaybackTarget(
        title: '4K HEVC',
        sourceId: 'emby-main',
        streamUrl: 'https://example.com/movie.mkv',
        sourceName: 'Emby',
        sourceKind: MediaSourceKind.emby,
        width: 3840,
        height: 2160,
        bitrate: 22000000,
        videoCodec: 'hevc',
      );

      final preset = resolveEffectivePlaybackMpvQualityPreset(
        requestedPreset: PlaybackMpvQualityPreset.qualityFirst,
        target: target,
        isWindowsPlatform: true,
        isTelevision: false,
        isFullscreen: false,
        aggressiveTuningEnabled: false,
        decodeMode: PlaybackDecodeMode.auto,
      );

      expect(preset, PlaybackMpvQualityPreset.performanceFirst);
    });

    test('keeps fullscreen windows quality-first for non-heavy remote playback',
        () {
      const target = PlaybackTarget(
        title: '1080p AVC',
        sourceId: 'emby-main',
        streamUrl: 'https://example.com/movie.mkv',
        sourceName: 'Emby',
        sourceKind: MediaSourceKind.emby,
        width: 1920,
        height: 1080,
        bitrate: 8000000,
        videoCodec: 'h264',
      );

      final preset = resolveEffectivePlaybackMpvQualityPreset(
        requestedPreset: PlaybackMpvQualityPreset.qualityFirst,
        target: target,
        isWindowsPlatform: true,
        isTelevision: false,
        isFullscreen: true,
        aggressiveTuningEnabled: false,
        decodeMode: PlaybackDecodeMode.auto,
      );

      expect(preset, PlaybackMpvQualityPreset.qualityFirst);
    });

    test('uses buffered remote tuning profile for http playback', () {
      const target = PlaybackTarget(
        title: 'HTTP Movie',
        sourceId: 'emby-main',
        streamUrl: 'https://example.com/movie.mkv',
        sourceName: 'Emby',
        sourceKind: MediaSourceKind.emby,
      );

      final profile = resolveMpvRemotePlaybackTuningProfile(
        target: target,
        aggressiveTuning: false,
        heavyPlayback: true,
      );

      expect(profile, isNotNull);
      expect(profile!.lowLatency, isFalse);
      expect(profile.cacheOnDisk, 'no');
      expect(profile.cacheSecs, '30');
      expect(profile.networkTimeoutSeconds, '15');
      expect(profile.cachePauseInitial, 'yes');
    });

    test('uses low latency tuning profile for rtsp playback', () {
      const target = PlaybackTarget(
        title: 'RTSP Live',
        sourceId: 'cam-main',
        streamUrl: 'rtsp://example.com/live',
        sourceName: 'Camera',
        sourceKind: MediaSourceKind.nas,
      );

      final profile = resolveMpvRemotePlaybackTuningProfile(
        target: target,
        aggressiveTuning: false,
        heavyPlayback: false,
      );

      expect(profile, isNotNull);
      expect(profile!.lowLatency, isTrue);
      expect(profile.cacheOnDisk, 'no');
      expect(profile.cacheSecs, isEmpty);
      expect(profile.cachePauseInitial, 'no');
    });

    test('recognizes local iso device sources only for local paths', () {
      expect(
        isLikelyLocalMpvIsoDeviceSource(
          r'D:\Movies\Movie.iso',
          windowsPlatform: true,
          posixPlatform: false,
        ),
        isTrue,
      );
      expect(
        isLikelyLocalMpvIsoDeviceSource(
          r'\\NAS\Movies\Movie.iso',
          windowsPlatform: true,
          posixPlatform: false,
        ),
        isTrue,
      );
      expect(
        isLikelyLocalMpvIsoDeviceSource(
          'file:///D:/Movies/Movie.iso',
          windowsPlatform: true,
          posixPlatform: false,
        ),
        isTrue,
      );
      expect(
        isLikelyLocalMpvIsoDeviceSource(
          'https://example.com/Movie.iso',
          windowsPlatform: true,
          posixPlatform: false,
        ),
        isFalse,
      );
    });
  });
}
