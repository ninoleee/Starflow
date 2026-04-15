// ignore_for_file: invalid_use_of_protected_member

part of '../player_page.dart';

extension _PlayerPageStateRuntimeActions on _PlayerPageState {
  Future<void> _applyStartupPlaybackPreferences(Player player) async {
    final settings = _providerContainer.read(appSettingsProvider);

    try {
      if ((settings.playbackDefaultSpeed - 1.0).abs() > 0.0001) {
        await player.setRate(settings.playbackDefaultSpeed);
      }
    } catch (_) {
      // Ignore preference application failures to keep playback available.
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
        await _applyAutoPreferredSubtitleTrack(
          player,
          configuredLanguages: settings.subtitlePreferredLanguages,
        );
      } catch (_) {
        // Ignore preference application failures to keep playback available.
      }
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
    SubtitleTrack? bestTrack;
    var bestScore = 0;

    for (final track in tracks) {
      if (_isSyntheticSubtitleTrack(track)) {
        continue;
      }
      final score = scorePreferredSubtitleText(
            [
              track.title ?? '',
              track.language ?? '',
            ].where((item) => item.trim().isNotEmpty).join(' '),
            configuredLanguages: configuredLanguages,
          ) +
          (track.isDefault == true ? 6 : 0);
      if (score <= 0) {
        continue;
      }
      if (bestTrack == null || score > bestScore) {
        bestTrack = track;
        bestScore = score;
      }
    }

    return bestTrack;
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
      if (deltaMs < 4000) {
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

  Future<void> _restorePlaybackProgress(
    Player player,
    PlaybackProgressEntry? resumeEntry,
  ) async {
    if (resumeEntry == null || !resumeEntry.canResume) {
      return;
    }

    final resolvedDuration = await _awaitKnownDuration(player);
    final duration = resolvedDuration > Duration.zero
        ? resolvedDuration
        : resumeEntry.duration;
    if (duration <= Duration.zero) {
      return;
    }

    final maxPosition = duration - const Duration(seconds: 3);
    final desiredPosition =
        resumeEntry.position < maxPosition ? resumeEntry.position : maxPosition;
    if (desiredPosition <= const Duration(seconds: 5)) {
      return;
    }

    try {
      await player.seek(desiredPosition);
      _latestPosition = desiredPosition;
      _latestDuration = duration;
      if (!mounted) {
        return;
      }
      _showMessage(
        '已从 ${formatPlaybackClockDuration(desiredPosition)} 继续播放',
      );
    } catch (_) {
      // Keep playback available even if resume fails.
    }
  }

  Future<Duration> _awaitKnownDuration(Player player) async {
    final current = player.state.duration;
    if (current > Duration.zero) {
      return current;
    }

    try {
      return await player.stream.duration
          .firstWhere((duration) => duration > Duration.zero)
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      return Duration.zero;
    }
  }

  void _maybeApplyAutoSkip(Player player, Duration position) {
    final preference = _seriesSkipPreference;
    if (preference == null || !preference.enabled) {
      return;
    }

    final duration = _latestDuration > Duration.zero
        ? _latestDuration
        : player.state.duration;

    if (!_introSkipApplied && preference.introDuration > Duration.zero) {
      if (position >= preference.introDuration) {
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

    final triggerPosition = duration - preference.outroDuration;
    if (triggerPosition <= Duration.zero) {
      return;
    }
    if (position < triggerPosition) {
      return;
    }

    _outroSkipApplied = true;
    final seekTarget = duration > const Duration(milliseconds: 400)
        ? duration - const Duration(milliseconds: 400)
        : duration;
    _latestPosition = seekTarget;
    unawaited(player.seek(seekTarget));
    _showMessage('已自动跳过片尾');
  }

  void _syncSkipFlagsWithCurrentPosition() {
    final preference = _seriesSkipPreference;
    if (preference == null || !preference.enabled) {
      _introSkipApplied = true;
      _outroSkipApplied = true;
      return;
    }

    _introSkipApplied = preference.introDuration <= Duration.zero ||
        _latestPosition >= preference.introDuration;
    if (_latestDuration <= Duration.zero ||
        preference.outroDuration <= Duration.zero) {
      _outroSkipApplied = false;
      return;
    }
    _outroSkipApplied =
        (_latestDuration - _latestPosition) <= preference.outroDuration;
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
    final uri = Uri.file(resolvedPath).toString();
    await _runPlayerCommand(
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
    _syncSkipFlagsWithCurrentPosition();
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

  Future<_StartupProbeResult> _probeStartup(PlaybackTarget target) async {
    if (!_startupProbeEnabled) {
      return const _StartupProbeResult();
    }
    final streamUrl = isLoopbackPlaybackRelayUrl(target.streamUrl)
        ? target.actualAddress.trim()
        : target.streamUrl.trim();
    if (streamUrl.isEmpty) {
      return const _StartupProbeResult();
    }

    final uri = Uri.tryParse(streamUrl);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return const _StartupProbeResult();
    }

    final client = StarflowHttpClient(http.Client());
    StreamSubscription<List<int>>? subscription;
    final completer = Completer<_StartupProbeResult>();
    final stopwatch = Stopwatch();
    var completed = false;
    var bytesRead = 0;

    Future<void> finish() async {
      if (completed) {
        return;
      }
      completed = true;
      stopwatch.stop();
      await subscription?.cancel();
      client.close();

      final elapsedSeconds = stopwatch.elapsedMilliseconds <= 0
          ? 0.0
          : stopwatch.elapsedMilliseconds / 1000;
      final speedBytesPerSecond = elapsedSeconds <= 0 || bytesRead <= 0
          ? null
          : (bytesRead / elapsedSeconds).round();

      completer.complete(
        _StartupProbeResult(
          estimatedSpeedBytesPerSecond: speedBytesPerSecond,
        ),
      );
    }

    try {
      final request = http.Request('GET', uri)
        ..headers.addAll(target.headers)
        ..headers['Range'] = 'bytes=0-262143';
      stopwatch.start();
      final response = await client.send(request).timeout(
            const Duration(seconds: 4),
          );

      subscription = response.stream.listen(
        (chunk) {
          bytesRead += chunk.length;
          if (bytesRead >= 192 * 1024 ||
              stopwatch.elapsedMilliseconds >= 1400) {
            unawaited(finish());
          }
        },
        onError: (_) {
          unawaited(finish());
        },
        onDone: () {
          unawaited(finish());
        },
        cancelOnError: true,
      );

      return completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () async {
          await finish();
          return completer.future;
        },
      );
    } catch (_) {
      await subscription?.cancel();
      client.close();
      return const _StartupProbeResult();
    }
  }
}
