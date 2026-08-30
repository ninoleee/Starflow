import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:starflow/core/utils/playback_trace.dart';
import 'package:starflow/features/playback/data/native_playback_launcher.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
import 'package:starflow/features/playback/domain/playback_episode_queue.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

NativePlaybackLauncher createNativePlaybackLauncher() {
  return PlatformNativePlaybackLauncher();
}

class PlatformNativePlaybackLauncher implements NativePlaybackLauncher {
  PlatformNativePlaybackLauncher() {
    _resolverChannel.setMethodCallHandler(_handleResolverMethodCall);
  }

  static const _platformChannel = MethodChannel('starflow/platform');
  static const _resolverChannel =
      MethodChannel('starflow/native_playback_resolver');
  NativePlaybackEpisodeResolver? _episodeResolver;
  String _resolverSessionId = '';

  @override
  Future<NativePlaybackLaunchResult> launch(
    PlaybackTarget target, {
    required PlaybackDecodeMode decodeMode,
    required NativeAudioOutputMode audioOutputMode,
    required double subtitleScale,
    required bool backgroundPlaybackEnabled,
    required PlaybackSubtitlePreference subtitlePreference,
    required List<String> subtitlePreferredLanguages,
    PlaybackEpisodeQueue? episodeQueue,
    String mediaMimeType = '',
    NativePlaybackEpisodeResolver? episodeResolver,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return const NativePlaybackLaunchResult(
        launched: false,
        message: '原生播放器（实验性）当前仅支持 Android 和 iOS。',
      );
    }

    final uri = Uri.tryParse(target.streamUrl.trim());
    if (uri == null || !uri.hasScheme) {
      return const NativePlaybackLaunchResult(
        launched: false,
        message: '播放地址无效，无法启动原生播放器。',
      );
    }

    _traceQuarkNativeLaunch(
      'quark.native-launch.invoke.begin',
      target: target,
      fields: {
        'decodeMode': decodeMode.name,
        'audioOutputMode': audioOutputMode.name,
        'streamUrl': target.streamUrl,
        'headers': target.headers.keys.join('|'),
      },
    );
    _episodeResolver = episodeResolver;
    _resolverSessionId = episodeResolver == null
        ? ''
        : DateTime.now().microsecondsSinceEpoch.toString();
    try {
      final launched = await _platformChannel.invokeMethod<bool>(
        'launchNativePlaybackContainer',
        {
          'url': target.streamUrl.trim(),
          'title': target.title,
          'headersJson': jsonEncode(target.headers),
          'decodeMode': decodeMode.name,
          'audioOutputMode': audioOutputMode.name,
          'subtitleScale': clampPlaybackSubtitleScale(subtitleScale),
          'backgroundPlaybackEnabled': backgroundPlaybackEnabled,
          'subtitlePreference': subtitlePreference.name,
          'subtitlePreferredLanguages': subtitlePreferredLanguages,
          'mediaMimeType': mediaMimeType,
          'resolverSessionId': _resolverSessionId,
          'playbackTargetJson': jsonEncode(target.toJson()),
          'playbackItemKey': buildPlaybackItemKey(target),
          'seriesKey': buildSeriesKeyForTarget(target),
          'episodeQueueJson':
              episodeQueue == null ? '' : jsonEncode(episodeQueue.toJson()),
        },
      );
      _traceQuarkNativeLaunch(
        'quark.native-launch.invoke.result',
        target: target,
        fields: {
          'decodeMode': decodeMode.name,
          'audioOutputMode': audioOutputMode.name,
          'launched': launched == true,
        },
      );
      return NativePlaybackLaunchResult(
        launched: launched == true,
        message: launched == true ? '' : '原生播放器启动失败。',
      );
    } catch (error, stackTrace) {
      _traceQuarkNativeLaunch(
        'quark.native-launch.invoke.failed',
        target: target,
        fields: {
          'decodeMode': decodeMode.name,
          'audioOutputMode': audioOutputMode.name,
        },
        error: error,
        stackTrace: stackTrace,
      );
      return const NativePlaybackLaunchResult(
        launched: false,
        message: '原生播放器启动失败。',
      );
    }
  }

  Future<Object?> _handleResolverMethodCall(MethodCall call) async {
    if (call.method != 'resolveNativePlaybackEpisode') {
      throw MissingPluginException('Unsupported native playback resolver call');
    }
    final arguments = Map<String, Object?>.from(
      call.arguments as Map<dynamic, dynamic>? ?? const {},
    );
    final resolverSessionId =
        arguments['resolverSessionId']?.toString().trim() ?? '';
    final rawTargetJson = arguments['playbackTargetJson']?.toString() ?? '';
    final resolver = _episodeResolver;
    if (resolver == null ||
        resolverSessionId.isEmpty ||
        resolverSessionId != _resolverSessionId ||
        rawTargetJson.trim().isEmpty) {
      return const <String, Object?>{
        'ok': false,
        'message': '原生播放会话已变化，请重新选择剧集。',
      };
    }
    try {
      final target = PlaybackTarget.fromJson(
        Map<String, dynamic>.from(jsonDecode(rawTargetJson) as Map),
      );
      final resolved = await resolver(target);
      final resolvedPlaybackItemKey = buildPlaybackItemKey(resolved.target);
      return <String, Object?>{
        'ok': true,
        'playbackTargetJson': jsonEncode(resolved.target.toJson()),
        'playbackItemKey': resolvedPlaybackItemKey,
        'seriesKey': buildSeriesKeyForTarget(resolved.target),
        'mediaMimeType': resolved.mediaMimeType,
      };
    } catch (error) {
      return <String, Object?>{
        'ok': false,
        'message': '解析剧集失败：$error',
      };
    }
  }
}

void _traceQuarkNativeLaunch(
  String stage, {
  required PlaybackTarget target,
  Map<String, Object?> fields = const <String, Object?>{},
  Object? error,
  StackTrace? stackTrace,
}) {
  if (target.sourceKind.name != 'quark') {
    return;
  }
  playbackTrace(
    stage,
    fields: <String, Object?>{
      'title': target.title.trim().isEmpty ? 'Starflow' : target.title.trim(),
      'sourceKind': target.sourceKind.name,
      'container': target.container,
      ...fields,
    },
    error: error,
    stackTrace: stackTrace,
  );
}
