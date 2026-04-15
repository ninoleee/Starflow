import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:starflow/core/platform/android_picture_in_picture.dart';
import 'package:starflow/core/platform/background_playback.dart';
import 'package:starflow/core/platform/playback_system_session.dart';
import 'package:starflow/core/utils/playback_trace.dart';
import 'package:starflow/core/utils/subtitle_search_trace.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/network/starflow_http_client.dart';
import 'package:starflow/core/widgets/starflow_action_dialog.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/active_playback_cleanup.dart';
import 'package:starflow/features/playback/application/mpv_tuning_policy.dart';
import 'package:starflow/features/playback/application/playback_remote_preflight.dart';
import 'package:starflow/features/playback/application/playback_stream_relay_contract.dart';
import 'package:starflow/features/playback/application/playback_engine_router.dart';
import 'package:starflow/features/playback/application/playback_session.dart';
import 'package:starflow/features/playback/application/subtitle_language_preferences.dart';
import 'package:starflow/features/playback/application/playback_startup_coordinator.dart';
import 'package:starflow/features/playback/application/playback_startup_executor.dart';
import 'package:starflow/features/playback/application/playback_target_resolver.dart';
import 'package:starflow/features/playback/data/native_playback_launcher.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart'
    hide isLoopbackPlaybackRelayUrl;
import 'package:starflow/features/playback/data/subtitle_file_picker.dart';
import 'package:starflow/features/playback/data/system_playback_launcher.dart';
import 'package:starflow/features/playback/domain/playback_memory_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/playback/presentation/widgets/mpv_stall_watchdog.dart';
import 'package:starflow/features/playback/presentation/widgets/player_adaptive_top_chrome.dart';
import 'package:starflow/features/playback/presentation/widgets/player_playback_dialogs.dart';
import 'package:starflow/features/playback/presentation/widgets/player_playback_formatters.dart';
import 'package:starflow/features/playback/presentation/widgets/player_playback_options_dialog.dart';
import 'package:starflow/features/playback/presentation/widgets/player_playback_overlays.dart';
import 'package:starflow/features/playback/presentation/widgets/player_tv_playback_widgets.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

part 'widgets/player_page_platform_session.part.dart';
part 'widgets/player_page_startup_mpv.part.dart';
part 'widgets/player_page_runtime_actions.part.dart';
part 'widgets/player_page_controls.part.dart';

class _OpenPlaybackOptionsIntent extends Intent {
  const _OpenPlaybackOptionsIntent();
}

class _ShowTvPlaybackChromeIntent extends Intent {
  const _ShowTvPlaybackChromeIntent();
}

@immutable
class _TvPlaybackState {
  const _TvPlaybackState({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playing = false,
    this.bufferingPercentage = 0.0,
  });

  final Duration position;
  final Duration duration;
  final bool playing;
  final double bufferingPercentage;

  _TvPlaybackState copyWith({
    Duration? position,
    Duration? duration,
    bool? playing,
    double? bufferingPercentage,
  }) {
    return _TvPlaybackState(
      position: position ?? this.position,
      duration: duration ?? this.duration,
      playing: playing ?? this.playing,
      bufferingPercentage: bufferingPercentage ?? this.bufferingPercentage,
    );
  }
}

class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key, required this.target});

  final PlaybackTarget target;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage>
    with WidgetsBindingObserver {
  static const MethodChannel _platformChannel = MethodChannel(
    'starflow/platform',
  );
  static const int _maxPlaybackAttempts = 3;
  static const _kSeekStep = Duration(seconds: 10);
  static const _kSubtitleDelaySteps = <double>[-2, -1, -0.5, 0, 0.5, 1, 2];
  static const _kProgressPersistInterval = Duration(seconds: 8);
  static const int _kDefaultMpvBufferSizeBytes = 32 * 1024 * 1024;
  static const int _kNetworkMpvBufferSizeBytes = 64 * 1024 * 1024;
  static const int _kHeavyMpvBufferSizeBytes = 96 * 1024 * 1024;
  static const int _kAggressiveMpvBufferSizeBytes = 128 * 1024 * 1024;
  static const int _kQuarkMpvBufferSizeBytes = 192 * 1024 * 1024;
  static const int _kAggressiveQuarkMpvBufferSizeBytes = 256 * 1024 * 1024;
  static const int _kMinMpvBackBufferSizeBytes = 8 * 1024 * 1024;
  static const int _kMaxMpvBackBufferSizeBytes = 32 * 1024 * 1024;
  static const int _kMaxQuarkMpvBackBufferSizeBytes = 64 * 1024 * 1024;
  static Future<void> _playerShutdownQueue = Future<void>.value();

  Player? _player;
  VideoController? _videoController;
  StreamSubscription<String>? _playerErrorSubscription;
  StreamSubscription<bool>? _playerPlayingSubscription;
  StreamSubscription<Duration>? _playerPositionSubscription;
  StreamSubscription<Duration>? _playerDurationSubscription;
  StreamSubscription<int?>? _playerWidthSubscription;
  StreamSubscription<int?>? _playerHeightSubscription;
  StreamSubscription<bool>? _playerBufferingSubscription;
  StreamSubscription<double>? _playerBufferingPercentageSubscription;
  PlaybackTarget? _resolvedTarget;
  _StartupProbeResult _startupProbe = const _StartupProbeResult();
  SeriesSkipPreference? _seriesSkipPreference;
  Object? _error;
  bool _isReady = false;
  bool _pictureInPictureSupported = false;
  bool _isInPictureInPictureMode = false;
  bool _playbackSystemSessionBound = false;
  bool _subtitleDelaySupported = false;
  double _subtitleDelaySeconds = 0;
  bool _tvPlaybackChromeVisible = false;
  final ValueNotifier<_TvPlaybackState> _tvPlaybackStateNotifier =
      ValueNotifier(const _TvPlaybackState());
  final FocusNode _tvBackControlFocusNode =
      FocusNode(debugLabel: 'tv-player-control-back');
  final FocusNode _tvPlayPauseControlFocusNode =
      FocusNode(debugLabel: 'tv-player-control-play');
  final FocusNode _tvSubtitleControlFocusNode =
      FocusNode(debugLabel: 'tv-player-control-subtitle');
  final FocusNode _tvAudioControlFocusNode =
      FocusNode(debugLabel: 'tv-player-control-audio');
  final FocusNode _tvMoreControlFocusNode =
      FocusNode(debugLabel: 'tv-player-control-more');
  final PlayerAdaptiveTopChromeController _adaptiveTopChromeController =
      PlayerAdaptiveTopChromeController(
    visible: true,
    autoHideEnabled: true,
  );
  final PlaybackRemotePreflight _playbackRemotePreflight =
      PlaybackRemotePreflight();
  PlaybackRemotePreflightResult? _lastRemotePreflight;
  LogicalKeyboardKey? _tvSeekHoldKey;
  DateTime? _tvSeekHoldStartedAt;
  int _tvSeekHoldRepeatCount = 0;

  List<FocusNode> get _tvChromeControlFocusNodes => <FocusNode>[
        _tvBackControlFocusNode,
        _tvPlayPauseControlFocusNode,
        _tvSubtitleControlFocusNode,
        _tvAudioControlFocusNode,
        _tvMoreControlFocusNode,
      ];

  bool get _hasFocusedTvChromeControl =>
      _tvChromeControlFocusNodes.any((node) => node.hasFocus);

  void _updateTvPlaybackState({
    Duration? position,
    Duration? duration,
    bool? playing,
    double? bufferingPercentage,
  }) {
    final current = _tvPlaybackStateNotifier.value;
    final next = current.copyWith(
      position: position,
      duration: duration,
      playing: playing,
      bufferingPercentage: bufferingPercentage,
    );
    if (current.position == next.position &&
        current.duration == next.duration &&
        current.playing == next.playing &&
        current.bufferingPercentage == next.bufferingPercentage) {
      return;
    }
    _tvPlaybackStateNotifier.value = next;
  }

  bool _tvExitDialogVisible = false;
  bool _isEmbeddedMpvFullscreen = false;
  double _adaptiveGestureBrightness = 0.5;
  double _adaptiveGestureVolume = 1.0;
  int _adaptiveGestureLevelsRevision = 0;
  bool _introSkipApplied = false;
  bool _outroSkipApplied = false;
  Duration _latestPosition = Duration.zero;
  Duration _latestDuration = Duration.zero;
  DateTime? _lastProgressPersistedAt;
  Duration _lastPersistedPosition = Duration.zero;
  Duration _lastPlaybackSystemSessionPosition = Duration.zero;
  Duration _lastPlaybackSystemSessionDuration = Duration.zero;
  bool _lastPlaybackSystemSessionPlaying = false;
  bool _lastPlaybackSystemSessionBuffering = false;
  String _lastPlaybackSystemSessionTitle = '';
  String _lastPlaybackSystemSessionSubtitle = '';
  int? _lastTracedVideoWidth;
  int? _lastTracedVideoHeight;
  bool? _lastTracedBufferingState;
  int? _lastTracedBufferingBucket;
  late final ProviderContainer _providerContainer;
  late final StateController<bool> _playbackPerformanceModeController;
  Timer? _tvPlaybackChromeHideTimer;
  Timer? _mpvStallWatchdogTimer;
  Future<void>? _exitPlaybackFuture;
  int? _activePlaybackCleanupToken;
  MpvStallWatchdog? _mpvStallWatchdog;
  bool _mpvStallRecoveryInProgress = false;
  DateTime? _lastRuntimeMpvErrorAt;
  int _runtimeMpvErrorBurstCount = 0;
  int _runtimeMpvErrorRecoveryAttempts = 0;
  bool _runtimeMpvErrorRecoveryInProgress = false;

  @override
  void initState() {
    super.initState();
    _providerContainer = ProviderScope.containerOf(context, listen: false);
    WidgetsBinding.instance.addObserver(this);
    _playbackPerformanceModeController = ref.read(
      playbackPerformanceModeProvider.notifier,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _playbackPerformanceModeController.state = true;
    });
    _activePlaybackCleanupToken = ActivePlaybackCleanupCoordinator.register(
      _handleExternalPlaybackCleanup,
    );
    for (final node in _tvChromeControlFocusNodes) {
      node.addListener(_handleTvChromeControlFocusChanged);
    }
    unawaited(_bindAdaptiveGestureSystemLevels());
    unawaited(_bindPictureInPictureSupport());
    unawaited(_bindPlaybackSystemSession());
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tvPlaybackChromeHideTimer?.cancel();
    _stopMpvStallWatchdog();
    if (_useWindowManagedEmbeddedMpvFullscreen && _isEmbeddedMpvFullscreen) {
      unawaited(defaultExitNativeFullscreen());
    }
    final activePlaybackCleanupToken = _activePlaybackCleanupToken;
    if (activePlaybackCleanupToken != null) {
      ActivePlaybackCleanupCoordinator.unregister(activePlaybackCleanupToken);
      _activePlaybackCleanupToken = null;
    }
    Future<void>(() {
      _playbackPerformanceModeController.state = false;
    });
    final player = _detachActivePlayerState();
    unawaited(
      _shutdownDetachedPlayer(
        player,
        reason: 'player-page-dispose',
        persistProgress: true,
        teardownPlatformState: true,
      ),
    );
    _tvPlaybackStateNotifier.dispose();
    for (final node in _tvChromeControlFocusNodes) {
      node
        ..removeListener(_handleTvChromeControlFocusChanged)
        ..dispose();
    }
    _adaptiveTopChromeController.dispose();
    super.dispose();
  }

  Player? _detachActivePlayerState({
    bool clearStallRecoveryFlag = true,
  }) {
    final player = _player;
    _player = null;
    _videoController = null;
    _isReady = false;
    _isEmbeddedMpvFullscreen = false;
    _stopMpvStallWatchdog(clearRecoveryFlag: clearStallRecoveryFlag);
    _lastRuntimeMpvErrorAt = null;
    _runtimeMpvErrorBurstCount = 0;
    _runtimeMpvErrorRecoveryAttempts = 0;
    _runtimeMpvErrorRecoveryInProgress = false;
    return player;
  }

  Future<void> _shutdownDetachedPlayer(
    Player? player, {
    required String reason,
    required bool persistProgress,
    required bool teardownPlatformState,
  }) async {
    if (persistProgress) {
      await _persistPlaybackProgress(
        force: true,
        playerOverride: player,
      );
    }
    await _cancelPlayerSubscriptions();
    if (teardownPlatformState) {
      await _teardownPictureInPicture();
      await _teardownPlaybackSystemSession();
    }
    if (player != null) {
      await _enqueuePlayerShutdown(player, reason: reason);
    }
  }

  Future<void> _cancelPlayerSubscriptions() async {
    final errorSubscription = _playerErrorSubscription;
    final playingSubscription = _playerPlayingSubscription;
    final positionSubscription = _playerPositionSubscription;
    final durationSubscription = _playerDurationSubscription;
    final widthSubscription = _playerWidthSubscription;
    final heightSubscription = _playerHeightSubscription;
    final bufferingSubscription = _playerBufferingSubscription;
    final bufferingPercentageSubscription =
        _playerBufferingPercentageSubscription;

    _playerErrorSubscription = null;
    _playerPlayingSubscription = null;
    _playerPositionSubscription = null;
    _playerDurationSubscription = null;
    _playerWidthSubscription = null;
    _playerHeightSubscription = null;
    _playerBufferingSubscription = null;
    _playerBufferingPercentageSubscription = null;

    await errorSubscription?.cancel();
    await playingSubscription?.cancel();
    await positionSubscription?.cancel();
    await durationSubscription?.cancel();
    await widthSubscription?.cancel();
    await heightSubscription?.cancel();
    await bufferingSubscription?.cancel();
    await bufferingPercentageSubscription?.cancel();
  }

  Future<void> _handleExternalPlaybackCleanup(String reason) async {
    await _stopPlaybackBeforeExit(reason: reason);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_bindAdaptiveGestureSystemLevels());
    }
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
      ref.read(effectivePlaybackBackgroundEnabledProvider);

  AppSettings get _playbackSettings => ref.read(appSettingsProvider);

  bool get _leanPlaybackUiEnabled =>
      _playbackSettings.effectiveLeanPlaybackUiEnabled(
        isTelevision: _isTelevisionPlaybackDevice,
      );

  bool get _isLeanPlaybackMode =>
      _leanPlaybackUiEnabled && !_isInPictureInPictureMode;

  bool get _aggressivePlaybackTuningEnabled =>
      _playbackSettings.performanceAggressivePlaybackTuningEnabled;

  bool get _preferLeanPlaybackRendering => _leanPlaybackUiEnabled;

  PlaybackDecodeMode get _playbackDecodeMode =>
      _playbackSettings.playbackDecodeMode;

  PlaybackMpvQualityPreset get _playbackMpvQualityPreset =>
      PlaybackMpvQualityPreset.performanceFirst;

  bool get _mpvDoubleTapToSeekEnabled =>
      _playbackSettings.playbackMpvDoubleTapToSeekEnabled;

  bool get _mpvSwipeToSeekEnabled =>
      _playbackSettings.playbackMpvSwipeToSeekEnabled;

  bool get _mpvLongPressSpeedBoostEnabled =>
      _playbackSettings.playbackMpvLongPressSpeedBoostEnabled;

  bool get _mpvStallAutoRecoveryEnabled =>
      _playbackSettings.playbackMpvStallAutoRecoveryEnabled;

  bool get _autoDowngradePlaybackQualityEnabled =>
      _playbackSettings.performanceAutoDowngradeHeavyPlaybackEnabled;

  bool get _startupProbeEnabled =>
      _playbackSettings.effectiveStartupProbeEnabled;

  double? get _startupProbeMegabitsPerSecond {
    final bytesPerSecond = _startupProbe.estimatedSpeedBytesPerSecond;
    if (bytesPerSecond == null || bytesPerSecond <= 0) {
      return null;
    }
    return (bytesPerSecond * 8) / 1000000;
  }

  bool get _shouldTraceWindowsMpv {
    return false;
  }

  bool get _useWindowManagedEmbeddedMpvFullscreen {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.windows &&
        !_isTelevisionPlaybackDevice;
  }

  void _traceWindowsMpv(
    String stage, {
    Map<String, Object?> fields = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!_shouldTraceWindowsMpv) {
      return;
    }
    final target = _resolvedTarget ?? widget.target;
    playbackTrace(
      stage,
      fields: <String, Object?>{
        'title': target.title.trim().isEmpty ? 'Starflow' : target.title.trim(),
        'engine': 'embeddedMpv',
        ...fields,
      },
      error: error,
      stackTrace: stackTrace,
    );
  }

  Future<void> _waitForPendingPlayerShutdowns({
    required String reason,
  }) async {
    try {
      _traceWindowsMpv(
        'windows-mpv.shutdown.wait-begin',
        fields: {'reason': reason},
      );
      await _playerShutdownQueue;
      _traceWindowsMpv(
        'windows-mpv.shutdown.wait-end',
        fields: {'reason': reason},
      );
    } catch (error, stackTrace) {
      _traceWindowsMpv(
        'windows-mpv.shutdown.wait-error',
        fields: {'reason': reason},
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _enqueuePlayerShutdown(
    Player player, {
    required String reason,
  }) async {
    final shutdown = _playerShutdownQueue.then((_) async {
      _traceWindowsMpv(
        'windows-mpv.shutdown.begin',
        fields: {'reason': reason},
      );
      try {
        await player.pause();
      } catch (error, stackTrace) {
        _traceWindowsMpv(
          'windows-mpv.shutdown.pause-error',
          fields: {'reason': reason},
          error: error,
          stackTrace: stackTrace,
        );
      }
      try {
        await player.stop();
      } catch (error, stackTrace) {
        _traceWindowsMpv(
          'windows-mpv.shutdown.stop-error',
          fields: {'reason': reason},
          error: error,
          stackTrace: stackTrace,
        );
      }
      try {
        await player.dispose();
      } catch (error, stackTrace) {
        _traceWindowsMpv(
          'windows-mpv.shutdown.dispose-error',
          fields: {'reason': reason},
          error: error,
          stackTrace: stackTrace,
        );
      }
      _traceWindowsMpv(
        'windows-mpv.shutdown.end',
        fields: {'reason': reason},
      );
    });
    _playerShutdownQueue = shutdown.catchError((_) {});
    await shutdown;
  }

  Future<void> _stopPlaybackBeforeExit({
    required String reason,
  }) async {
    _traceWindowsMpv(
      'windows-mpv.exit.stop-before-pop',
      fields: {'reason': reason},
    );
    final player = _detachActivePlayerState();
    await _shutdownDetachedPlayer(
      player,
      reason: reason,
      persistProgress: true,
      teardownPlatformState: true,
    );
  }

  Future<void> _requestExitPlayer({
    required String reason,
  }) async {
    final inFlight = _exitPlaybackFuture;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    final request = _performExitPlayer(reason: reason);
    _exitPlaybackFuture = request;
    try {
      await request;
    } finally {
      if (identical(_exitPlaybackFuture, request)) {
        _exitPlaybackFuture = null;
      }
    }
  }

  Future<void> _performExitPlayer({
    required String reason,
  }) async {
    if (_useWindowManagedEmbeddedMpvFullscreen && _isEmbeddedMpvFullscreen) {
      await _setEmbeddedMpvFullscreen(
        false,
        reason: '$reason-before-exit',
      );
    }
    if (!_backgroundPlaybackEnabled) {
      await _stopPlaybackBeforeExit(reason: reason);
    } else {
      await _persistPlaybackProgress(force: true);
    }
    if (!mounted) {
      return;
    }
    context.pop();
  }

  bool _isTvSeekKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;
  }

  void _resetTvSeekHold({LogicalKeyboardKey? key}) {
    if (key != null && _tvSeekHoldKey != key) {
      return;
    }
    _tvSeekHoldKey = null;
    _tvSeekHoldStartedAt = null;
    _tvSeekHoldRepeatCount = 0;
  }

  Duration _resolveTvSeekStep({
    required Duration heldFor,
    required int repeatCount,
  }) {
    // Match common TV players: single press seeks a fixed step, long press
    // progressively increases the jump size.
    if (heldFor >= const Duration(seconds: 5) || repeatCount >= 12) {
      return const Duration(minutes: 2);
    }
    if (heldFor >= const Duration(seconds: 3) || repeatCount >= 7) {
      return const Duration(minutes: 1);
    }
    if (heldFor >= const Duration(milliseconds: 1500) || repeatCount >= 3) {
      return const Duration(seconds: 30);
    }
    return _kSeekStep;
  }

  void _handleTvChromeControlFocusChanged() {
    if (!_isTelevisionPlaybackDevice) {
      return;
    }
    if (_hasFocusedTvChromeControl) {
      _tvPlaybackChromeHideTimer?.cancel();
      if (!_tvPlaybackChromeVisible && mounted) {
        setState(() {
          _tvPlaybackChromeVisible = true;
        });
      }
      return;
    }
    if (_tvPlaybackChromeVisible && (_player?.state.playing ?? false)) {
      _scheduleTvPlaybackChromeHide();
    }
  }

  KeyEventResult _handleTvSeekKeyEvent(KeyEvent event) {
    if (!_isTelevisionPlaybackDevice ||
        !_isTvSeekKey(event.logicalKey) ||
        _hasFocusedTvChromeControl) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (event is KeyUpEvent) {
      _resetTvSeekHold(key: key);
      return KeyEventResult.handled;
    }

    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    if (_tvSeekHoldKey != key || _tvSeekHoldStartedAt == null) {
      _tvSeekHoldKey = key;
      _tvSeekHoldStartedAt = DateTime.now();
      _tvSeekHoldRepeatCount = 0;
    } else if (event is KeyRepeatEvent) {
      _tvSeekHoldRepeatCount += 1;
    }

    final heldFor = DateTime.now().difference(_tvSeekHoldStartedAt!);
    final step = _resolveTvSeekStep(
      heldFor: heldFor,
      repeatCount: _tvSeekHoldRepeatCount,
    );
    final direction = key == LogicalKeyboardKey.arrowLeft ? -1 : 1;
    final delta = Duration(milliseconds: step.inMilliseconds * direction);
    unawaited(_seekRelative(delta));
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    final playbackSettings = _playbackSettings;
    final leanPlaybackUiEnabled = ref.watch(
      appSettingsProvider.select(
        (settings) =>
            settings.effectiveLeanPlaybackUiEnabled(isTelevision: isTelevision),
      ),
    );
    final showMinimalPlayerChrome =
        _isInPictureInPictureMode || leanPlaybackUiEnabled;

    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        if (isTelevision) {
          unawaited(_handleTvBack());
        } else {
          unawaited(_handleDesktopBack(reason: 'route-back'));
        }
      },
      child: Shortcuts(
        shortcuts: isTelevision
            ? const <ShortcutActivator, Intent>{
                SingleActivator(LogicalKeyboardKey.goBack): DismissIntent(),
                SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
                SingleActivator(LogicalKeyboardKey.backspace): DismissIntent(),
                SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.numpadEnter):
                    ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.mediaPlayPause):
                    ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.mediaPlay): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.mediaPause):
                    ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.arrowUp):
                    _ShowTvPlaybackChromeIntent(),
                SingleActivator(LogicalKeyboardKey.arrowDown):
                    _OpenPlaybackOptionsIntent(),
                SingleActivator(LogicalKeyboardKey.contextMenu):
                    _OpenPlaybackOptionsIntent(),
                SingleActivator(LogicalKeyboardKey.gameButtonY):
                    _OpenPlaybackOptionsIntent(),
              }
            : const <ShortcutActivator, Intent>{},
        child: Actions(
          actions: <Type, Action<Intent>>{
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) {
                if (isTelevision) {
                  unawaited(_handleTvBack());
                } else {
                  unawaited(_handleDesktopBack(reason: 'dismiss-intent'));
                }
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
                if (isTelevision) {
                  _showTvPlaybackChrome(autoHide: false);
                }
                _showPlaybackOptions(
                  isTelevision: isTelevision,
                );
                return null;
              },
            ),
            _ShowTvPlaybackChromeIntent:
                CallbackAction<_ShowTvPlaybackChromeIntent>(
              onInvoke: (_) {
                if (isTelevision) {
                  _showTvPlaybackChrome();
                }
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            canRequestFocus: isTelevision,
            onKeyEvent: (_, event) => _handleTvSeekKeyEvent(event),
            child: Scaffold(
              backgroundColor: Colors.black,
              body: !isTelevision
                  ? KeyedSubtree(
                      key: ValueKey(showMinimalPlayerChrome),
                      child: ColoredBox(
                        color: Colors.black,
                        child: _buildVideoSurface(
                          theme,
                          isTelevision: false,
                          settings: playbackSettings,
                        ),
                      ),
                    )
                  : PlayerTvPlaybackSurface(
                      aspectRatio: _currentAspectRatio(),
                      videoSurface: _buildVideoSurface(
                        theme,
                        isTelevision: true,
                        settings: playbackSettings,
                      ),
                      chrome: !_tvPlaybackChromeVisible
                          ? null
                          : ValueListenableBuilder<_TvPlaybackState>(
                              valueListenable: _tvPlaybackStateNotifier,
                              builder: (context, state, child) {
                                final player = _player;
                                if (player == null) {
                                  return const SizedBox.shrink();
                                }
                                final resolvedPosition =
                                    state.position > Duration.zero
                                        ? state.position
                                        : _latestPosition;
                                final resolvedDuration =
                                    state.duration > Duration.zero
                                        ? state.duration
                                        : (_latestDuration > Duration.zero
                                            ? _latestDuration
                                            : player.state.duration);
                                return PlayerTvPlaybackChrome(
                                  title:
                                      (_resolvedTarget ?? widget.target).title,
                                  position: resolvedPosition,
                                  duration: resolvedDuration,
                                  playing:
                                      state.playing || player.state.playing,
                                  bufferingPercentage:
                                      state.bufferingPercentage,
                                  backFocusNode: _tvBackControlFocusNode,
                                  playPauseFocusNode:
                                      _tvPlayPauseControlFocusNode,
                                  subtitleFocusNode:
                                      _tvSubtitleControlFocusNode,
                                  audioFocusNode: _tvAudioControlFocusNode,
                                  moreFocusNode: _tvMoreControlFocusNode,
                                  onBack: () {
                                    unawaited(_handleTvBack());
                                  },
                                  onTogglePlayback: _togglePlayback,
                                  onOpenSubtitle: () {
                                    _showTvPlaybackChrome(autoHide: false);
                                    unawaited(
                                      _openCurrentSubtitleSelector(),
                                    );
                                  },
                                  onOpenAudio: () {
                                    _showTvPlaybackChrome(autoHide: false);
                                    unawaited(
                                      _openCurrentAudioSelector(),
                                    );
                                  },
                                  onOpenOptions: () {
                                    _showTvPlaybackChrome(autoHide: false);
                                    unawaited(
                                      _showPlaybackOptions(isTelevision: true),
                                    );
                                  },
                                );
                              },
                            ),
                    ),
            ),
          ),
        ),
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

enum _MpvIsoDiscKind {
  bluray,
  dvd,
}

class _MpvIsoOpenPlan {
  const _MpvIsoOpenPlan({
    required this.discKind,
    required this.deviceSource,
  });

  final _MpvIsoDiscKind discKind;
  final String deviceSource;

  String get mediaUri {
    return switch (discKind) {
      _MpvIsoDiscKind.bluray => 'bd://longest',
      _MpvIsoDiscKind.dvd => 'dvd://',
    };
  }

  String get deviceProperty {
    return switch (discKind) {
      _MpvIsoDiscKind.bluray => 'bluray-device',
      _MpvIsoDiscKind.dvd => 'dvd-device',
    };
  }

  String get otherDeviceProperty {
    return switch (discKind) {
      _MpvIsoDiscKind.bluray => 'dvd-device',
      _MpvIsoDiscKind.dvd => 'bluray-device',
    };
  }
}

class _PlayerOpenException implements Exception {
  const _PlayerOpenException(this.message);

  final String message;

  @override
  String toString() => message;
}
