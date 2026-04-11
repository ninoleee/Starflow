import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

enum PlaybackStartupRouteAction {
  openEmbeddedMpv,
  launchSystemPlayer,
  launchNativeContainer,
  launchPerformanceFallback,
}

class PlaybackStartupRouteInput {
  const PlaybackStartupRouteInput({
    required this.playbackEngine,
    required this.performanceAutoDowngradeHeavyPlaybackEnabled,
    required this.isTelevision,
    required this.isWeb,
    required this.target,
  });

  final PlaybackEngine playbackEngine;
  final bool performanceAutoDowngradeHeavyPlaybackEnabled;
  final bool isTelevision;
  final bool isWeb;
  final PlaybackTarget target;
}

PlaybackStartupRouteAction decidePlaybackStartupRoute(
  PlaybackStartupRouteInput input,
) {
  if (input.playbackEngine == PlaybackEngine.systemPlayer) {
    return PlaybackStartupRouteAction.launchSystemPlayer;
  }
  if (input.playbackEngine == PlaybackEngine.nativeContainer) {
    return PlaybackStartupRouteAction.launchNativeContainer;
  }
  if (_shouldAutoDowngradeToPerformanceFallback(input)) {
    return PlaybackStartupRouteAction.launchPerformanceFallback;
  }
  return PlaybackStartupRouteAction.openEmbeddedMpv;
}

bool _shouldAutoDowngradeToPerformanceFallback(
    PlaybackStartupRouteInput input) {
  if (!input.performanceAutoDowngradeHeavyPlaybackEnabled) {
    return false;
  }
  if (!input.isTelevision) {
    return false;
  }
  if (input.playbackEngine != PlaybackEngine.embeddedMpv) {
    return false;
  }
  if (input.isWeb) {
    return false;
  }

  final width = input.target.width ?? 0;
  final height = input.target.height ?? 0;
  final bitrate = input.target.bitrate ?? 0;
  final codec = input.target.videoCodec.trim().toLowerCase();
  final is4k = width >= 3840 || height >= 2160;
  final isHevc = codec == 'hevc' || codec == 'h265' || codec == 'x265';
  final veryHighBitrate = bitrate >= 25000000;
  final heavyHevc = isHevc && (is4k || bitrate >= 18000000);
  return is4k || veryHighBitrate || heavyHevc;
}
