/// Shared auto-skip and continuous-playback rules for the embedded MPV player.
///
/// The Android ExoPlayer container implements the same rules natively in
/// `NativePlaybackStartPolicy` / `NativePlaybackSkipPolicy`; keep both sides in
/// sync when the behavior changes.
library;

/// How long before the end boundary the adjacent episode may be resolved.
const Duration kPlaybackNextEpisodePrepareLead = Duration(seconds: 30);

/// How long a prepared episode address stays usable.
const Duration kPlaybackPreparedEpisodeTtl = Duration(seconds: 60);

/// Upper bound for one episode address resolution.
const Duration kPlaybackEpisodeResolveTimeout = Duration(seconds: 30);

class PlaybackStartPosition {
  const PlaybackStartPosition({
    required this.position,
    this.isResume = false,
    this.introPosition = Duration.zero,
  });

  final Duration position;
  final bool isResume;
  final Duration introPosition;

  bool get isIntroSkip => introPosition > Duration.zero;
}

/// Decides where playback starts before the first frame is shown.
///
/// An automatically advanced episode ignores its stale resume history and
/// applies the series intro rule; explicit "resume" and "play from start"
/// entries keep their own semantics.
PlaybackStartPosition resolvePlaybackStartPosition({
  required bool allowResume,
  required Duration resumePosition,
  required bool automaticNext,
  required bool skipEnabled,
  required Duration introDuration,
}) {
  if (!automaticNext) {
    if (!allowResume) {
      return const PlaybackStartPosition(position: Duration.zero);
    }
    if (resumePosition > Duration.zero) {
      return PlaybackStartPosition(position: resumePosition, isResume: true);
    }
  }
  final introPosition = skipEnabled && introDuration > Duration.zero
      ? introDuration
      : Duration.zero;
  return PlaybackStartPosition(
    position: introPosition,
    introPosition: introPosition,
  );
}

/// The position where the current episode is considered finished: the outro
/// skip point when the series rule applies, otherwise the natural end.
Duration resolvePlaybackEndBoundary({
  required Duration duration,
  required bool skipEnabled,
  required Duration outroDuration,
}) {
  if (skipEnabled &&
      outroDuration > Duration.zero &&
      outroDuration < duration) {
    return duration - outroDuration;
  }
  return duration;
}

/// Whether the adjacent episode may be resolved ahead of the boundary.
bool shouldPrepareNextEpisode({
  required Duration position,
  required Duration boundary,
}) {
  if (boundary <= Duration.zero) {
    return false;
  }
  final lead = boundary - kPlaybackNextEpisodePrepareLead;
  final threshold = lead > Duration.zero ? lead : Duration.zero;
  return position >= threshold && position < boundary;
}
