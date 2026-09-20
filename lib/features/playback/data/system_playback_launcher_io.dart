import 'package:starflow/core/logging/app_logger.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:starflow/features/playback/data/external_playback_file_store.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:starflow/features/playback/data/system_playback_launcher.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

SystemPlaybackLauncher createSystemPlaybackLauncher() {
  return const DesktopAwareSystemPlaybackLauncher();
}

class DesktopAwareSystemPlaybackLauncher implements SystemPlaybackLauncher {
  const DesktopAwareSystemPlaybackLauncher();

  static const _platformChannel = MethodChannel('starflow/platform');
  static final _playlistFiles = ExternalPlaybackFileStore();

  @override
  Future<SystemPlaybackLaunchResult> launch(PlaybackTarget target) async {
    final uri = Uri.tryParse(target.streamUrl.trim());
    if (uri == null || !uri.hasScheme) {
      return const SystemPlaybackLaunchResult(
        launched: false,
        message: '播放地址无效，无法调用外部系统播放器。',
      );
    }
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return _launchDesktopPlaylist(target);
    }

    if (_requiresExternalPlaybackHeaders(target) && !Platform.isIOS) {
      return const SystemPlaybackLaunchResult(
        launched: false,
        message: '当前资源依赖请求头鉴权，外部播放器暂不支持。请改用内置 MPV 或原生播放器。',
      );
    }

    if (Platform.isAndroid || Platform.isIOS) {
      final launched = await _launchPlatformVideoIntent(target);
      return SystemPlaybackLaunchResult(
        launched: launched,
        message: launched ? '' : '外部播放器启动失败。',
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
    final file = await _playlistFiles.create(target);
    final launched = await _openDesktopPlaylist(file.path);
    if (launched) {
      unawaited(
        Future<void>.delayed(const Duration(minutes: 10), () async {
          try {
            await _playlistFiles.delete(file);
          } catch (_) {}
        }),
      );
    } else {
      try {
        await _playlistFiles.delete(file);
      } catch (_) {}
    }
    return SystemPlaybackLaunchResult(
      launched: launched,
      message: launched ? '' : '外部系统播放器启动失败。',
    );
  }

  Future<bool> _openDesktopPlaylist(String path) async {
    try {
      if (Platform.isWindows) {
        final preferred = await _findWindowsExternalPlayer();
        if (preferred != null) {
          return _startExternalPlayer(preferred, [path]);
        }
        final process = await Process.start(
          'cmd',
          ['/c', 'start', '', path],
          runInShell: false,
        );
        return _processStarted(process);
      }
      if (Platform.isMacOS) {
        for (final candidate in const [
          ('VLC', '/Applications/VLC.app'),
          ('IINA', '/Applications/IINA.app'),
          ('mpv', '/Applications/mpv.app'),
        ]) {
          if (await Directory(candidate.$2).exists()) {
            return _startExternalPlayer('open', ['-a', candidate.$1, path]);
          }
        }
        return _startExternalPlayer('open', [path]);
      }
      if (Platform.isLinux) {
        return _startExternalPlayer('xdg-open', [path]);
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _findWindowsExternalPlayer() async {
    final programFiles = <String>{
      Platform.environment['ProgramFiles']?.trim() ?? '',
      Platform.environment['ProgramFiles(x86)']?.trim() ?? '',
    }.where((value) => value.isNotEmpty);
    for (final root in programFiles) {
      final vlcPath = p.join(root, 'VideoLAN', 'VLC', 'vlc.exe');
      if (await File(vlcPath).exists()) {
        return vlcPath;
      }
    }
    for (final executable in const ['vlc.exe', 'mpv.exe']) {
      try {
        final result = await Process.run(
          'where.exe',
          [executable],
          runInShell: false,
        ).timeout(const Duration(seconds: 2));
        if (result.exitCode != 0) {
          continue;
        }
        for (final line in '${result.stdout}'.split(RegExp(r'[\r\n]+'))) {
          final path = line.trim();
          if (path.isNotEmpty && await File(path).exists()) {
            return path;
          }
        }
      } catch (_) {}
    }
    return null;
  }

  Future<bool> _startExternalPlayer(
    String executable,
    List<String> arguments,
  ) async {
    try {
      final process = await Process.start(
        executable,
        arguments,
        runInShell: false,
      );
      return _processStarted(process);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _processStarted(Process process) async {
    process.stdout.listen((_) {});
    process.stderr.listen((_) {});
    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 3),
      onTimeout: () => 0,
    );
    return exitCode == 0;
  }

  Future<bool> _launchPlatformVideoIntent(PlaybackTarget target) async {
    final platformName = Platform.isIOS ? 'ios' : 'android';
    try {
      final launched =
          await _platformChannel.invokeMethod<bool>('launchSystemVideoPlayer', {
        'url': target.streamUrl.trim(),
        'title': target.title,
        'headersJson': jsonEncode(target.headers),
      });
      if (launched == true) {
        return true;
      }
    } catch (error, stackTrace) {
      _traceQuarkSystemLaunch(
        'quark.system-launch.$platformName.channel.failed',
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
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalNonBrowserApplication,
      );
      return launched;
    } catch (error, stackTrace) {
      _traceQuarkSystemLaunch(
        'quark.system-launch.$platformName.url.failed',
        target: target,
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  bool _requiresExternalPlaybackHeaders(PlaybackTarget target) {
    return target.requiresHeaderRestrictedPlayback;
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
  appLogError('playback', stage,
      fields: <String, Object?>{
        'title': target.title.trim().isEmpty ? 'Starflow' : target.title.trim(),
        'sourceKind': target.sourceKind.name,
        'container': target.container,
        ...fields,
      },
      error: error,
      stackTrace: stackTrace);
}
