// ignore_for_file: invalid_use_of_protected_member

part of '../player_page.dart';

const _nativeSmartStrmProbeOptions = PlaybackRemotePreflightOptions(
  requestTimeout: Duration(milliseconds: 1200),
  streamSampleTimeout: Duration(milliseconds: 300),
  rangeProbeBytes: 64,
  readSampleBytes: 64,
);

extension _PlayerPageStateStartupMpvLaunch on _PlayerPageState {
  Future<void> _launchWithSystemPlayer(PlaybackTarget target) async {
    _traceQuarkPlaybackStartup(
      'quark.launch.system.begin',
      target: target,
      fields: {'streamUrl': target.streamUrl},
    );
    final result = await _launchSystemPlaybackTarget(target);
    _traceQuarkPlaybackStartup(
      'quark.launch.system.result',
      target: target,
      fields: {
        'launched': result.launched,
        'message': result.message,
      },
    );
    _ensureExternalLaunchSucceeded(
      launched: result.launched,
      message: result.message,
      fallbackMessage: '外部系统播放器启动失败',
    );
    _closePlayerPageAfterExternalLaunch();
  }

  Future<void> _launchWithNativeContainer(PlaybackTarget target) async {
    final nativeLaunchStartedAt = DateTime.now();
    _traceQuarkPlaybackStartup(
      'quark.launch.native.begin',
      target: target,
      fields: {
        'streamUrl': target.streamUrl,
        'decodeMode': _playbackDecodeMode.name,
        'audioOutputMode': _playbackSettings.nativeAudioOutputMode.name,
      },
    );
    final result = await _launchNativePlaybackTarget(target);
    appLogInfo(
      'playback.performance',
      'Native playback launch completed',
      fields: <String, Object?>{
        'engine': 'exo',
        'targetResolutionMs': _playbackTargetResolutionMs,
        'nativeLaunchMs':
            DateTime.now().difference(nativeLaunchStartedAt).inMilliseconds,
        'startupToFirstFrameMs': _playbackStartupStartedAt == null
            ? 0
            : DateTime.now()
                .difference(_playbackStartupStartedAt!)
                .inMilliseconds,
        'launched': result.launched,
      },
    );
    _traceQuarkPlaybackStartup(
      'quark.launch.native.result',
      target: target,
      fields: {
        'launched': result.launched,
        'message': result.message,
      },
    );
    _ensureExternalLaunchSucceeded(
      launched: result.launched,
      message: result.message,
      fallbackMessage: '原生播放器启动失败',
    );
    _closePlayerPageAfterExternalLaunch();
  }

  Future<NativePlaybackLaunchResult> _launchNativePlaybackTarget(
    PlaybackTarget target,
  ) async {
    final mediaMimeType = await _resolveNativeLaunchMimeType(target);
    final launcher = _providerContainer.read(nativePlaybackLauncherProvider);
    final queueSnapshot = _episodeQueue;
    final resolvedTargetSnapshot = _resolvedTarget;
    final nativeEpisodeQueue = defaultTargetPlatform == TargetPlatform.android
        ? buildDeferredNativeEpisodeQueue(
            queue: queueSnapshot,
            resolvedTarget: resolvedTargetSnapshot,
          )
        : await _resolveNativePlayableEpisodeQueue(
            queue: queueSnapshot,
            resolvedTarget: resolvedTargetSnapshot,
          );
    return launcher.launch(
      target,
      decodeMode: _playbackDecodeMode,
      audioOutputMode: _playbackSettings.nativeAudioOutputMode,
      subtitleScale: _playbackSettings.playbackSubtitleScale,
      primarySubtitlePosition:
          _playbackSettings.playbackPrimarySubtitlePosition,
      secondarySubtitlePosition:
          _playbackSettings.playbackSecondarySubtitlePosition,
      secondarySubtitleScale: _playbackSettings.playbackSecondarySubtitleScale,
      backgroundPlaybackEnabled: _backgroundPlaybackEnabled,
      subtitlePreference: _playbackSettings.playbackSubtitlePreference,
      defaultSubtitle: _playbackSettings.playbackDefaultSubtitle,
      dualSubtitlePrimaryLanguage:
          _playbackSettings.playbackDualSubtitlePrimaryLanguage,
      dualSubtitleSecondaryLanguage:
          _playbackSettings.playbackDualSubtitleSecondaryLanguage,
      episodeQueue: nativeEpisodeQueue,
      mediaMimeType: mediaMimeType ?? '',
      episodeResolver: defaultTargetPlatform == TargetPlatform.android
          ? _buildNativeEpisodeResolver()
          : null,
    );
  }

  NativePlaybackEpisodeResolver _buildNativeEpisodeResolver() {
    final providerContainer = _providerContainer;
    final remotePreflight = _playbackRemotePreflight;
    return (target) async {
      final resolved = await PlaybackTargetResolver(
        read: providerContainer.read,
      ).resolve(target);
      if (resolved.streamUrl.trim().isEmpty || resolved.needsResolution) {
        throw StateError('没有取得可播放地址');
      }
      String mediaMimeType = '';
      if (shouldProbeNativeSmartStrmMediaType(resolved)) {
        final preflight = await remotePreflight.probe(
          resolved,
          options: _nativeSmartStrmProbeOptions,
        );
        mediaMimeType = resolveNativePlaybackMimeType(preflight) ?? '';
      }
      return NativeResolvedPlaybackTarget(
        target: resolved,
        mediaMimeType: mediaMimeType,
      );
    };
  }

  Future<String?> _resolveNativeLaunchMimeType(PlaybackTarget target) async {
    if (defaultTargetPlatform != TargetPlatform.android ||
        !shouldProbeNativeSmartStrmMediaType(target)) {
      return null;
    }
    final preflight = await _playbackRemotePreflight.probe(
      target,
      options: _nativeSmartStrmProbeOptions,
    );
    final resolvedMimeType = resolveNativePlaybackMimeType(preflight);
    playbackTrace(
      'native.smartstrm-media-probe',
      fields: <String, Object?>{
        'statusCode': preflight.statusCode,
        'contentType': preflight.contentType ?? '',
        'finalPath': preflight.finalUri?.path ?? '',
        'durationMs': preflight.duration.inMilliseconds,
        'sampledBytes': preflight.sampledBytes,
        'resolvedMimeType': resolvedMimeType ?? '',
        'failureReason': preflight.failureReason.name,
      },
    );
    return resolvedMimeType;
  }

  Future<SystemPlaybackLaunchResult> _launchSystemPlaybackTarget(
    PlaybackTarget target,
  ) {
    return _providerContainer.read(systemPlaybackLauncherProvider).launch(
          target,
        );
  }

  void _ensureExternalLaunchSucceeded({
    required bool launched,
    required String message,
    required String fallbackMessage,
  }) {
    if (launched) {
      return;
    }
    throw _PlayerOpenException(
      message.isEmpty ? fallbackMessage : message,
    );
  }

  void _closePlayerPageAfterExternalLaunch() {
    if (!mounted) {
      return;
    }
    context.pop();
  }

  Future<PlaybackEpisodeQueue?> _preparePlaybackEpisodeQueue(
    PlaybackTarget queueSeedTarget, {
    required PlaybackTarget currentTarget,
  }) async {
    try {
      final queue = await PlaybackEpisodeQueueResolver(
        read: _providerContainer.read,
      ).resolve(queueSeedTarget);
      return queue?.replaceCurrentTarget(currentTarget);
    } catch (_) {
      return null;
    }
  }

  /// Resolves the episode queue off the startup path: the embedded player does
  /// not need it to start, only the episode controls and the next-episode
  /// prefetch do.
  Future<void> _resolveEpisodeQueueInBackground(
    PlaybackTarget queueSeedTarget, {
    required PlaybackTarget currentTarget,
  }) async {
    final queue = await _preparePlaybackEpisodeQueue(
      queueSeedTarget,
      currentTarget: currentTarget,
    );
    if (queue == null ||
        !mounted ||
        _episodeQueue != null ||
        !identical(_resolvedTarget, currentTarget)) {
      return;
    }
    setState(() {
      _episodeQueue = queue;
    });
    unawaited(_syncPlaybackSystemSession(force: true));
  }

  Future<PlaybackEpisodeQueue?> _resolveNativePlayableEpisodeQueue({
    PlaybackEpisodeQueue? queue,
    PlaybackTarget? resolvedTarget,
  }) async {
    if (queue == null || resolvedTarget == null || !queue.hasCurrent) {
      return null;
    }

    final targetResolver =
        PlaybackTargetResolver(read: _providerContainer.read);
    final resolvedEntries = <PlaybackEpisodeQueueEntry>[];
    for (var index = queue.currentIndex;
        index < queue.entries.length;
        index++) {
      final entry = queue.entries[index];
      PlaybackTarget resolvedEntryTarget;
      if (index == queue.currentIndex) {
        resolvedEntryTarget = resolvedTarget;
      } else {
        try {
          resolvedEntryTarget = await targetResolver.resolve(entry.target);
        } catch (_) {
          break;
        }
      }
      resolvedEntries.add(entry.copyWith(target: resolvedEntryTarget));
    }
    if (resolvedEntries.length <= 1) {
      return null;
    }
    return PlaybackEpisodeQueue(entries: resolvedEntries);
  }

  bool _isAutomaticPlaybackQueueReason(String reason) =>
      reason == 'outro' || reason == 'playback-completed';

  Future<bool> _movePlaybackQueue({
    required bool forward,
    required String reason,
  }) async {
    final queue = _episodeQueue;
    if (queue == null || !queue.hasCurrent) {
      return false;
    }
    final nextIndex = forward ? queue.currentIndex + 1 : queue.currentIndex - 1;
    return _switchPlaybackQueueIndex(
      index: nextIndex,
      reason: reason,
      markCurrentCompleted: _isAutomaticPlaybackQueueReason(reason),
    );
  }

  Future<bool> _switchPlaybackQueueIndex({
    required int index,
    required String reason,
    bool markCurrentCompleted = false,
  }) async {
    if (_episodeQueueAdvanceInProgress) {
      _showMessage('正在解析剧集，请稍候');
      return false;
    }
    final queue = _episodeQueue;
    final player = _player;
    if (queue == null || player == null || !queue.hasCurrent) {
      return false;
    }
    if (index < 0 ||
        index >= queue.entries.length ||
        index == queue.currentIndex) {
      return false;
    }
    final requestedEntry = queue.entries[index];
    final automaticNext = _isAutomaticPlaybackQueueReason(reason);

    _episodeQueueAdvanceInProgress = true;
    try {
      final preparedTarget = _takePreparedEpisodeTarget(
        _buildPreparedEpisodeSignature(index, requestedEntry),
      );
      _nextEpisodePrepareAttempt = null;
      if (preparedTarget == null && requestedEntry.target.needsResolution) {
        _showMessage(
          '正在解析 ${formatPlaybackEpisodePickerLabel(requestedEntry, index)}',
        );
      }
      final resolvedTarget = preparedTarget ??
          await PlaybackTargetResolver(
            read: _providerContainer.read,
          ).resolve(requestedEntry.target).timeout(
                kPlaybackEpisodeResolveTimeout,
                onTimeout: () => throw TimeoutException('解析剧集超时，请手动重试'),
              );
      if (resolvedTarget.streamUrl.trim().isEmpty ||
          resolvedTarget.needsResolution) {
        throw StateError('没有取得可播放地址');
      }
      if (!mounted ||
          !identical(_player, player) ||
          !identical(_episodeQueue, queue)) {
        return false;
      }

      final resolvedDuration = player.state.duration;
      final resolvedPosition = player.state.position;
      if (markCurrentCompleted && resolvedDuration > Duration.zero) {
        _latestDuration = resolvedDuration;
        _latestPosition = resolvedDuration;
      } else {
        _latestDuration = resolvedDuration > Duration.zero
            ? resolvedDuration
            : _latestDuration;
        _latestPosition = resolvedPosition;
      }
      await _persistPlaybackProgress(force: true);

      final detachedPlayer = _detachActivePlayerState();
      await _shutdownDetachedPlayer(
        detachedPlayer,
        reason: 'player-page-$reason',
        persistProgress: false,
        teardownPlatformState: false,
      );

      if (!mounted) {
        return false;
      }

      final nextQueue = queue
          .copyWith(currentIndex: index)
          .replaceCurrentTarget(resolvedTarget);
      setState(() {
        _episodeQueue = nextQueue;
        _error = null;
        _introSkipApplied = false;
        _outroSkipApplied = false;
        _playbackStartPositionApplied = false;
        _latestPosition = Duration.zero;
        _latestDuration = Duration.zero;
        _lastProgressPersistedAt = null;
        _lastPersistedPosition = Duration.zero;
      });
      _nextEpisodeIsAutomatic = automaticNext;
      await _initialize(initialTarget: resolvedTarget);
      if (preparedTarget != null && mounted && !_isReady && _error != null) {
        await _retryEpisodeSwitchWithFreshAddress(
          entry: requestedEntry,
          index: index,
          automaticNext: automaticNext,
        );
      }
      if (mounted && _isReady && _isTelevisionPlaybackDevice) {
        _showTvPlaybackChrome(autoHide: false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            requestTvFocus(_tvPlayPauseControlFocusNode);
          }
        });
      }
      return mounted && _isReady;
    } catch (error) {
      if (mounted && identical(_player, player)) {
        _showMessage('解析剧集失败：${_buildPlaybackErrorMessage(error)}');
      }
      return false;
    } finally {
      _episodeQueueAdvanceInProgress = false;
    }
  }

  /// A prepared address can expire between the prefetch and the switch, so a
  /// permanent open failure on one is worth a single fresh resolution.
  Future<void> _retryEpisodeSwitchWithFreshAddress({
    required PlaybackEpisodeQueueEntry entry,
    required int index,
    required bool automaticNext,
  }) async {
    final error = _error;
    if (!entry.target.needsResolution ||
        error == null ||
        classifyMpvOpenFailure(error) != MpvOpenFailureKind.permanent) {
      return;
    }
    try {
      final refreshedTarget = await PlaybackTargetResolver(
        read: _providerContainer.read,
      ).resolve(entry.target).timeout(kPlaybackEpisodeResolveTimeout);
      final queue = _episodeQueue;
      if (!mounted ||
          queue == null ||
          queue.currentIndex != index ||
          refreshedTarget.streamUrl.trim().isEmpty ||
          refreshedTarget.needsResolution) {
        return;
      }
      setState(() {
        _episodeQueue = queue.replaceCurrentTarget(refreshedTarget);
        _error = null;
      });
      _nextEpisodeIsAutomatic = automaticNext;
      await _initialize(initialTarget: refreshedTarget);
    } catch (_) {
      // Keep the original playback error on screen.
    }
  }

  Future<void> _openPlaybackEpisodePicker({
    required bool isTelevision,
  }) async {
    final queue = _episodeQueue;
    if (queue == null || queue.entries.length <= 1 || !queue.hasCurrent) {
      return;
    }
    final selectedIndex = await showPlaybackEpisodePickerDialog(
      context: context,
      queue: queue,
      isTelevision: isTelevision,
    );
    final activeQueue = _episodeQueue;
    if (!mounted ||
        selectedIndex == null ||
        activeQueue == null ||
        selectedIndex < 0 ||
        selectedIndex >= activeQueue.entries.length ||
        selectedIndex == activeQueue.currentIndex) {
      return;
    }
    await _switchPlaybackQueueIndex(
      index: selectedIndex,
      reason: 'episode-picker',
    );
  }
}
