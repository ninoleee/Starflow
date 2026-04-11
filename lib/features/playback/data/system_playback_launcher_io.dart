import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:starflow/core/utils/playback_trace.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:starflow/features/playback/data/system_playback_launcher.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

SystemPlaybackLauncher createSystemPlaybackLauncher() {
  return const DesktopAwareSystemPlaybackLauncher();
}

class DesktopAwareSystemPlaybackLauncher implements SystemPlaybackLauncher {
  const DesktopAwareSystemPlaybackLauncher();

  static const _platformChannel = MethodChannel('starflow/platform');

  @override
  Future<SystemPlaybackLaunchResult> launch(PlaybackTarget target) async {
    final uri = Uri.tryParse(target.streamUrl.trim());
    if (uri == null || !uri.hasScheme) {
      return const SystemPlaybackLaunchResult(
        launched: false,
        message: '播放地址无效，无法调用外部系统播放器。',
      );
    }
    if (_requiresExternalPlaybackHeaders(target)) {
      return const SystemPlaybackLaunchResult(
        launched: false,
        message: '当前资源依赖请求头鉴权，外部系统播放器暂不支持。请改用内置 MPV 或原生播放器。',
      );
    }

    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return _launchDesktopPlaylist(target);
    }

    if (Platform.isAndroid) {
      final launched = await _launchAndroidVideoIntent(target);
      return SystemPlaybackLaunchResult(
        launched: launched,
        message: launched ? '' : '外部系统播放器启动失败。',
      );
    }

    bool launched = false;
    try {
      launched = await launchUrl(
        uri,
        mode: LaunchMode.externalNonBrowserApplication,
      );
    } catch (_) {
      launched = false;
    }
    return SystemPlaybackLaunchResult(
      launched: launched,
      message: launched ? '' : '外部系统播放器启动失败。',
    );
  }

  Future<SystemPlaybackLaunchResult> _launchDesktopPlaylist(
    PlaybackTarget target,
  ) async {
    final file = await _createPlaylistFile(target);
    final launched = await _openFile(file.path);
    return SystemPlaybackLaunchResult(
      launched: launched,
      message: launched ? '' : '外部系统播放器启动失败。',
    );
  }

  Future<File> _createPlaylistFile(PlaybackTarget target) async {
    final safeTitle = _sanitizeFileName(target.title);
    final filename =
        'starflow-$safeTitle-${DateTime.now().millisecondsSinceEpoch}.m3u';
    final file = File(p.join(Directory.systemTemp.path, filename));
    final content = <String>[
      '#EXTM3U',
      '#EXTINF:-1,${target.title}',
      target.streamUrl.trim(),
      '',
    ].join('\n');
    await file.writeAsString(content, flush: true);
    return file;
  }

  Future<bool> _openFile(String path) async {
    try {
      late final Process process;
      if (Platform.isWindows) {
        process = await Process.start(
          'cmd',
          ['/c', 'start', '', path],
          runInShell: false,
        );
      } else if (Platform.isMacOS) {
        process = await Process.start('open', [path], runInShell: false);
      } else if (Platform.isLinux) {
        process = await Process.start('xdg-open', [path], runInShell: false);
      } else {
        return false;
      }

      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 8),
        onTimeout: () => 0,
      );
      return exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _launchAndroidVideoIntent(PlaybackTarget target) async {
    _traceQuarkSystemLaunch(
      'quark.system-launch.android.channel.begin',
      target: target,
      fields: {'streamUrl': target.streamUrl},
    );
    try {
      final launched =
          await _platformChannel.invokeMethod<bool>('launchSystemVideoPlayer', {
        'url': target.streamUrl.trim(),
        'title': target.title,
      });
      _traceQuarkSystemLaunch(
        'quark.system-launch.android.channel.result',
        target: target,
        fields: {'launched': launched == true},
      );
      if (launched == true) {
        return true;
      }
    } catch (error, stackTrace) {
      _traceQuarkSystemLaunch(
        'quark.system-launch.android.channel.failed',
        target: target,
        error: error,
        stackTrace: stackTrace,
      );
      // Fall back to a best-effort non-browser external launch below.
    }

    final uri = Uri.tryParse(target.streamUrl.trim());
    if (uri == null || !uri.hasScheme) {
      return false;
    }
    _traceQuarkSystemLaunch(
      'quark.system-launch.android.url.begin',
      target: target,
      fields: {'streamUrl': target.streamUrl},
    );
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalNonBrowserApplication,
      );
      _traceQuarkSystemLaunch(
        'quark.system-launch.android.url.result',
        target: target,
        fields: {'launched': launched},
      );
      return launched;
    } catch (error, stackTrace) {
      _traceQuarkSystemLaunch(
        'quark.system-launch.android.url.failed',
        target: target,
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  String _sanitizeFileName(String raw) {
    final sanitized = raw
        .replaceAll(RegExp(r'[\\/:*?"<>|&^%!]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (sanitized.isEmpty) {
      return 'playback';
    }
    return sanitized.length > 48 ? sanitized.substring(0, 48) : sanitized;
  }

  bool _requiresExternalPlaybackHeaders(PlaybackTarget target) {
    if (target.headers.isEmpty) {
      return false;
    }
    return target.headers.entries.any(
      (entry) =>
          entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty,
    );
  }
}

void _traceQuarkSystemLaunch(
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
