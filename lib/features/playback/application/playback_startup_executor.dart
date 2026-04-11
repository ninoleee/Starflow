import 'package:starflow/features/playback/application/playback_startup_routing.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

typedef PlaybackStartupLaunch = Future<void> Function(PlaybackTarget target);
typedef PlaybackStartupPerformanceFallback = Future<bool> Function(
  PlaybackTarget target,
);

class PlaybackStartupExecutor {
  PlaybackStartupExecutor({
    required this.launchSystemPlayer,
    required this.launchNativeContainer,
    required this.launchPerformanceFallback,
  });

  final PlaybackStartupLaunch launchSystemPlayer;
  final PlaybackStartupLaunch launchNativeContainer;
  final PlaybackStartupPerformanceFallback launchPerformanceFallback;

  /// Returns `true` if caller should continue (`openEmbeddedMpv` path).
  Future<bool> execute(
    PlaybackStartupRouteAction action,
    PlaybackTarget target,
  ) async {
    switch (action) {
      case PlaybackStartupRouteAction.launchSystemPlayer:
        await launchSystemPlayer(target);
        return false;
      case PlaybackStartupRouteAction.launchNativeContainer:
        await launchNativeContainer(target);
        return false;
      case PlaybackStartupRouteAction.launchPerformanceFallback:
        return !(await launchPerformanceFallback(target));
      case PlaybackStartupRouteAction.openEmbeddedMpv:
        return true;
    }
  }
}
