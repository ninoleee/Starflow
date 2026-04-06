import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:starflow/features/playback/data/native_playback_launcher.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

NativePlaybackLauncher createNativePlaybackLauncher() {
  return const PlatformNativePlaybackLauncher();
}

class PlatformNativePlaybackLauncher implements NativePlaybackLauncher {
  const PlatformNativePlaybackLauncher();

  static const _platformChannel = MethodChannel('starflow/platform');

  @override
  Future<NativePlaybackLaunchResult> launch(
    PlaybackTarget target, {
    required PlaybackDecodeMode decodeMode,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return const NativePlaybackLaunchResult(
        launched: false,
        message: 'App 内原生播放器容器页当前仅支持 Android 和 iOS。',
      );
    }

    final uri = Uri.tryParse(target.streamUrl.trim());
    if (uri == null || !uri.hasScheme) {
      return const NativePlaybackLaunchResult(
        launched: false,
        message: '播放地址无效，无法启动原生播放器。',
      );
    }

    try {
      final launched = await _platformChannel.invokeMethod<bool>(
        'launchNativePlaybackContainer',
        {
          'url': target.streamUrl.trim(),
          'title': target.title,
          'headersJson': jsonEncode(target.headers),
          'decodeMode': decodeMode.name,
          'playbackTargetJson': jsonEncode(target.toJson()),
          'playbackItemKey': buildPlaybackItemKey(target),
          'seriesKey': buildSeriesKeyForTarget(target),
        },
      );
      return NativePlaybackLaunchResult(
        launched: launched == true,
        message: launched == true ? '' : '原生播放器启动失败。',
      );
    } catch (_) {
      return const NativePlaybackLaunchResult(
        launched: false,
        message: '原生播放器启动失败。',
      );
    }
  }
}
