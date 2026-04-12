// ignore_for_file: invalid_use_of_protected_member

part of '../player_page.dart';

extension _PlayerPageStatePlatformSession on _PlayerPageState {
  Future<void> _bindPictureInPictureSupport() async {
    if (!AndroidPictureInPictureController.isSupportedPlatform) {
      return;
    }
    await AndroidPictureInPictureController.attach((enabled) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isInPictureInPictureMode = enabled;
      });
    });
    final supported = await AndroidPictureInPictureController.isSupported();
    if (!mounted) {
      return;
    }
    setState(() {
      _pictureInPictureSupported = supported;
    });
    if (supported && _isReady) {
      unawaited(_syncBackgroundPlayback(enabled: _isActivelyPlaying));
    }
  }

  Future<void> _teardownPictureInPicture() async {
    if (!AndroidPictureInPictureController.isSupportedPlatform) {
      await BackgroundPlaybackController.setEnabled(false);
      return;
    }
    await AndroidPictureInPictureController.setPlaybackEnabled(
      enabled: false,
      aspectRatioWidth: 16,
      aspectRatioHeight: 9,
    );
    await AndroidPictureInPictureController.detach();
    await BackgroundPlaybackController.setEnabled(false);
  }

  Future<void> _syncBackgroundPlayback({required bool enabled}) async {
    final shouldEnable = enabled && _backgroundPlaybackEnabled;
    if (_pictureInPictureSupported) {
      final size = _currentPictureInPictureAspectRatio();
      await AndroidPictureInPictureController.setPlaybackEnabled(
        enabled: shouldEnable,
        aspectRatioWidth: size.width,
        aspectRatioHeight: size.height,
      );
    }
    await BackgroundPlaybackController.setEnabled(shouldEnable);
  }

  Future<void> _bindPlaybackSystemSession() async {
    if (!PlaybackSystemSessionController.isSupportedPlatform ||
        _playbackSystemSessionBound) {
      return;
    }
    await PlaybackSystemSessionController.attach(_handlePlaybackRemoteCommand);
    _playbackSystemSessionBound = true;
  }

  Future<void> _teardownPlaybackSystemSession() async {
    if (PlaybackSystemSessionController.isSupportedPlatform) {
      await PlaybackSystemSessionController.setActive(false);
      await PlaybackSystemSessionController.detach();
    }
    _playbackSystemSessionBound = false;
  }

  Future<void> _syncPlaybackSystemSession({bool force = false}) async {
    if (!PlaybackSystemSessionController.isSupportedPlatform) {
      return;
    }

    final player = _player;
    if (!_isReady || player == null) {
      if (force) {
        await PlaybackSystemSessionController.setActive(false);
      }
      return;
    }

    final title = _buildPlaybackSystemSessionTitle();
    final subtitle = _buildPlaybackSystemSessionSubtitle();

    final state = PlaybackSystemSessionState(
      title: title,
      subtitle: subtitle,
      position: player.state.position,
      duration: player.state.duration,
      playing: player.state.playing,
      buffering: player.state.buffering,
      speed: player.state.rate,
      canSeek: true,
    );

    final positionChanged =
        (state.position - _lastPlaybackSystemSessionPosition).inSeconds != 0;
    final durationChanged =
        state.duration != _lastPlaybackSystemSessionDuration;
    final playingChanged = state.playing != _lastPlaybackSystemSessionPlaying;
    final bufferingChanged =
        state.buffering != _lastPlaybackSystemSessionBuffering;
    final titleChanged = title != _lastPlaybackSystemSessionTitle;
    final subtitleChanged = subtitle != _lastPlaybackSystemSessionSubtitle;

    if (!force &&
        !positionChanged &&
        !durationChanged &&
        !playingChanged &&
        !bufferingChanged &&
        !titleChanged &&
        !subtitleChanged) {
      return;
    }

    _lastPlaybackSystemSessionPosition = state.position;
    _lastPlaybackSystemSessionDuration = state.duration;
    _lastPlaybackSystemSessionPlaying = state.playing;
    _lastPlaybackSystemSessionBuffering = state.buffering;
    _lastPlaybackSystemSessionTitle = state.title;
    _lastPlaybackSystemSessionSubtitle = state.subtitle;

    await PlaybackSystemSessionController.setActive(true);
    await PlaybackSystemSessionController.update(state);
  }

  Future<void> _handlePlaybackRemoteCommand(
    PlaybackRemoteCommand command,
  ) async {
    switch (command.type) {
      case PlaybackRemoteCommandType.play:
        await _setPlayWhenReady(true);
        break;
      case PlaybackRemoteCommandType.pause:
      case PlaybackRemoteCommandType.stop:
      case PlaybackRemoteCommandType.becomingNoisy:
      case PlaybackRemoteCommandType.interruptionPause:
        await _setPlayWhenReady(false);
        await _persistPlaybackProgress(force: true);
        break;
      case PlaybackRemoteCommandType.toggle:
        await _togglePlayback();
        break;
      case PlaybackRemoteCommandType.seekForward:
      case PlaybackRemoteCommandType.next:
        await _seekRelative(_PlayerPageState._kSeekStep);
        break;
      case PlaybackRemoteCommandType.seekBackward:
      case PlaybackRemoteCommandType.previous:
        await _seekRelative(-_PlayerPageState._kSeekStep);
        break;
      case PlaybackRemoteCommandType.seekTo:
        final position = command.position;
        if (position != null) {
          await _seekTo(position);
        }
        break;
      case PlaybackRemoteCommandType.interruptionResume:
        await _setPlayWhenReady(true);
        break;
    }
  }

  _PictureInPictureAspectRatio _currentPictureInPictureAspectRatio() {
    final width = _player?.state.width ?? 0;
    final height = _player?.state.height ?? 0;
    if (width > 0 && height > 0) {
      return _PictureInPictureAspectRatio(width: width, height: height);
    }
    return const _PictureInPictureAspectRatio(width: 16, height: 9);
  }

  String _buildPlaybackSystemSessionTitle() {
    final target = _resolvedTarget ?? widget.target;
    final seasonNumber = target.seasonNumber;
    final episodeNumber = target.episodeNumber;
    if (target.isEpisode &&
        seasonNumber != null &&
        seasonNumber > 0 &&
        episodeNumber != null &&
        episodeNumber > 0) {
      return '${target.title} · S${seasonNumber.toString().padLeft(2, '0')}'
          'E${episodeNumber.toString().padLeft(2, '0')}';
    }
    return target.title.trim().isEmpty ? 'Starflow' : target.title.trim();
  }

  String _buildPlaybackSystemSessionSubtitle() {
    final target = _resolvedTarget ?? widget.target;
    if (target.isEpisode) {
      final seriesTitle = target.resolvedSeriesTitle.trim();
      if (seriesTitle.isNotEmpty) {
        return seriesTitle;
      }
    }
    final parts = <String>[
      if (target.sourceName.trim().isNotEmpty) target.sourceName.trim(),
      if (target.formatLabel.trim().isNotEmpty) target.formatLabel.trim(),
    ];
    return parts.join(' · ');
  }
}
