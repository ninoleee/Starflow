import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:starflow/core/platform/android_picture_in_picture.dart';
import 'package:starflow/core/platform/background_playback.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/network/starflow_http_client.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_session.dart';
import 'package:starflow/features/playback/data/native_playback_launcher.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
import 'package:starflow/features/playback/data/subtitle_file_picker.dart';
import 'package:starflow/features/playback/data/system_playback_launcher.dart';
import 'package:starflow/features/playback/domain/playback_memory_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

class _OpenPlaybackOptionsIntent extends Intent {
  const _OpenPlaybackOptionsIntent();
}

class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key, required this.target});

  final PlaybackTarget target;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage>
    with WidgetsBindingObserver {
  static const int _maxPlaybackAttempts = 3;
  static const _kSeekStep = Duration(seconds: 10);
  static const _kSpeedOptions = <double>[0.75, 1.0, 1.25, 1.5, 2.0];
  static const _kSubtitleDelaySteps = <double>[-2, -1, -0.5, 0, 0.5, 1, 2];
  static const _kProgressPersistInterval = Duration(seconds: 8);

  Player? _player;
  VideoController? _videoController;
  StreamSubscription<String>? _playerErrorSubscription;
  StreamSubscription<bool>? _playerPlayingSubscription;
  StreamSubscription<Duration>? _playerPositionSubscription;
  StreamSubscription<Duration>? _playerDurationSubscription;
  PlaybackTarget? _resolvedTarget;
  _StartupProbeResult _startupProbe = const _StartupProbeResult();
  SeriesSkipPreference? _seriesSkipPreference;
  Object? _error;
  bool _isReady = false;
  bool _pictureInPictureSupported = false;
  bool _isInPictureInPictureMode = false;
  bool _subtitleDelaySupported = false;
  double _subtitleDelaySeconds = 0;
  bool _introSkipApplied = false;
  bool _outroSkipApplied = false;
  Duration _latestPosition = Duration.zero;
  Duration _latestDuration = Duration.zero;
  DateTime? _lastProgressPersistedAt;
  Duration _lastPersistedPosition = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(playbackPerformanceModeProvider.notifier).state =
        ref.read(appSettingsProvider).highPerformanceModeEnabled;
    unawaited(_bindPictureInPictureSupport());
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ref.read(playbackPerformanceModeProvider.notifier).state = false;
    unawaited(_persistPlaybackProgress(force: true));
    unawaited(_teardownPictureInPicture());
    unawaited(_playerErrorSubscription?.cancel());
    unawaited(_playerPlayingSubscription?.cancel());
    unawaited(_playerPositionSubscription?.cancel());
    unawaited(_playerDurationSubscription?.cancel());
    final player = _player;
    _player = null;
    unawaited(player?.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_persistPlaybackProgress(force: true));
    }
    if (state != AppLifecycleState.paused) {
      return;
    }
    if (!_backgroundPlaybackEnabled) {
      return;
    }
    if (!_pictureInPictureSupported || _isInPictureInPictureMode) {
      return;
    }
    if (!_isActivelyPlaying) {
      return;
    }
    final size = _currentPictureInPictureAspectRatio();
    unawaited(
      AndroidPictureInPictureController.enter(
        aspectRatioWidth: size.width,
        aspectRatioHeight: size.height,
      ),
    );
  }

  bool get _isActivelyPlaying {
    final player = _player;
    return _isReady && player != null && player.state.playing;
  }

  bool get _backgroundPlaybackEnabled =>
      ref.read(appSettingsProvider).playbackBackgroundPlaybackEnabled;

  bool get _highPerformanceModeEnabled =>
      ref.read(appSettingsProvider).highPerformanceModeEnabled;

  bool get _isHighPerformancePlaybackMode =>
      _highPerformanceModeEnabled && !_isInPictureInPictureMode;

  bool get _prefersAggressiveHardwareDecoding => _highPerformanceModeEnabled;

  PlaybackDecodeMode get _playbackDecodeMode =>
      ref.read(appSettingsProvider).playbackDecodeMode;

  Future<void> _bindPictureInPictureSupport() async {
    if (!AndroidPictureInPictureController.isSupportedPlatform) {
      return;
    }
    await AndroidPictureInPictureController.attach((enabled) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isInPictureInPictureMode = enabled;
      });
    });
    final supported = await AndroidPictureInPictureController.isSupported();
    if (!mounted) {
      return;
    }
    setState(() {
      _pictureInPictureSupported = supported;
    });
    if (supported && _isReady) {
      unawaited(_syncBackgroundPlayback(enabled: _isActivelyPlaying));
    }
  }

  Future<void> _teardownPictureInPicture() async {
    if (!AndroidPictureInPictureController.isSupportedPlatform) {
      await BackgroundPlaybackController.setEnabled(false);
      return;
    }
    await AndroidPictureInPictureController.setPlaybackEnabled(
      enabled: false,
      aspectRatioWidth: 16,
      aspectRatioHeight: 9,
    );
    await AndroidPictureInPictureController.detach();
    await BackgroundPlaybackController.setEnabled(false);
  }

  Future<void> _syncBackgroundPlayback({required bool enabled}) async {
    final shouldEnable = enabled && _backgroundPlaybackEnabled;
    if (_pictureInPictureSupported) {
      final size = _currentPictureInPictureAspectRatio();
      await AndroidPictureInPictureController.setPlaybackEnabled(
        enabled: shouldEnable,
        aspectRatioWidth: size.width,
        aspectRatioHeight: size.height,
      );
    }
    await BackgroundPlaybackController.setEnabled(shouldEnable);
  }

  _PictureInPictureAspectRatio _currentPictureInPictureAspectRatio() {
    final width = _player?.state.width ?? 0;
    final height = _player?.state.height ?? 0;
    if (width > 0 && height > 0) {
      return _PictureInPictureAspectRatio(width: width, height: height);
    }
    return const _PictureInPictureAspectRatio(width: 16, height: 9);
  }

  Future<void> _initialize() async {
    if (!widget.target.canPlay) {
      setState(() {
        _error = '没有可播放的流地址';
      });
      return;
    }

    try {
      final settings = ref.read(appSettingsProvider);
      if (settings.highPerformanceModeEnabled) {
        await ref.read(mediaRepositoryProvider).cancelActiveWebDavRefreshes();
      }
      final resolvedTarget = await _resolveTarget(widget.target);
      final playbackMemoryRepository =
          ref.read(playbackMemoryRepositoryProvider);
      final resumeEntry = await playbackMemoryRepository.loadEntryForTarget(
        resolvedTarget,
      );
      final skipPreference = await playbackMemoryRepository.loadSkipPreference(
        resolvedTarget,
      );
      if (mounted) {
        setState(() {
          _resolvedTarget = resolvedTarget;
          _seriesSkipPreference = skipPreference;
        });
      }
      if (settings.playbackEngine == PlaybackEngine.systemPlayer) {
        await _launchWithSystemPlayer(resolvedTarget);
        return;
      }
      if (settings.playbackEngine == PlaybackEngine.nativeContainer) {
        await _launchWithNativeContainer(resolvedTarget);
        return;
      }
      if (_shouldAutoDowngradeToSystemPlayer(resolvedTarget)) {
        final launched = await _tryLaunchWithPerformanceFallback(
          resolvedTarget,
        );
        if (launched) {
          return;
        }
      }
      unawaited(_runStartupProbe(resolvedTarget));
      final timeoutSeconds = settings.playbackOpenTimeoutSeconds.clamp(1, 600);
      final playback = await _openWithRetry(
        resolvedTarget,
        timeout: Duration(seconds: timeoutSeconds),
      );
      await _applyStartupPlaybackPreferences(playback.player);

      if (!mounted) {
        await playback.errorSubscription.cancel();
        await playback.player.dispose();
        return;
      }

      _playerErrorSubscription = playback.errorSubscription;
      _playerPlayingSubscription = playback.player.stream.playing.listen((
        playing,
      ) {
        unawaited(_syncBackgroundPlayback(enabled: playing));
        if (!playing) {
          unawaited(_persistPlaybackProgress(force: true));
        }
      });
      _playerDurationSubscription = playback.player.stream.duration.listen((
        duration,
      ) {
        _latestDuration = duration;
      });
      _playerPositionSubscription = playback.player.stream.position.listen((
        position,
      ) {
        _latestPosition = position;
        _maybeApplyAutoSkip(playback.player, position);
        unawaited(_persistPlaybackProgress());
      });
      setState(() {
        _player = playback.player;
        _videoController = playback.videoController;
        _isReady = true;
        _error = null;
        _latestPosition = playback.player.state.position;
        _latestDuration = playback.player.state.duration;
      });
      await _syncSubtitleDelayState(playback.player);
      await _restorePlaybackProgress(playback.player, resumeEntry);
      _syncSkipFlagsWithCurrentPosition();
      unawaited(_syncBackgroundPlayback(enabled: true));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _buildPlaybackErrorMessage(error);
      });
      unawaited(_syncBackgroundPlayback(enabled: false));
    }
  }

  Future<_OpenedPlayback> _openWithRetry(
    PlaybackTarget resolvedTarget, {
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    Object? lastError;

    for (var attempt = 1; attempt <= _maxPlaybackAttempts; attempt++) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        break;
      }

      try {
        return await _openSingleAttempt(
          resolvedTarget,
          timeout: remaining,
        );
      } catch (error) {
        lastError = error;
        if (attempt >= _maxPlaybackAttempts) {
          break;
        }
      }
    }

    if (deadline.difference(DateTime.now()) <= Duration.zero) {
      throw TimeoutException('超过最大等待时间，已停止尝试播放');
    }
    throw lastError ?? const _PlayerOpenException('播放打开失败');
  }

  Future<_OpenedPlayback> _openSingleAttempt(
    PlaybackTarget resolvedTarget, {
    required Duration timeout,
  }) async {
    final player = Player(
      configuration: const PlayerConfiguration(
        title: 'Starflow',
        logLevel: MPVLogLevel.warn,
      ),
    );
    final videoController = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        hwdec: _resolveMpvHardwareDecodeMode(),
        enableHardwareAcceleration:
            _playbackDecodeMode != PlaybackDecodeMode.softwarePreferred,
      ),
    );
    final startupError = Completer<String>();
    var awaitingStartup = true;
    late final StreamSubscription<String> errorSubscription;
    errorSubscription = player.stream.error.listen((message) {
      final normalized = message.trim();
      if (normalized.isEmpty) {
        return;
      }
      if (awaitingStartup && !startupError.isCompleted) {
        startupError.complete(normalized);
        return;
      }
      if (!mounted || _player != player) {
        return;
      }
      setState(() {
        _error = normalized;
      });
    });

    try {
      await Future.any<void>([
        player.open(
          Media(
            resolvedTarget.streamUrl,
            httpHeaders: resolvedTarget.headers,
          ),
          play: true,
        ),
        startupError.future.then<void>((message) {
          throw _PlayerOpenException(message);
        }),
      ]).timeout(timeout);
      awaitingStartup = false;
      return _OpenedPlayback(
        player: player,
        videoController: videoController,
        errorSubscription: errorSubscription,
      );
    } catch (_) {
      await errorSubscription.cancel();
      await player.dispose();
      rethrow;
    }
  }

  Future<void> _launchWithSystemPlayer(PlaybackTarget target) async {
    final result =
        await ref.read(systemPlaybackLauncherProvider).launch(target);
    if (!result.launched) {
      throw _PlayerOpenException(
        result.message.isEmpty ? '系统播放器启动失败' : result.message,
      );
    }

    if (!mounted) {
      return;
    }
    context.pop();
  }

  Future<void> _launchWithNativeContainer(PlaybackTarget target) async {
    final result = await ref.read(nativePlaybackLauncherProvider).launch(
          target,
          decodeMode: _playbackDecodeMode,
        );
    if (!result.launched) {
      throw _PlayerOpenException(
        result.message.isEmpty ? '原生播放器启动失败' : result.message,
      );
    }

    if (!mounted) {
      return;
    }
    context.pop();
  }

  Future<bool> _tryLaunchWithPerformanceFallback(
    PlaybackTarget target,
  ) async {
    final nativeResult = await ref.read(nativePlaybackLauncherProvider).launch(
          target,
          decodeMode: _playbackDecodeMode,
        );
    if (nativeResult.launched) {
      if (mounted) {
        context.pop();
      }
      return true;
    }

    final result =
        await ref.read(systemPlaybackLauncherProvider).launch(target);
    if (!result.launched) {
      return false;
    }
    if (!mounted) {
      return true;
    }
    context.pop();
    return true;
  }

  String _resolveMpvHardwareDecodeMode() {
    switch (_playbackDecodeMode) {
      case PlaybackDecodeMode.auto:
        return _prefersAggressiveHardwareDecoding ? 'auto' : 'auto-safe';
      case PlaybackDecodeMode.hardwarePreferred:
        return 'auto';
      case PlaybackDecodeMode.softwarePreferred:
        return 'no';
    }
  }

  Future<void> _applyStartupPlaybackPreferences(Player player) async {
    final settings = ref.read(appSettingsProvider);

    try {
      if ((settings.playbackDefaultSpeed - 1.0).abs() > 0.0001) {
        await player.setRate(settings.playbackDefaultSpeed);
      }
    } catch (_) {
      // Ignore preference application failures to keep playback available.
    }

    if (settings.playbackSubtitlePreference == PlaybackSubtitlePreference.off) {
      try {
        await player.setSubtitleTrack(SubtitleTrack.no());
      } catch (_) {
        // Ignore preference application failures to keep playback available.
      }
    }
  }

  Future<void> _persistPlaybackProgress({bool force = false}) async {
    final player = _player;
    final target = _resolvedTarget ?? widget.target;
    if (!_isReady || player == null) {
      return;
    }

    final now = DateTime.now();
    if (!force) {
      final lastPersistedAt = _lastProgressPersistedAt;
      if (lastPersistedAt != null &&
          now.difference(lastPersistedAt) < _kProgressPersistInterval) {
        return;
      }
      final deltaMs = (_latestPosition.inMilliseconds -
              _lastPersistedPosition.inMilliseconds)
          .abs();
      if (deltaMs < 4000) {
        return;
      }
    }

    _lastProgressPersistedAt = now;
    _lastPersistedPosition = _latestPosition;

    await ref.read(playbackMemoryRepositoryProvider).saveProgress(
          target: target,
          position: _latestPosition,
          duration: _latestDuration > Duration.zero
              ? _latestDuration
              : player.state.duration,
        );
  }

  Future<void> _restorePlaybackProgress(
    Player player,
    PlaybackProgressEntry? resumeEntry,
  ) async {
    if (resumeEntry == null || !resumeEntry.canResume) {
      return;
    }

    final resolvedDuration = await _awaitKnownDuration(player);
    final duration = resolvedDuration > Duration.zero
        ? resolvedDuration
        : resumeEntry.duration;
    if (duration <= Duration.zero) {
      return;
    }

    final maxPosition = duration - const Duration(seconds: 3);
    final desiredPosition =
        resumeEntry.position < maxPosition ? resumeEntry.position : maxPosition;
    if (desiredPosition <= const Duration(seconds: 5)) {
      return;
    }

    try {
      await player.seek(desiredPosition);
      _latestPosition = desiredPosition;
      _latestDuration = duration;
      if (!mounted) {
        return;
      }
      _showMessage('已从 ${_formatClockDuration(desiredPosition)} 继续播放');
    } catch (_) {
      // Keep playback available even if resume fails.
    }
  }

  Future<Duration> _awaitKnownDuration(Player player) async {
    final current = player.state.duration;
    if (current > Duration.zero) {
      return current;
    }

    try {
      return await player.stream.duration
          .firstWhere((duration) => duration > Duration.zero)
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      return Duration.zero;
    }
  }

  void _maybeApplyAutoSkip(Player player, Duration position) {
    final preference = _seriesSkipPreference;
    if (preference == null || !preference.enabled) {
      return;
    }

    final duration = _latestDuration > Duration.zero
        ? _latestDuration
        : player.state.duration;

    if (!_introSkipApplied && preference.introDuration > Duration.zero) {
      if (position >= preference.introDuration) {
        _introSkipApplied = true;
      } else {
        _introSkipApplied = true;
        _latestPosition = preference.introDuration;
        unawaited(player.seek(preference.introDuration));
        _showMessage('已自动跳过片头');
        return;
      }
    }

    if (_outroSkipApplied ||
        preference.outroDuration <= Duration.zero ||
        duration <= Duration.zero) {
      return;
    }

    final triggerPosition = duration - preference.outroDuration;
    if (triggerPosition <= Duration.zero) {
      return;
    }
    if (position < triggerPosition) {
      return;
    }

    _outroSkipApplied = true;
    final seekTarget = duration > const Duration(milliseconds: 400)
        ? duration - const Duration(milliseconds: 400)
        : duration;
    _latestPosition = seekTarget;
    unawaited(player.seek(seekTarget));
    _showMessage('已自动跳过片尾');
  }

  void _syncSkipFlagsWithCurrentPosition() {
    final preference = _seriesSkipPreference;
    if (preference == null || !preference.enabled) {
      _introSkipApplied = true;
      _outroSkipApplied = true;
      return;
    }

    _introSkipApplied = preference.introDuration <= Duration.zero ||
        _latestPosition >= preference.introDuration;
    if (_latestDuration <= Duration.zero ||
        preference.outroDuration <= Duration.zero) {
      _outroSkipApplied = false;
      return;
    }
    _outroSkipApplied =
        (_latestDuration - _latestPosition) <= preference.outroDuration;
  }

  Future<void> _syncSubtitleDelayState(Player player) async {
    final delay = await _readSubtitleDelaySeconds(player);
    if (!mounted) {
      return;
    }
    setState(() {
      _subtitleDelaySupported = delay != null;
      _subtitleDelaySeconds = delay ?? 0;
    });
  }

  Future<double?> _readSubtitleDelaySeconds(Player player) async {
    final native = player.platform;
    if (native == null) {
      return null;
    }

    try {
      final raw = await (native as dynamic).getProperty('sub-delay');
      return double.tryParse('$raw');
    } catch (_) {
      return null;
    }
  }

  Future<void> _setSubtitleDelay(Player player, double value) async {
    final native = player.platform;
    if (native == null) {
      _showMessage('当前播放器内核暂不支持字幕偏移');
      return;
    }

    try {
      await (native as dynamic).setProperty(
        'sub-delay',
        value.toStringAsFixed(3),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _subtitleDelaySupported = true;
        _subtitleDelaySeconds = value;
      });
    } catch (error) {
      _showMessage('字幕偏移设置失败：$error');
    }
  }

  Future<void> _openSubtitleDelayDialog(Player player) async {
    if (!_subtitleDelaySupported) {
      await _syncSubtitleDelayState(player);
    }
    if (!mounted) {
      return;
    }
    if (!_subtitleDelaySupported) {
      _showMessage('当前播放器内核暂不支持字幕偏移');
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var currentDelay = _subtitleDelaySeconds;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('字幕偏移'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('当前偏移：${_formatSubtitleDelayValue(currentDelay)}'),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final step in _kSubtitleDelaySteps)
                        StarflowButton(
                          label: step == 0
                              ? '重置'
                              : step > 0
                                  ? '+${step.toStringAsFixed(step == step.roundToDouble() ? 0 : 1)}s'
                                  : '${step.toStringAsFixed(step == step.roundToDouble() ? 0 : 1)}s',
                          onPressed: () async {
                            final nextDelay =
                                step == 0 ? 0.0 : currentDelay + step;
                            await _setSubtitleDelay(player, nextDelay);
                            setDialogState(() {
                              currentDelay = _subtitleDelaySeconds;
                            });
                          },
                          variant: StarflowButtonVariant.secondary,
                          compact: true,
                        ),
                    ],
                  ),
                ],
              ),
              actions: [
                StarflowButton(
                  label: '关闭',
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  variant: StarflowButtonVariant.ghost,
                  compact: true,
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _loadExternalSubtitle(Player player) async {
    final isTelevision = ref.read(isTelevisionProvider).valueOrNull ?? false;
    if (isTelevision) {
      _showMessage('电视模式暂不打开系统文件选择器，请改用内嵌字幕或在其他设备上准备字幕文件。');
      return;
    }
    final picker = ref.read(subtitleFilePickerProvider);
    if (!picker.isSupported) {
      _showMessage(picker.unsupportedReason);
      return;
    }

    String? path;
    try {
      path = await picker.pickSubtitlePath();
    } catch (error) {
      _showMessage('打开字幕文件选择器失败：$error');
      return;
    }
    if (path == null || path.trim().isEmpty) {
      return;
    }
    final resolvedPath = path;

    final uri = Uri.file(resolvedPath).toString();
    await _runPlayerCommand(
      () => player.setSubtitleTrack(
        SubtitleTrack.uri(
          uri,
          title: p.basenameWithoutExtension(resolvedPath),
        ),
      ),
      failureMessage: '加载字幕失败',
    );
  }

  Future<void> _showOnlineSubtitleSearch(PlaybackTarget target) async {
    final query = _buildSubtitleSearchQuery(target);
    final isTelevision = ref.read(isTelevisionProvider).valueOrNull ?? false;
    if (isTelevision) {
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('在线查找字幕'),
            content: Text(
              '电视模式暂不直接拉起外部浏览器，避免系统兼容性问题。\n\n'
              '请在其他设备上搜索：\n$query 字幕',
            ),
            actions: [
              StarflowButton(
                label: '知道了',
                onPressed: () => Navigator.of(dialogContext).pop(),
                variant: StarflowButtonVariant.ghost,
                compact: true,
              ),
            ],
          );
        },
      );
      return;
    }
    final options = <_SubtitleSearchOption>[
      _SubtitleSearchOption(
        label: 'SubHD',
        uri: Uri.parse(
          'https://subhd.tv/search/${Uri.encodeComponent(query)}',
        ),
      ),
      _SubtitleSearchOption(
        label: 'Bing',
        uri: Uri.https('www.bing.com', '/search', {'q': '$query 字幕'}),
      ),
      _SubtitleSearchOption(
        label: '百度',
        uri: Uri.https('www.baidu.com', '/s', {'wd': '$query 字幕'}),
      ),
    ];

    final selection = await showDialog<_SubtitleSearchOption>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('在线查找字幕'),
          children: [
            for (final option in options)
              SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(option),
                child: Text(option.label),
              ),
          ],
        );
      },
    );
    if (selection == null) {
      return;
    }

    bool launched = false;
    try {
      launched = await launchUrl(
        selection.uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      launched = false;
    }
    if (!launched) {
      _showMessage('打开字幕搜索失败');
    }
  }

  Future<void> _configureSeriesSkipPreference(Player player) async {
    final target = _resolvedTarget ?? widget.target;
    final seriesKey = buildSeriesKeyForTarget(target);
    if (seriesKey.isEmpty) {
      _showMessage('当前内容没有可绑定的剧集信息，暂时不能按剧设置跳过规则');
      return;
    }

    final playerDuration = _latestDuration > Duration.zero
        ? _latestDuration
        : player.state.duration;
    final currentPosition = _latestPosition;
    final seedPreference = _seriesSkipPreference ??
        SeriesSkipPreference(
          seriesKey: seriesKey,
          updatedAt: DateTime.now(),
          seriesTitle: target.resolvedSeriesTitle,
        );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var enabled = seedPreference.enabled;
        var introDuration = seedPreference.introDuration;
        var outroDuration = seedPreference.outroDuration;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final canCaptureOutro = playerDuration > Duration.zero &&
                currentPosition < playerDuration;
            return AlertDialog(
              title: Text(
                target.resolvedSeriesTitle.isEmpty ? '跳过片头片尾' : '本剧跳过设置',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StarflowToggleTile(
                    title: '自动跳过',
                    subtitle: target.resolvedSeriesTitle.isEmpty
                        ? '只对当前绑定的剧集生效'
                        : '只对《${target.resolvedSeriesTitle}》生效',
                    value: enabled,
                    onChanged: (value) {
                      setDialogState(() {
                        enabled = value;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  StarflowSelectionTile(
                    title: '片头结束位置',
                    subtitle: introDuration > Duration.zero
                        ? _formatClockDuration(introDuration)
                        : '未设置',
                    onPressed: () {
                      setDialogState(() {
                        introDuration = currentPosition;
                      });
                    },
                    trailing: StarflowButton(
                      label: '用当前位置',
                      onPressed: () {
                        setDialogState(() {
                          introDuration = currentPosition;
                        });
                      },
                      variant: StarflowButtonVariant.secondary,
                      compact: true,
                    ),
                  ),
                  StarflowSelectionTile(
                    title: '片尾提前跳过',
                    subtitle: outroDuration > Duration.zero
                        ? '距结尾 ${_formatClockDuration(outroDuration)}'
                        : '未设置',
                    onPressed: !canCaptureOutro
                        ? null
                        : () {
                            setDialogState(() {
                              outroDuration = playerDuration - currentPosition;
                            });
                          },
                    trailing: StarflowButton(
                      label: '用当前位置',
                      onPressed: !canCaptureOutro
                          ? null
                          : () {
                              setDialogState(() {
                                outroDuration =
                                    playerDuration - currentPosition;
                              });
                            },
                      variant: StarflowButtonVariant.secondary,
                      compact: true,
                    ),
                  ),
                  if (playerDuration > Duration.zero)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '当前位置 ${_formatClockDuration(currentPosition)} / ${_formatClockDuration(playerDuration)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
              actions: [
                StarflowButton(
                  label: '清空',
                  onPressed: () {
                    setDialogState(() {
                      enabled = false;
                      introDuration = Duration.zero;
                      outroDuration = Duration.zero;
                    });
                  },
                  variant: StarflowButtonVariant.secondary,
                  compact: true,
                ),
                StarflowButton(
                  label: '取消',
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  variant: StarflowButtonVariant.ghost,
                  compact: true,
                ),
                StarflowButton(
                  label: '保存',
                  onPressed: () async {
                    final nextPreference = SeriesSkipPreference(
                      seriesKey: seriesKey,
                      updatedAt: DateTime.now(),
                      seriesTitle: target.resolvedSeriesTitle,
                      enabled: enabled,
                      introDuration: introDuration,
                      outroDuration: outroDuration,
                    );
                    await ref
                        .read(playbackMemoryRepositoryProvider)
                        .saveSkipPreference(nextPreference);
                    if (!mounted) {
                      return;
                    }
                    if (!dialogContext.mounted) {
                      return;
                    }
                    setState(() {
                      _seriesSkipPreference = nextPreference;
                    });
                    _syncSkipFlagsWithCurrentPosition();
                    Navigator.of(dialogContext).pop();
                  },
                  compact: true,
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _buildPlaybackErrorMessage(Object error) {
    if (error is TimeoutException) {
      return error.message ?? '超过最大等待时间，已停止尝试播放';
    }
    if (error is _PlayerOpenException) {
      return error.message;
    }
    return '$error';
  }

  Future<PlaybackTarget> _resolveTarget(PlaybackTarget target) async {
    if (!target.needsResolution) {
      return target;
    }

    final settings = ref.read(appSettingsProvider);
    MediaSourceConfig? source;
    for (final candidate in settings.mediaSources) {
      if (candidate.id == target.sourceId) {
        source = candidate;
        break;
      }
    }

    if (source == null) {
      throw const _PlayerOpenException('媒体源不存在或已被移除');
    }
    if (source.kind == MediaSourceKind.emby) {
      if (!source.hasActiveSession) {
        throw const EmbyApiException('Emby 会话已失效，请重新登录');
      }
      return ref.read(embyApiClientProvider).resolvePlaybackTarget(
            source: source,
            target: target,
          );
    }
    return ref.read(webDavNasClientProvider).resolvePlaybackTarget(
          source: source,
          target: target,
        );
  }

  Future<void> _runStartupProbe(PlaybackTarget target) async {
    final probe = await _probeStartup(target);
    if (!mounted) {
      return;
    }
    setState(() {
      _startupProbe = probe;
    });
  }

  Future<_StartupProbeResult> _probeStartup(PlaybackTarget target) async {
    final streamUrl = target.streamUrl.trim();
    if (streamUrl.isEmpty) {
      return const _StartupProbeResult();
    }

    final uri = Uri.tryParse(streamUrl);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return const _StartupProbeResult();
    }

    final client = StarflowHttpClient(http.Client());
    StreamSubscription<List<int>>? subscription;
    final completer = Completer<_StartupProbeResult>();
    final stopwatch = Stopwatch();
    var completed = false;
    var bytesRead = 0;

    Future<void> finish() async {
      if (completed) {
        return;
      }
      completed = true;
      stopwatch.stop();
      await subscription?.cancel();
      client.close();

      final elapsedSeconds = stopwatch.elapsedMilliseconds <= 0
          ? 0.0
          : stopwatch.elapsedMilliseconds / 1000;
      final speedBytesPerSecond = elapsedSeconds <= 0 || bytesRead <= 0
          ? null
          : (bytesRead / elapsedSeconds).round();

      completer.complete(
        _StartupProbeResult(
          estimatedSpeedBytesPerSecond: speedBytesPerSecond,
        ),
      );
    }

    try {
      final request = http.Request('GET', uri)
        ..headers.addAll(target.headers)
        ..headers['Range'] = 'bytes=0-262143';
      stopwatch.start();
      final response = await client.send(request).timeout(
            const Duration(seconds: 4),
          );

      subscription = response.stream.listen(
        (chunk) {
          bytesRead += chunk.length;
          if (bytesRead >= 192 * 1024 ||
              stopwatch.elapsedMilliseconds >= 1400) {
            unawaited(finish());
          }
        },
        onError: (_) {
          unawaited(finish());
        },
        onDone: () {
          unawaited(finish());
        },
        cancelOnError: true,
      );

      return completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () async {
          await finish();
          return completer.future;
        },
      );
    } catch (_) {
      await subscription?.cancel();
      client.close();
      return const _StartupProbeResult();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeTarget = _resolvedTarget ?? widget.target;
    final isTelevision = ref.watch(isTelevisionProvider).valueOrNull ?? false;
    final playbackSettings = ref.watch(appSettingsProvider);
    final showMinimalPlayerChrome = _isInPictureInPictureMode ||
        playbackSettings.highPerformanceModeEnabled;

    return Shortcuts(
      shortcuts: isTelevision
          ? const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.goBack): DismissIntent(),
              SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
              SingleActivator(LogicalKeyboardKey.backspace): DismissIntent(),
              SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.mediaPlayPause):
                  ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.mediaPlay): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.mediaPause): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.contextMenu):
                  _OpenPlaybackOptionsIntent(),
              SingleActivator(LogicalKeyboardKey.gameButtonY):
                  _OpenPlaybackOptionsIntent(),
              SingleActivator(LogicalKeyboardKey.arrowLeft):
                  DirectionalFocusIntent(TraversalDirection.left),
              SingleActivator(LogicalKeyboardKey.arrowRight):
                  DirectionalFocusIntent(TraversalDirection.right),
            }
          : const <ShortcutActivator, Intent>{},
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              context.pop();
              return null;
            },
          ),
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _togglePlayback();
              return null;
            },
          ),
          _OpenPlaybackOptionsIntent:
              CallbackAction<_OpenPlaybackOptionsIntent>(
            onInvoke: (_) {
              _showPlaybackOptions(
                isTelevision: isTelevision,
                settings: playbackSettings,
              );
              return null;
            },
          ),
          DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
            onInvoke: (intent) {
              if (intent.direction == TraversalDirection.left) {
                _seekRelative(-_kSeekStep);
              } else if (intent.direction == TraversalDirection.right) {
                _seekRelative(_kSeekStep);
              }
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          canRequestFocus: isTelevision,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: showMinimalPlayerChrome
                ? ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: _currentAspectRatio(),
                        child: _buildVideoSurface(
                          theme,
                          isTelevision: isTelevision,
                          settings: playbackSettings,
                        ),
                      ),
                    ),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: Colors.black,
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: _currentAspectRatio(),
                            child: _buildVideoSurface(
                              theme,
                              isTelevision: isTelevision,
                              settings: playbackSettings,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.black.withValues(alpha: 0.62),
                                Colors.black.withValues(alpha: 0.22),
                                Colors.transparent,
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                          child: OverlayToolbar(
                            onBack: () => context.pop(),
                            trailing: StarflowIconButton(
                              icon: Icons.tune_rounded,
                              tooltip: '播放设置',
                              variant: StarflowButtonVariant.ghost,
                              onPressed: _player == null
                                  ? null
                                  : () => _showPlaybackOptions(
                                        isTelevision: isTelevision,
                                        settings: playbackSettings,
                                      ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.16),
                                  Colors.black.withValues(alpha: 0.62),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                            child: SafeArea(
                              top: false,
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(18, 40, 18, 18),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      activeTarget.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.headlineSmall
                                          ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${activeTarget.sourceKind.label} · ${activeTarget.sourceName}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color: const Color(0xCCFFFFFF),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _togglePlayback() async {
    final player = _player;
    if (!_isReady || player == null) {
      return;
    }
    await player.playOrPause();
  }

  Future<void> _seekRelative(Duration delta) async {
    final player = _player;
    if (!_isReady || player == null) {
      return;
    }
    final current = player.state.position;
    final target = current + delta;
    await player.seek(target < Duration.zero ? Duration.zero : target);
  }

  Widget _buildVideoSurface(
    ThemeData theme, {
    required bool isTelevision,
    required AppSettings settings,
  }) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '播放失败：$_error',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white),
          ),
        ),
      );
    }

    final player = _player;
    final videoController = _videoController;
    if (!_isReady || player == null || videoController == null) {
      return _PlayerStartupOverlay(
        target: _resolvedTarget ?? widget.target,
        probe: _startupProbe,
      );
    }

    return StreamBuilder<int?>(
      stream: player.stream.width,
      initialData: player.state.width,
      builder: (context, widthSnapshot) {
        return StreamBuilder<int?>(
          stream: player.stream.height,
          initialData: player.state.height,
          builder: (context, heightSnapshot) {
            final width = widthSnapshot.data ?? 0;
            final height = heightSnapshot.data ?? 0;
            final aspectRatio =
                width > 0 && height > 0 ? width / height : 16 / 9;
            return ColoredBox(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: aspectRatio,
                      child: Video(
                        controller: videoController,
                        controls: isTelevision
                            ? NoVideoControls
                            : AdaptiveVideoControls,
                        fill: Colors.black,
                        fit: BoxFit.contain,
                        subtitleViewConfiguration:
                            _buildSubtitleViewConfiguration(
                          settings,
                          isTelevision: isTelevision,
                        ),
                      ),
                    ),
                  ),
                  if (!_isHighPerformancePlaybackMode)
                    StreamBuilder<bool>(
                      stream: player.stream.buffering,
                      initialData: player.state.buffering,
                      builder: (context, bufferingSnapshot) {
                        final isBuffering = bufferingSnapshot.data ?? false;
                        if (!isBuffering) {
                          return const SizedBox.shrink();
                        }
                        return StreamBuilder<double>(
                          stream: player.stream.bufferingPercentage,
                          initialData: player.state.bufferingPercentage,
                          builder: (context, progressSnapshot) {
                            return IgnorePointer(
                              child: _PlayerStartupOverlay(
                                target: _resolvedTarget ?? widget.target,
                                probe: _startupProbe,
                                bufferingProgress: progressSnapshot.data,
                              ),
                            );
                          },
                        );
                      },
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  double _currentAspectRatio() {
    final player = _player;
    if (!_isReady || player == null) {
      return 16 / 9;
    }

    final width = player.state.width ?? 0;
    final height = player.state.height ?? 0;
    if (width <= 0 || height <= 0) {
      return 16 / 9;
    }
    return width / height;
  }

  SubtitleViewConfiguration _buildSubtitleViewConfiguration(
    AppSettings settings, {
    required bool isTelevision,
  }) {
    final simplifyForPerformance = settings.highPerformanceModeEnabled;
    return SubtitleViewConfiguration(
      style: TextStyle(
        height: 1.35,
        fontSize: (simplifyForPerformance ? 28 : 32) *
            settings.playbackSubtitleScale.textScale,
        color: Colors.white,
        fontWeight: FontWeight.w600,
        backgroundColor: simplifyForPerformance
            ? Colors.transparent
            : const Color(0xAA000000),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        simplifyForPerformance ? 18 : 28,
      ),
    );
  }

  bool _shouldAutoDowngradeToSystemPlayer(PlaybackTarget target) {
    if (!_highPerformanceModeEnabled) {
      return false;
    }
    final isTelevision = ref.read(isTelevisionProvider).valueOrNull ?? false;
    if (!isTelevision) {
      return false;
    }
    if (ref.read(appSettingsProvider).playbackEngine !=
        PlaybackEngine.embeddedMpv) {
      return false;
    }
    if (kIsWeb) {
      return false;
    }

    final width = target.width ?? 0;
    final height = target.height ?? 0;
    final bitrate = target.bitrate ?? 0;
    final codec = target.videoCodec.trim().toLowerCase();
    final is4k = width >= 3840 || height >= 2160;
    final isHevc = codec == 'hevc' || codec == 'h265' || codec == 'x265';
    final veryHighBitrate = bitrate >= 25000000;
    final heavyHevc = isHevc && (is4k || bitrate >= 18000000);
    return is4k || veryHighBitrate || heavyHevc;
  }

  Future<void> _showPlaybackOptions({
    required bool isTelevision,
    required AppSettings settings,
  }) async {
    final player = _player;
    if (player == null || !mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return _PlaybackOptionsDialog(
          player: player,
          target: _resolvedTarget ?? widget.target,
          isTelevision: isTelevision,
          defaultSubtitleScaleLabel: settings.playbackSubtitleScale.label,
          subtitleDelayLabel: _formatSubtitleDelayLabel(
            _subtitleDelaySeconds,
            supported: _subtitleDelaySupported,
          ),
          seriesSkipLabel: _formatSeriesSkipPreferenceLabel(
            _seriesSkipPreference,
            target: _resolvedTarget ?? widget.target,
          ),
          onSelectSpeed: (currentRate) =>
              _selectPlaybackSpeed(player, currentRate),
          onSelectSubtitle: (tracks, current) =>
              _selectSubtitleTrack(player, tracks, current),
          onSelectAudio: (tracks, current) =>
              _selectAudioTrack(player, tracks, current),
          onAdjustSubtitleDelay: () => _openSubtitleDelayDialog(player),
          onLoadExternalSubtitle: () => _loadExternalSubtitle(player),
          onSearchSubtitlesOnline: () =>
              _showOnlineSubtitleSearch(_resolvedTarget ?? widget.target),
          onConfigureSeriesSkip: () => _configureSeriesSkipPreference(player),
        );
      },
    );
  }

  Future<void> _selectPlaybackSpeed(Player player, double currentRate) async {
    final selection = await showDialog<double>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('播放速度'),
          children: [
            for (final rate in _kSpeedOptions)
              SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(rate),
                child: Text(
                  rate == currentRate
                      ? '${_formatPlaybackSpeed(rate)}  当前'
                      : _formatPlaybackSpeed(rate),
                ),
              ),
          ],
        );
      },
    );
    if (selection == null) {
      return;
    }

    await _runPlayerCommand(
      () => player.setRate(selection),
      failureMessage: '切换播放速度失败',
    );
  }

  Future<void> _selectSubtitleTrack(
    Player player,
    List<SubtitleTrack> tracks,
    SubtitleTrack current,
  ) async {
    final selection = await showDialog<SubtitleTrack>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('字幕选择'),
          children: [
            for (final track in tracks)
              SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(track),
                child: Text(
                  track == current
                      ? '${_formatSubtitleTrackLabel(track)}  当前'
                      : _formatSubtitleTrackLabel(track),
                ),
              ),
          ],
        );
      },
    );
    if (selection == null) {
      return;
    }

    await _runPlayerCommand(
      () => player.setSubtitleTrack(selection),
      failureMessage: '切换字幕失败',
    );
  }

  Future<void> _selectAudioTrack(
    Player player,
    List<AudioTrack> tracks,
    AudioTrack current,
  ) async {
    final selection = await showDialog<AudioTrack>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('音轨选择'),
          children: [
            for (final track in tracks)
              SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(track),
                child: Text(
                  track == current
                      ? '${_formatAudioTrackLabel(track)}  当前'
                      : _formatAudioTrackLabel(track),
                ),
              ),
          ],
        );
      },
    );
    if (selection == null) {
      return;
    }

    await _runPlayerCommand(
      () => player.setAudioTrack(selection),
      failureMessage: '切换音轨失败',
    );
  }

  Future<void> _runPlayerCommand(
    Future<void> Function() action, {
    required String failureMessage,
  }) async {
    try {
      await action();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$failureMessage：$error')),
      );
    }
  }
}

class _PlayerStartupOverlay extends StatelessWidget {
  const _PlayerStartupOverlay({
    required this.target,
    required this.probe,
    this.bufferingProgress,
  });

  final PlaybackTarget target;
  final _StartupProbeResult probe;
  final double? bufferingProgress;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: Colors.white,
            ),
          ),
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + kToolbarHeight + 12,
          right: 18,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _StartupMetricText(
                label: '网速',
                value: probe.speedLabel.isEmpty ? '测速中' : probe.speedLabel,
              ),
              const SizedBox(height: 6),
              _StartupMetricText(
                label: '格式',
                value: _buildFormatValue(target),
              ),
              if (_normalizeBufferProgress(bufferingProgress)
                  case final progress?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SizedBox(
                    width: 108,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 2.5,
                        value: progress,
                        color: Colors.white,
                        backgroundColor: Colors.white.withValues(alpha: 0.16),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static double? _normalizeBufferProgress(double? value) {
    final progress = value ?? 0;
    if (progress <= 0) {
      return null;
    }
    if (progress > 1) {
      return (progress / 100).clamp(0.0, 1.0);
    }
    return progress.clamp(0.0, 1.0);
  }

  static String _buildFormatValue(PlaybackTarget target) {
    final parts = <String>[
      if (target.resolutionLabel.isNotEmpty) target.resolutionLabel,
      if (target.formatLabel.isNotEmpty) target.formatLabel,
      if (target.bitrateLabel.isNotEmpty) target.bitrateLabel,
    ];
    if (parts.isEmpty) {
      return '识别中';
    }
    return parts.join(' · ');
  }
}

class _StartupMetricText extends StatelessWidget {
  const _StartupMetricText({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RichText(
      textAlign: TextAlign.right,
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              shadows: const [
                Shadow(
                  color: Color(0xA6000000),
                  blurRadius: 10,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              shadows: [
                Shadow(
                  color: Color(0xB8000000),
                  blurRadius: 12,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StartupProbeResult {
  const _StartupProbeResult({
    this.estimatedSpeedBytesPerSecond,
  });

  final int? estimatedSpeedBytesPerSecond;

  String get speedLabel {
    final speed = estimatedSpeedBytesPerSecond ?? 0;
    if (speed <= 0) {
      return '';
    }
    return '${formatByteSize(speed)}/s';
  }
}

class _PictureInPictureAspectRatio {
  const _PictureInPictureAspectRatio({
    required this.width,
    required this.height,
  });

  final int width;
  final int height;
}

class _OpenedPlayback {
  const _OpenedPlayback({
    required this.player,
    required this.videoController,
    required this.errorSubscription,
  });

  final Player player;
  final VideoController videoController;
  final StreamSubscription<String> errorSubscription;
}

class _PlaybackOptionsDialog extends StatelessWidget {
  const _PlaybackOptionsDialog({
    required this.player,
    required this.target,
    required this.isTelevision,
    required this.defaultSubtitleScaleLabel,
    required this.subtitleDelayLabel,
    required this.seriesSkipLabel,
    required this.onSelectSpeed,
    required this.onSelectSubtitle,
    required this.onSelectAudio,
    required this.onAdjustSubtitleDelay,
    required this.onLoadExternalSubtitle,
    required this.onSearchSubtitlesOnline,
    required this.onConfigureSeriesSkip,
  });

  final Player player;
  final PlaybackTarget target;
  final bool isTelevision;
  final String defaultSubtitleScaleLabel;
  final String subtitleDelayLabel;
  final String seriesSkipLabel;
  final Future<void> Function(double currentRate) onSelectSpeed;
  final Future<void> Function(
    List<SubtitleTrack> tracks,
    SubtitleTrack current,
  ) onSelectSubtitle;
  final Future<void> Function(
    List<AudioTrack> tracks,
    AudioTrack current,
  ) onSelectAudio;
  final Future<void> Function() onAdjustSubtitleDelay;
  final Future<void> Function() onLoadExternalSubtitle;
  final Future<void> Function() onSearchSubtitlesOnline;
  final Future<void> Function() onConfigureSeriesSkip;

  Future<void> _openSubtitleOptionsDialog(
    BuildContext context,
    Tracks tracks,
    Track currentTrack,
  ) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _PlaybackSubtitleOptionsDialog(
          isTelevision: isTelevision,
          currentSubtitleLabel:
              _formatSubtitleTrackLabel(currentTrack.subtitle),
          defaultSubtitleScaleLabel: defaultSubtitleScaleLabel,
          subtitleDelayLabel: subtitleDelayLabel,
          onSelectSubtitle: () =>
              onSelectSubtitle(tracks.subtitle, currentTrack.subtitle),
          onAdjustSubtitleDelay: onAdjustSubtitleDelay,
          onLoadExternalSubtitle: onLoadExternalSubtitle,
          onSearchSubtitlesOnline: onSearchSubtitlesOnline,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('播放设置'),
      content: SizedBox(
        width: 440,
        child: StreamBuilder<Tracks>(
          stream: player.stream.tracks,
          initialData: player.state.tracks,
          builder: (context, tracksSnapshot) {
            final tracks = tracksSnapshot.data ?? const Tracks();
            return StreamBuilder<Track>(
              stream: player.stream.track,
              initialData: player.state.track,
              builder: (context, trackSnapshot) {
                final currentTrack = trackSnapshot.data ?? const Track();
                return StreamBuilder<double>(
                  stream: player.stream.rate,
                  initialData: player.state.rate,
                  builder: (context, rateSnapshot) {
                    final rate = rateSnapshot.data ?? 1.0;
                    return ListView(
                      shrinkWrap: true,
                      children: [
                        Text(
                          target.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _buildPlaybackOptionMeta(target),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                        ),
                        const SizedBox(height: 16),
                        _PlaybackOptionTile(
                          isTelevision: isTelevision,
                          title: '播放速度',
                          value: _formatPlaybackSpeed(rate),
                          onPressed: () => onSelectSpeed(rate),
                        ),
                        const SizedBox(height: 10),
                        _PlaybackOptionTile(
                          isTelevision: isTelevision,
                          title: '字幕',
                          value: _buildSubtitleOptionsSummary(
                            currentTrack.subtitle,
                            subtitleDelayLabel: subtitleDelayLabel,
                          ),
                          onPressed: () => _openSubtitleOptionsDialog(
                            context,
                            tracks,
                            currentTrack,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _PlaybackOptionTile(
                          isTelevision: isTelevision,
                          title: '音轨',
                          value: _formatAudioTrackLabel(currentTrack.audio),
                          onPressed: () =>
                              onSelectAudio(tracks.audio, currentTrack.audio),
                        ),
                        const SizedBox(height: 10),
                        _PlaybackOptionTile(
                          isTelevision: isTelevision,
                          title: '本剧跳过片头片尾',
                          value: seriesSkipLabel,
                          onPressed: onConfigureSeriesSkip,
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
      actions: [
        StarflowButton(
          label: '关闭',
          onPressed: () => Navigator.of(context).pop(),
          variant: StarflowButtonVariant.ghost,
          compact: true,
        ),
      ],
    );
  }
}

class _PlaybackSubtitleOptionsDialog extends StatelessWidget {
  const _PlaybackSubtitleOptionsDialog({
    required this.isTelevision,
    required this.currentSubtitleLabel,
    required this.defaultSubtitleScaleLabel,
    required this.subtitleDelayLabel,
    required this.onSelectSubtitle,
    required this.onAdjustSubtitleDelay,
    required this.onLoadExternalSubtitle,
    required this.onSearchSubtitlesOnline,
  });

  final bool isTelevision;
  final String currentSubtitleLabel;
  final String defaultSubtitleScaleLabel;
  final String subtitleDelayLabel;
  final Future<void> Function() onSelectSubtitle;
  final Future<void> Function() onAdjustSubtitleDelay;
  final Future<void> Function() onLoadExternalSubtitle;
  final Future<void> Function() onSearchSubtitlesOnline;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('字幕'),
      content: SizedBox(
        width: 440,
        child: ListView(
          shrinkWrap: true,
          children: [
            _PlaybackOptionTile(
              isTelevision: isTelevision,
              title: '字幕选择',
              value: currentSubtitleLabel,
              onPressed: onSelectSubtitle,
            ),
            const SizedBox(height: 10),
            _PlaybackOptionTile(
              isTelevision: isTelevision,
              title: '字幕偏移',
              value: subtitleDelayLabel,
              onPressed: onAdjustSubtitleDelay,
            ),
            const SizedBox(height: 10),
            _PlaybackOptionTile(
              isTelevision: isTelevision,
              title: '加载外部字幕',
              value: '选择 SRT / ASS / SSA / VTT',
              onPressed: onLoadExternalSubtitle,
            ),
            const SizedBox(height: 10),
            _PlaybackOptionTile(
              isTelevision: isTelevision,
              title: '在线查找字幕',
              value: 'SubHD / 搜索引擎',
              onPressed: onSearchSubtitlesOnline,
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '默认字幕大小',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$defaultSubtitleScaleLabel，可在设置页修改',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        StarflowButton(
          label: '关闭',
          onPressed: () => Navigator.of(context).pop(),
          variant: StarflowButtonVariant.ghost,
          compact: true,
        ),
      ],
    );
  }
}

class _PlaybackOptionTile extends StatelessWidget {
  const _PlaybackOptionTile({
    required this.isTelevision,
    required this.title,
    required this.value,
    required this.onPressed,
  });

  final bool isTelevision;
  final String title;
  final String value;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return StarflowSelectionTile(
      title: title,
      subtitle: value,
      onPressed: () {
        unawaited(onPressed());
      },
    );
  }
}

class _SubtitleSearchOption {
  const _SubtitleSearchOption({
    required this.label,
    required this.uri,
  });

  final String label;
  final Uri uri;
}

class _PlayerOpenException implements Exception {
  const _PlayerOpenException(this.message);

  final String message;

  @override
  String toString() => message;
}

String _buildSubtitleOptionsSummary(
  SubtitleTrack track, {
  required String subtitleDelayLabel,
}) {
  return '${_formatSubtitleTrackLabel(track)} · 偏移 $subtitleDelayLabel';
}

String _buildPlaybackOptionMeta(PlaybackTarget target) {
  final parts = <String>[
    if (target.resolutionLabel.isNotEmpty) target.resolutionLabel,
    if (target.formatLabel.isNotEmpty) target.formatLabel,
    if (target.bitrateLabel.isNotEmpty) target.bitrateLabel,
  ];
  if (parts.isEmpty) {
    return '${target.sourceKind.label} · ${target.sourceName}';
  }
  return '${target.sourceKind.label} · ${target.sourceName} · ${parts.join(' · ')}';
}

String _formatPlaybackSpeed(double speed) {
  if (speed == speed.roundToDouble()) {
    return '${speed.toStringAsFixed(0)}x';
  }
  return '${speed.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')}x';
}

String _formatSubtitleDelayLabel(
  double seconds, {
  required bool supported,
}) {
  if (!supported) {
    return '当前内核暂不支持';
  }
  return _formatSubtitleDelayValue(seconds);
}

String _formatSubtitleDelayValue(double seconds) {
  if (seconds.abs() < 0.001) {
    return '0s';
  }
  final normalized = seconds
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
  return seconds > 0 ? '+${normalized}s' : '${normalized}s';
}

String _formatSeriesSkipPreferenceLabel(
  SeriesSkipPreference? preference, {
  required PlaybackTarget target,
}) {
  final seriesKey = buildSeriesKeyForTarget(target);
  if (seriesKey.isEmpty) {
    return '当前内容没有可绑定的剧集信息';
  }
  if (preference == null ||
      (!preference.enabled &&
          preference.introDuration <= Duration.zero &&
          preference.outroDuration <= Duration.zero)) {
    return '未设置';
  }

  final parts = <String>[
    preference.enabled ? '已开启' : '已关闭',
    if (preference.introDuration > Duration.zero)
      '片头 ${_formatClockDuration(preference.introDuration)}',
    if (preference.outroDuration > Duration.zero)
      '片尾 ${_formatClockDuration(preference.outroDuration)}',
  ];
  return parts.join(' · ');
}

String _buildSubtitleSearchQuery(PlaybackTarget target) {
  final baseTitle = target.seriesTitle.trim().isNotEmpty
      ? target.seriesTitle.trim()
      : target.title.trim();
  final parts = <String>[
    if (baseTitle.isNotEmpty) baseTitle,
    if (target.seasonNumber != null && target.episodeNumber != null)
      'S${target.seasonNumber!.toString().padLeft(2, '0')}E${target.episodeNumber!.toString().padLeft(2, '0')}',
    if (!target.isEpisode && target.year > 0) '${target.year}',
  ];
  return parts.join(' ');
}

String _formatClockDuration(Duration value) {
  final totalSeconds = value.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String _formatAudioTrackLabel(AudioTrack track) {
  if (track.id == 'auto') {
    return '自动';
  }
  if (track.id == 'no') {
    return '关闭';
  }

  final parts = <String>[
    if ((track.title ?? '').trim().isNotEmpty) track.title!.trim(),
    if ((track.language ?? '').trim().isNotEmpty)
      track.language!.trim().toUpperCase(),
    if ((track.codec ?? '').trim().isNotEmpty)
      track.codec!.trim().toUpperCase(),
  ];
  final channelCount = track.audiochannels ?? track.channelscount;
  if (channelCount != null && channelCount > 0) {
    parts.add('${channelCount}ch');
  }
  if (track.isDefault == true) {
    parts.add('默认');
  }
  return parts.isEmpty ? '音轨 ${track.id}' : parts.join(' · ');
}

String _formatSubtitleTrackLabel(SubtitleTrack track) {
  if (track.id == 'auto') {
    return '自动';
  }
  if (track.id == 'no') {
    return '关闭';
  }

  final parts = <String>[
    if ((track.title ?? '').trim().isNotEmpty) track.title!.trim(),
    if ((track.language ?? '').trim().isNotEmpty)
      track.language!.trim().toUpperCase(),
  ];
  if (track.isDefault == true) {
    parts.add('默认');
  }
  return parts.isEmpty ? '字幕 ${track.id}' : parts.join(' · ');
}
