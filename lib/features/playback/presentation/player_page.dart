import 'dart:async';
import 'package:starflow/app/theme/app_typography.dart';
import 'package:starflow/features/playback/application/mpv_memory_priority_policy.dart';
import 'package:starflow/features/playback/application/playback_control_intents.dart';
import 'package:starflow/features/playback/application/playback_recovery_intent.dart';
import 'package:starflow/features/playback/application/playback_seek_coalescer.dart';
import 'package:starflow/features/playback/application/playback_track_guard.dart';
import 'widgets/player_controls_layout.dart';
import 'widgets/player_menu_style.dart';
import 'dart:math' as math;
import 'package:starflow/features/playback/application/playback_reliability_policy.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:starflow/core/platform/android_picture_in_picture.dart';
import 'package:starflow/core/platform/background_playback.dart';
import 'package:starflow/core/platform/playback_system_session.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/network/starflow_http_client.dart';
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/core/logging/app_log_api.dart';
import 'package:starflow/features/playback/application/mpv_playback_diagnostics.dart';
import 'package:starflow/core/widgets/starflow_action_dialog.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/data/media_server_client.dart';
import 'package:starflow/features/playback/application/active_playback_cleanup.dart';
import 'package:starflow/features/playback/application/fntv_session_owner.dart';
import 'package:starflow/features/playback/application/mpv_tuning_policy.dart';
import 'package:starflow/features/playback/application/mpv_startup_scope.dart';
import 'package:starflow/features/playback/application/mpv_playback_lifecycle.dart';
import 'package:starflow/features/playback/application/playback_platform_session_owner.dart';
import 'package:starflow/features/playback/application/mpv_buffer_progress.dart';
import 'package:starflow/features/playback/application/playback_subtitle_session_preference.dart';
import 'package:starflow/features/playback/application/native_playback_episode_queue_policy.dart';
import 'package:starflow/features/playback/application/native_playback_media_type.dart';
import 'package:starflow/features/playback/application/playback_episode_queue_resolver.dart';
import 'package:starflow/features/playback/application/playback_episode_browser.dart';
import 'package:starflow/features/playback/application/playback_performance_tracker.dart';
import 'package:starflow/features/playback/application/playback_remote_preflight.dart';
import 'package:starflow/features/playback/application/playback_server_track_resolver.dart';
import 'package:starflow/features/playback/application/fntv_quality_menu.dart';
import 'package:starflow/features/playback/application/playback_variant_resolver.dart';
import 'package:starflow/features/playback/presentation/widgets/player_variant_picker_dialog.dart';
import 'package:starflow/features/playback/application/playback_engine_router.dart';
import 'package:starflow/features/playback/application/playback_session.dart';
import 'package:starflow/features/playback/application/subtitle_language_preferences.dart';
import 'package:starflow/features/playback/application/playback_auto_skip_policy.dart';
import 'package:starflow/features/playback/application/playback_episode_advance_guard.dart';
import 'package:starflow/features/playback/application/playback_completion_state.dart';
import 'package:starflow/features/playback/application/playback_interaction_player.dart';
import 'package:starflow/features/playback/application/playback_intro_start_guard.dart';
import 'package:starflow/features/playback/application/playback_episode_preparation.dart';
import 'package:starflow/features/playback/application/playback_startup_coordinator.dart';
import 'package:starflow/features/playback/application/playback_startup_executor.dart';
import 'package:starflow/features/playback/application/playback_startup_routing.dart';
import 'package:starflow/features/playback/application/playback_target_resolver.dart';
import 'package:starflow/features/playback/application/playback_stream_relay_contract.dart';
import 'package:starflow/features/playback/application/playback_stream_relay_service.dart';
import 'package:starflow/features/playback/application/subtitle_content_processing.dart';
import 'package:starflow/features/playback/application/subtitle_render_policy.dart';
import 'package:starflow/features/playback/application/mpv_subtitle_render_binding.dart';
import 'package:starflow/features/playback/data/native_playback_launcher.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart'
    hide isLoopbackPlaybackRelayUrl;
import 'package:starflow/features/playback/data/subtitle_file_picker.dart';
import 'package:starflow/features/playback/data/system_playback_launcher.dart';
import 'package:starflow/features/playback/domain/playback_memory_models.dart';
import 'package:starflow/features/playback/domain/playback_episode_queue.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/playback/presentation/widgets/mpv_stall_watchdog.dart';
import 'package:starflow/features/playback/presentation/widgets/player_adaptive_top_chrome.dart';
import 'package:starflow/features/playback/presentation/widgets/player_episode_picker_dialog.dart';
import 'package:starflow/features/playback/presentation/widgets/player_network_speed_label.dart';
import 'package:starflow/features/playback/presentation/widgets/player_title.dart';
import 'package:starflow/features/playback/presentation/widgets/player_playback_dialogs.dart';
import 'package:starflow/features/playback/presentation/widgets/player_playback_formatters.dart';
import 'package:starflow/features/playback/presentation/widgets/player_playback_options_dialog.dart';
import 'package:starflow/features/playback/presentation/widgets/player_playback_overlays.dart';
import 'package:starflow/features/playback/presentation/widgets/player_tv_playback_widgets.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

part 'widgets/player_page_platform_session.part.dart';
part 'widgets/player_page_startup_mpv.part.dart';
part 'widgets/player_page_startup_mpv_open.part.dart';
part 'widgets/player_page_startup_mpv_recovery.part.dart';
part 'widgets/player_page_startup_mpv_launch.part.dart';
part 'widgets/player_page_startup_mpv_tuning.part.dart';
part 'widgets/player_page_performance.part.dart';
part 'widgets/player_page_memory_priority.part.dart';
part 'widgets/player_page_runtime_actions.part.dart';
part 'widgets/player_page_controls.part.dart';

class _OpenPlaybackOptionsIntent extends Intent {
  const _OpenPlaybackOptionsIntent();
}

class _OpenTvEpisodePickerIntent extends Intent {
  const _OpenTvEpisodePickerIntent();
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
  static const int _maxPlaybackAttempts =
      PlaybackPolicyValues.maxPlayerAttempts;
  static const _kSeekStep = Duration(seconds: 10);
  static const _kSubtitleDelaySteps = <double>[-2, -1, -0.5, 0, 0.5, 1, 2];
  static const _kProgressPersistInterval = Duration(seconds: 10);
  static Future<void> _playerShutdownQueue = Future<void>.value();
  int _startupGeneration = 0;
  MpvStartupScope _startupScope = MpvStartupScope();

  bool _isCurrentStartup(int generation) =>
      mounted && generation == _startupGeneration;
  static final PlaybackHostBandwidthCache _hostBandwidthCache =
      PlaybackHostBandwidthCache();

  Player? _player;
  VideoController? _videoController;
  MpvPlaybackLifecycle _mpvLifecycle = MpvPlaybackLifecycle();
  final _mpvRelays = <Player, PlaybackStreamRelayService>{};
  final _mpvRelayUrls = <Player, String>{};
  final _mpvRelayClosures = Expando<Future<void>>();
  bool _mpvBitmapSubtitle = false;
  PlaybackTarget? _resolvedTarget;
  PlaybackEpisodeQueue? _episodeQueue;
  _PlaybackNetworkEstimate _networkEstimate =
      const _PlaybackNetworkEstimate.none();
  SeriesSkipPreference? _seriesSkipPreference;
  Object? _error;
  bool _isReady = false;
  bool _pictureInPictureSupported = false;
  bool _isInPictureInPictureMode = false;
  final _platformSession = PlaybackPlatformSessionOwner(
    supported: PlaybackSystemSessionController.isSupportedPlatform,
    attach: PlaybackSystemSessionController.attach,
    detach: PlaybackSystemSessionController.detach,
    setActive: PlaybackSystemSessionController.setActive,
    update: PlaybackSystemSessionController.update,
  );
  bool _subtitleDelaySupported = false;
  double _subtitleDelaySeconds = 0;
  bool _mpvDualSubtitleEnabled = false;
  PlaybackSubtitleSessionPreference? _subtitleSessionPreference;
  late double _sessionPrimarySubtitlePosition;
  late double _sessionSecondarySubtitlePosition;
  late double _sessionSecondarySubtitleScale;
  bool _tvPlaybackChromeVisible = false;
  final ValueNotifier<_TvPlaybackState> _tvPlaybackStateNotifier =
      ValueNotifier(const _TvPlaybackState());
  final FocusNode _tvBackControlFocusNode =
      FocusNode(debugLabel: 'tv-player-control-back');
  final FocusNode _tvPlayPauseControlFocusNode =
      FocusNode(debugLabel: 'tv-player-control-play');
  final FocusNode _tvPreviousEpisodeControlFocusNode =
      FocusNode(debugLabel: 'tv-player-control-previous-episode');
  final FocusNode _tvNextEpisodeControlFocusNode =
      FocusNode(debugLabel: 'tv-player-control-next-episode');
  final FocusNode _tvEpisodePickerControlFocusNode =
      FocusNode(debugLabel: 'tv-player-control-episode-picker');
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
  LogicalKeyboardKey? _tvSeekHoldKey;
  DateTime? _tvSeekHoldStartedAt;
  int _tvSeekHoldRepeatCount = 0;
  PlaybackSeekCoalescer? _tvSeekCoalescer;
  int _manualTrackRevision = 0;
  bool get _startupTrackWorkIsCurrent => PlaybackTrackGuard.allowsWrite;

  List<FocusNode> get _tvChromeControlFocusNodes => <FocusNode>[
        _tvBackControlFocusNode,
        _tvPreviousEpisodeControlFocusNode,
        _tvPlayPauseControlFocusNode,
        _tvNextEpisodeControlFocusNode,
        _tvEpisodePickerControlFocusNode,
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

  void _syncPlaybackVisualStateFromPlayer() {
    if (!_isTelevisionPlaybackDevice || !_shouldUpdatePlaybackVisualState) {
      return;
    }
    final player = _player;
    if (player == null) {
      return;
    }
    _updateTvPlaybackState(
      position: player.state.position,
      duration: player.state.duration,
      playing: player.state.playing,
      bufferingPercentage: player.state.bufferingPercentage,
    );
  }

  bool _tvExitDialogVisible = false;
  bool _isEmbeddedMpvFullscreen = false;
  bool _playbackPageInForeground = true;
  double _adaptiveGestureBrightness = 0.5;
  double _adaptiveGestureVolume = 1.0;
  int _adaptiveGestureLevelsRevision = 0;
  bool _introSkipApplied = false;
  bool _outroSkipApplied = false;
  final _completionState = PlaybackCompletionState();
  bool _playbackStartPositionApplied = false;
  Duration _pendingIntroStartValidation = Duration.zero;
  bool _nextEpisodeIsAutomatic = false;
  final _episodePreparation = PlaybackEpisodePreparation();
  Object? _episodePreparationContext;
  Duration _latestPosition = Duration.zero;
  Duration _latestDuration = Duration.zero;
  DateTime? _lastProgressPersistedAt;
  Duration _lastPersistedPosition = Duration.zero;
  Future<void> _fntvProgressTail = Future<void>.value();
  int _fntvProgressQueued = 0;
  bool _fntvSwitchInProgress = false;
  late final _fntvSessions = FntvSessionOwner((target) async {
    final client = _providerContainer
        .read(mediaServerClientProvider(MediaSourceKind.fntv));
    if (client is MediaServerSessionClient) {
      await (client as MediaServerSessionClient).releasePlaybackSession(
          source: _sourceForTarget(target), target: target);
    }
  });
  bool _iosBackgroundAudioOnlyRequested = false;
  Player? _iosBackgroundAudioOnlyPlayer;
  VideoTrack? _iosBackgroundPreviousVideoTrack;
  Future<void> _iosBackgroundAudioOnlyQueue = Future<void>.value();
  bool? _lastTracedBufferingState;
  int? _lastTracedBufferingBucket;
  late final ProviderContainer _providerContainer;
  late final StateController<bool> _playbackPerformanceModeController;
  Timer? _tvPlaybackChromeHideTimer;
  Timer? _mpvStallWatchdogTimer;
  Future<void>? _exitPlaybackFuture;
  bool _platformStateTornDownBeforePop = false;
  int? _activePlaybackCleanupToken;
  MpvStallWatchdog? _mpvStallWatchdog;
  bool _mpvStallRecoveryInProgress = false;
  DateTime? _lastRuntimeMpvErrorAt;
  int _runtimeMpvErrorBurstCount = 0;
  int _runtimeMpvErrorRecoveryAttempts = 0;
  final _automaticRecoveryBudget = PlaybackRecoveryBudget();
  int? _recoveryStartupIntent;
  late final _recoveryIntent = PlaybackRecoveryIntent(onInvalidated: () {
    if (_recoveryStartupIntent != null) _startupScope.cancel();
  });
  bool _runtimeMpvErrorRecoveryInProgress = false;
  final _episodeAdvanceGuard = PlaybackEpisodeAdvanceGuard();
  bool get _episodeQueueAdvanceInProgress => _episodeAdvanceGuard.isActive;
  bool _subtitleSearchActive = false;
  bool _skipPreferenceSaveInProgress = false;
  int? _androidMemoryClassMb;
  bool _androidMemoryClassResolved = false;
  PlaybackPerformanceTracker? _mpvPerformanceTracker;
  Timer? _mpvPerformanceSampleTimer;
  Timer? _mpvMemoryTimer;
  bool _mpvMemoryBusy = false;
  int _mpvMemoryEpoch = 0;
  MpvMemoryPriorityPolicy _mpvMemoryPolicy = MpvMemoryPriorityPolicy();
  bool _mpvPerformanceSampleInProgress = false;
  int _mpvPerformanceSampleGeneration = 0;
  MpvHealthLogGate _mpvHealthLogGate = MpvHealthLogGate();
  int _mpvLastDroppedFrames = 0;
  DateTime? _playbackStartupStartedAt;
  int _playbackTargetResolutionMs = 0;

  @override
  void initState() {
    super.initState();
    _providerContainer = ProviderScope.containerOf(context, listen: false);
    final initialSettings = ref.read(appSettingsProvider);
    _sessionPrimarySubtitlePosition =
        initialSettings.playbackPrimarySubtitlePosition;
    _sessionSecondarySubtitlePosition =
        initialSettings.playbackSecondarySubtitlePosition;
    _sessionSecondarySubtitleScale =
        initialSettings.playbackSecondarySubtitleScale;
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
    _recoveryIntent.invalidate();
    _tvSeekCoalescer?.cancel();
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
    _playbackPerformanceModeController.state = false;
    final player = _detachActivePlayerState();
    unawaited(
      _shutdownDetachedPlayer(
        player,
        reason: 'player-page-dispose',
        persistProgress: true,
        teardownPlatformState: !_platformStateTornDownBeforePop,
        closeSessionOwner: true,
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

  _DetachedPlayback _detachActivePlayerState({
    bool clearStallRecoveryFlag = true,
  }) {
    _episodeAdvanceGuard.reset();
    _resetPreparedNextEpisode();
    _tvSeekCoalescer?.cancel();
    _tvSeekCoalescer = null;
    _resetTvSeekHold();
    _startupGeneration++;
    _startupScope.cancel();
    _stopMpvPerformanceSampling();
    _stopMpvMemorySampling();
    final player = _player;
    final resourcesClosed =
        _mpvLifecycle.close().catchError((Object error, StackTrace stack) {
      appLogWarning('playback.dispose', 'MPV resource cleanup failed',
          error: error, stackTrace: stack);
    });
    // Install a fresh owner synchronously; delayed shutdown cannot close it.
    _mpvLifecycle = MpvPlaybackLifecycle();
    _mpvBitmapSubtitle = false;
    _player = null;
    _videoController = null;
    _isReady = false;
    _isEmbeddedMpvFullscreen = false;
    _mpvDualSubtitleEnabled = false;
    _stopMpvStallWatchdog(clearRecoveryFlag: clearStallRecoveryFlag);
    _lastRuntimeMpvErrorAt = null;
    _runtimeMpvErrorBurstCount = 0;
    _runtimeMpvErrorRecoveryAttempts = 0;
    _runtimeMpvErrorRecoveryInProgress = false;
    return _DetachedPlayback(player, resourcesClosed, _resolvedTarget);
  }

  Future<void> _shutdownDetachedPlayer(
    _DetachedPlayback detached, {
    required String reason,
    required bool persistProgress,
    required bool teardownPlatformState,
    bool closeSessionOwner = false,
  }) async {
    final player = detached.player;
    final sessionTarget = detached.target;
    await _finishMpvPerformanceSession(reason: reason, player: player);
    if (persistProgress) {
      await _persistPlaybackProgress(
        force: true,
        playerOverride: player,
      );
    }
    await detached.resourcesClosed;
    if (teardownPlatformState) {
      await _teardownPictureInPicture();
      await _teardownPlaybackSystemSession();
    }
    if (player != null) {
      await _enqueuePlayerShutdown(player, reason: reason);
    }
    if (closeSessionOwner) {
      await _fntvSessions.close();
    } else if (!_fntvSwitchInProgress && sessionTarget != null) {
      await _fntvSessions.release(sessionTarget);
    }
  }

  Future<void> _handleExternalPlaybackCleanup(String reason) async {
    await _stopPlaybackBeforeExit(reason: reason);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _recoveryIntent.foreground(state == AppLifecycleState.resumed);
    if (state != AppLifecycleState.resumed) {
      _tvSeekCoalescer?.cancel();
      _resetTvSeekHold();
    }
    _playbackPageInForeground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      unawaited(_bindAdaptiveGestureSystemLevels());
      unawaited(_setIosBackgroundAudioOnly(false));
      unawaited(_syncPlaybackSystemSession(force: true));
      _syncPlaybackVisualStateFromPlayer();
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_persistPlaybackProgress(force: true));
    }
    if (state != AppLifecycleState.paused) {
      return;
    }
    if (!_backgroundPlaybackEnabled) {
      unawaited(_setPlayWhenReady(false));
      unawaited(_platformSession.deactivate());
      return;
    }
    if (_isActivelyPlaying) {
      unawaited(_setIosBackgroundAudioOnly(true));
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

  bool get _shouldUpdatePlaybackVisualState => _playbackPageInForeground;

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

  double? get _networkEstimateMegabitsPerSecond {
    final bytesPerSecond = _networkEstimate.estimatedSpeedBytesPerSecond;
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
    appLogError('playback', stage,
        fields: <String, Object?>{
          'title':
              target.title.trim().isEmpty ? 'Starflow' : target.title.trim(),
          'engine': 'embeddedMpv',
          ...fields,
        },
        error: error,
        stackTrace: stackTrace);
  }

  Future<void> _waitForPendingPlayerShutdowns({
    required String reason,
  }) async {
    try {
      await _playerShutdownQueue;
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
      // Abort this owner's transport before libmpv stop/dispose can wait on it.
      // A replacement player has a separate relay and is not affected.
      try {
        await _closeMpvRelay(player);
      } catch (error, stackTrace) {
        _traceWindowsMpv(
          'windows-mpv.shutdown.relay-error',
          fields: {'reason': reason},
          error: error,
          stackTrace: stackTrace,
        );
      }
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
    });
    _playerShutdownQueue = shutdown.catchError((_) {});
    await shutdown;
  }

  Future<void> _closeMpvRelay(Player player) =>
      _mpvRelayClosures[player] ??= Future<void>.sync(() async {
        _mpvRelayUrls.remove(player);
        await _mpvRelays.remove(player)?.close();
      });

  PlaybackRelayCacheControl? _mpvCacheControl(Player player) {
    final relay = _mpvRelays[player];
    return relay is PlaybackRelayCacheControl
        ? relay as PlaybackRelayCacheControl
        : null;
  }

  Future<int?> _readMpvDiskCacheBytes(Player player) async =>
      _mpvCacheControl(player)
          ?.cacheSnapshot(url: _mpvRelayUrls[player])
          ?.storedBytes;

  void _setMpvPlaybackActive(Player player, bool active) {
    if (!active) _invalidateMpvMemoryReady(player);
    _mpvCacheControl(player)
        ?.setPlaybackActive(active, url: _mpvRelayUrls[player]);
  }

  void _cancelMpvReadAhead(Player player) {
    _invalidateMpvMemoryReady(player);
    _mpvCacheControl(player)?.cancelReadAhead(url: _mpvRelayUrls[player]);
  }

  Future<void> _stopPlaybackBeforeExit({
    required String reason,
  }) async {
    _recoveryIntent.invalidate();
    final player = _detachActivePlayerState();
    await _shutdownDetachedPlayer(
      player,
      reason: reason,
      persistProgress: true,
      teardownPlatformState: true,
      closeSessionOwner: true,
    );
  }

  Future<void> _requestExitPlayer({
    required String reason,
  }) async {
    _recoveryIntent.invalidate();
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

    final detached = _detachActivePlayerState();
    _platformStateTornDownBeforePop = true;
    if (!mounted) {
      await _shutdownDetachedPlayer(
        detached,
        reason: reason,
        persistProgress: true,
        teardownPlatformState: true,
        closeSessionOwner: true,
      );
      return;
    }

    final player = detached.player;
    if (player != null) {
      unawaited(player.pause().catchError((_) {}));
    }
    context.pop();
    await _shutdownDetachedPlayer(
      detached,
      reason: reason,
      persistProgress: true,
      teardownPlatformState: true,
      closeSessionOwner: true,
    );
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
      _tvSeekCoalescer?.cancel();
      _resetTvSeekHold();
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
      if (_tvSeekHoldKey == key) _tvSeekCoalescer?.flush();
      _resetTvSeekHold(key: key);
      return KeyEventResult.handled;
    }

    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    if (_tvSeekHoldKey != key || _tvSeekHoldStartedAt == null) {
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      _tvSeekCoalescer?.cancel();
      final player = _player;
      if (!_isReady || player == null) return KeyEventResult.handled;
      late final PlaybackSeekCoalescer coalescer;
      coalescer = PlaybackSeekCoalescer(seek: (target) async {
        if (!mounted ||
            !identical(_player, player) ||
            !_isReady ||
            !identical(_tvSeekCoalescer, coalescer)) {
          return;
        }
        await player.seek(target);
        if (!mounted ||
            !identical(_player, player) ||
            !identical(_tvSeekCoalescer, coalescer)) {
          return;
        }
        _showTvPlaybackChrome();
      });
      _tvSeekCoalescer = coalescer;
      _tvSeekHoldKey = key;
      _tvSeekHoldStartedAt = DateTime.now();
      _tvSeekHoldRepeatCount = 0;
    } else if (event is KeyRepeatEvent) {
      _tvSeekHoldRepeatCount += 1;
    }

    final heldFor = DateTime.now().difference(_tvSeekHoldStartedAt!);
    _recoveryIntent.invalidate();
    final step = _resolveTvSeekStep(
      heldFor: heldFor,
      repeatCount: _tvSeekHoldRepeatCount,
    );
    final direction = key == LogicalKeyboardKey.arrowLeft ? -1 : 1;
    final delta = Duration(milliseconds: step.inMilliseconds * direction);
    _tvSeekCoalescer?.add(delta,
        position: _player?.state.position ?? Duration.zero,
        duration: _player?.state.duration ?? Duration.zero);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    final playbackSettings = ref.watch(appSettingsProvider);
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
      child: TvRemoteShortcuts(
        shortcuts: isTelevision
            ? const {
                SingleActivator(LogicalKeyboardKey.goBack): DismissIntent(),
                SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
                SingleActivator(LogicalKeyboardKey.backspace): DismissIntent(),
                SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.numpadEnter):
                    ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.gameButtonA):
                    ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
                ...playbackMediaShortcuts,
                SingleActivator(LogicalKeyboardKey.arrowUp):
                    _ShowTvPlaybackChromeIntent(),
                SingleActivator(LogicalKeyboardKey.arrowDown):
                    _OpenTvEpisodePickerIntent(),
                SingleActivator(LogicalKeyboardKey.contextMenu):
                    _OpenPlaybackOptionsIntent(),
                SingleActivator(LogicalKeyboardKey.gameButtonY):
                    _OpenPlaybackOptionsIntent(),
              }
            : const <SingleActivator, Intent>{},
        child: Actions(
          actions: <Type, Action<Intent>>{
            PlaybackPlayIntent: CallbackAction<PlaybackPlayIntent>(
              onInvoke: (_) {
                unawaited(_setPlayWhenReady(true));
                return null;
              },
            ),
            PlaybackPauseIntent: CallbackAction<PlaybackPauseIntent>(
              onInvoke: (_) {
                unawaited(_setPlayWhenReady(false));
                return null;
              },
            ),
            PlaybackToggleIntent: CallbackAction<PlaybackToggleIntent>(
              onInvoke: (_) {
                unawaited(_togglePlayback());
                return null;
              },
            ),
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
            _OpenTvEpisodePickerIntent:
                CallbackAction<_OpenTvEpisodePickerIntent>(
              onInvoke: (_) {
                if (!isTelevision) {
                  return null;
                }
                final queue = _episodeQueue;
                if (queue != null &&
                    queue.entries.isNotEmpty &&
                    queue.hasCurrent) {
                  unawaited(
                    _openPlaybackEpisodePicker(isTelevision: true),
                  );
                } else {
                  _showPlaybackOptions(isTelevision: true);
                }
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
            onFocusChange: (focused) {
              if (!focused) {
                _tvSeekCoalescer?.cancel();
                _resetTvSeekHold();
              }
            },
            child: Scaffold(
              key: const ValueKey<String>('player:surface'),
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
                                final episodeQueue = _episodeQueue;
                                final showEpisodeControls =
                                    episodeQueue != null &&
                                        episodeQueue.entries.isNotEmpty &&
                                        episodeQueue.hasCurrent;
                                return PlayerTvPlaybackChrome(
                                  title: playerTitle(
                                      _resolvedTarget ?? widget.target),
                                  position: resolvedPosition,
                                  duration: resolvedDuration,
                                  playing:
                                      state.playing || player.state.playing,
                                  bufferingPercentage:
                                      state.bufferingPercentage,
                                  networkSpeed: MpvNetworkSpeedLabel(
                                    player: player,
                                    generation: _startupGeneration,
                                    readDiskCacheBytes: playbackSettings
                                                .playbackDiskCacheMiB >
                                            0
                                        ? () => _readMpvDiskCacheBytes(player)
                                        : null,
                                  ),
                                  videoFormat: MpvNetworkSpeedLabel(
                                    player: player,
                                    generation: _startupGeneration,
                                    formatOnly: true,
                                  ),
                                  backFocusNode: _tvBackControlFocusNode,
                                  previousEpisodeFocusNode:
                                      _tvPreviousEpisodeControlFocusNode,
                                  playPauseFocusNode:
                                      _tvPlayPauseControlFocusNode,
                                  nextEpisodeFocusNode:
                                      _tvNextEpisodeControlFocusNode,
                                  episodePickerFocusNode:
                                      _tvEpisodePickerControlFocusNode,
                                  subtitleFocusNode:
                                      _tvSubtitleControlFocusNode,
                                  audioFocusNode: _tvAudioControlFocusNode,
                                  moreFocusNode: _tvMoreControlFocusNode,
                                  onBack: () {
                                    unawaited(_handleTvBack());
                                  },
                                  showEpisodeControls: showEpisodeControls,
                                  onPreviousEpisode: showEpisodeControls &&
                                          episodeQueue.hasPrevious
                                      ? () {
                                          unawaited(
                                            _movePlaybackQueue(
                                              forward: false,
                                              reason: 'tv-control-previous',
                                            ),
                                          );
                                        }
                                      : null,
                                  onTogglePlayback: _togglePlayback,
                                  onNextEpisode: showEpisodeControls &&
                                          episodeQueue.hasNext
                                      ? () {
                                          unawaited(
                                            _movePlaybackQueue(
                                              forward: true,
                                              reason: 'tv-control-next',
                                            ),
                                          );
                                        }
                                      : null,
                                  onOpenEpisodePicker: () {
                                    _showTvPlaybackChrome(autoHide: false);
                                    unawaited(
                                      _openPlaybackEpisodePicker(
                                        isTelevision: true,
                                      ),
                                    );
                                  },
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

class _PlaybackNetworkEstimate {
  const _PlaybackNetworkEstimate.none() : estimatedSpeedBytesPerSecond = null;

  const _PlaybackNetworkEstimate.fromBytesPerSecond(
    int this.estimatedSpeedBytesPerSecond,
  );

  final int? estimatedSpeedBytesPerSecond;
}

class _PictureInPictureAspectRatio {
  const _PictureInPictureAspectRatio({
    required this.width,
    required this.height,
  });

  final int width;
  final int height;
}

class _DetachedPlayback {
  const _DetachedPlayback(this.player, this.resourcesClosed, this.target);

  final Player? player;
  final Future<void> resourcesClosed;
  final PlaybackTarget? target;
}

class _OpenedPlayback {
  const _OpenedPlayback({
    required this.player,
    required this.videoController,
    required this.errorSubscription,
    required this.logSubscription,
    required this.effectiveStartPosition,
  });

  final Player player;
  final VideoController videoController;
  final StreamSubscription<String> errorSubscription;
  final StreamSubscription<PlayerLog> logSubscription;
  final PlaybackStartPosition effectiveStartPosition;

  Future<void> cancelSubscriptions() async {
    await errorSubscription.cancel();
    await logSubscription.cancel();
  }
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
