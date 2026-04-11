import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_startup_routing.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  const baseTarget = PlaybackTarget(
    title: 'Demo',
    sourceId: 'emby-main',
    streamUrl: 'https://example.com/stream.mkv',
    sourceName: 'Emby',
    sourceKind: MediaSourceKind.emby,
  );

  group('decidePlaybackStartupRoute', () {
    test('routes to system player when engine is system player', () {
      final route = decidePlaybackStartupRoute(
        const PlaybackStartupRouteInput(
          playbackEngine: PlaybackEngine.systemPlayer,
          performanceAutoDowngradeHeavyPlaybackEnabled: true,
          isTelevision: true,
          isWeb: false,
          target: baseTarget,
        ),
      );

      expect(route, PlaybackStartupRouteAction.launchSystemPlayer);
    });

    test('routes to native container when engine is native container', () {
      final route = decidePlaybackStartupRoute(
        const PlaybackStartupRouteInput(
          playbackEngine: PlaybackEngine.nativeContainer,
          performanceAutoDowngradeHeavyPlaybackEnabled: true,
          isTelevision: true,
          isWeb: false,
          target: baseTarget,
        ),
      );

      expect(route, PlaybackStartupRouteAction.launchNativeContainer);
    });

    test('routes to performance fallback for heavy 4k tv target', () {
      final route = decidePlaybackStartupRoute(
        PlaybackStartupRouteInput(
          playbackEngine: PlaybackEngine.embeddedMpv,
          performanceAutoDowngradeHeavyPlaybackEnabled: true,
          isTelevision: true,
          isWeb: false,
          target: baseTarget.copyWith(
            width: 3840,
            height: 2160,
            bitrate: 12000000,
            videoCodec: 'h264',
          ),
        ),
      );

      expect(route, PlaybackStartupRouteAction.launchPerformanceFallback);
    });

    test('stays on embedded mpv for heavy target when device is not television',
        () {
      final route = decidePlaybackStartupRoute(
        PlaybackStartupRouteInput(
          playbackEngine: PlaybackEngine.embeddedMpv,
          performanceAutoDowngradeHeavyPlaybackEnabled: true,
          isTelevision: false,
          isWeb: false,
          target: baseTarget.copyWith(
            width: 3840,
            height: 2160,
            bitrate: 26000000,
            videoCodec: 'hevc',
          ),
        ),
      );

      expect(route, PlaybackStartupRouteAction.openEmbeddedMpv);
    });

    test('routes to performance fallback for very high bitrate target', () {
      final route = decidePlaybackStartupRoute(
        PlaybackStartupRouteInput(
          playbackEngine: PlaybackEngine.embeddedMpv,
          performanceAutoDowngradeHeavyPlaybackEnabled: true,
          isTelevision: true,
          isWeb: false,
          target: baseTarget.copyWith(
            width: 1280,
            height: 720,
            bitrate: 30000000,
            videoCodec: 'h264',
          ),
        ),
      );

      expect(route, PlaybackStartupRouteAction.launchPerformanceFallback);
    });

    test('stays on embedded mpv when heavy target downgrade is disabled', () {
      final route = decidePlaybackStartupRoute(
        PlaybackStartupRouteInput(
          playbackEngine: PlaybackEngine.embeddedMpv,
          performanceAutoDowngradeHeavyPlaybackEnabled: false,
          isTelevision: true,
          isWeb: false,
          target: baseTarget.copyWith(
            width: 3840,
            height: 2160,
            bitrate: 26000000,
            videoCodec: 'hevc',
          ),
        ),
      );

      expect(route, PlaybackStartupRouteAction.openEmbeddedMpv);
    });

    test('stays on embedded mpv on web even for heavy target', () {
      final route = decidePlaybackStartupRoute(
        PlaybackStartupRouteInput(
          playbackEngine: PlaybackEngine.embeddedMpv,
          performanceAutoDowngradeHeavyPlaybackEnabled: true,
          isTelevision: true,
          isWeb: true,
          target: baseTarget.copyWith(
            width: 3840,
            height: 2160,
            bitrate: 26000000,
            videoCodec: 'hevc',
          ),
        ),
      );

      expect(route, PlaybackStartupRouteAction.openEmbeddedMpv);
    });

    test('stays on embedded mpv for non-heavy target', () {
      final route = decidePlaybackStartupRoute(
        PlaybackStartupRouteInput(
          playbackEngine: PlaybackEngine.embeddedMpv,
          performanceAutoDowngradeHeavyPlaybackEnabled: true,
          isTelevision: true,
          isWeb: false,
          target: baseTarget.copyWith(
            width: 1920,
            height: 1080,
            bitrate: 8000000,
            videoCodec: 'h264',
          ),
        ),
      );

      expect(route, PlaybackStartupRouteAction.openEmbeddedMpv);
    });
  });
}
