import 'package:starflow/features/playback/data/native_playback_launcher.dart';
import 'package:starflow/features/playback/domain/playback_episode_queue.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

NativePlaybackLauncher createNativePlaybackLauncher() {
  return const UnsupportedNativePlaybackLauncher();
}

class UnsupportedNativePlaybackLauncher implements NativePlaybackLauncher {
  const UnsupportedNativePlaybackLauncher();

  @override
  Future<NativePlaybackLaunchResult> launch(
    PlaybackTarget target, {
    required PlaybackDecodeMode decodeMode,
    PlaybackEpisodeQueue? episodeQueue,
  }) async {
    return const NativePlaybackLaunchResult(
      launched: false,
      message: '当前平台暂不支持 App 内原生播放器容器页。',
    );
  }
}
