import 'package:url_launcher/url_launcher.dart';
import 'package:starflow/features/playback/data/system_playback_launcher.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

SystemPlaybackLauncher createSystemPlaybackLauncher() {
  return const UrlSystemPlaybackLauncher();
}

class UrlSystemPlaybackLauncher implements SystemPlaybackLauncher {
  const UrlSystemPlaybackLauncher();

  @override
  Future<SystemPlaybackLaunchResult> launch(PlaybackTarget target) async {
    final uri = Uri.tryParse(target.streamUrl.trim());
    if (uri == null || !uri.hasScheme) {
      return const SystemPlaybackLaunchResult(
        launched: false,
        message: '播放地址无效，无法调用系统播放器。',
      );
    }

    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalNonBrowserApplication,
    );
    return SystemPlaybackLaunchResult(
      launched: launched,
      message: launched ? '' : '系统播放器启动失败。',
    );
  }
}
