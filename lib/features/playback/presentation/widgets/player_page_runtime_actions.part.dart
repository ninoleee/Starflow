// ignore_for_file: invalid_use_of_protected_member

part of '../player_page.dart';

class _ServerSubtitleSelection {
  const _ServerSubtitleSelection(this.stream);

  final PlaybackSubtitleStream stream;
}

extension _PlayerPageStateRuntimeActions on _PlayerPageState {
  Future<void> _seekPlayerAutomatically(Player player, Duration position) {
    _cancelMpvReadAhead(player);
    return player is PlaybackInteractionPlayer
        ? player.seekAutomatically(position)
        : player.seek(position);
  }

  Future<void> _playPlayerAutomatically(Player player) {
    _setMpvPlaybackActive(player, true);
    return player is PlaybackInteractionPlayer
        ? player.playAutomatically()
        : player.play();
  }

  Player _createInteractionPlayer(PlayerConfiguration configuration) {
    late final PlaybackInteractionPlayer player;
    player = PlaybackInteractionPlayer(
      configuration: configuration,
      onUserSeek: (position) {
        if (mounted && identical(_player, player)) {
          _cancelMpvReadAhead(player);
          _recoveryIntent.invalidate();
          _syncSkipFlagsAfterUserSeek(position);
        }
      },
      onUserPlaybackIntent: (playing) {
        if (!mounted || !identical(_player, player)) return;
        _setMpvPlaybackActive(player, playing);
        _recoveryIntent.playback(playing);
        if (!playing) _cancelPendingAutomaticAdvance();
      },
    );
    return player;
  }

  Future<void> _setGuardedSubtitleTrack(
      Player player, SubtitleTrack track) async {
    if (!_startupTrackWorkIsCurrent ||
        !mounted ||
        !identical(_player, player)) {
      return;
    }
    await player.setSubtitleTrack(track);
  }

  Future<void> _applyStartupPlaybackPreferences(
    Player player,
    PlaybackTarget target,
  ) async {
    final settings = _providerContainer.read(appSettingsProvider);
    final loadedPreference = await _loadMpvSeriesSubtitlePreference(target);
    if (!_startupTrackWorkIsCurrent) return;
    _subtitleSessionPreference = loadedPreference;

    if (target.isFntvTranscoding) {
      if (target.preferredSubtitleStreamId.isEmpty) {
        await _setGuardedSubtitleTrack(player, SubtitleTrack.no());
      }
      return;
    }
    if (target.fntvTrackSelectionExplicit &&
        target.preferredSubtitleStreamId.isEmpty) {
      await _setGuardedSubtitleTrack(player, SubtitleTrack.no());
      return;
    }

    final sessionPreference = _subtitleSessionPreference;
    if (sessionPreference != null) {
      try {
        final restored = await _restoreMpvSubtitleSessionPreference(
          player,
          sessionPreference,
        );
        if (restored) {
          return;
        }
      } catch (_) {
        try {
          await _setMpvSubtitleProperty(player, 'secondary-sid', 'no');
        } catch (_) {
          // Continue with the configured automatic preference below.
        }
        _setMpvDualSubtitleSessionEnabled(false);
      }
    }

    if (settings.playbackSubtitlePreference == PlaybackSubtitlePreference.off) {
      try {
        await _setGuardedSubtitleTrack(player, SubtitleTrack.no());
      } catch (_) {
        // Ignore preference application failures to keep playback available.
      }
      return;
    }

    if (settings.playbackSubtitlePreference ==
        PlaybackSubtitlePreference.auto) {
      try {
        final defaultSubtitle = settings.playbackDefaultSubtitle;
        if (defaultSubtitle == PlaybackDefaultSubtitle.dual) {
          final restored = await _applyDefaultMpvDualSubtitleTracks(
            player,
            primaryLanguage: settings.playbackDualSubtitlePrimaryLanguage,
            secondaryLanguage: settings.playbackDualSubtitleSecondaryLanguage,
          );
          if (restored) {
            return;
          }
        }
        await _applyAutoPreferredSubtitleTrack(
          player,
          configuredLanguages: defaultSubtitle.preferredLanguages,
        );
      } catch (_) {
        // Ignore preference application failures to keep playback available.
      }
    }
  }

  Future<void> _applyGlobalMpvSubtitlePreference(
    Player player,
    PlaybackTarget target,
  ) async {
    _subtitleSessionPreference = null;
    await _persistMpvSeriesSubtitlePreference(target, null);
    await _setMpvSubtitleProperty(player, 'secondary-sid', 'no');
    _setMpvDualSubtitleSessionEnabled(false);

    final settings = _providerContainer.read(appSettingsProvider);
    if (settings.playbackSubtitlePreference == PlaybackSubtitlePreference.off) {
      await _setGuardedSubtitleTrack(player, SubtitleTrack.no());
      return;
    }
    final defaultSubtitle = settings.playbackDefaultSubtitle;
    if (defaultSubtitle == PlaybackDefaultSubtitle.dual) {
      final applied = await _applyDefaultMpvDualSubtitleTracks(
        player,
        primaryLanguage: settings.playbackDualSubtitlePrimaryLanguage,
        secondaryLanguage: settings.playbackDualSubtitleSecondaryLanguage,
      );
      if (applied) {
        return;
      }
    }
    await _applyAutoPreferredSubtitleTrack(
      player,
      configuredLanguages: defaultSubtitle.preferredLanguages,
    );
  }

  Future<void> _applyStartupServerTracks(
    Player player,
    PlaybackTarget target,
  ) async {
    try {
      final preferredAudio = target.isFntvTranscoding
          ? null
          : preferredPlaybackAudioStream(target);
      if (preferredAudio != null) {
        final tracks = await _awaitAvailableAudioTracks(player);
        if (!_startupTrackWorkIsCurrent) return;
        final audioTrack = resolvePlaybackAudioTrack(
          target: target,
          tracks: tracks,
          preferred: preferredAudio,
        );
        if (audioTrack != null && player.state.track.audio != audioTrack) {
          await player.setAudioTrack(audioTrack);
        }
      }
    } catch (error, stackTrace) {
      appLogWarning(
        'playback.tracks',
        'Startup audio selection failed',
        fields: {'audioStreams': target.audioStreams.length},
        error: error,
        stackTrace: stackTrace,
      );
    }
    try {
      if (target.isFntvTranscoding) {
        final external = target.subtitleStreams
            .where((stream) =>
                stream.isExternal &&
                stream.id == target.preferredSubtitleStreamId)
            .firstOrNull;
        if (external != null) {
          await _applyServerExternalSubtitle(player, target, external);
        }
        return;
      }
      final settings = _providerContainer.read(appSettingsProvider);
      if (target.fntvTrackSelectionExplicit &&
          target.preferredSubtitleStreamId.isEmpty) {
        return;
      }
      final preferredSubtitle = preferredPlaybackSubtitleStream(target);
      final shouldApplySubtitle = preferredSubtitle != null &&
          _subtitleSessionPreference == null &&
          settings.playbackSubtitlePreference != PlaybackSubtitlePreference.off;
      if (!shouldApplySubtitle) {
        return;
      }
      if (preferredSubtitle.isExternal) {
        await _applyServerExternalSubtitle(player, target, preferredSubtitle);
        return;
      }
      final tracks = await _awaitAvailableSubtitleTracks(player);
      if (!_startupTrackWorkIsCurrent) return;
      final subtitleTrack = resolveEmbeddedPlaybackSubtitleTrack(
        target: target,
        tracks: tracks,
        preferred: preferredSubtitle,
      );
      if (subtitleTrack != null &&
          player.state.track.subtitle != subtitleTrack) {
        await _disableMpvDualSubtitle(player);
        await _setGuardedSubtitleTrack(player, subtitleTrack);
      }
    } catch (error, stackTrace) {
      appLogWarning(
        'playback.tracks',
        'Startup subtitle selection failed',
        fields: {
          'audioStreams': target.audioStreams.length,
          'subtitleStreams': target.subtitleStreams.length,
          'sourceKind': target.sourceKind.name,
        },
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<List<AudioTrack>> _awaitAvailableAudioTracks(
    Player player, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    List<AudioTrack> current() => player.state.tracks.audio
        .where((track) =>
            track.id != 'auto' && track.id != 'no' && track.uri == false)
        .toList(growable: false);
    final available = current();
    if (available.isNotEmpty) {
      return available;
    }
    final completer = Completer<List<AudioTrack>>();
    late final StreamSubscription<Tracks> subscription;
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.complete(current());
      }
    });
    subscription = player.stream.tracks.listen(
      (tracks) {
        final resolved = tracks.audio
            .where((track) =>
                track.id != 'auto' && track.id != 'no' && track.uri == false)
            .toList(growable: false);
        if (resolved.isNotEmpty && !completer.isCompleted) {
          completer.complete(resolved);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );
    try {
      return await completer.future;
    } finally {
      timer.cancel();
      await subscription.cancel();
    }
  }

  Future<void> _applyServerExternalSubtitle(
    Player player,
    PlaybackTarget target,
    PlaybackSubtitleStream stream,
  ) async {
    if (!target.sourceKind.isMediaServer || stream.id.isEmpty) {
      return;
    }
    if (isBitmapSubtitle(image: stream.isBitmap, codec: stream.codec)) {
      _showMessage('当前飞牛字幕是位图字幕，不能作为文本字幕加载');
      return;
    }
    final generation = _startupGeneration;
    final revision = _manualTrackRevision;
    await PlaybackTrackGuard(() =>
        mounted &&
        identical(_player, player) &&
        generation == _startupGeneration &&
        revision == _manualTrackRevision).run([
      () async {
        final client = _providerContainer.read(
          mediaServerClientProvider(target.sourceKind),
        );
        final bytes = await client.downloadExternalSubtitleBytes(
          source: _sourceForTarget(target),
          subtitleId: stream.id,
        );
        if (!_startupTrackWorkIsCurrent) return;
        final content =
            await processSubtitleContent(bytes, preferredName: stream.title);
        if (!_startupTrackWorkIsCurrent || content.trim().isEmpty) return;
        await _disableMpvDualSubtitle(player);
        await _setGuardedSubtitleTrack(player, SubtitleTrack.no());
        await _setGuardedSubtitleTrack(
          player,
          SubtitleTrack.data(
            content,
            title: stream.title.isEmpty ? null : stream.title,
            language: stream.language.isEmpty ? null : stream.language,
          ),
        );
        if (!_startupTrackWorkIsCurrent) return;
        _subtitleSessionPreference = null;
        _showMessage('已加载飞牛字幕：${stream.title.isEmpty ? '未命名字幕' : stream.title}');
      },
    ]);
  }

  MediaSourceConfig _sourceForTarget(PlaybackTarget target) {
    final settings = _providerContainer.read(appSettingsProvider);
    for (final source in settings.mediaSources) {
      if (source.id == target.sourceId) {
        return source;
      }
    }
    throw StateError('媒体源不存在或已被移除');
  }

  String _formatServerAudioTrackLabel(
    PlaybackTarget target,
    List<AudioTrack> tracks,
    AudioTrack track,
  ) {
    final stream = matchPlaybackAudioStreamForTrack(
      target: target,
      tracks: tracks,
      track: track,
    );
    if (stream == null) {
      return formatPlaybackAudioTrackLabel(track);
    }
    final label = [
      if (stream.title.trim().isNotEmpty) stream.title.trim(),
      if (stream.language.trim().isNotEmpty) stream.language.trim(),
      if (stream.codec.trim().isNotEmpty) stream.codec.trim(),
      if (stream.channels > 0) '${stream.channels} 声道',
    ].join(' · ');
    return label.isEmpty ? formatPlaybackAudioTrackLabel(track) : label;
  }

  String _formatServerSubtitleStreamLabel(PlaybackSubtitleStream stream) {
    final label = [
      if (stream.title.trim().isNotEmpty) stream.title.trim(),
      if (stream.language.trim().isNotEmpty) stream.language.trim(),
      if (stream.codec.trim().isNotEmpty) stream.codec.trim(),
      '外挂',
    ].join(' · ');
    return label.isEmpty ? '飞牛外挂字幕' : label;
  }

  Future<PlaybackSubtitleSessionPreference?> _loadMpvSeriesSubtitlePreference(
    PlaybackTarget target,
  ) async {
    final preference = await _providerContainer
        .read(playbackMemoryRepositoryProvider)
        .loadSubtitlePreference(target);
    return preference == null
        ? null
        : PlaybackSubtitleSessionPreference.fromSeriesPreference(preference);
  }

  Future<void> _persistMpvSeriesSubtitlePreference(
    PlaybackTarget target,
    PlaybackSubtitleSessionPreference? preference,
  ) async {
    final repository =
        _providerContainer.read(playbackMemoryRepositoryProvider);
    if (preference == null) {
      await repository.removeSubtitlePreference(target);
      return;
    }
    final seriesKey = buildSeriesKeyForTarget(target);
    final persisted = preference.toSeriesPreference(seriesKey);
    if (persisted != null) {
      await repository.saveSubtitlePreference(persisted);
    }
  }

  Future<bool> _applyDefaultMpvDualSubtitleTracks(
    Player player, {
    required PlaybackSubtitleLanguage primaryLanguage,
    required PlaybackSubtitleLanguage secondaryLanguage,
  }) async {
    final tracks = await _awaitAvailableSubtitleTracks(player);
    final candidates =
        tracks.where(_canUseMpvDualSubtitleTrack).toList(growable: false);
    final primary = _selectMpvSubtitleTrackForLanguages(
      candidates,
      primaryLanguage.preferredLanguages,
    );
    if (primary == null) {
      return false;
    }
    final secondary = _selectMpvSubtitleTrackForLanguages(
      candidates.where((track) => track.id != primary.id).toList(),
      secondaryLanguage.preferredLanguages,
    );
    if (secondary == null) {
      return false;
    }
    await _setGuardedSubtitleTrack(player, primary);
    await _setMpvSubtitleProperty(player, 'secondary-sid', secondary.id);
    await _applyMpvSubtitleLayout(player);
    _setMpvDualSubtitleSessionEnabled(true);
    return true;
  }

  SubtitleTrack? _selectMpvSubtitleTrackForLanguages(
    List<SubtitleTrack> tracks,
    List<String> languages,
  ) {
    return selectSubtitleTrackForLanguages(
      tracks.where((track) => !_isSyntheticSubtitleTrack(track)).map(
            (track) => AutomaticSubtitleCandidate<SubtitleTrack>(
              value: track,
              searchableText: [
                track.title ?? '',
                track.language ?? '',
              ].where((item) => item.trim().isNotEmpty).join(' '),
              isDefault: track.isDefault == true,
            ),
          ),
      configuredLanguages: languages,
    );
  }

  Future<bool> _restoreMpvSubtitleSessionPreference(
    Player player,
    PlaybackSubtitleSessionPreference preference,
  ) async {
    switch (preference.mode) {
      case PlaybackSubtitleSessionMode.automatic:
        await _setMpvSubtitleProperty(player, 'secondary-sid', 'no');
        await _setGuardedSubtitleTrack(player, SubtitleTrack.auto());
        _setMpvDualSubtitleSessionEnabled(false);
        return true;
      case PlaybackSubtitleSessionMode.off:
        await _setMpvSubtitleProperty(player, 'secondary-sid', 'no');
        await _setGuardedSubtitleTrack(player, SubtitleTrack.no());
        _setMpvDualSubtitleSessionEnabled(false);
        return true;
      case PlaybackSubtitleSessionMode.single:
        final fingerprint = preference.primary;
        if (fingerprint == null) {
          return false;
        }
        final tracks = await _awaitAvailableSubtitleTracks(player);
        final selected = matchPlaybackSubtitleTrack(tracks, fingerprint);
        if (selected == null) {
          return false;
        }
        await _setMpvSubtitleProperty(player, 'secondary-sid', 'no');
        await _setGuardedSubtitleTrack(player, selected);
        _setMpvDualSubtitleSessionEnabled(false);
        return true;
      case PlaybackSubtitleSessionMode.dual:
        final primaryFingerprint = preference.primary;
        final secondaryFingerprint = preference.secondary;
        if (primaryFingerprint == null || secondaryFingerprint == null) {
          return false;
        }
        final tracks = await _awaitAvailableSubtitleTracks(player);
        final candidates =
            tracks.where(_canUseMpvDualSubtitleTrack).toList(growable: false);
        final primary = matchPlaybackSubtitleTrack(
          candidates,
          primaryFingerprint,
          textOnly: true,
        );
        if (primary == null) {
          return false;
        }
        final secondary = matchPlaybackSubtitleTrack(
          candidates,
          secondaryFingerprint,
          excludedIds: {primary.id},
          textOnly: true,
        );
        if (secondary == null) {
          return false;
        }
        await _setGuardedSubtitleTrack(player, primary);
        await _setMpvSubtitleProperty(player, 'secondary-sid', secondary.id);
        await _applyMpvSubtitleLayout(player);
        _setMpvDualSubtitleSessionEnabled(true);
        return true;
    }
  }

  void _setMpvDualSubtitleSessionEnabled(bool enabled) {
    if (!_startupTrackWorkIsCurrent) return;
    if (_mpvDualSubtitleEnabled == enabled) {
      return;
    }
    if (mounted) {
      setState(() {
        _mpvDualSubtitleEnabled = enabled;
      });
    } else {
      _mpvDualSubtitleEnabled = enabled;
    }
  }

  Future<void> _applyAutoPreferredSubtitleTrack(
    Player player, {
    required List<String> configuredLanguages,
  }) async {
    final tracks = await _awaitAvailableSubtitleTracks(player);
    if (tracks.isEmpty) {
      return;
    }
    final selectedTrack = _selectAutoPreferredSubtitleTrack(
      tracks,
      configuredLanguages: configuredLanguages,
    );
    if (selectedTrack == null) {
      return;
    }

    final currentTrack = player.state.track.subtitle;
    if (currentTrack.id == selectedTrack.id) {
      return;
    }
    await _setGuardedSubtitleTrack(player, selectedTrack);
  }

  Future<List<SubtitleTrack>> _awaitAvailableSubtitleTracks(
      Player player) async {
    final currentTracks = player.state.tracks.subtitle;
    if (_hasSelectableSubtitleTracks(currentTracks)) {
      return currentTracks;
    }

    final completer = Completer<List<SubtitleTrack>>();
    void finish(List<SubtitleTrack> tracks) {
      if (!completer.isCompleted) completer.complete(tracks);
    }

    final subscription = player.stream.tracks.listen((tracks) {
      if (_hasSelectableSubtitleTracks(tracks.subtitle)) {
        finish(tracks.subtitle);
      }
    },
        onError: (Object error) => finish(currentTracks),
        onDone: () => finish(currentTracks));
    final timer =
        Timer(const Duration(seconds: 3), () => finish(currentTracks));
    try {
      return await completer.future;
    } finally {
      timer.cancel();
      await subscription.cancel();
    }
  }

  bool _hasSelectableSubtitleTracks(List<SubtitleTrack> tracks) {
    return tracks.any((track) => !_isSyntheticSubtitleTrack(track));
  }

  bool _isSyntheticSubtitleTrack(SubtitleTrack track) {
    return track.id == 'auto' || track.id == 'no';
  }

  SubtitleTrack? _selectAutoPreferredSubtitleTrack(
    List<SubtitleTrack> tracks, {
    required List<String> configuredLanguages,
  }) {
    return selectSubtitleTrackWithSystemFallback(
      tracks.where((track) => !_isSyntheticSubtitleTrack(track)).map(
            (track) => AutomaticSubtitleCandidate<SubtitleTrack>(
              value: track,
              searchableText: [
                track.title ?? '',
                track.language ?? '',
              ].where((item) => item.trim().isNotEmpty).join(' '),
              isDefault: track.isDefault == true,
            ),
          ),
      preferredLanguages: configuredLanguages,
    );
  }

  Future<void> _persistPlaybackProgress({
    bool force = false,
    Player? playerOverride,
  }) async {
    final player = playerOverride ?? _player;
    final target = _resolvedTarget ?? widget.target;
    final canPersistDetachedPlayer = playerOverride != null;
    if (((!_isReady && !canPersistDetachedPlayer) || player == null)) {
      return;
    }

    final now = DateTime.now();
    if (!force) {
      final lastPersistedAt = _lastProgressPersistedAt;
      if (lastPersistedAt != null &&
          now.difference(lastPersistedAt) <
              _PlayerPageState._kProgressPersistInterval) {
        return;
      }
      final deltaMs = (_latestPosition.inMilliseconds -
              _lastPersistedPosition.inMilliseconds)
          .abs();
      if (deltaMs < _PlayerPageState._kProgressPersistInterval.inMilliseconds) {
        return;
      }
    }

    _lastProgressPersistedAt = now;
    _lastPersistedPosition = _latestPosition;
    final position = _latestPosition;
    final duration = _latestDuration > Duration.zero
        ? _latestDuration
        : player.state.duration;
    final completedByAutoSkip = _completionState.completedByAutoSkip;

    await _providerContainer
        .read(playbackMemoryRepositoryProvider)
        .saveProgress(
          target: target,
          position: position,
          duration: duration,
          completedByAutoSkip: completedByAutoSkip,
        );
    final report = _reportFntvPlaybackProgress(
      target: target,
      force: force,
      position: completedByAutoSkip ? duration : position,
      duration: duration,
    );
    if (force) {
      await report;
    } else {
      unawaited(report);
    }
  }

  Future<void> _reportFntvPlaybackProgress({
    required PlaybackTarget target,
    required Duration position,
    required Duration duration,
    bool force = false,
  }) async {
    if (target.sourceKind != MediaSourceKind.fntv ||
        target.itemId.trim().isEmpty ||
        target.preferredMediaSourceId.trim().isEmpty ||
        target.videoStreamId.trim().isEmpty) {
      return;
    }
    if (!force && _fntvProgressQueued > 0) return;
    final client = _providerContainer
        .read(mediaServerClientProvider(MediaSourceKind.fntv));
    final source = _sourceForTarget(target);
    _fntvProgressQueued++;
    final pending = _fntvProgressTail.then((_) async {
      try {
        await client.reportPlaybackProgress(
            source: source,
            target: target,
            position: position,
            duration: duration);
      } catch (_) {
        // Server progress is best effort and must never interrupt playback.
      } finally {
        _fntvProgressQueued--;
      }
    });
    _fntvProgressTail = pending;
    await pending;
  }

  Future<void> _selectPlaybackVersion(Player player, bool isTelevision) async {
    final target = _resolvedTarget ?? widget.target;
    final selected = await showPlaybackMenuDialog<PlaybackTarget>(
      context: context,
      builder: (_) => PlayerVariantPickerDialog(
        target: target,
        isTelevision: isTelevision,
        load: () => PlaybackVariantResolver(read: _providerContainer.read)
            .load(target)
            .timeout(const Duration(seconds: 30)),
      ),
    );
    if (!mounted ||
        !identical(_player, player) ||
        selected == null ||
        isSamePlaybackVariant(selected, target)) {
      return;
    }
    await _switchFntvPlayback(player, selected, switchingVersion: true);
  }

  Future<void> _switchFntvPlaybackQuality(
    Player player,
    FntvPlaybackQuality quality,
  ) async {
    final target = _resolvedTarget ?? widget.target;
    if (target.sourceKind != MediaSourceKind.fntv ||
        quality.index == target.preferredPlaybackQualityIndex) {
      return;
    }
    await _switchFntvPlayback(
        player, target.copyWith(preferredPlaybackQualityIndex: quality.index));
  }

  Future<void> _switchFntvPlayback(
    Player player,
    PlaybackTarget requested, {
    bool switchingVersion = false,
  }) async {
    if (_fntvSwitchInProgress || _episodeQueueAdvanceInProgress) return;
    _fntvSwitchInProgress = true;
    final oldTarget = _resolvedTarget ?? widget.target;
    PlaybackTarget? next;
    var detached = false;
    var committed = false;
    var rollbackAttempted = false;
    var position = player.state.position;
    var playing = player.state.playing;
    var rate = player.state.rate;
    final subtitlePreference = _subtitleSessionPreference;
    Future<void> restoreState() async {
      final active = _player;
      if (!_isReady || active == null || !mounted) return;
      await active.setRate(rate);
      if (!playing) await active.pause();
      if ((!switchingVersion || rollbackAttempted) &&
          subtitlePreference != null &&
          !(_resolvedTarget?.isFntvTranscoding ?? false)) {
        _subtitleSessionPreference = subtitlePreference;
        await _restoreMpvSubtitleSessionPreference(active, subtitlePreference);
      }
    }

    Future<void> restoreOriginal() async {
      rollbackAttempted = true;
      final failed = _detachActivePlayerState();
      await _shutdownDetachedPlayer(failed,
          reason: 'fntv-switch-rollback',
          persistProgress: false,
          teardownPlatformState: false);
      if (next != null) await _fntvSessions.release(next);
      if (!mounted) return;
      setState(() => _error = null);
      await _initialize(
          initialTarget: oldTarget,
          targetAlreadyResolved: true,
          startPositionOverride: position);
      if (!_isReady) await _fntvSessions.release(oldTarget);
    }

    try {
      final request = switchingVersion
          ? requested
          : requested.copyWith(
              streamUrl: '',
              headers: const {},
              fntvSessionLink: '',
              fntvStartPositionMs: player.state.position.inMilliseconds,
              fntvTrackSelectionExplicit: true,
              preferredSubtitleStreamId: !oldTarget.isFntvTranscoding &&
                      player.state.track.subtitle.id == 'no'
                  ? ''
                  : requested.preferredSubtitleStreamId,
            );
      next = await PlaybackTargetResolver(read: _providerContainer.read)
          .resolve(request);
      await _fntvSessions.retain(next);
      if (!mounted || !identical(_player, player)) {
        await _fntvSessions.release(next);
        return;
      }
      position = player.state.position;
      playing = player.state.playing;
      rate = player.state.rate;
      _latestPosition = position;
      _latestDuration = player.state.duration;
      await _persistPlaybackProgress(force: true);
      if (!mounted || !identical(_player, player)) {
        await _fntvSessions.release(next);
        return;
      }
      final oldPlayer = _detachActivePlayerState();
      detached = true;
      await _shutdownDetachedPlayer(oldPlayer,
          reason: 'fntv-playback-switch',
          persistProgress: false,
          teardownPlatformState: false);
      if (!mounted) return;
      _nextEpisodeIsAutomatic = false;
      setState(() => _error = null);
      await _initialize(
          initialTarget: next,
          targetAlreadyResolved: true,
          startPositionOverride: position);
      if (!mounted) return;
      final switched = _isReady;
      if (!switched) {
        await restoreOriginal();
      }
      if (!mounted) return;
      committed = switched;
      try {
        await restoreState();
      } finally {
        if (switched) await _fntvSessions.release(oldTarget);
      }
      _showMessage(switched ? '播放设置已切换' : '切换失败，已尝试恢复原播放');
    } catch (_) {
      if (!detached && next != null) await _fntvSessions.release(next);
      if (detached && !committed && !rollbackAttempted && mounted) {
        try {
          await restoreOriginal();
          await restoreState();
        } catch (_) {
          await _fntvSessions.release(oldTarget);
          if (next != null) await _fntvSessions.release(next);
        }
      }
      if (mounted) _showMessage(detached ? '切换播放设置失败' : '解析失败，已保留当前播放');
    } finally {
      _fntvSwitchInProgress = false;
    }
  }

  /// Decides where the media should open, before the player is created, so a
  /// remote source never buffers from zero only to be seeked afterwards.
  PlaybackStartPosition _resolvePlaybackStartPosition({
    required PlaybackTarget target,
    required PlaybackProgressEntry? resumeEntry,
    required SeriesSkipPreference? skipPreference,
  }) {
    final automaticNext = _nextEpisodeIsAutomatic;
    _nextEpisodeIsAutomatic = false;
    return resolvePlaybackStartPosition(
      allowResume: target.allowResume,
      resumePosition: _resolveResumeStartPosition(
        resumeEntry,
        resumeEntry?.duration ?? Duration.zero,
      ),
      automaticNext: automaticNext,
      skipEnabled: skipPreference != null && skipPreference.enabled,
      introDuration: skipPreference?.introDuration ?? Duration.zero,
    );
  }

  /// Records the applied start position and opens the auto-skip gate. Auto-skip
  /// stays inert until this ran, so a startup position event cannot fight it.
  void _finalizePlaybackStartPosition(
    Player player,
    PlaybackStartPosition start,
  ) {
    final duration = player.state.duration;
    if (start.isIntroSkip &&
        duration > Duration.zero &&
        start.position >= duration) {
      start = const PlaybackStartPosition(position: Duration.zero);
      unawaited(_seekPlayerAutomatically(player, Duration.zero));
    }
    final position = player.state.position;
    _latestPosition = position > start.position ? position : start.position;
    if (duration > Duration.zero) {
      _latestDuration = duration;
    }

    // The real duration may still be unknown; validate the intro bound as soon
    // as it arrives instead of blocking the open on it.
    _pendingIntroStartValidation =
        start.isIntroSkip ? start.position : Duration.zero;
    _validatePendingIntroStartPosition(player, duration);
    // Safety net for a backend that ignored the open-time start position
    // (keyframe alignment keeps the real position close, never far behind).
    if (start.position > Duration.zero &&
        position + const Duration(seconds: 10) < start.position) {
      _latestPosition = start.position;
      unawaited(_seekPlayerAutomatically(player, start.position));
    }
    if (start.position > Duration.zero && mounted) {
      _showMessage(
        start.isResume
            ? '已从 ${formatPlaybackClockDuration(start.position)} 继续播放'
            : '已自动跳过片头',
      );
    }

    _introSkipApplied = true;
    _syncSkipFlagsWithCurrentPosition();
    _playbackStartPositionApplied = true;
  }

  /// An intro longer than the episode itself would strand playback at the tail,
  /// so fall back to the beginning once the duration is known.
  void _validatePendingIntroStartPosition(Player player, Duration duration) {
    final introPosition = _pendingIntroStartValidation;
    if (introPosition <= Duration.zero || duration <= Duration.zero) {
      return;
    }
    _pendingIntroStartValidation = Duration.zero;
    if (introPosition < duration) {
      return;
    }
    _latestPosition = Duration.zero;
    unawaited(_seekPlayerAutomatically(player, Duration.zero));
  }

  Duration _resolveResumeStartPosition(
    PlaybackProgressEntry? resumeEntry,
    Duration duration,
  ) {
    if (resumeEntry == null || !resumeEntry.canResume) {
      return Duration.zero;
    }
    if (duration <= Duration.zero) {
      // No stored duration to clamp against; `canResume` already rejects
      // finished and near-finished entries.
      return resumeEntry.position > const Duration(seconds: 5)
          ? resumeEntry.position
          : Duration.zero;
    }
    final maxPosition = duration - const Duration(seconds: 3);
    final desiredPosition =
        resumeEntry.position < maxPosition ? resumeEntry.position : maxPosition;
    if (desiredPosition <= const Duration(seconds: 5)) {
      return Duration.zero;
    }
    return desiredPosition;
  }

  void _handlePlaybackRuntimePosition(Player player, Duration position) {
    if (!_playbackStartPositionApplied) {
      return;
    }
    _maybeApplyAutoSkip(player, position);
    _maybePrepareNextEpisode(player, position);
  }

  void _maybeApplyAutoSkip(Player player, Duration position) {
    final preference = _seriesSkipPreference;
    if (preference == null ||
        !preference.enabled ||
        _subtitleSearchActive ||
        _skipPreferenceSaveInProgress ||
        _episodeQueueAdvanceInProgress ||
        !player.state.playing) {
      return;
    }

    final duration = _latestDuration > Duration.zero
        ? _latestDuration
        : player.state.duration;

    if (!_introSkipApplied && preference.introDuration > Duration.zero) {
      if (position >= preference.introDuration ||
          (duration > Duration.zero && preference.introDuration >= duration)) {
        _introSkipApplied = true;
      } else {
        _introSkipApplied = true;
        _latestPosition = preference.introDuration;
        unawaited(_seekPlayerAutomatically(player, preference.introDuration));
        _showMessage('已自动跳过片头');
        return;
      }
    }

    if (_outroSkipApplied ||
        preference.outroDuration <= Duration.zero ||
        duration <= Duration.zero) {
      return;
    }

    final boundary = resolvePlaybackEndBoundary(
      duration: duration,
      skipEnabled: true,
      outroDuration: preference.outroDuration,
    );
    if (boundary >= duration || position < boundary) {
      return;
    }

    _outroSkipApplied = true;
    unawaited(_advanceAtPlaybackEndBoundary(player, duration));
  }

  /// Switches straight into the next episode at the outro boundary instead of
  /// seeking to the file tail and waiting for the end event.
  Future<void> _advanceAtPlaybackEndBoundary(
    Player player,
    Duration duration,
  ) async {
    final queue = _episodeQueue;
    if (queue != null && queue.hasCurrent && queue.hasNext) {
      await _movePlaybackQueue(forward: true, reason: 'outro');
      return;
    }

    _latestDuration = duration;
    _latestPosition = player.state.position;
    _completionState.markCompletedByAutoSkip();
    await (player is PlaybackInteractionPlayer
        ? player.pauseAutomatically()
        : player.pause());
    if (!mounted || !identical(_player, player)) {
      return;
    }
    await _persistPlaybackProgress(force: true);
    if (!mounted || !identical(_player, player)) return;
    _showMessage('本集已播放完毕');
  }

  void _maybePrepareNextEpisode(Player player, Duration position) {
    if (_subtitleSearchActive ||
        _skipPreferenceSaveInProgress ||
        _episodeQueueAdvanceInProgress ||
        !player.state.playing) {
      return;
    }
    final queue = _episodeQueue;
    if (queue == null || !queue.hasCurrent || !queue.hasNext) {
      return;
    }
    final duration = _latestDuration > Duration.zero
        ? _latestDuration
        : player.state.duration;
    if (duration <= Duration.zero) {
      return;
    }
    final preference = _seriesSkipPreference;
    final boundary = resolvePlaybackEndBoundary(
      duration: duration,
      skipEnabled: preference?.enabled ?? false,
      outroDuration: preference?.outroDuration ?? Duration.zero,
    );
    if (!shouldPrepareNextEpisode(position: position, boundary: boundary)) {
      return;
    }

    final nextIndex = queue.currentIndex + 1;
    final entry = queue.entries[nextIndex];
    if (!entry.target.needsResolution) {
      return;
    }
    final signature = _buildPreparedEpisodeSignature(nextIndex, entry);
    _syncEpisodePreparationContext();
    unawaited(_episodePreparation.prepare(
      key: (null, signature),
      resolver: () => _resolveEpisodeAddress(entry.target),
    ));
  }

  Future<PlaybackTarget> _resolveEpisodeAddress(PlaybackTarget target) async {
    final resolved = await PlaybackTargetResolver(read: _providerContainer.read)
        .resolve(target);
    if (resolved.streamUrl.trim().isEmpty || resolved.needsResolution) {
      throw StateError('没有取得可播放地址');
    }
    return resolved;
  }

  void _syncEpisodePreparationContext() {
    final context = (
      _startupGeneration,
      _episodeQueue,
      _resolvedTarget,
      _providerContainer.read(appSettingsProvider),
    );
    if (_episodePreparationContext != context) {
      _episodePreparation.reset();
      _episodePreparationContext = context;
    }
  }

  String _buildPreparedEpisodeSignature(
    int index,
    PlaybackEpisodeQueueEntry entry,
  ) {
    return '$_startupGeneration|${_episodeQueue?.currentEntry?.playbackItemKey}|'
        '${_seriesSkipPreference?.updatedAt.microsecondsSinceEpoch}|'
        '$index|${entry.playbackItemKey}|${entry.seriesKey}|'
        '${entry.target.sourceId}|${entry.target.itemId}|'
        '${entry.target.streamUrl}|${entry.target.actualAddress}';
  }

  void _resetPreparedNextEpisode() {
    _episodePreparation.reset();
    _episodePreparationContext = null;
  }

  void _syncSkipFlagsWithCurrentPosition() {
    final preference = _seriesSkipPreference;
    if (preference == null || !preference.enabled) {
      _introSkipApplied = true;
      _outroSkipApplied = true;
      return;
    }

    if (_latestDuration <= Duration.zero ||
        preference.outroDuration <= Duration.zero ||
        _latestPosition < _latestDuration - preference.outroDuration) {
      _outroSkipApplied = false;
    }
  }

  /// Mirrors the native `onUserSeek` rule: a manual seek back into the body
  /// re-arms the outro switch, a manual seek into the outro keeps it disarmed.
  void _syncSkipFlagsAfterUserSeek(Duration position) {
    _cancelPendingAutomaticAdvance();
    _completionState.clearForManualSeek();
    _latestPosition = position;
    _syncSkipFlagsWithCurrentPosition();
    _introSkipApplied = true;
    final preference = _seriesSkipPreference;
    if (preference == null || !preference.enabled) {
      return;
    }
    final boundary = resolvePlaybackEndBoundary(
      duration: _latestDuration,
      skipEnabled: true,
      outroDuration: preference.outroDuration,
    );
    if (boundary > Duration.zero && position >= boundary) {
      _outroSkipApplied = true;
    }
  }

  Future<void> _syncSubtitleDelayState(Player player) async {
    final delay = await _readSubtitleDelaySeconds(player);
    if (!mounted) {
      return;
    }
    setState(() {
      _subtitleDelaySupported = delay != null;
      _subtitleDelaySeconds = delay ?? 0;
    });
  }

  Future<double?> _readSubtitleDelaySeconds(Player player) async {
    final native = player.platform;
    if (native == null) {
      return null;
    }

    try {
      final raw = await (native as dynamic).getProperty('sub-delay');
      return double.tryParse('$raw');
    } catch (_) {
      return null;
    }
  }

  Future<void> _setSubtitleDelay(Player player, double value) async {
    final native = player.platform;
    if (native == null) {
      _showMessage('当前播放器内核暂不支持字幕偏移');
      return;
    }

    try {
      await (native as dynamic).setProperty(
        'sub-delay',
        value.toStringAsFixed(3),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _subtitleDelaySupported = true;
        _subtitleDelaySeconds = value;
      });
    } catch (error) {
      _showMessage('字幕偏移设置失败：$error');
    }
  }

  Future<void> _openSubtitleDelayDialog(Player player) async {
    if (!_subtitleDelaySupported) {
      await _syncSubtitleDelayState(player);
    }
    if (!mounted) {
      return;
    }
    if (!_subtitleDelaySupported) {
      _showMessage('当前播放器内核暂不支持字幕偏移');
      return;
    }

    await showPlaybackSubtitleDelayDialog(
      context: context,
      initialDelay: _subtitleDelaySeconds,
      steps: _PlayerPageState._kSubtitleDelaySteps,
      onApplyDelay: (nextDelay) async {
        await _setSubtitleDelay(player, nextDelay);
        return _subtitleDelaySeconds;
      },
    );
  }

  Future<void> _loadExternalSubtitle(Player player) async {
    _manualTrackRevision++;
    final isTelevision = _isTelevisionPlaybackDevice;
    if (isTelevision) {
      _showMessage('电视模式暂不打开系统文件选择器，请改用内嵌字幕或在其他设备上准备字幕文件。');
      return;
    }
    final picker = _providerContainer.read(subtitleFilePickerProvider);
    if (!picker.isSupported) {
      _showMessage(picker.unsupportedReason);
      return;
    }

    String? path;
    try {
      path = await picker.pickSubtitlePath();
    } catch (error) {
      _showMessage('打开字幕文件选择器失败：$error');
      return;
    }
    if (path == null || path.trim().isEmpty) {
      return;
    }
    await _applyExternalSubtitlePath(player, path);
  }

  Future<void> _applyExternalSubtitlePath(
    Player player,
    String path, {
    String? displayName,
    bool showFeedback = true,
  }) async {
    final resolvedPath = path.trim();
    if (resolvedPath.isEmpty || !mounted || !identical(_player, player)) {
      return;
    }
    String content;
    try {
      content = await readLocalSubtitleText(resolvedPath);
    } catch (error) {
      if (mounted && identical(_player, player)) _showMessage('加载字幕失败：$error');
      return;
    }
    if (!mounted ||
        !identical(_player, player) ||
        !_startupTrackWorkIsCurrent) {
      return;
    }
    await _disableMpvDualSubtitle(player);
    final applied = await _runPlayerCommand(
      () => _setGuardedSubtitleTrack(
        player,
        SubtitleTrack.data(
          content,
          title: (displayName?.trim().isNotEmpty ?? false)
              ? displayName!.trim()
              : p.basenameWithoutExtension(resolvedPath),
        ),
      ),
      failureMessage: '加载字幕失败',
    );
    if (!applied ||
        !mounted ||
        !identical(_player, player) ||
        !_startupTrackWorkIsCurrent) {
      return;
    }
    _subtitleSessionPreference = null;
    if (showFeedback) {
      _showMessage('外挂字幕已加载');
    }
  }

  Future<void> _applyStartupExternalSubtitle(
    Player player,
    PlaybackTarget target,
  ) async {
    final subtitlePath = target.externalSubtitleFilePath.trim();
    if (subtitlePath.isEmpty) {
      return;
    }
    await _applyExternalSubtitlePath(
      player,
      subtitlePath,
      displayName: target.externalSubtitleDisplayName,
      showFeedback: false,
    );
  }

  Future<void> _showOnlineSubtitleSearch(
    Player player,
    PlaybackTarget target,
  ) async {
    _manualTrackRevision++;
    final query = buildSubtitleSearchQuery(target);
    final initialInput = buildSubtitleSearchInitialInput(target);
    final request = SubtitleSearchRequest(
      query: query,
      title: initialInput,
      initialInput: initialInput,
      originalTitle: target.originalTitle.trim(),
      year: target.year > 0 ? target.year : null,
      imdbId: target.imdbId.trim(),
      tmdbId: target.tmdbId.trim(),
      seasonNumber: target.seasonNumber,
      episodeNumber: target.episodeNumber,
      filePath: target.actualAddress.trim().isNotEmpty
          ? target.actualAddress.trim()
          : target.streamUrl.trim(),
      applyMode: SubtitleSearchApplyMode.downloadAndApply,
    );
    final location = request.toLocation();
    if (query.trim().isEmpty) {
      _showMessage('缺少片名信息，暂时无法搜索字幕');
      return;
    }

    _cancelPendingAutomaticAdvance();
    _subtitleSearchActive = true;
    SubtitleSearchSelection? selection;
    try {
      selection = await context.push<SubtitleSearchSelection>(location);
    } finally {
      _subtitleSearchActive = false;
    }
    if (selection == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    if (!selection.canApply) {
      _showMessage('字幕已缓存，但当前结果暂不能直接挂载播放');
      return;
    }
    await _applyExternalSubtitlePath(
      player,
      selection.subtitleFilePath!,
      displayName: selection.displayName,
    );
  }

  Future<void> _configureSeriesSkipPreference(Player player) async {
    final target = _resolvedTarget ?? widget.target;
    final seriesKey = buildSeriesKeyForTarget(target);
    if (seriesKey.isEmpty) {
      _showMessage('当前内容没有可绑定的剧集信息，暂时不能按剧设置跳过规则');
      return;
    }

    final playerDuration = _latestDuration > Duration.zero
        ? _latestDuration
        : player.state.duration;
    final currentPosition = _latestPosition;
    final seedPreference = _seriesSkipPreference ??
        SeriesSkipPreference(
          seriesKey: seriesKey,
          updatedAt: DateTime.now(),
          seriesTitle: target.resolvedSeriesTitle,
        );

    final nextPreference = await showPlaybackSeriesSkipDialog(
      context: context,
      target: target,
      playerDuration: playerDuration,
      currentPosition: currentPosition,
      seedPreference: seedPreference,
    );
    if (nextPreference == null ||
        !mounted ||
        !identical(_player, player) ||
        buildSeriesKeyForTarget(_resolvedTarget ?? widget.target) !=
            seriesKey) {
      return;
    }
    _cancelPendingAutomaticAdvance();
    _skipPreferenceSaveInProgress = true;
    try {
      await _providerContainer
          .read(playbackMemoryRepositoryProvider)
          .saveSkipPreference(nextPreference);
    } finally {
      _skipPreferenceSaveInProgress = false;
    }
    if (!mounted || !identical(_player, player)) {
      return;
    }
    setState(() {
      _seriesSkipPreference = nextPreference;
    });
    _introSkipApplied = false;
    _outroSkipApplied = false;
    _resetPreparedNextEpisode();
    _syncSkipFlagsWithCurrentPosition();
    _maybeApplyAutoSkip(player, _latestPosition);
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _buildPlaybackErrorMessage(Object error) {
    if (error is TimeoutException) {
      return error.message ?? '超过最大等待时间，已停止尝试播放';
    }
    if (error is _PlayerOpenException) {
      return error.message;
    }
    return '$error';
  }
}
