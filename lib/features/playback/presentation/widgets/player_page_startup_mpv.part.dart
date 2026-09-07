// ignore_for_file: invalid_use_of_protected_member

part of '../player_page.dart';

const Duration _kRuntimeMpvErrorConfirmWindow = Duration(seconds: 3);
const Duration _kRuntimeMpvErrorBurstWindow = Duration(seconds: 10);
const int _kMaxTransientRuntimeMpvErrorBurst = 2;
const int _kMaxRuntimeMpvErrorRecoveryAttempts = 2;

extension _PlayerPageStateStartupMpv on _PlayerPageState {
  Future<void> _initialize({
    PlaybackTarget? initialTarget,
  }) async {
    final generation = ++_startupGeneration;
    _startupScope.cancel();
    final scope = _startupScope = MpvStartupScope();
    _playbackStartupStartedAt = DateTime.now();
    _playbackTargetResolutionMs = 0;
    _playbackStartPositionApplied = false;
    _pendingIntroStartValidation = Duration.zero;
    _resetPreparedNextEpisode();
    final startupTarget = initialTarget ?? widget.target;
    await ActivePlaybackCleanupCoordinator.cleanupAll(
      reason: 'player-page-initialize',
      exceptToken: _activePlaybackCleanupToken,
    );
    await _waitForPendingPlayerShutdowns(reason: 'player-page-initialize');
    if (!_isCurrentStartup(generation)) {
      return;
    }
    _traceWindowsMpv(
      'windows-mpv.initialize.begin',
      fields: {
        'canPlay': startupTarget.canPlay,
        'needsResolution': startupTarget.needsResolution,
        'decodeMode': _playbackDecodeMode.name,
        'qualityPresetRequested': _playbackMpvQualityPreset.name,
        'leanUi': _leanPlaybackUiEnabled,
        'aggressiveTuning': _aggressivePlaybackTuningEnabled,
      },
    );
    if (!startupTarget.canPlay) {
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
      final outcome = await scope.wait(coordinator.start(
        initialTarget: startupTarget,
        isTelevision: _isTelevisionPlaybackDevice,
        isWeb: kIsWeb,
      ));
      if (!_isCurrentStartup(generation)) {
        return;
      }
      _playbackTargetResolutionMs =
          DateTime.now().difference(_playbackStartupStartedAt!).inMilliseconds;
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
      // An episode switch or a recovery restart already owns the right queue,
      // and only the launch routes need one before the executor runs, so the
      // embedded route resolves it in the background instead of blocking.
      final existingQueue = _episodeQueue;
      final reusableQueue = existingQueue != null && existingQueue.hasCurrent
          ? existingQueue.replaceCurrentTarget(resolvedTarget)
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
      if (!_isCurrentStartup(generation)) {
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
      _traceQuarkPlaybackStartup(
        'quark.startup.executor-result',
        target: resolvedTarget,
        fields: {
          'routeAction': outcome.routeAction.name,
          'shouldOpenEmbedded': shouldOpen,
        },
      );
      if (!shouldOpen || !_isCurrentStartup(generation)) {
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
      final startPosition = _resolvePlaybackStartPosition(
        target: resolvedTarget,
        resumeEntry: resumeEntry,
        skipPreference: skipPreference,
      );
      await _resolveAndroidMemoryClassIfNeeded();
      if (!_isCurrentStartup(generation)) {
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

      if (!_isCurrentStartup(generation)) {
        await playback.errorSubscription.cancel();
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
      _playerCompletedSubscription = playback.player.stream.completed.listen((
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
      _playerDurationSubscription = playback.player.stream.duration.listen((
        duration,
      ) {
        _latestDuration = duration;
        _validatePendingIntroStartPosition(playback.player, duration);
        if (_isTelevisionPlaybackDevice && _shouldUpdatePlaybackVisualState) {
          _updateTvPlaybackState(duration: duration);
        }
        unawaited(_syncPlaybackSystemSession());
      });
      _playerPositionSubscription = playback.player.stream.position.listen((
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
      _bindWindowsMpvTraceStreams(playback.player);
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
      // The player already opened at the start position, so there is nothing
      // to seek and nothing to re-confirm here; the stall watchdog started
      // below owns everything after the open.
      _finalizePlaybackStartPosition(playback.player, startPosition);
      if (!_isCurrentStartup(generation) || _player != playback.player) {
        return;
      }
      setState(() {
        _isReady = true;
        _lastRuntimeMpvErrorAt = null;
        _runtimeMpvErrorBurstCount = 0;
        _runtimeMpvErrorRecoveryAttempts = 0;
        _runtimeMpvErrorRecoveryInProgress = false;
      });
      _startMpvStallWatchdog(playback.player, resolvedTarget);
      _startMpvPerformanceSampling(playback.player, resolvedTarget);
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
      if (!_playbackPageInForeground) {
        unawaited(_setIosBackgroundAudioOnly(true));
      }
      unawaited(_syncPlaybackSystemSession(force: true));
    } catch (error, stackTrace) {
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
      if (!_isCurrentStartup(generation)) {
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
    return resolved.clamp(1, 120);
  }
}
