// ignore_for_file: invalid_use_of_protected_member

part of '../player_page.dart';

extension _PlayerPageStateStartupMpv on _PlayerPageState {
  Future<void> _initialize() async {
    await ActivePlaybackCleanupCoordinator.cleanupAll(
      reason: 'player-page-initialize',
      exceptToken: _activePlaybackCleanupToken,
    );
    await _waitForPendingPlayerShutdowns(reason: 'player-page-initialize');
    _traceWindowsMpv(
      'windows-mpv.initialize.begin',
      fields: {
        'canPlay': widget.target.canPlay,
        'needsResolution': widget.target.needsResolution,
        'decodeMode': _playbackDecodeMode.name,
        'qualityPresetRequested': _playbackMpvQualityPreset.name,
        'qualityAutoDowngrade': _autoDowngradePlaybackQualityEnabled,
        'leanUi': _leanPlaybackUiEnabled,
        'aggressiveTuning': _aggressivePlaybackTuningEnabled,
      },
    );
    if (!widget.target.canPlay) {
      _traceWindowsMpv('windows-mpv.initialize.no-playable-source');
      setState(() {
        _error = '没有可播放的流地址';
      });
      return;
    }

    try {
      final coordinator = PlaybackStartupCoordinator(
        read: _providerContainer.read,
        targetResolver: PlaybackTargetResolver(read: _providerContainer.read),
        engineRouter: const PlaybackEngineRouter(),
      );
      final outcome = await coordinator.start(
        initialTarget: widget.target,
        isTelevision: _isTelevisionPlaybackDevice,
        isWeb: kIsWeb,
      );
      final resolvedTarget = outcome.resolvedTarget;
      _traceQuarkPlaybackStartup(
        'quark.startup.outcome',
        target: resolvedTarget,
        fields: {
          'routeAction': outcome.routeAction.name,
          'engine': outcome.settings.playbackEngine.name,
          'headers': resolvedTarget.headers.length,
          'streamUrl': resolvedTarget.streamUrl,
        },
      );
      _traceWindowsMpv(
        'windows-mpv.initialize.target-resolved',
        fields: {
          'urlScheme':
              Uri.tryParse(resolvedTarget.streamUrl.trim())?.scheme ?? '',
          'sourceName': resolvedTarget.sourceName,
          'resolution': resolvedTarget.resolutionLabel,
          'format': resolvedTarget.formatLabel,
          'videoCodec': resolvedTarget.videoCodec,
          'audioCodec': resolvedTarget.audioCodec,
          'bitrate': resolvedTarget.bitrate ?? 0,
          'headers': resolvedTarget.headers.length,
        },
      );
      final startupPreparation = outcome.startupPreparation;
      final resumeEntry = startupPreparation.resumeEntry;
      final skipPreference = startupPreparation.skipPreference;
      if (mounted) {
        setState(() {
          _resolvedTarget = resolvedTarget;
          _seriesSkipPreference = skipPreference;
        });
      }
      final executor = PlaybackStartupExecutor(
        launchSystemPlayer: _launchWithSystemPlayer,
        launchNativeContainer: _launchWithNativeContainer,
        launchPerformanceFallback: _tryLaunchWithPerformanceFallback,
      );
      final shouldOpen = await executor.execute(
        outcome.routeAction,
        resolvedTarget,
      );
      _traceQuarkPlaybackStartup(
        'quark.startup.executor-result',
        target: resolvedTarget,
        fields: {
          'routeAction': outcome.routeAction.name,
          'shouldOpenEmbedded': shouldOpen,
        },
      );
      if (!shouldOpen) {
        return;
      }
      _adaptiveTopChromeController.setVisible(true);
      final diagnostics = await _prepareStartupDiagnostics(resolvedTarget);
      final preflight = diagnostics.preflight;
      final probe = diagnostics.probe;
      final settings = outcome.settings;
      final timeoutSeconds = _resolvePlaybackOpenTimeoutSeconds(
        baseSeconds: settings.playbackOpenTimeoutSeconds.clamp(1, 600),
        target: resolvedTarget,
        preflight: preflight,
        probe: probe,
      );
      _traceWindowsMpv(
        'windows-mpv.initialize.open-start',
        fields: {
          'timeoutSeconds': timeoutSeconds,
          'bufferSizeBytes': _resolveMpvBufferSizeBytes(resolvedTarget),
          'hwdec': _resolveMpvHardwareDecodeMode(),
        },
      );
      final playback = await _openEmbeddedPlayback(
        resolvedTarget,
        Duration(seconds: timeoutSeconds),
      );

      if (!mounted) {
        await playback.errorSubscription.cancel();
        await playback.player.dispose();
        return;
      }

      _playerErrorSubscription = playback.errorSubscription;
      _playerPlayingSubscription = playback.player.stream.playing.listen((
        playing,
      ) {
        _traceWindowsMpv(
          'windows-mpv.player.playing',
          fields: {'playing': playing},
        );
        _updateTvPlaybackState(playing: playing);
        unawaited(_syncBackgroundPlayback(enabled: playing));
        unawaited(_syncPlaybackSystemSession(force: true));
        if (_isTelevisionPlaybackDevice) {
          if (!playing) {
            _showTvPlaybackChrome(autoHide: false);
          } else if (_tvPlaybackChromeVisible) {
            _scheduleTvPlaybackChromeHide();
          }
        }
        if (!playing) {
          unawaited(_persistPlaybackProgress(force: true));
        }
      });
      _playerDurationSubscription = playback.player.stream.duration.listen((
        duration,
      ) {
        _latestDuration = duration;
        _updateTvPlaybackState(duration: duration);
        unawaited(_syncPlaybackSystemSession());
      });
      _playerPositionSubscription = playback.player.stream.position.listen((
        position,
      ) {
        _latestPosition = position;
        _updateTvPlaybackState(position: position);
        _maybeApplyAutoSkip(playback.player, position);
        unawaited(_persistPlaybackProgress());
        unawaited(_syncPlaybackSystemSession());
      });
      _bindWindowsMpvTraceStreams(playback.player);
      setState(() {
        _player = playback.player;
        _videoController = playback.videoController;
        _isReady = false;
        _error = null;
        _latestPosition = playback.player.state.position;
        _latestDuration = playback.player.state.duration;
      });
      await _syncSubtitleDelayState(playback.player);
      await _restorePlaybackProgress(playback.player, resumeEntry);
      _syncSkipFlagsWithCurrentPosition();
      await _awaitStrictPlaybackReady(
        playback.player,
        target: resolvedTarget,
        timeout: Duration(seconds: timeoutSeconds),
        stageLabel: 'post-resume',
        progressBaseline: playback.player.state.position > _latestPosition
            ? playback.player.state.position
            : _latestPosition,
      );
      if (!mounted || _player != playback.player) {
        return;
      }
      setState(() {
        _isReady = true;
      });
      _startMpvStallWatchdog(playback.player, resolvedTarget);
      _traceWindowsMpv(
        'windows-mpv.initialize.ready',
        fields: {
          'durationMs': playback.player.state.duration.inMilliseconds,
          'width': playback.player.state.width ?? 0,
          'height': playback.player.state.height ?? 0,
          'buffering': playback.player.state.buffering,
        },
      );
      unawaited(_syncBackgroundPlayback(enabled: true));
      unawaited(_syncPlaybackSystemSession(force: true));
    } catch (error, stackTrace) {
      _traceQuarkPlaybackStartup(
        'quark.startup.failed',
        target: _resolvedTarget ?? widget.target,
        error: error,
        stackTrace: stackTrace,
      );
      _traceWindowsMpv(
        'windows-mpv.initialize.failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      _adaptiveTopChromeController.setVisible(true);
      setState(() {
        _error = _buildPlaybackErrorMessage(error);
      });
      unawaited(_syncBackgroundPlayback(enabled: false));
      unawaited(_teardownPlaybackSystemSession());
    }
  }

  Future<_OpenedPlayback> _openWithRetry(
    PlaybackTarget resolvedTarget, {
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    Object? lastError;

    for (var attempt = 1;
        attempt <= _PlayerPageState._maxPlaybackAttempts;
        attempt++) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        break;
      }

      try {
        _traceWindowsMpv(
          'windows-mpv.open.attempt',
          fields: {
            'attempt': attempt,
            'remainingMs': remaining.inMilliseconds,
          },
        );
        final opened = await _openSingleAttempt(
          resolvedTarget,
          timeout: remaining,
        );
        _traceWindowsMpv(
          'windows-mpv.open.attempt-success',
          fields: {'attempt': attempt},
        );
        return opened;
      } catch (error, stackTrace) {
        lastError = error;
        _traceWindowsMpv(
          'windows-mpv.open.attempt-failed',
          fields: {'attempt': attempt},
          error: error,
          stackTrace: stackTrace,
        );
        if (attempt >= _PlayerPageState._maxPlaybackAttempts) {
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
    final bufferSizeBytes = _resolveMpvBufferSizeBytes(resolvedTarget);
    final hardwareDecodeMode = _resolveMpvHardwareDecodeMode();
    final player = Player(
      configuration: PlayerConfiguration(
        title: 'Starflow',
        logLevel: MPVLogLevel.error,
        bufferSize: bufferSizeBytes,
      ),
    );
    final videoController = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        hwdec: hardwareDecodeMode,
        enableHardwareAcceleration:
            _playbackDecodeMode != PlaybackDecodeMode.softwarePreferred,
      ),
    );
    _traceWindowsMpv(
      'windows-mpv.open.create-player',
      fields: {
        'timeoutMs': timeout.inMilliseconds,
        'bufferSizeBytes': bufferSizeBytes,
        'hwdec': hardwareDecodeMode,
        'hardwareAcceleration':
            _playbackDecodeMode != PlaybackDecodeMode.softwarePreferred,
      },
    );
    Completer<String>? startupError;
    var awaitingStartup = false;
    late final StreamSubscription<String> errorSubscription;
    errorSubscription = player.stream.error.listen((message) {
      final normalized = message.trim();
      if (normalized.isEmpty) {
        return;
      }
      _traceWindowsMpv(
        'windows-mpv.player.error',
        fields: {
          'startup': awaitingStartup,
          'message': normalized,
        },
      );
      final pendingStartupError = startupError;
      if (awaitingStartup &&
          pendingStartupError != null &&
          !pendingStartupError.isCompleted) {
        pendingStartupError.complete(normalized);
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
      await _applyMpvPerformanceTuning(player, resolvedTarget);
      _traceWindowsMpv('windows-mpv.open.tuning-applied');
      final deadline = DateTime.now().add(timeout);
      Completer<String> beginStartupWait() {
        final completer = Completer<String>();
        startupError = completer;
        awaitingStartup = true;
        return completer;
      }

      await _openResolvedTargetWithMpv(
        player,
        resolvedTarget,
        deadline: deadline,
        beginStartupWait: beginStartupWait,
      );
      startupError = Completer<String>();
      await _awaitStrictPlaybackReady(
        player,
        target: resolvedTarget,
        timeout: _remainingMpvOpenTimeout(deadline),
        startupError: startupError!.future,
        stageLabel: 'open-attempt',
        progressBaseline: player.state.position,
      );
      awaitingStartup = false;
      startupError = null;
      _traceWindowsMpv(
        'windows-mpv.open.ready',
        fields: {
          'positionMs': player.state.position.inMilliseconds,
          'durationMs': player.state.duration.inMilliseconds,
          'width': player.state.width ?? 0,
          'height': player.state.height ?? 0,
          'buffering': player.state.buffering,
        },
      );
      return _OpenedPlayback(
        player: player,
        videoController: videoController,
        errorSubscription: errorSubscription,
      );
    } catch (error, stackTrace) {
      _traceWindowsMpv(
        'windows-mpv.open.failed',
        error: error,
        stackTrace: stackTrace,
      );
      await errorSubscription.cancel();
      await player.dispose();
      rethrow;
    }
  }

  Future<_OpenedPlayback> _openEmbeddedPlayback(
    PlaybackTarget resolvedTarget,
    Duration timeout,
  ) async {
    final playback = await _openWithRetry(
      resolvedTarget,
      timeout: timeout,
    );
    await _applyStartupPlaybackPreferences(playback.player);
    await _applyStartupExternalSubtitle(playback.player, resolvedTarget);
    return playback;
  }

  Future<({PlaybackRemotePreflightResult? preflight, _StartupProbeResult probe})>
  _prepareStartupDiagnostics(PlaybackTarget target) async {
    final preflightFuture = _shouldRunRemotePreflight(target)
        ? _playbackRemotePreflight.probe(target)
        : Future<PlaybackRemotePreflightResult?>.value(null);
    final probeFuture = _startupProbeEnabled
        ? _probeStartup(target)
        : Future<_StartupProbeResult>.value(const _StartupProbeResult());

    final results = await Future.wait<Object?>([
      preflightFuture,
      probeFuture,
    ]);
    final preflight = results[0] as PlaybackRemotePreflightResult?;
    final probe = results[1] as _StartupProbeResult;

    if (preflight != null) {
      _traceWindowsMpv(
        'windows-mpv.remote-preflight.result',
        fields: {
          'statusCode': preflight.statusCode,
          'supportsByteRange': preflight.supportsByteRange,
          'sampledBytes': preflight.sampledBytes,
          'durationMs': preflight.duration.inMilliseconds,
          'failureReason': preflight.failureReason.name,
          'authLikelyInvalid': preflight.authLikelyInvalid,
          'linkLikelyExpired': preflight.linkLikelyExpired,
        },
      );
    }

    if (mounted) {
      setState(() {
        _lastRemotePreflight = preflight;
        _startupProbe = probe;
      });
    } else {
      _lastRemotePreflight = preflight;
      _startupProbe = probe;
    }

    if (preflight != null && preflight.hasHardFailure) {
      throw _PlayerOpenException(
        _buildRemotePreflightFailureMessage(preflight),
      );
    }

    return (preflight: preflight, probe: probe);
  }

  bool _shouldRunRemotePreflight(PlaybackTarget target) {
    final transportUrl = isLoopbackPlaybackRelayUrl(target.streamUrl)
        ? target.actualAddress.trim()
        : target.streamUrl.trim();
    final scheme = Uri.tryParse(transportUrl)?.scheme.toLowerCase() ?? '';
    return scheme == 'http' || scheme == 'https';
  }

  int _resolvePlaybackOpenTimeoutSeconds({
    required int baseSeconds,
    required PlaybackTarget target,
    PlaybackRemotePreflightResult? preflight,
    required _StartupProbeResult probe,
  }) {
    var resolved = baseSeconds;
    final startupProbeMegabitsPerSecond = probe.estimatedSpeedBytesPerSecond ==
            null
        ? null
        : (probe.estimatedSpeedBytesPerSecond! * 8) / 1000000;
    final lowStartupSpeed = startupProbeMegabitsPerSecond != null &&
        startupProbeMegabitsPerSecond > 0 &&
        startupProbeMegabitsPerSecond < 12;
    final criticalStartupSpeed = startupProbeMegabitsPerSecond != null &&
        startupProbeMegabitsPerSecond > 0 &&
        startupProbeMegabitsPerSecond < 6;
    final remotePlayback = _isLikelyRemotePlaybackTarget(target);

    if (remotePlayback && lowStartupSpeed) {
      resolved += 6;
    }
    if (remotePlayback && criticalStartupSpeed) {
      resolved += 8;
    }
    if (preflight != null && !preflight.supportsByteRange) {
      resolved += 4;
    }
    if (remotePlayback && isLikelyQuarkPlaybackTarget(target)) {
      resolved += 4;
    }
    return resolved.clamp(1, 90);
  }

  String _buildRemotePreflightFailureMessage(
    PlaybackRemotePreflightResult result,
  ) {
    return switch (result.failureReason) {
      PlaybackRemotePreflightFailureReason.emptyUrl => '播放地址为空',
      PlaybackRemotePreflightFailureReason.unsupportedScheme =>
        '当前播放地址协议暂不支持预检',
      PlaybackRemotePreflightFailureReason.timeout =>
        '播放链接预检超时，远端响应过慢',
      PlaybackRemotePreflightFailureReason.unauthorized =>
        '播放链接鉴权失败，请重新登录或刷新授权',
      PlaybackRemotePreflightFailureReason.forbidden =>
        '播放链接已被拒绝，请检查会员/VIP 或权限状态',
      PlaybackRemotePreflightFailureReason.notFound =>
        '播放链接已失效或文件不存在',
      PlaybackRemotePreflightFailureReason.linkExpired =>
        '播放链接已过期，请重新获取播放地址',
      PlaybackRemotePreflightFailureReason.serverError =>
        '远端服务暂时不可用，请稍后重试',
      PlaybackRemotePreflightFailureReason.networkError =>
        '播放链接预检失败，请检查网络或远端连接',
      PlaybackRemotePreflightFailureReason.none => '远程流预检失败',
    };
  }

  Future<void> _awaitStrictPlaybackReady(
    Player player, {
    required PlaybackTarget target,
    required Duration timeout,
    required String stageLabel,
    Duration? progressBaseline,
    Future<String>? startupError,
  }) async {
    final deadline = DateTime.now().add(timeout);
    final readyCompleter = Completer<void>();
    final subscriptions = <StreamSubscription<dynamic>>[];
    final startupFailureFuture = startupError?.then<void>((message) {
      throw _PlayerOpenException(message);
    });
    final baseline = progressBaseline ?? player.state.position;
    final watchdog = MpvStallWatchdog(
      config: _resolveStartupStallWatchdogConfig(target),
    );

    void evaluateReady() {
      if (readyCompleter.isCompleted) {
        return;
      }
      if (_isStrictPlaybackReady(player, progressBaseline: baseline)) {
        readyCompleter.complete();
      }
    }

    subscriptions.addAll([
      player.stream.position.listen((_) => evaluateReady()),
      player.stream.duration.listen((_) => evaluateReady()),
      player.stream.width.listen((_) => evaluateReady()),
      player.stream.height.listen((_) => evaluateReady()),
      player.stream.playing.listen((_) => evaluateReady()),
      player.stream.buffering.listen((_) => evaluateReady()),
    ]);
    evaluateReady();

    try {
      while (!readyCompleter.isCompleted) {
        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) {
          throw TimeoutException('播放器打开后长时间没有开始播放');
        }
        final tick = remaining > const Duration(seconds: 1)
            ? const Duration(seconds: 1)
            : remaining;
        final waiters = <Future<void>>[
          readyCompleter.future,
          Future<void>.delayed(tick),
        ];
        if (startupFailureFuture != null) {
          waiters.add(startupFailureFuture);
        }
        await Future.any(waiters);
        if (readyCompleter.isCompleted) {
          break;
        }
        evaluateReady();
        if (readyCompleter.isCompleted) {
          break;
        }
        final decision = watchdog.evaluate(
          MpvPlaybackSnapshot.fromPlayer(player),
        );
        if (!decision.triggered) {
          continue;
        }
        _traceWindowsMpv(
          'windows-mpv.startup.stall-detected',
          fields: {
            'stage': stageLabel,
            'level': decision.level.name,
            'positionMs': decision.position.inMilliseconds,
            'bufferingForMs': decision.bufferingFor.inMilliseconds,
            'stagnantForMs': decision.stagnantFor.inMilliseconds,
            'bufferingPercentage': decision.bufferingPercentage,
            'reason': decision.reason,
          },
        );
        if (decision.level == MpvStallRecoveryLevel.soft) {
          await _performSoftMpvStallRecovery(
            player,
            decision,
            stageLabel: '$stageLabel-soft',
          );
          evaluateReady();
          continue;
        }
        throw TimeoutException('播放器启动后持续缓冲且进度未前进，已自动重试');
      }
    } finally {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    }
  }

  bool _isStrictPlaybackReady(
    Player player, {
    required Duration progressBaseline,
  }) {
    final state = player.state;
    final positionDelta = state.position - progressBaseline;
    final hasProgress = positionDelta >= const Duration(milliseconds: 250);
    final hasMetadata = _hasStrictPlaybackMetadata(player);
    return state.playing && hasProgress && (hasMetadata || !state.buffering);
  }

  bool _hasStrictPlaybackMetadata(Player player) {
    final state = player.state;
    final width = state.width ?? 0;
    final height = state.height ?? 0;
    return state.duration > Duration.zero || (width > 0 && height > 0);
  }

  MpvStallWatchdogConfig _resolveStartupStallWatchdogConfig(
    PlaybackTarget target,
  ) {
    final remotePlayback = _isLikelyRemotePlaybackTarget(target);
    final quarkPlayback = isLikelyQuarkPlaybackTarget(target);
    if (quarkPlayback) {
      return const MpvStallWatchdogConfig(
        minBufferingBeforeCheck: Duration(seconds: 2),
        softRecoverAfter: Duration(seconds: 6),
        hardRecoverAfter: Duration(seconds: 12),
        requirePlaying: false,
      );
    }
    if (remotePlayback) {
      return const MpvStallWatchdogConfig(
        minBufferingBeforeCheck: Duration(seconds: 2),
        softRecoverAfter: Duration(seconds: 5),
        hardRecoverAfter: Duration(seconds: 10),
        requirePlaying: false,
      );
    }
    return const MpvStallWatchdogConfig(
      minBufferingBeforeCheck: Duration(seconds: 2),
      softRecoverAfter: Duration(seconds: 4),
      hardRecoverAfter: Duration(seconds: 8),
      requirePlaying: false,
    );
  }

  MpvStallWatchdogConfig _resolveRuntimeStallWatchdogConfig(
    PlaybackTarget target,
  ) {
    if (isLikelyQuarkPlaybackTarget(target)) {
      return const MpvStallWatchdogConfig(
        minBufferingBeforeCheck: Duration(seconds: 2),
        softRecoverAfter: Duration(seconds: 6),
        hardRecoverAfter: Duration(seconds: 12),
      );
    }
    if (_isLikelyRemotePlaybackTarget(target)) {
      return const MpvStallWatchdogConfig(
        minBufferingBeforeCheck: Duration(seconds: 2),
        softRecoverAfter: Duration(seconds: 5),
        hardRecoverAfter: Duration(seconds: 10),
      );
    }
    return const MpvStallWatchdogConfig(
      minBufferingBeforeCheck: Duration(seconds: 3),
      softRecoverAfter: Duration(seconds: 6),
      hardRecoverAfter: Duration(seconds: 12),
    );
  }

  Future<void> _performSoftMpvStallRecovery(
    Player player,
    MpvStallDecision decision, {
    required String stageLabel,
  }) async {
    _traceWindowsMpv(
      'windows-mpv.stall.recover-soft',
      fields: {
        'stage': stageLabel,
        'positionMs': decision.position.inMilliseconds,
        'bufferingForMs': decision.bufferingFor.inMilliseconds,
        'stagnantForMs': decision.stagnantFor.inMilliseconds,
      },
    );
    await player.play();
    await player.seek(decision.position);
  }

  void _startMpvStallWatchdog(Player player, PlaybackTarget target) {
    _stopMpvStallWatchdog();
    _mpvStallWatchdog = MpvStallWatchdog(
      config: _resolveRuntimeStallWatchdogConfig(target),
    );
    _mpvStallWatchdogTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_tickMpvStallWatchdog(player, target));
    });
  }

  void _stopMpvStallWatchdog({bool clearRecoveryFlag = true}) {
    _mpvStallWatchdogTimer?.cancel();
    _mpvStallWatchdogTimer = null;
    _mpvStallWatchdog = null;
    if (clearRecoveryFlag) {
      _mpvStallRecoveryInProgress = false;
    }
  }

  Future<void> _tickMpvStallWatchdog(
    Player player,
    PlaybackTarget target,
  ) async {
    if (!mounted ||
        !_isReady ||
        _error != null ||
        _player != player ||
        _mpvStallRecoveryInProgress) {
      return;
    }
    final watchdog = _mpvStallWatchdog;
    if (watchdog == null) {
      return;
    }
    final decision = watchdog.evaluate(
      MpvPlaybackSnapshot.fromPlayer(player),
    );
    if (!decision.triggered) {
      return;
    }
    if (decision.level == MpvStallRecoveryLevel.soft) {
      _mpvStallRecoveryInProgress = true;
      try {
        await _performSoftMpvStallRecovery(
          player,
          decision,
          stageLabel: 'runtime',
        );
      } finally {
        _mpvStallRecoveryInProgress = false;
      }
      return;
    }
    await _performHardMpvStallRecovery(player, target, decision);
  }

  Future<void> _performHardMpvStallRecovery(
    Player player,
    PlaybackTarget target,
    MpvStallDecision decision,
  ) async {
    if (_mpvStallRecoveryInProgress || _player != player) {
      return;
    }
    _mpvStallRecoveryInProgress = true;
    _traceWindowsMpv(
      'windows-mpv.stall.recover-hard',
      fields: {
        'positionMs': decision.position.inMilliseconds,
        'bufferingForMs': decision.bufferingFor.inMilliseconds,
        'stagnantForMs': decision.stagnantFor.inMilliseconds,
        'targetTitle': target.title,
      },
    );
    try {
      _latestPosition = decision.position;
      if (player.state.duration > Duration.zero) {
        _latestDuration = player.state.duration;
      }
      final detachedPlayer = _detachActivePlayerState(
        clearStallRecoveryFlag: false,
      );
      if (mounted) {
        setState(() {
          _error = null;
        });
      } else {
        _error = null;
      }
      await _shutdownDetachedPlayer(
        detachedPlayer,
        reason: 'mpv-stall-hard-recover',
        persistProgress: true,
        teardownPlatformState: true,
      );
      if (!mounted) {
        return;
      }
      await _initialize();
    } catch (error, stackTrace) {
      _traceWindowsMpv(
        'windows-mpv.stall.recover-hard-failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _error = _buildPlaybackErrorMessage(error);
        });
      }
    } finally {
      _mpvStallRecoveryInProgress = false;
    }
  }

  Future<void> _launchWithSystemPlayer(PlaybackTarget target) async {
    _traceQuarkPlaybackStartup(
      'quark.launch.system.begin',
      target: target,
      fields: {'streamUrl': target.streamUrl},
    );
    final result =
        await _providerContainer.read(systemPlaybackLauncherProvider).launch(
          target,
        );
    _traceQuarkPlaybackStartup(
      'quark.launch.system.result',
      target: target,
      fields: {
        'launched': result.launched,
        'message': result.message,
      },
    );
    if (!result.launched) {
      throw _PlayerOpenException(
        result.message.isEmpty ? '外部系统播放器启动失败' : result.message,
      );
    }

    if (!mounted) {
      return;
    }
    context.pop();
  }

  Future<void> _launchWithNativeContainer(PlaybackTarget target) async {
    _traceQuarkPlaybackStartup(
      'quark.launch.native.begin',
      target: target,
      fields: {
        'streamUrl': target.streamUrl,
        'decodeMode': _playbackDecodeMode.name,
      },
    );
    final result = await _providerContainer
        .read(nativePlaybackLauncherProvider)
        .launch(
          target,
          decodeMode: _playbackDecodeMode,
        );
    _traceQuarkPlaybackStartup(
      'quark.launch.native.result',
      target: target,
      fields: {
        'launched': result.launched,
        'message': result.message,
      },
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
    _traceQuarkPlaybackStartup(
      'quark.launch.fallback.begin',
      target: target,
      fields: {'decodeMode': _playbackDecodeMode.name},
    );
    final nativeResult = await _providerContainer
        .read(nativePlaybackLauncherProvider)
        .launch(
          target,
          decodeMode: _playbackDecodeMode,
        );
    _traceQuarkPlaybackStartup(
      'quark.launch.fallback.native-result',
      target: target,
      fields: {
        'launched': nativeResult.launched,
        'message': nativeResult.message,
      },
    );
    if (nativeResult.launched) {
      if (mounted) {
        context.pop();
      }
      return true;
    }

    final result =
        await _providerContainer.read(systemPlaybackLauncherProvider).launch(
          target,
        );
    _traceQuarkPlaybackStartup(
      'quark.launch.fallback.system-result',
      target: target,
      fields: {
        'launched': result.launched,
        'message': result.message,
      },
    );
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
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
          return 'auto-safe';
        }
        return _prefersAggressiveHardwareDecoding ? 'auto' : 'auto-safe';
      case PlaybackDecodeMode.hardwarePreferred:
        return 'auto';
      case PlaybackDecodeMode.softwarePreferred:
        return 'no';
    }
  }

  Future<void> _setMpvOption(Player player, String name, String value) async {
    if (kIsWeb) {
      return;
    }
    final native = player.platform;
    if (native == null) {
      return;
    }
    try {
      await (native as dynamic).setProperty(name, value);
    } catch (_) {
      // Keep playback available even if a tuning hint is unsupported.
    }
  }

  Future<void> _openResolvedTargetWithMpv(
    Player player,
    PlaybackTarget target, {
    required DateTime deadline,
    required Completer<String> Function() beginStartupWait,
  }) async {
    final regularMedia = _buildRegularMpvMedia(target);
    if (!target.isIsoLike) {
      _traceWindowsMpv(
        'windows-mpv.open.dispatch',
        fields: {
          'urlScheme': Uri.tryParse(target.streamUrl)?.scheme ?? '',
          'openMode': 'direct',
        },
      );
      await _awaitMpvMediaOpen(
        player,
        regularMedia,
        timeout: _remainingMpvOpenTimeout(deadline),
        startupError: beginStartupWait(),
      );
      return;
    }

    final isoPlans = _buildMpvIsoOpenPlans(target);
    _traceWindowsMpv(
      'windows-mpv.iso.plan',
      fields: {
        'candidateCount': isoPlans.length,
        'discKinds':
            _inferMpvIsoDiscKinds(target).map((kind) => kind.name).join(','),
        'hasHeaders': target.headers.isNotEmpty,
      },
    );
    if (isoPlans.isEmpty) {
      _traceWindowsMpv(
        'windows-mpv.iso.skip-device-mode',
        fields: {
          'urlScheme': Uri.tryParse(target.streamUrl)?.scheme ?? '',
        },
      );
      await _awaitMpvMediaOpen(
        player,
        regularMedia,
        timeout: _remainingMpvOpenTimeout(deadline),
        startupError: beginStartupWait(),
      );
      return;
    }

    Object? lastError;
    for (final plan in isoPlans) {
      try {
        await _applyMpvIsoOpenPlan(player, target, plan);
        _traceWindowsMpv(
          'windows-mpv.open.dispatch',
          fields: {
            'urlScheme': Uri.tryParse(target.streamUrl)?.scheme ??
                Uri.tryParse(plan.deviceSource)?.scheme ??
                '',
            'openMode': 'iso',
            'discKind': plan.discKind.name,
            'deviceProperty': plan.deviceProperty,
            'deviceSourceKind': _describeMpvIsoDeviceSource(plan.deviceSource),
          },
        );
        await _awaitMpvMediaOpen(
          player,
          Media(plan.mediaUri),
          timeout: _remainingMpvOpenTimeout(deadline),
          startupError: beginStartupWait(),
        );
        return;
      } catch (error, stackTrace) {
        lastError = error;
        _traceWindowsMpv(
          'windows-mpv.iso.open-attempt-failed',
          fields: {
            'discKind': plan.discKind.name,
            'deviceProperty': plan.deviceProperty,
            'deviceSourceKind': _describeMpvIsoDeviceSource(plan.deviceSource),
          },
          error: error,
          stackTrace: stackTrace,
        );
        try {
          await player.stop();
        } catch (_) {
          // Ignore stop failures and allow the next ISO fallback to continue.
        }
      }
    }

    _traceWindowsMpv(
      'windows-mpv.iso.fallback-direct',
      fields: {
        'urlScheme': Uri.tryParse(target.streamUrl)?.scheme ?? '',
      },
    );
    try {
      await _resetMpvIsoOpenState(player);
      await _awaitMpvMediaOpen(
        player,
        regularMedia,
        timeout: _remainingMpvOpenTimeout(deadline),
        startupError: beginStartupWait(),
      );
      return;
    } catch (error, stackTrace) {
      if (lastError != null) {
        _traceWindowsMpv(
          'windows-mpv.iso.fallback-direct-failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
      rethrow;
    }
  }

  Future<void> _awaitMpvMediaOpen(
    Player player,
    Media media, {
    required Duration timeout,
    required Completer<String> startupError,
  }) async {
    await Future.any<void>([
      player.open(media, play: true),
      startupError.future.then<void>((message) {
        throw _PlayerOpenException(message);
      }),
    ]).timeout(timeout);
  }

  Media _buildRegularMpvMedia(PlaybackTarget target) {
    final resource = target.streamUrl.trim().isNotEmpty
        ? target.streamUrl.trim()
        : target.actualAddress.trim();
    final resolvedResource = buildStarflowWebProxyUrl(
      resource,
      headers: target.headers,
    );
    return Media(
      resolvedResource,
      httpHeaders: kIsWeb || target.headers.isEmpty ? null : target.headers,
    );
  }

  Duration _remainingMpvOpenTimeout(DateTime deadline) {
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      throw TimeoutException('超过最大等待时间，已停止尝试播放');
    }
    return remaining;
  }

  List<_MpvIsoOpenPlan> _buildMpvIsoOpenPlans(PlaybackTarget target) {
    final deviceSources = <String>[];
    final seen = <String>{};

    void addDeviceSource(String raw) {
      final normalized = _normalizeMpvIsoDeviceSource(raw);
      if (normalized.isEmpty) {
        return;
      }
      final dedupeKey = normalized.toLowerCase();
      if (!seen.add(dedupeKey)) {
        return;
      }
      deviceSources.add(normalized);
    }

    final actualAddress = _normalizeMpvIsoDeviceSource(target.actualAddress);
    final streamUrl = _normalizeMpvIsoDeviceSource(target.streamUrl);
    if (_isLikelyLocalMpvIsoDeviceSource(actualAddress)) {
      addDeviceSource(actualAddress);
    }
    if (_isLikelyLocalMpvIsoDeviceSource(streamUrl)) {
      addDeviceSource(streamUrl);
    }

    final discKinds = _inferMpvIsoDiscKinds(target);
    return [
      for (final deviceSource in deviceSources)
        for (final discKind in discKinds)
          _MpvIsoOpenPlan(
            discKind: discKind,
            deviceSource: deviceSource,
          ),
    ];
  }

  List<_MpvIsoDiscKind> _inferMpvIsoDiscKinds(PlaybackTarget target) {
    final hint = [
      target.container,
      target.streamUrl,
      target.actualAddress,
      target.title,
      target.sourceName,
    ].join(' ').toLowerCase();
    final looksLikeBluray = hint.contains('bluray') ||
        hint.contains('blu-ray') ||
        hint.contains('bdmv') ||
        hint.contains('bdrom');
    final looksLikeDvd = hint.contains('dvd') ||
        hint.contains('video_ts') ||
        hint.contains('vts_');
    if (looksLikeDvd && !looksLikeBluray) {
      return const [_MpvIsoDiscKind.dvd, _MpvIsoDiscKind.bluray];
    }
    return const [_MpvIsoDiscKind.bluray, _MpvIsoDiscKind.dvd];
  }

  String _normalizeMpvIsoDeviceSource(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (_looksLikeWindowsAbsolutePath(trimmed) || _looksLikeUncPath(trimmed)) {
      return trimmed;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.scheme.toLowerCase() == 'file') {
      try {
        return uri.toFilePath(
          windows: defaultTargetPlatform == TargetPlatform.windows,
        );
      } catch (_) {
        return trimmed;
      }
    }
    if (uri != null && uri.hasScheme) {
      return uri.toString();
    }
    return trimmed;
  }

  bool _isLikelyLocalMpvIsoDeviceSource(String value) {
    return isLikelyLocalMpvIsoDeviceSource(
      value,
      windowsPlatform: defaultTargetPlatform == TargetPlatform.windows,
      posixPlatform: defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS,
    );
  }

  bool _isLikelyRemoteMpvIsoDeviceSource(String value) {
    final uri = Uri.tryParse(value.trim());
    final scheme = uri?.scheme.toLowerCase() ?? '';
    return switch (scheme) {
      'http' || 'https' || 'rtsp' || 'rtmp' || 'ftp' || 'ftps' => true,
      _ => false,
    };
  }

  bool _looksLikeWindowsAbsolutePath(String value) {
    return RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(value);
  }

  bool _looksLikeUncPath(String value) {
    return value.startsWith(r'\\') || value.startsWith('//');
  }

  Future<void> _applyMpvIsoOpenPlan(
    Player player,
    PlaybackTarget target,
    _MpvIsoOpenPlan plan,
  ) async {
    await _setMpvOption(player, plan.deviceProperty, plan.deviceSource);
    await _setMpvOption(player, plan.otherDeviceProperty, '');
    final headerFields = _isLikelyRemoteMpvIsoDeviceSource(plan.deviceSource)
        ? _encodeMpvHttpHeaderFields(target.headers)
        : '';
    await _setMpvOption(player, 'http-header-fields', headerFields);
  }

  Future<void> _resetMpvIsoOpenState(Player player) async {
    await _setMpvOption(player, 'dvd-device', '');
    await _setMpvOption(player, 'bluray-device', '');
    await _setMpvOption(player, 'http-header-fields', '');
  }

  String _encodeMpvHttpHeaderFields(Map<String, String> headers) {
    return headers.entries
        .where(
          (entry) =>
              entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty,
        )
        .map(
          (entry) =>
              '${_escapeMpvListValue(entry.key.trim())}: ${_escapeMpvListValue(entry.value.trim().replaceAll(RegExp(r'[\r\n]+'), ' '))}',
        )
        .join(',');
  }

  String _escapeMpvListValue(String value) {
    return value.replaceAll('\\', r'\\').replaceAll(',', r'\,');
  }

  String _describeMpvIsoDeviceSource(String value) {
    final trimmed = value.trim();
    if (_looksLikeWindowsAbsolutePath(trimmed)) {
      return 'windows-path';
    }
    if (_looksLikeUncPath(trimmed)) {
      return 'unc-path';
    }
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasScheme) {
      return uri.scheme.toLowerCase();
    }
    if (trimmed.startsWith('/')) {
      return 'posix-path';
    }
    return 'plain-path';
  }

  Future<void> _applyMpvVisualQualityPreset(
    Player player,
    PlaybackMpvQualityPreset preset,
  ) async {
    switch (preset) {
      case PlaybackMpvQualityPreset.qualityFirst:
        await _setMpvOption(player, 'deband', 'yes');
        await _setMpvOption(player, 'scale', 'ewa_lanczossharp');
        await _setMpvOption(player, 'cscale', 'ewa_lanczossoft');
        await _setMpvOption(player, 'dscale', 'mitchell');
        await _setMpvOption(player, 'sigmoid-upscaling', 'yes');
        await _setMpvOption(player, 'correct-downscaling', 'yes');
        await _setMpvOption(player, 'interpolation', 'no');
        break;
      case PlaybackMpvQualityPreset.balanced:
        await _setMpvOption(player, 'deband', 'yes');
        await _setMpvOption(player, 'scale', 'spline36');
        await _setMpvOption(player, 'cscale', 'bilinear');
        await _setMpvOption(player, 'dscale', 'mitchell');
        await _setMpvOption(player, 'sigmoid-upscaling', 'no');
        await _setMpvOption(player, 'correct-downscaling', 'yes');
        await _setMpvOption(player, 'interpolation', 'no');
        break;
      case PlaybackMpvQualityPreset.performanceFirst:
        await _setMpvOption(player, 'deband', 'no');
        await _setMpvOption(player, 'scale', 'bilinear');
        await _setMpvOption(player, 'cscale', 'bilinear');
        await _setMpvOption(player, 'dscale', 'bilinear');
        await _setMpvOption(player, 'sigmoid-upscaling', 'no');
        await _setMpvOption(player, 'correct-downscaling', 'no');
        await _setMpvOption(player, 'interpolation', 'no');
        break;
    }
  }

  bool get _isTelevisionPlaybackDevice =>
      _providerContainer.read(isTelevisionProvider).value ?? false;

  void _traceQuarkPlaybackStartup(
    String stage, {
    required PlaybackTarget target,
    Map<String, Object?> fields = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (target.sourceKind != MediaSourceKind.quark) {
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

  int _resolveMpvBufferSizeBytes(PlaybackTarget target) {
    if (isLikelyQuarkPlaybackTarget(target)) {
      return _shouldUseAggressiveMpvTuning(target)
          ? _PlayerPageState._kAggressiveQuarkMpvBufferSizeBytes
          : _PlayerPageState._kQuarkMpvBufferSizeBytes;
    }
    if (_shouldUseAggressiveMpvTuning(target)) {
      return _PlayerPageState._kAggressiveMpvBufferSizeBytes;
    }
    if (_isTelevisionPlaybackDevice && _isLikelyRemotePlaybackTarget(target)) {
      return _PlayerPageState._kHeavyMpvBufferSizeBytes;
    }
    if (_isHeavyPlaybackTarget(target)) {
      return _PlayerPageState._kHeavyMpvBufferSizeBytes;
    }
    if (_isLikelyRemotePlaybackTarget(target)) {
      return _PlayerPageState._kNetworkMpvBufferSizeBytes;
    }
    return _PlayerPageState._kDefaultMpvBufferSizeBytes;
  }

  bool _isLikelyRemotePlaybackTarget(PlaybackTarget target) {
    return isLikelyRemotePlaybackTargetTransport(target);
  }

  bool _isHeavyPlaybackTarget(PlaybackTarget target) {
    return isHeavyPlaybackTargetMetadata(target);
  }

  bool _shouldUseAggressiveMpvTuning(PlaybackTarget target) {
    if (_aggressivePlaybackTuningEnabled) {
      return true;
    }
    final startupProbeMegabitsPerSecond = _startupProbeMegabitsPerSecond;
    final lowStartupSpeed = startupProbeMegabitsPerSecond != null &&
        startupProbeMegabitsPerSecond > 0 &&
        startupProbeMegabitsPerSecond < 12;
    if (_isLikelyRemotePlaybackTarget(target) &&
        (_remotePreflightIndicatesRangeRisk || lowStartupSpeed)) {
      return true;
    }
    if (!_isHeavyPlaybackTarget(target)) {
      return false;
    }
    return _isTelevisionPlaybackDevice ||
        _playbackDecodeMode == PlaybackDecodeMode.softwarePreferred;
  }

  PlaybackMpvQualityPreset _resolveEffectiveMpvQualityPreset(
    PlaybackTarget target,
  ) {
    final requestedPreset = _playbackMpvQualityPreset;
    if (!_autoDowngradePlaybackQualityEnabled) {
      return requestedPreset;
    }
    return resolveEffectivePlaybackMpvQualityPreset(
      requestedPreset: requestedPreset,
      target: target,
      isWindowsPlatform:
          !kIsWeb && defaultTargetPlatform == TargetPlatform.windows,
      isTelevision: _isTelevisionPlaybackDevice,
      isFullscreen: _isEmbeddedMpvFullscreen,
      aggressiveTuningEnabled: _aggressivePlaybackTuningEnabled,
      decodeMode: _playbackDecodeMode,
      remotePlaybackOverride: _isLikelyRemotePlaybackTarget(target),
      highRiskContainerOverride:
          isHighRiskRemotePlaybackContainer(target) ||
          _remotePreflightIndicatesRangeRisk,
      startupProbeMegabitsPerSecond: _startupProbeMegabitsPerSecond,
    );
  }

  Future<void> _syncEmbeddedMpvFullscreen(bool isFullscreen) async {
    if (_isEmbeddedMpvFullscreen == isFullscreen) {
      return;
    }
    if (mounted) {
      setState(() {
        _isEmbeddedMpvFullscreen = isFullscreen;
      });
    } else {
      _isEmbeddedMpvFullscreen = isFullscreen;
    }
    final player = _player;
    if (player == null) {
      return;
    }
    await _applyMpvPerformanceTuning(player, _resolvedTarget ?? widget.target);
  }

  Future<void> _applyMpvPerformanceTuning(
    Player player,
    PlaybackTarget target,
  ) async {
    if (kIsWeb) {
      return;
    }

    final remotePlayback = _isLikelyRemotePlaybackTarget(target);
    final heavyPlayback = _isHeavyPlaybackTarget(target);
    final aggressiveTuning = _shouldUseAggressiveMpvTuning(target);
    final leanPlayback = _preferLeanPlaybackRendering;
    final requestedQualityPreset = _playbackMpvQualityPreset;
    final qualityPreset = _resolveEffectiveMpvQualityPreset(target);
    final bufferSizeBytes = _resolveMpvBufferSizeBytes(target);
    final highRiskContainer = isHighRiskRemotePlaybackContainer(target) ||
        _remotePreflightIndicatesRangeRisk;
    final remoteProfile = resolveMpvRemotePlaybackTuningProfile(
      target: target,
      aggressiveTuning: aggressiveTuning,
      heavyPlayback: heavyPlayback,
      startupProbeMegabitsPerSecond: _startupProbeMegabitsPerSecond,
      highRiskContainerOverride: highRiskContainer,
    );
    final backBufferBytes = _resolveMpvBackBufferSizeBytes(
      target,
      bufferSizeBytes: bufferSizeBytes,
    );

    await _setMpvOption(player, 'demuxer-thread', 'yes');
    await _setMpvOption(
      player,
      'demuxer-max-bytes',
      bufferSizeBytes.toString(),
    );
    await _setMpvOption(
      player,
      'demuxer-max-back-bytes',
      backBufferBytes.toString(),
    );
    await _setMpvOption(player, 'audio-display', 'no');
    await _applyMpvVisualQualityPreset(player, qualityPreset);

    if (_isTelevisionPlaybackDevice) {
      await _setMpvOption(player, 'osd-bar', 'no');
    }

    if (remotePlayback && remoteProfile != null) {
      await _setMpvOption(
        player,
        'network-timeout',
        remoteProfile.networkTimeoutSeconds,
      );
      await _setMpvOption(player, 'cache', 'yes');
      await _setMpvOption(player, 'cache-on-disk', remoteProfile.cacheOnDisk);
      if (remoteProfile.cacheSecs.isNotEmpty) {
        await _setMpvOption(player, 'cache-secs', remoteProfile.cacheSecs);
      }
      await _setMpvOption(
        player,
        'demuxer-readahead-secs',
        remoteProfile.demuxerReadaheadSecs,
      );
      await _setMpvOption(
        player,
        'demuxer-hysteresis-secs',
        remoteProfile.demuxerHysteresisSecs,
      );
      await _setMpvOption(
        player,
        'cache-pause-wait',
        remoteProfile.cachePauseWait,
      );
      await _setMpvOption(
        player,
        'cache-pause-initial',
        remoteProfile.cachePauseInitial,
      );
    }

    await _setMpvOption(
      player,
      'vd-lavc-dr',
      (leanPlayback ||
              aggressiveTuning ||
              heavyPlayback ||
              qualityPreset == PlaybackMpvQualityPreset.performanceFirst)
          ? 'yes'
          : 'no',
    );

    final shouldSkipLoopFilter =
        _playbackDecodeMode == PlaybackDecodeMode.softwarePreferred &&
            (aggressiveTuning ||
                heavyPlayback ||
                qualityPreset == PlaybackMpvQualityPreset.performanceFirst);
    await _setMpvOption(
      player,
      'vd-lavc-skiploopfilter',
      shouldSkipLoopFilter ? 'nonref' : 'none',
    );
    _traceWindowsMpv(
      'windows-mpv.tuning.summary',
      fields: {
        'remotePlayback': remotePlayback,
        'heavyPlayback': heavyPlayback,
        'aggressiveTuning': aggressiveTuning,
        'leanPlayback': leanPlayback,
        'qualityPresetRequested': requestedQualityPreset.name,
        'qualityPresetApplied': qualityPreset.name,
        'bufferSizeBytes': bufferSizeBytes,
        'backBufferBytes': backBufferBytes,
        'quarkTuning': isLikelyQuarkPlaybackTarget(target),
        'startupProbeMbps':
            _startupProbeMegabitsPerSecond?.toStringAsFixed(2) ?? '',
        'rangeRisk': _remotePreflightIndicatesRangeRisk,
        'remoteProfile': remoteProfile == null
            ? ''
            : remoteProfile.lowLatency
                ? 'low-latency'
                : 'buffered',
        'skipLoopFilter': shouldSkipLoopFilter ? 'nonref' : 'none',
      },
    );
  }

  int _resolveMpvBackBufferSizeBytes(
    PlaybackTarget target, {
    required int bufferSizeBytes,
  }) {
    final maxBackBufferBytes = isLikelyQuarkPlaybackTarget(target)
        ? _PlayerPageState._kMaxQuarkMpvBackBufferSizeBytes
        : _PlayerPageState._kMaxMpvBackBufferSizeBytes;
    var backBufferBytes = bufferSizeBytes ~/ 4;
    if (backBufferBytes < _PlayerPageState._kMinMpvBackBufferSizeBytes) {
      backBufferBytes = _PlayerPageState._kMinMpvBackBufferSizeBytes;
    } else if (backBufferBytes > maxBackBufferBytes) {
      backBufferBytes = maxBackBufferBytes;
    }
    return backBufferBytes;
  }

  bool get _remotePreflightIndicatesRangeRisk {
    final preflight = _lastRemotePreflight;
    return preflight != null &&
        preflight.attempted &&
        !preflight.supportsByteRange;
  }
}
