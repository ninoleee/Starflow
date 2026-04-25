// ignore_for_file: invalid_use_of_protected_member

part of '../player_page.dart';

extension _PlayerPageStateStartupMpvRecovery on _PlayerPageState {
  Future<void> _handleRuntimeMpvError(
    Player player,
    PlaybackTarget target,
    String message,
  ) async {
    if (!mounted || _player != player) {
      return;
    }
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

    final shouldEscalateImmediately = _isFatalRuntimeMpvError(message) ||
        (_runtimeMpvErrorBurstCount > 1 &&
            !_isRecoverableRuntimeMpvError(
              target: target,
              lowerMessage: lowerMessage,
            )) ||
        _runtimeMpvErrorBurstCount > _kMaxTransientRuntimeMpvErrorBurst ||
        _runtimeMpvErrorRecoveryAttempts >=
            _kMaxRuntimeMpvErrorRecoveryAttempts;
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
    _runtimeMpvErrorRecoveryAttempts += 1;
    _showMessage('连接波动，正在尝试恢复播放…');
    final baselinePosition = player.state.position;

    try {
      final recoveredWithoutAction = await _awaitRuntimeMpvErrorRecoveryWindow(
        player,
        baselinePosition: baselinePosition,
      );
      if (recoveredWithoutAction) {
        _markRuntimeMpvErrorRecovered();
        return;
      }

      await _attemptSoftRuntimeMpvErrorRecovery(
        player,
        position: baselinePosition,
      );
      final recoveredAfterSoft = await _awaitRuntimeMpvErrorRecoveryWindow(
        player,
        baselinePosition: baselinePosition,
      );
      if (recoveredAfterSoft) {
        _markRuntimeMpvErrorRecovered();
        return;
      }

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
    final lower = message.toLowerCase();
    const fatalFragments = <String>[
      'protocol not found',
      'no such file',
      'file not found',
      'permission denied',
      'invalid argument',
      'unsupported',
      'unrecognized file format',
      'no video or audio streams selected',
    ];
    return fatalFragments.any(lower.contains);
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

  Future<bool> _awaitRuntimeMpvErrorRecoveryWindow(
    Player player, {
    required Duration baselinePosition,
  }) async {
    final deadline = DateTime.now().add(_kRuntimeMpvErrorConfirmWindow);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted || _player != player) {
        return false;
      }
      final state = player.state;
      final progressed = state.position - baselinePosition >=
          const Duration(milliseconds: 800);
      final healthy = state.playing &&
          !state.buffering &&
          (progressed || _hasStrictPlaybackMetadata(player));
      if (healthy) {
        return true;
      }
    }
    return false;
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
    if (!mounted) {
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
    final baseTarget =
        widget.target.itemId.trim().isNotEmpty ? widget.target : target;
    final streamUrl = baseTarget.streamUrl.trim().toLowerCase();
    final actualAddress = baseTarget.actualAddress.trim().toLowerCase();
    final needsFreshResolution = baseTarget.sourceKind ==
            MediaSourceKind.quark ||
        baseTarget.sourceKind == MediaSourceKind.emby ||
        (baseTarget.sourceKind == MediaSourceKind.nas &&
            (streamUrl.endsWith('.strm') || actualAddress.endsWith('.strm')));
    if (!needsFreshResolution) {
      return baseTarget;
    }
    return baseTarget.copyWith(
      streamUrl: '',
      headers: const <String, String>{},
    );
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
      minBufferingBeforeCheck:
          startupPhase ? const Duration(seconds: 2) : const Duration(seconds: 3),
      softRecoverAfter:
          startupPhase ? const Duration(seconds: 5) : const Duration(seconds: 6),
      hardRecoverAfter:
          startupPhase ? const Duration(seconds: 10) : const Duration(seconds: 12),
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
}
