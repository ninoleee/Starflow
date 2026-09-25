// ignore_for_file: invalid_use_of_protected_member

part of '../player_page.dart';

const Duration _kRuntimeMpvErrorConfirmWindow = Duration(
  milliseconds: PlaybackPolicyValues.localErrorConfirmationMs,
);
const Duration _kRuntimeMpvErrorBurstWindow = Duration(seconds: 10);
const int _kMaxTransientRuntimeMpvErrorBurst = 2;
const int _kMaxRuntimeMpvErrorRecoveryAttempts =
    PlaybackPolicyValues.maxRuntimeRecoveries;

extension _PlayerPageStateStartupMpv on _PlayerPageState {
  Future<void> _initialize({
    PlaybackTarget? initialTarget,
    bool automaticRecovery = false,
    bool targetAlreadyResolved = false,
    Duration? startPositionOverride,
    int? recoveryIntent,
  }) async {
    if (!automaticRecovery) {
      _automaticRecoveryBudget.reset();
      _recoveryStartupIntent = null;
      _recoveryIntent.playback(true);
    }
    final generation = ++_startupGeneration;
    _startupScope.cancel();
    final scope = _startupScope = MpvStartupScope();
    _recoveryStartupIntent = recoveryIntent;
    bool startupIsCurrent() =>
        _isCurrentStartup(generation) &&
        (recoveryIntent == null || _recoveryIntent.allows(recoveryIntent));
    _playbackStartupStartedAt = DateTime.now();
    _playbackTargetResolutionMs = 0;
    _playbackStartPositionApplied = false;
    _pendingIntroStartValidation = Duration.zero;
    _resetPreparedNextEpisode();
    final startupTarget = initialTarget ?? widget.target;
    _completionState.startMedia(
      buildPlaybackItemKey(startupTarget),
      isRecovery: automaticRecovery || startPositionOverride != null,
    );
    await ActivePlaybackCleanupCoordinator.cleanupAll(
      reason: 'player-page-initialize',
      exceptToken: _activePlaybackCleanupToken,
    );
    await _waitForPendingPlayerShutdowns(reason: 'player-page-initialize');
    if (!startupIsCurrent()) {
      await _finishCancelledRecovery(generation, recoveryIntent);
      return;
    }
    if (!startupTarget.canPlay) {
      setState(() {
        _error = '没有可播放的流地址';
      });
      return;
    }

    PlaybackTarget? retainedStartupTarget;
    try {
      final coordinator = PlaybackStartupCoordinator(
        read: _providerContainer.read,
        targetResolver: PlaybackTargetResolver(read: _providerContainer.read),
        engineRouter: const PlaybackEngineRouter(),
        releaseSession: (target) async {
          await _fntvSessions.retain(target);
          await _fntvSessions.release(target);
        },
      );
      final outcome = await scope.wait(coordinator.start(
        initialTarget: startupTarget,
        isTelevision: _isTelevisionPlaybackDevice,
        isWeb: kIsWeb,
        targetAlreadyResolved: targetAlreadyResolved,
        checkActive: () {
          scope.checkActive();
          if (!startupIsCurrent()) throw const MpvStartupCancelled();
        },
        onTargetResolved: (target, routeAction) async {
          // Ownership precedes the cancellation check, including late results.
          if (routeAction == PlaybackStartupRouteAction.openEmbeddedMpv ||
              !startupIsCurrent()) {
            await _fntvSessions.retain(target);
            retainedStartupTarget = target;
            if (!startupIsCurrent()) {
              await _fntvSessions.release(target);
            }
          }
        },
      ));
      if (!startupIsCurrent()) {
        return;
      }
      _playbackTargetResolutionMs =
          DateTime.now().difference(_playbackStartupStartedAt!).inMilliseconds;
      final resolvedTarget = outcome.resolvedTarget;
      final startupPreparation = outcome.startupPreparation;
      final resumeEntry = startupPreparation.resumeEntry;
      final skipPreference = startupPreparation.skipPreference;
      // An episode switch or a recovery restart already owns the right queue,
      // and only the launch routes need one before the executor runs, so the
      // embedded route resolves it in the background instead of blocking.
      final existingQueue = _episodeQueue;
      final reusableQueue = existingQueue != null && existingQueue.hasCurrent
          ? existingQueue.replaceCurrentTarget(resolvedTarget,
              playbackItemKey: buildPlaybackItemKey(resolvedTarget),
              seriesKey: buildSeriesKeyForTarget(resolvedTarget))
          : null;
      final needsQueueBeforeLaunch =
          outcome.routeAction != PlaybackStartupRouteAction.openEmbeddedMpv;
      final episodeQueue = reusableQueue ??
          (needsQueueBeforeLaunch
              ? await _preparePlaybackEpisodeQueue(
                  startupTarget,
                  currentTarget: resolvedTarget,
                )
              : null);
      if (!startupIsCurrent()) {
        return;
      }
      if (mounted) {
        setState(() {
          _resolvedTarget = resolvedTarget;
          _seriesSkipPreference = skipPreference;
          _episodeQueue = episodeQueue;
        });
      }
      final executor = PlaybackStartupExecutor(
        launchSystemPlayer: _launchWithSystemPlayer,
        launchNativeContainer: _launchWithNativeContainer,
      );
      final shouldOpen = await executor.execute(
        outcome.routeAction,
        resolvedTarget,
      );
      if (!shouldOpen || !startupIsCurrent()) {
        return;
      }
      if (episodeQueue == null) {
        unawaited(
          _resolveEpisodeQueueInBackground(
            startupTarget,
            currentTarget: resolvedTarget,
          ),
        );
      }
      final startPosition = startPositionOverride == null
          ? _resolvePlaybackStartPosition(
              target: resolvedTarget,
              resumeEntry: resumeEntry,
              skipPreference: skipPreference,
            )
          : PlaybackStartPosition(
              position: startPositionOverride, isResume: true);
      await _resolveAndroidMemoryClassIfNeeded();
      if (!startupIsCurrent()) {
        return;
      }
      _beginMpvPerformanceSession(resolvedTarget);
      _adaptiveTopChromeController.setVisible(true);
      final cachedBytesPerSecond =
          _PlayerPageState._hostBandwidthCache.resolve(resolvedTarget);
      _networkEstimate = cachedBytesPerSecond != null
          ? _PlaybackNetworkEstimate.fromBytesPerSecond(cachedBytesPerSecond)
          : const _PlaybackNetworkEstimate.none();
      if (_isBandwidthBelowSourceBitrate(resolvedTarget)) {
        _showMessage('当前网速低于片源码率，可能持续缓冲');
      }
      final settings = outcome.settings;
      final timeoutSeconds = _resolvePlaybackOpenTimeoutSeconds(
        baseSeconds: settings.playbackOpenTimeoutSeconds.clamp(1, 600),
        target: resolvedTarget,
        networkEstimate: _networkEstimate,
      );
      appLogInfo(
        'playback.mpv',
        'Opening MPV directly without remote preflight',
        fields: {
          'timeoutSeconds': timeoutSeconds,
          'bandwidthCacheHit': cachedBytesPerSecond != null,
          'bufferSizeBytes': _resolveMpvBufferSizeBytes(resolvedTarget),
          'hwdec': _resolveMpvHardwareDecodeMode(),
        },
      );
      final playback = await _openEmbeddedPlayback(
        resolvedTarget,
        Duration(seconds: timeoutSeconds),
        startPosition: startPosition,
      );

      if (!startupIsCurrent()) {
        await playback.cancelSubscriptions();
        return;
      }

      final lifecycle = _mpvLifecycle;
      lifecycle.retain(playback.errorSubscription);
      lifecycle.retain(playback.logSubscription);
      await _bindMpvSubtitleRendering(playback.player);
      if (!startupIsCurrent()) return;
      lifecycle.subtitles.listen(playback.player.stream.track);
      lifecycle.subtitles.listen(playback.player.stream.tracks);
      _syncMpvSubtitleRendering(playback.player);
      lifecycle.listen(playback.player.stream.playing, (
        playing,
      ) {
        if (_isTelevisionPlaybackDevice && _shouldUpdatePlaybackVisualState) {
          _updateTvPlaybackState(playing: playing);
        }
        unawaited(_syncBackgroundPlayback(enabled: playing));
        unawaited(_syncPlaybackSystemSession(force: true));
        if (_isTelevisionPlaybackDevice && _shouldUpdatePlaybackVisualState) {
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
      lifecycle.listen(playback.player.stream.completed, (
        completed,
      ) {
        if (!completed || !mounted || _player != playback.player) {
          return;
        }
        unawaited(
          _movePlaybackQueue(
            forward: true,
            reason: 'playback-completed',
          ),
        );
      });
      lifecycle.listen(playback.player.stream.duration, (
        duration,
      ) {
        _latestDuration = duration;
        _validatePendingIntroStartPosition(playback.player, duration);
        if (_isTelevisionPlaybackDevice && _shouldUpdatePlaybackVisualState) {
          _updateTvPlaybackState(duration: duration);
        }
        unawaited(_syncPlaybackSystemSession());
      });
      lifecycle.listen(playback.player.stream.position, (
        position,
      ) {
        _latestPosition = position;
        if (_isTelevisionPlaybackDevice && _shouldUpdatePlaybackVisualState) {
          _updateTvPlaybackState(position: position);
        }
        _handlePlaybackRuntimePosition(playback.player, position);
        unawaited(_persistPlaybackProgress());
        unawaited(_syncPlaybackSystemSession());
      });
      _bindMpvBufferingStreams(playback.player);
      _attachOpeningEmbeddedPlayback(
        playback.player,
        playback.videoController,
      );
      if (_isTelevisionPlaybackDevice) {
        _updateTvPlaybackState(
          position: playback.player.state.position,
          duration: playback.player.state.duration,
          playing: playback.player.state.playing,
          bufferingPercentage: playback.player.state.bufferingPercentage,
        );
      }
      await _syncSubtitleDelayState(playback.player);
      if (!startupIsCurrent()) return;
      // The player already opened at the start position, so there is nothing
      // to seek and nothing to re-confirm here; the stall watchdog started
      // below owns everything after the open.
      _finalizePlaybackStartPosition(
        playback.player,
        playback.effectiveStartPosition,
      );
      if (!_isCurrentStartup(generation) || _player != playback.player) {
        return;
      }
      setState(() {
        _recoveryStartupIntent = null;
        _isReady = true;
        _lastRuntimeMpvErrorAt = null;
        _runtimeMpvErrorBurstCount = 0;
        _runtimeMpvErrorRecoveryAttempts = 0;
        _runtimeMpvErrorRecoveryInProgress = false;
      });
      _startMpvStallWatchdog(playback.player, resolvedTarget);
      unawaited(_prepareOptionalStartupTracks(playback.player, resolvedTarget));
      _startMpvPerformanceSampling(playback.player, resolvedTarget);
      unawaited(_syncBackgroundPlayback(enabled: true));
      unawaited(_bindPlaybackSystemSession());
      if (!_playbackPageInForeground) {
        unawaited(_setIosBackgroundAudioOnly(true));
      }
      unawaited(_syncPlaybackSystemSession(force: true));
    } catch (error, stackTrace) {
      if (_isCurrentStartup(generation) && !startupIsCurrent()) {
        return;
      }
      if (!_isCurrentStartup(generation)) {
        return;
      }
      appLogError(
        'playback.startup',
        'Playback startup failed',
        error: error,
        stackTrace: stackTrace,
      );
      _traceQuarkPlaybackStartup(
        'quark.startup.failed',
        target: _resolvedTarget ?? startupTarget,
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
      await _finishMpvPerformanceSession(
        reason: 'failed',
        player: _player,
      );
      if (!_fntvSwitchInProgress && _resolvedTarget != null) {
        await _fntvSessions.release(_resolvedTarget!);
      }
      if (!_isCurrentStartup(generation)) {
        return;
      }
      _adaptiveTopChromeController.setVisible(true);
      setState(() {
        _error = _buildPlaybackErrorMessage(error);
      });
      unawaited(_syncBackgroundPlayback(enabled: false));
      unawaited(_teardownPlaybackSystemSession());
    } finally {
      final cancelled = !startupIsCurrent();
      await _finishCancelledRecovery(generation, recoveryIntent);
      if (cancelled && retainedStartupTarget != null) {
        await _fntvSessions.release(retainedStartupTarget!);
      }
      if (_isCurrentStartup(generation)) _recoveryStartupIntent = null;
    }
  }

  int _resolvePlaybackOpenTimeoutSeconds({
    required int baseSeconds,
    required PlaybackTarget target,
    required _PlaybackNetworkEstimate networkEstimate,
  }) {
    var resolved = baseSeconds;
    final estimatedMegabitsPerSecond =
        networkEstimate.estimatedSpeedBytesPerSecond == null
            ? null
            : (networkEstimate.estimatedSpeedBytesPerSecond! * 8) / 1000000;
    final lowStartupSpeed = estimatedMegabitsPerSecond != null &&
        estimatedMegabitsPerSecond > 0 &&
        estimatedMegabitsPerSecond < 16;
    final criticalStartupSpeed = estimatedMegabitsPerSecond != null &&
        estimatedMegabitsPerSecond > 0 &&
        estimatedMegabitsPerSecond < 8;
    final remotePlayback = _isLikelyRemotePlaybackTarget(target);

    if (remotePlayback && resolved < 28) {
      resolved = 28;
    }
    if (remotePlayback && lowStartupSpeed) {
      resolved += 8;
    }
    if (remotePlayback && criticalStartupSpeed) {
      resolved += 10;
    }
    if (remotePlayback && isLikelyQuarkPlaybackTarget(target)) {
      resolved += 10;
    }
    return resolved.clamp(1, PlaybackPolicyValues.startupHardLimitMs ~/ 1000);
  }
}
