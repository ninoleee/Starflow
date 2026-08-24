import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

enum PlaybackStartupRouteAction {
  openEmbeddedMpv,
  launchSystemPlayer,
  launchNativeContainer,
}

class PlaybackStartupRouteInput {
  const PlaybackStartupRouteInput({
    required this.playbackEngine,
    required this.target,
  });

  final PlaybackEngine playbackEngine;
  final PlaybackTarget target;
}

PlaybackStartupRouteAction decidePlaybackStartupRoute(
  PlaybackStartupRouteInput input,
) {
  if (_requiresHeaderAwareEmbeddedPlayback(input.target)) {
    if (input.playbackEngine == PlaybackEngine.nativeContainer) {
      return PlaybackStartupRouteAction.launchNativeContainer;
    }
    return PlaybackStartupRouteAction.openEmbeddedMpv;
  }
  if (input.playbackEngine == PlaybackEngine.systemPlayer) {
    return PlaybackStartupRouteAction.launchSystemPlayer;
  }
  if (input.playbackEngine == PlaybackEngine.nativeContainer) {
    return PlaybackStartupRouteAction.launchNativeContainer;
  }
  return PlaybackStartupRouteAction.openEmbeddedMpv;
}

bool _requiresHeaderAwareEmbeddedPlayback(PlaybackTarget target) {
  return target.requiresHeaderRestrictedPlayback;
}
