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
    final startupTarget = initialTarget ?? widget.target;
    await ActivePlaybackCleanupCoordinator.cleanupAll(
      reason: 'player-page-initialize',
      exceptToken: _activePlaybackCleanupToken,
    );
    await _waitForPendingPlayerShutdowns(reason: 'player-page-initialize');
    _traceWindowsMpv(
      'windows-mpv.initialize.begin',
      fields: {
        'canPlay': startupTarget.canPlay,
        'needsResolution': startupTarget.needsResolution,
        'decodeMode': _playbackDecodeMode.name,
        'qualityPresetRequested': _playbackMpvQualityPreset.name,
        'qualityAutoDowngrade': _autoDowngradePlaybackQualityEnabled,
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
      final outcome = await coordinator.start(
        initialTarget: startupTarget,
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
      final episodeQueue = await _preparePlaybackEpisodeQueue(
        startupTarget,
        currentTarget: resolvedTarget,
      );
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
        if (_isTelevisionPlaybackDevice) {
          _updateTvPlaybackState(playing: playing);
        }
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
            showFeedback: false,
          ),
        );
      });
      _playerDurationSubscription = playback.player.stream.duration.listen((
        duration,
      ) {
        _latestDuration = duration;
        if (_isTelevisionPlaybackDevice) {
          _updateTvPlaybackState(duration: duration);
        }
        unawaited(_syncPlaybackSystemSession());
      });
      _playerPositionSubscription = playback.player.stream.position.listen((
        position,
      ) {
        _latestPosition = position;
        if (_isTelevisionPlaybackDevice) {
          _updateTvPlaybackState(position: position);
        }
        _maybeApplyAutoSkip(playback.player, position);
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
        _lastRuntimeMpvErrorAt = null;
        _runtimeMpvErrorBurstCount = 0;
        _runtimeMpvErrorRecoveryAttempts = 0;
        _runtimeMpvErrorRecoveryInProgress = false;
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
      _adaptiveTopChromeController.setVisible(true);
      setState(() {
        _error = _buildPlaybackErrorMessage(error);
      });
      unawaited(_syncBackgroundPlayback(enabled: false));
      unawaited(_teardownPlaybackSystemSession());
    }
  }

  Future<
      ({
        PlaybackRemotePreflightResult? preflight,
        _StartupProbeResult probe
      })> _prepareStartupDiagnostics(PlaybackTarget target) async {
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
    final startupProbeMegabitsPerSecond =
        probe.estimatedSpeedBytesPerSecond == null
            ? null
            : (probe.estimatedSpeedBytesPerSecond! * 8) / 1000000;
    final lowStartupSpeed = startupProbeMegabitsPerSecond != null &&
        startupProbeMegabitsPerSecond > 0 &&
        startupProbeMegabitsPerSecond < 16;
    final criticalStartupSpeed = startupProbeMegabitsPerSecond != null &&
        startupProbeMegabitsPerSecond > 0 &&
        startupProbeMegabitsPerSecond < 8;
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
    if (preflight != null && !preflight.supportsByteRange) {
      resolved += 8;
    }
    if (remotePlayback && isLikelyQuarkPlaybackTarget(target)) {
      resolved += 10;
    }
    return resolved.clamp(1, 120);
  }

  String _buildRemotePreflightFailureMessage(
    PlaybackRemotePreflightResult result,
  ) {
    return switch (result.failureReason) {
      PlaybackRemotePreflightFailureReason.emptyUrl => '播放地址为空',
      PlaybackRemotePreflightFailureReason.unsupportedScheme =>
        '当前播放地址协议暂不支持预检',
      PlaybackRemotePreflightFailureReason.timeout => '播放链接预检超时，远端响应过慢',
      PlaybackRemotePreflightFailureReason.unauthorized =>
        '播放链接鉴权失败，请重新登录或刷新授权',
      PlaybackRemotePreflightFailureReason.forbidden =>
        '播放链接已被拒绝，请检查会员/VIP 或权限状态',
      PlaybackRemotePreflightFailureReason.notFound => '播放链接已失效或文件不存在',
      PlaybackRemotePreflightFailureReason.linkExpired => '播放链接已过期，请重新获取播放地址',
      PlaybackRemotePreflightFailureReason.serverError => '远端服务暂时不可用，请稍后重试',
      PlaybackRemotePreflightFailureReason.networkError =>
        '播放链接预检失败，请检查网络或远端连接',
      PlaybackRemotePreflightFailureReason.none => '远程流预检失败',
    };
  }
}
