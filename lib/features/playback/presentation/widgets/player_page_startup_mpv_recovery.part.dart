// ignore_for_file: invalid_use_of_protected_member

part of '../player_page.dart';

enum _MpvRuntimeRecoveryResult { recovered, buffering, failed }

extension _PlayerPageStateStartupMpvRecovery on _PlayerPageState {
  Future<void> _handleRuntimeMpvError(
    Player player,
    PlaybackTarget target,
    String message,
  ) async {
    if (!mounted || _player != player) {
      return;
    }
    final fatal = _isFatalRuntimeMpvError(message);
    if (_runtimeMpvErrorRecoveryInProgress && !fatal) return;
    final lowerMessage = message.toLowerCase();
    final now = DateTime.now();
    if (_lastRuntimeMpvErrorAt != null &&
        now.difference(_lastRuntimeMpvErrorAt!) <=
            _kRuntimeMpvErrorBurstWindow) {
      _runtimeMpvErrorBurstCount += 1;
    } else {
      _runtimeMpvErrorBurstCount = 1;
    }
    _lastRuntimeMpvErrorAt = now;

    final shouldEscalateImmediately = fatal ||
        (_runtimeMpvErrorBurstCount > 1 &&
            !_isRecoverableRuntimeMpvError(
              target: target,
              lowerMessage: lowerMessage,
            )) ||
        _runtimeMpvErrorBurstCount > _kMaxTransientRuntimeMpvErrorBurst;
    if (shouldEscalateImmediately) {
      if (!mounted || _player != player) {
        return;
      }
      setState(() {
        _error = message;
      });
      return;
    }
    if (_runtimeMpvErrorRecoveryInProgress) {
      return;
    }

    _runtimeMpvErrorRecoveryInProgress = true;
    _showMessage('连接波动，正在尝试恢复播放…');
    final baselinePosition = player.state.position;

    try {
      final recoveredWithoutAction = await _awaitRuntimeMpvErrorRecoveryWindow(
        player,
        baselinePosition: baselinePosition,
      );
      if (recoveredWithoutAction == _MpvRuntimeRecoveryResult.recovered) {
        _markRuntimeMpvErrorRecovered();
        return;
      }
      if (recoveredWithoutAction == _MpvRuntimeRecoveryResult.buffering) return;

      if (!mounted || _player != player || _error != null) return;
      if (_runtimeMpvErrorRecoveryAttempts >=
          _kMaxRuntimeMpvErrorRecoveryAttempts) {
        setState(() => _error = message);
        return;
      }
      _runtimeMpvErrorRecoveryAttempts += 1;
      _mpvPerformanceTracker?.recordRecovery();
      await _attemptSoftRuntimeMpvErrorRecovery(
        player,
        position: baselinePosition,
      );
      final recoveredAfterSoft = await _awaitRuntimeMpvErrorRecoveryWindow(
        player,
        baselinePosition: baselinePosition,
      );
      if (recoveredAfterSoft == _MpvRuntimeRecoveryResult.recovered) {
        _markRuntimeMpvErrorRecovered();
        return;
      }
      if (recoveredAfterSoft == _MpvRuntimeRecoveryResult.buffering) return;

      if (!mounted || _player != player || _error != null) return;

      if (_isLikelyRemotePlaybackTarget(target)) {
        await _attemptRuntimeMpvReinitializeRecovery(
          player,
          target,
          message: message,
        );
        return;
      }

      if (!mounted || _player != player) {
        return;
      }
      setState(() {
        _error = message;
      });
    } finally {
      _runtimeMpvErrorRecoveryInProgress = false;
    }
  }

  bool _isFatalRuntimeMpvError(String message) {
    return classifyMpvOpenFailure(message) == MpvOpenFailureKind.permanent;
  }

  bool _isRecoverableRuntimeMpvError({
    required PlaybackTarget target,
    required String lowerMessage,
  }) {
    const recoverableFragments = <String>[
      'connection',
      'timed out',
      'timeout',
      'network',
      'broken pipe',
      'resource temporarily unavailable',
      'i/o error',
      'server returned',
      'failed to open',
      'http error',
      'reset by peer',
      'end of file',
    ];
    if (recoverableFragments.any(lowerMessage.contains)) {
      return true;
    }
    return _isLikelyRemotePlaybackTarget(target) &&
        _latestPosition >= const Duration(seconds: 2);
  }

  Future<_MpvRuntimeRecoveryResult> _awaitRuntimeMpvErrorRecoveryWindow(
    Player player, {
    required Duration baselinePosition,
  }) async {
    final remote =
        _isLikelyRemotePlaybackTarget(_resolvedTarget ?? widget.target);
    final deadline = DateTime.now().add(
      remote ? const Duration(seconds: 15) : _kRuntimeMpvErrorConfirmWindow,
    );
    final progress = MpvBufferProgress();
    progress.observe(
      buffer: player.state.buffer,
      percentage: player.state.bufferingPercentage,
    );
    DateTime? lastBufferProgressAt;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted || _player != player || _error != null) {
        return _MpvRuntimeRecoveryResult.failed;
      }
      final state = player.state;
      if (progress.observe(
        buffer: state.buffer,
        percentage: state.bufferingPercentage,
      )) {
        lastBufferProgressAt = DateTime.now();
      }
      final progressed = state.position - baselinePosition >=
          const Duration(milliseconds: 800);
      final healthy = state.playing && !state.buffering && progressed;
      if (healthy) {
        return _MpvRuntimeRecoveryResult.recovered;
      }
    }
    // Continued buffering is not playback success. Leave this connection to
    // the watchdog, which now also tracks buffer progress, without seeking it.
    if (lastBufferProgressAt != null &&
        _mpvStallAutoRecoveryEnabled &&
        DateTime.now().difference(lastBufferProgressAt) <=
            _kRuntimeMpvErrorConfirmWindow) {
      return _MpvRuntimeRecoveryResult.buffering;
    }
    return _MpvRuntimeRecoveryResult.failed;
  }

  Future<void> _attemptSoftRuntimeMpvErrorRecovery(
    Player player, {
    required Duration position,
  }) async {
    try {
      await _playAndSeekWithTimeout(player, position);
    } catch (error, stackTrace) {
      _traceWindowsMpv(
        'windows-mpv.player.error.recover-soft-failed',
        fields: {'positionMs': position.inMilliseconds},
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _attemptRuntimeMpvReinitializeRecovery(
    Player player,
    PlaybackTarget target, {
    required String message,
  }) async {
    if (_player != player) {
      return;
    }
    _traceWindowsMpv(
      'windows-mpv.player.error.reinitialize',
      fields: {
        'message': message,
        'positionMs': player.state.position.inMilliseconds,
      },
    );
    _latestPosition = player.state.position;
    if (player.state.duration > Duration.zero) {
      _latestDuration = player.state.duration;
    }
    final detachedPlayer =
        _detachActivePlayerState(clearStallRecoveryFlag: false);
    final generation = _startupGeneration;
    if (mounted) {
      setState(() {
        _error = null;
      });
    } else {
      _error = null;
    }
    await _shutdownDetachedPlayer(
      detachedPlayer,
      reason: 'mpv-runtime-error-recover',
      persistProgress: true,
      teardownPlatformState: true,
    );
    if (!_isCurrentStartup(generation)) {
      return;
    }
    await _initialize(
      initialTarget: _buildRuntimeMpvRecoveryTarget(target),
    );
    if (_error == null) {
      _markRuntimeMpvErrorRecovered();
    }
  }

  PlaybackTarget _buildRuntimeMpvRecoveryTarget(PlaybackTarget target) {
    return buildMpvRecoveryTarget(target);
  }

  void _markRuntimeMpvErrorRecovered() {
    _lastRuntimeMpvErrorAt = null;
    _runtimeMpvErrorBurstCount = 0;
    _runtimeMpvErrorRecoveryAttempts = 0;
  }

  MpvStallWatchdogConfig _resolveMpvStallWatchdogConfig(
    PlaybackTarget target, {
    required bool startupPhase,
  }) {
    if (resolveMpvHttpReconnectOptions(target) != null) {
      return MpvStallWatchdogConfig(
        minBufferingBeforeCheck: const Duration(seconds: 3),
        softRecoverAfter: const Duration(seconds: 15),
        hardRecoverAfter: const Duration(seconds: 30),
        requirePlaying: !startupPhase,
      );
    }
    final quarkPlayback = isLikelyQuarkPlaybackTarget(target);
    final remotePlayback = _isLikelyRemotePlaybackTarget(target);
    if (quarkPlayback) {
      return MpvStallWatchdogConfig(
        minBufferingBeforeCheck: const Duration(seconds: 3),
        softRecoverAfter: const Duration(seconds: 8),
        hardRecoverAfter: const Duration(seconds: 16),
        requirePlaying: !startupPhase,
      );
    }
    if (remotePlayback) {
      return MpvStallWatchdogConfig(
        minBufferingBeforeCheck: const Duration(seconds: 3),
        softRecoverAfter: const Duration(seconds: 7),
        hardRecoverAfter: const Duration(seconds: 14),
        requirePlaying: !startupPhase,
      );
    }
    return MpvStallWatchdogConfig(
      minBufferingBeforeCheck: startupPhase
          ? const Duration(seconds: 2)
          : const Duration(seconds: 3),
      softRecoverAfter: startupPhase
          ? const Duration(seconds: 5)
          : const Duration(seconds: 6),
      hardRecoverAfter: startupPhase
          ? const Duration(seconds: 10)
          : const Duration(seconds: 12),
      requirePlaying: !startupPhase,
    );
  }

  Future<void> _playAndSeekWithTimeout(
    Player player,
    Duration position,
  ) async {
    await player.play().timeout(const Duration(seconds: 2));
    await player.seek(position).timeout(const Duration(seconds: 2));
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
    await _playAndSeekWithTimeout(player, decision.position);
  }

  Future<void> _attemptSoftMpvStallRecovery(
    Player player,
    MpvStallDecision decision, {
    required String stageLabel,
  }) async {
    try {
      await _performSoftMpvStallRecovery(
        player,
        decision,
        stageLabel: stageLabel,
      );
    } catch (error, stackTrace) {
      _traceWindowsMpv(
        'windows-mpv.stall.recover-soft-failed',
        fields: {
          'stage': stageLabel,
          'positionMs': decision.position.inMilliseconds,
          'bufferingForMs': decision.bufferingFor.inMilliseconds,
          'stagnantForMs': decision.stagnantFor.inMilliseconds,
        },
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _startMpvStallWatchdog(Player player, PlaybackTarget target) {
    _stopMpvStallWatchdog();
    if (!_mpvStallAutoRecoveryEnabled) {
      return;
    }
    _mpvStallWatchdog = MpvStallWatchdog(
      config: _resolveMpvStallWatchdogConfig(target, startupPhase: false),
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
        _runtimeMpvErrorRecoveryInProgress ||
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
      _mpvPerformanceTracker?.recordRecovery();
      try {
        await _attemptSoftMpvStallRecovery(
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
    if (_isBandwidthBelowSourceBitrate(target)) {
      _showMessage('当前网速低于片源码率，继续等待缓冲');
      return;
    }
    _mpvStallRecoveryInProgress = true;
    _mpvPerformanceTracker?.recordRecovery();
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
      final generation = _startupGeneration;
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
      if (!_isCurrentStartup(generation)) {
        return;
      }
      await _initialize(initialTarget: _buildRuntimeMpvRecoveryTarget(target));
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
}
