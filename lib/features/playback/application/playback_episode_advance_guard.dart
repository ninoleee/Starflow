/// An opaque ownership token for one episode resolution and switch.
final class PlaybackEpisodeAdvanceRequest {
  const PlaybackEpisodeAdvanceRequest._({
    required this.generation,
    required this.key,
    required this.automatic,
  });

  final int generation;
  final String key;
  final bool automatic;
}

/// Fences asynchronous episode resolution without cancelling its underlying I/O.
///
/// Check [isCurrent] after awaits and [commit] immediately before the first
/// switching side effect, without an intervening await. Always [finish] in a
/// finally block using the same token. A committed switch retains ownership
/// until finished, including across cancellation and reset attempts.
final class PlaybackEpisodeAdvanceGuard {
  final Set<String> _automaticFailures = <String>{};
  int _generation = 0;
  PlaybackEpisodeAdvanceRequest? _active;
  bool _committed = false;

  bool get isActive => _active != null;
  bool get isSwitching => _committed;

  /// Returns null if busy or if this automatic key already failed.
  ///
  /// Use a stable key identifying the source episode and intended destination
  /// (including direction). Manual requests bypass automatic failure dedupe
  /// and may replace a pending automatic request, but never another manual one.
  PlaybackEpisodeAdvanceRequest? begin({
    required String key,
    required bool automatic,
  }) {
    if (automatic && _automaticFailures.contains(key)) return null;
    final active = _active;
    if (active != null && (_committed || automatic || !active.automatic)) {
      return null;
    }
    final request = PlaybackEpisodeAdvanceRequest._(
      generation: ++_generation,
      key: key,
      automatic: automatic,
    );
    _active = request;
    return request;
  }

  /// Identity, not just generation, prevents tokens from other guards matching.
  bool isCurrent(PlaybackEpisodeAdvanceRequest request) =>
      identical(_active, request);

  /// Claims the non-cancellable switch phase exactly once.
  bool commit(PlaybackEpisodeAdvanceRequest request) {
    if (!isCurrent(request) || _committed) return false;
    _committed = true;
    return true;
  }

  /// Invalidates only an automatic request still resolving its destination.
  ///
  /// Call for intentional pause, manual seek, or relevant preference changes.
  /// The caller must distinguish intentional cancellation from natural EOF:
  /// a `playing == false` notification alone is NOT a reason to call this.
  /// Cancellation does not count as an automatic failure or prevent a retry.
  bool invalidateAutomaticPending() {
    if (_active?.automatic != true || _committed) return false;
    _active = null;
    return true;
  }

  /// Releases only this token's operation; stale finally blocks are harmless.
  ///
  /// Set [failed] for resolution errors, no usable destination, or switch
  /// failures. Only current automatic failures are deduped until [reset].
  /// Returns false for an obsolete token, including duplicate completion.
  bool finish(PlaybackEpisodeAdvanceRequest request, {bool failed = false}) {
    if (!isCurrent(request)) return false;
    if (failed && request.automatic) _automaticFailures.add(request.key);
    _active = null;
    _committed = false;
    return true;
  }

  /// Starts a fresh playback scope, invalidating pending work and failure keys.
  ///
  /// Returns false without changing anything while a switch is committed.
  /// Finish that switch before resetting; reset cannot unlock ongoing side
  /// effects. Generations are never reused, even across successful resets.
  bool reset() {
    if (_committed) return false;
    _active = null;
    _automaticFailures.clear();
    return true;
  }
}
