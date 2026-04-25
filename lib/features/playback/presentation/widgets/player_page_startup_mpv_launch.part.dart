// ignore_for_file: invalid_use_of_protected_member

part of '../player_page.dart';

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
    _traceQuarkPlaybackStartup(
      'quark.launch.native.begin',
      target: target,
      fields: {
        'streamUrl': target.streamUrl,
        'decodeMode': _playbackDecodeMode.name,
      },
    );
    final result = await _launchNativePlaybackTarget(target);
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

  Future<bool> _tryLaunchWithPerformanceFallback(
    PlaybackTarget target,
  ) async {
    _traceQuarkPlaybackStartup(
      'quark.launch.fallback.begin',
      target: target,
      fields: {'decodeMode': _playbackDecodeMode.name},
    );
    final nativeResult = await _launchNativePlaybackTarget(target);
    _traceQuarkPlaybackStartup(
      'quark.launch.fallback.native-result',
      target: target,
      fields: {
        'launched': nativeResult.launched,
        'message': nativeResult.message,
      },
    );
    if (nativeResult.launched) {
      _closePlayerPageAfterExternalLaunch();
      return true;
    }

    final systemResult = await _launchSystemPlaybackTarget(target);
    _traceQuarkPlaybackStartup(
      'quark.launch.fallback.system-result',
      target: target,
      fields: {
        'launched': systemResult.launched,
        'message': systemResult.message,
      },
    );
    if (!systemResult.launched) {
      return false;
    }
    _closePlayerPageAfterExternalLaunch();
    return true;
  }

  Future<NativePlaybackLaunchResult> _launchNativePlaybackTarget(
    PlaybackTarget target,
  ) async {
    final nativeEpisodeQueue = await _resolveNativePlayableEpisodeQueue();
    return _providerContainer.read(nativePlaybackLauncherProvider).launch(
          target,
          decodeMode: _playbackDecodeMode,
          episodeQueue: nativeEpisodeQueue,
        );
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

  Future<PlaybackEpisodeQueue?> _resolveNativePlayableEpisodeQueue() async {
    final queue = _episodeQueue;
    final resolvedTarget = _resolvedTarget;
    if (queue == null || resolvedTarget == null || !queue.hasCurrent) {
      return null;
    }

    final targetResolver = PlaybackTargetResolver(read: _providerContainer.read);
    final resolvedEntries = <PlaybackEpisodeQueueEntry>[];
    for (var index = queue.currentIndex; index < queue.entries.length; index++) {
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

  Future<bool> _movePlaybackQueue({
    required bool forward,
    required String reason,
    required bool showFeedback,
  }) async {
    if (_episodeQueueAdvanceInProgress) {
      return false;
    }
    final queue = _episodeQueue;
    final player = _player;
    if (queue == null || player == null || !queue.hasCurrent) {
      return false;
    }
    final nextQueue = forward ? queue.moveToNext() : queue.moveToPrevious();
    if (identical(nextQueue, queue) || !nextQueue.hasCurrent) {
      return false;
    }

    _episodeQueueAdvanceInProgress = true;
    try {
      final resolvedDuration = player.state.duration;
      final resolvedPosition = player.state.position;
      if (forward && resolvedDuration > Duration.zero) {
        _latestDuration = resolvedDuration;
        _latestPosition = resolvedDuration;
      } else {
        _latestDuration =
            resolvedDuration > Duration.zero ? resolvedDuration : _latestDuration;
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

      setState(() {
        _episodeQueue = nextQueue;
        _error = null;
      });
      await _initialize(initialTarget: nextQueue.currentEntry!.target);
      if (mounted && showFeedback) {
        _showMessage(forward ? '已切到下一集' : '已切到上一集');
      }
      return true;
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _buildPlaybackErrorMessage(error);
        });
      }
      return false;
    } finally {
      _episodeQueueAdvanceInProgress = false;
    }
  }
}
