import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/playback/data/native_playback_launcher_stub.dart'
    if (dart.library.io) 'package:starflow/features/playback/data/native_playback_launcher_io.dart'
    as impl;
import 'package:starflow/features/playback/domain/playback_episode_queue.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

final nativePlaybackLauncherProvider = Provider<NativePlaybackLauncher>((ref) {
  return impl.createNativePlaybackLauncher(ref);
});

class NativeResolvedPlaybackTarget {
  const NativeResolvedPlaybackTarget({
    required this.target,
    this.mediaMimeType = '',
  });

  final PlaybackTarget target;
  final String mediaMimeType;
}

typedef NativePlaybackEpisodeResolver = Future<NativeResolvedPlaybackTarget>
    Function(PlaybackTarget target);

abstract class NativePlaybackLauncher {
  Future<NativePlaybackLaunchResult> launch(
    PlaybackTarget target, {
    required PlaybackDecodeMode decodeMode,
    required NativeAudioOutputMode audioOutputMode,
    required double subtitleScale,
    double primarySubtitlePosition = kPlaybackPrimarySubtitlePositionDefault,
    double secondarySubtitlePosition =
        kPlaybackSecondarySubtitlePositionDefault,
    double secondarySubtitleScale = kPlaybackSecondarySubtitleScaleDefault,
    required bool backgroundPlaybackEnabled,
    required PlaybackSubtitlePreference subtitlePreference,
    required PlaybackDefaultSubtitle defaultSubtitle,
    PlaybackEpisodeQueue? episodeQueue,
    String mediaMimeType = '',
    NativePlaybackEpisodeResolver? episodeResolver,
  });
}

class NativePlaybackLaunchResult {
  const NativePlaybackLaunchResult({
    required this.launched,
    this.message = '',
  });

  final bool launched;
  final String message;
}
