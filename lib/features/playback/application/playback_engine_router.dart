import 'package:starflow/features/playback/application/playback_startup_routing.dart';

class PlaybackEngineRouter {
  const PlaybackEngineRouter();

  PlaybackStartupRouteAction route(PlaybackStartupRouteInput input) {
    return decidePlaybackStartupRoute(input);
  }
}
