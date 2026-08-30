import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/playback/data/native_playback_launcher.dart';
import 'package:starflow/features/playback/domain/playback_episode_queue.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

NativePlaybackLauncher createNativePlaybackLauncher(Ref ref) {
  return const UnsupportedNativePlaybackLauncher();
}

class UnsupportedNativePlaybackLauncher implements NativePlaybackLauncher {
  const UnsupportedNativePlaybackLauncher();

  @override
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
    required PlaybackSubtitleLanguage dualSubtitlePrimaryLanguage,
    required PlaybackSubtitleLanguage dualSubtitleSecondaryLanguage,
    PlaybackEpisodeQueue? episodeQueue,
    String mediaMimeType = '',
    NativePlaybackEpisodeResolver? episodeResolver,
  }) async {
    return const NativePlaybackLaunchResult(
      launched: false,
      message: '当前平台暂不支持 App 内原生播放器容器页。',
    );
  }
}
