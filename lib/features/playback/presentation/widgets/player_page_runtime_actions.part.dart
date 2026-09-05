// ignore_for_file: invalid_use_of_protected_member

part of '../player_page.dart';

/// One prefetched episode address, bound to the queue slot it was resolved for.
class _PreparedNextEpisode {
  const _PreparedNextEpisode({
    required this.signature,
    required this.target,
    required this.preparedAt,
  });

  final String signature;
  final PlaybackTarget target;
  final DateTime preparedAt;
}

extension _PlayerPageStateRuntimeActions on _PlayerPageState {
  Future<void> _applyStartupPlaybackPreferences(
    Player player,
    PlaybackTarget target,
  ) async {
    final settings = _providerContainer.read(appSettingsProvider);
    _subtitleSessionPreference = await _loadMpvSeriesSubtitlePreference(target);

    try {
      if ((settings.playbackDefaultSpeed - 1.0).abs() > 0.0001) {
        await player.setRate(settings.playbackDefaultSpeed);
      }
    } catch (_) {
      // Ignore preference application failures to keep playback available.
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
        await player.setSubtitleTrack(SubtitleTrack.no());
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
      await player.setSubtitleTrack(SubtitleTrack.no());
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
    await player.setSubtitleTrack(primary);
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
        await player.setSubtitleTrack(SubtitleTrack.auto());
        _setMpvDualSubtitleSessionEnabled(false);
        return true;
      case PlaybackSubtitleSessionMode.off:
        await _setMpvSubtitleProperty(player, 'secondary-sid', 'no');
        await player.setSubtitleTrack(SubtitleTrack.no());
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
        await player.setSubtitleTrack(selected);
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
        await player.setSubtitleTrack(primary);
        await _setMpvSubtitleProperty(player, 'secondary-sid', secondary.id);
        await _applyMpvSubtitleLayout(player);
        _setMpvDualSubtitleSessionEnabled(true);
        return true;
    }
  }

  void _setMpvDualSubtitleSessionEnabled(bool enabled) {
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
    await player.setSubtitleTrack(selectedTrack);
  }

  Future<List<SubtitleTrack>> _awaitAvailableSubtitleTracks(
      Player player) async {
    final currentTracks = player.state.tracks.subtitle;
    if (_hasSelectableSubtitleTracks(currentTracks)) {
      return currentTracks;
    }

    try {
      return await player.stream.tracks
          .map((tracks) => tracks.subtitle)
          .firstWhere(_hasSelectableSubtitleTracks)
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      return currentTracks;
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

    await _providerContainer
        .read(playbackMemoryRepositoryProvider)
        .saveProgress(
          target: target,
          position: _latestPosition,
          duration: _latestDuration > Duration.zero
              ? _latestDuration
              : player.state.duration,
        );
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
    final position = player.state.position;
    _latestPosition = position > start.position ? position : start.position;
    final duration = player.state.duration;
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
      unawaited(player.seek(start.position));
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
    unawaited(player.seek(Duration.zero));
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
        unawaited(player.seek(preference.introDuration));
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
    _latestPosition = duration;
    await _persistPlaybackProgress(force: true);
    if (!mounted || _player != player) {
      return;
    }
    await player.pause();
    if (!mounted) {
      return;
    }
    _showMessage('本集已播放完毕');
  }

  void _maybePrepareNextEpisode(Player player, Duration position) {
    if (_episodeQueueAdvanceInProgress ||
        _nextEpisodePrepareInProgress ||
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
    if (_nextEpisodePrepareAttempt == signature) {
      return;
    }
    _nextEpisodePrepareAttempt = signature;
    unawaited(
      _prepareNextEpisodeTarget(
        signature: signature,
        index: nextIndex,
        entry: entry,
      ),
    );
  }

  /// Caches the adjacent episode address and headers only: no second player and
  /// no video pre-buffering.
  Future<void> _prepareNextEpisodeTarget({
    required String signature,
    required int index,
    required PlaybackEpisodeQueueEntry entry,
  }) async {
    _nextEpisodePrepareInProgress = true;
    try {
      final resolvedTarget =
          await PlaybackTargetResolver(read: _providerContainer.read)
              .resolve(entry.target)
              .timeout(kPlaybackEpisodeResolveTimeout);
      if (!mounted ||
          resolvedTarget.streamUrl.trim().isEmpty ||
          resolvedTarget.needsResolution) {
        return;
      }
      final queue = _episodeQueue;
      if (queue == null ||
          index >= queue.entries.length ||
          _buildPreparedEpisodeSignature(index, queue.entries[index]) !=
              signature) {
        return;
      }
      _preparedNextEpisode = _PreparedNextEpisode(
        signature: signature,
        target: resolvedTarget,
        preparedAt: DateTime.now(),
      );
    } catch (_) {
      // A background failure stays silent: the boundary switch resolves again.
    } finally {
      _nextEpisodePrepareInProgress = false;
    }
  }

  String _buildPreparedEpisodeSignature(
    int index,
    PlaybackEpisodeQueueEntry entry,
  ) {
    return '$index|${entry.playbackItemKey}|${entry.seriesKey}|'
        '${entry.target.sourceId}|${entry.target.itemId}|'
        '${entry.target.streamUrl}|${entry.target.actualAddress}';
  }

  PlaybackTarget? _takePreparedEpisodeTarget(String signature) {
    final prepared = _preparedNextEpisode;
    _preparedNextEpisode = null;
    if (prepared == null || prepared.signature != signature) {
      return null;
    }
    if (DateTime.now().difference(prepared.preparedAt) >=
        kPlaybackPreparedEpisodeTtl) {
      return null;
    }
    return prepared.target;
  }

  void _resetPreparedNextEpisode() {
    _preparedNextEpisode = null;
    _nextEpisodePrepareAttempt = null;
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
    if (resolvedPath.isEmpty) {
      return;
    }
    await _disableMpvDualSubtitle(player);
    final uri = Uri.file(resolvedPath).toString();
    final applied = await _runPlayerCommand(
      () => player.setSubtitleTrack(
        SubtitleTrack.uri(
          uri,
          title: (displayName?.trim().isNotEmpty ?? false)
              ? displayName!.trim()
              : p.basenameWithoutExtension(resolvedPath),
        ),
      ),
      failureMessage: '加载字幕失败',
    );
    if (!applied) {
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
    subtitleSearchTrace(
      'player.open-subtitle-search',
      fields: {
        'targetTitle': target.title.trim(),
        'seriesTitle': target.seriesTitle.trim(),
        'season': target.seasonNumber,
        'episode': target.episodeNumber,
        'originalTitle': target.originalTitle.trim(),
        'imdbId': target.imdbId.trim(),
        'tmdbId': target.tmdbId.trim(),
        'query': query,
        'initialInput': initialInput,
        'location': location,
      },
    );
    if (query.trim().isEmpty) {
      subtitleSearchTrace('player.open-subtitle-search.skip-empty-query');
      _showMessage('缺少片名信息，暂时无法搜索字幕');
      return;
    }

    final selection = await context.push<SubtitleSearchSelection>(location);
    if (selection == null) {
      subtitleSearchTrace('player.open-subtitle-search.cancelled');
      return;
    }
    if (!mounted) {
      return;
    }
    if (!selection.canApply) {
      subtitleSearchTrace(
        'player.open-subtitle-search.selection-not-applyable',
        fields: {
          'cachedPath': selection.cachedPath,
          'displayName': selection.displayName,
          'subtitleFilePath': selection.subtitleFilePath ?? '',
        },
      );
      _showMessage('字幕已缓存，但当前结果暂不能直接挂载播放');
      return;
    }
    subtitleSearchTrace(
      'player.open-subtitle-search.selection',
      fields: {
        'cachedPath': selection.cachedPath,
        'displayName': selection.displayName,
        'subtitleFilePath': selection.subtitleFilePath ?? '',
      },
    );
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
    if (nextPreference == null) {
      return;
    }
    await ref
        .read(playbackMemoryRepositoryProvider)
        .saveSkipPreference(nextPreference);
    if (!mounted) {
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
