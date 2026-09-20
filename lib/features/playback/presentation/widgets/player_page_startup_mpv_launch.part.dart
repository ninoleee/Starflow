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
    final result = await _launchSystemPlaybackTarget(target);
    _ensureExternalLaunchSucceeded(
      launched: result.launched,
      message: result.message,
      fallbackMessage: '外部系统播放器启动失败',
    );
    _closePlayerPageAfterExternalLaunch();
  }

  Future<void> _launchWithNativeContainer(PlaybackTarget target) async {
    final nativeLaunchStartedAt = DateTime.now();
    final result = await _launchNativePlaybackTarget(target);
    appLogInfo(
      'playback.performance',
      'Native playback launch completed',
      fields: <String, Object?>{
        'engine':
            defaultTargetPlatform == TargetPlatform.iOS ? 'avplayer' : 'exo',
        'targetResolutionMs': _playbackTargetResolutionMs,
        'nativeLaunchMs':
            DateTime.now().difference(nativeLaunchStartedAt).inMilliseconds,
        (defaultTargetPlatform == TargetPlatform.iOS
                ? 'startupToContainerPresentedMs'
                : 'startupToFirstFrameMs'):
            _playbackStartupStartedAt == null
                ? 0
                : DateTime.now()
                    .difference(_playbackStartupStartedAt!)
                    .inMilliseconds,
        'launched': result.launched,
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
    final nativeEpisodeQueue = buildDeferredNativeEpisodeQueue(
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
      episodeResolver: _buildNativeEpisodeResolver(),
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
      String mediaMimeType =
          resolved.isFntvTranscoding ? kNativePlaybackHlsMimeType : '';
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
    if (target.isFntvTranscoding) return kNativePlaybackHlsMimeType;
    if (defaultTargetPlatform != TargetPlatform.android ||
        !shouldProbeNativeSmartStrmMediaType(target)) {
      return null;
    }
    final preflight = await _playbackRemotePreflight.probe(
      target,
      options: _nativeSmartStrmProbeOptions,
    );
    final resolvedMimeType = resolveNativePlaybackMimeType(preflight);
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

  bool _isAutomaticPlaybackQueueReason(String reason) =>
      reason == 'outro' || reason == 'playback-completed';

  void _cancelPendingAutomaticAdvance() {
    if (_episodeAdvanceGuard.invalidateAutomaticPending()) {
      _outroSkipApplied = false;
    }
  }

  bool _canCommitAutomaticAdvance(Player player, String reason) {
    if (_subtitleSearchActive || _skipPreferenceSaveInProgress) return false;
    if (reason == 'playback-completed') return player.state.completed;
    final preference = _seriesSkipPreference;
    final duration = player.state.duration;
    final boundary = resolvePlaybackEndBoundary(
      duration: duration,
      skipEnabled: preference?.enabled ?? false,
      outroDuration: preference?.outroDuration ?? Duration.zero,
    );
    return (player.state.playing || player.state.completed) &&
        boundary > Duration.zero &&
        boundary < duration &&
        player.state.position >= boundary;
  }

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
    PlaybackEpisodeQueue? selectedQueue,
  }) async {
    if (!_isAutomaticPlaybackQueueReason(reason)) _recoveryIntent.invalidate();
    if (_fntvSwitchInProgress) {
      _showMessage('正在解析剧集，请稍候');
      return false;
    }
    final originalQueue = _episodeQueue;
    final queue = selectedQueue ?? originalQueue;
    final player = _player;
    if (queue == null ||
        player == null ||
        originalQueue == null ||
        !originalQueue.hasCurrent) {
      return false;
    }
    if (index < 0 ||
        index >= queue.entries.length ||
        queue.entries[index].playbackItemKey ==
            originalQueue.currentEntry!.playbackItemKey) {
      return false;
    }
    final requestedEntry = queue.entries[index];
    final automaticNext = _isAutomaticPlaybackQueueReason(reason);
    if (automaticNext && !_canCommitAutomaticAdvance(player, reason)) {
      return false;
    }
    final request = _episodeAdvanceGuard.begin(
      key: _buildPreparedEpisodeSignature(index, requestedEntry),
      automatic: automaticNext,
    );
    if (request == null) {
      if (!automaticNext) _showMessage('正在打开剧集，请稍候');
      return false;
    }
    var failed = false;
    try {
      _syncEpisodePreparationContext();
      final preparationContext = _episodePreparationContext;
      if (requestedEntry.target.needsResolution) {
        _showMessage(
          '正在解析 ${formatPlaybackEpisodePickerLabel(requestedEntry, index)}',
        );
      }
      final prepared = await _episodePreparation.resolve(
        key: (
          identical(selectedQueue, originalQueue) ? null : selectedQueue,
          request.key
        ),
        resolver: () => _resolveEpisodeAddress(requestedEntry.target),
        retryFailed: !automaticNext,
      );
      final resolvedTarget = prepared.target;
      if (resolvedTarget.streamUrl.trim().isEmpty ||
          resolvedTarget.needsResolution) {
        throw StateError('没有取得可播放地址');
      }
      if (!mounted ||
          !_episodeAdvanceGuard.isCurrent(request) ||
          !identical(_player, player) ||
          !identical(_episodeQueue, originalQueue)) {
        return false;
      }
      _syncEpisodePreparationContext();
      if (_episodePreparationContext != preparationContext) return false;
      if (automaticNext && !_canCommitAutomaticAdvance(player, reason)) {
        _cancelPendingAutomaticAdvance();
        return false;
      }
      if (!_episodeAdvanceGuard.commit(request)) return false;

      final resolvedDuration = player.state.duration;
      final resolvedPosition = player.state.position;
      if (markCurrentCompleted && resolvedDuration > Duration.zero) {
        _latestDuration = resolvedDuration;
        _latestPosition = resolvedPosition;
        _completionState.markCompletedByAutoSkip();
      } else {
        _latestDuration = resolvedDuration > Duration.zero
            ? resolvedDuration
            : _latestDuration;
        _latestPosition = resolvedPosition;
      }
      final detachedPlayer = _detachActivePlayerState();
      await _shutdownDetachedPlayer(
        detachedPlayer,
        reason: 'player-page-$reason',
        persistProgress: true,
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
      await _initialize(
        initialTarget: resolvedTarget,
        targetAlreadyResolved: true,
      );
      if (prepared.wasPrepared && mounted && !_isReady && _error != null) {
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
      failed = mounted && !_isReady;
      return mounted && _isReady;
    } catch (error) {
      failed = true;
      if (mounted &&
          _episodeAdvanceGuard.isCurrent(request) &&
          identical(_player, player)) {
        _showMessage(
            '${formatPlaybackEpisodePickerLabel(requestedEntry, index)} 打开失败，仍播放当前集：${_buildPlaybackErrorMessage(error)}');
      }
      return false;
    } finally {
      _episodeAdvanceGuard.finish(request, failed: failed);
    }
  }

  /// A prepared address can expire between the prefetch and the switch, so a
  /// confirmed expired-address status is worth a single fresh resolution.
  Future<void> _retryEpisodeSwitchWithFreshAddress({
    required PlaybackEpisodeQueueEntry entry,
    required int index,
    required bool automaticNext,
  }) async {
    final error = _error;
    if (!entry.target.needsResolution ||
        error == null ||
        !isMpvPreparedAddressRefreshable(error)) {
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
      await _initialize(
        initialTarget: refreshedTarget,
        targetAlreadyResolved: true,
      );
    } catch (_) {
      // Keep the original playback error on screen.
    }
  }

  Future<void> _openPlaybackEpisodePicker({
    required bool isTelevision,
  }) async {
    final queue = _episodeQueue;
    if (queue == null || queue.entries.isEmpty || !queue.hasCurrent) {
      return;
    }
    final selection = await showPlaybackEpisodePickerDialog(
      context: context,
      queue: queue,
      isTelevision: isTelevision,
      browser: PlaybackEpisodeBrowser(
          resolver: PlaybackEpisodeQueueResolver(read: _providerContainer.read),
          target: queue.currentEntry!.target),
      loadHistory: () => _providerContainer
          .read(playbackMemoryRepositoryProvider)
          .loadSnapshot(),
    );
    final activeQueue = _episodeQueue;
    if (!mounted ||
        selection == null ||
        activeQueue == null ||
        !identical(activeQueue, queue)) {
      return;
    }
    await _switchPlaybackQueueIndex(
      index: selection.index,
      selectedQueue: identical(selection.queue, queue) ? null : selection.queue,
      reason: 'episode-picker',
    );
  }
}
