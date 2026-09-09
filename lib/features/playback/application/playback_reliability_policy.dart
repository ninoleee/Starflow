import 'playback_policy_values.dart';

export 'playback_policy_values.dart';

enum PlaybackFailureKind { transientNetwork, permanent, unknown }

PlaybackFailureKind classifyPlaybackHttpStatus(int? status) {
  if (PlaybackPolicyValues.transientHttpStatuses.contains(status) ||
      (status != null && status >= 500 && status <= 599)) {
    return PlaybackFailureKind.transientNetwork;
  }
  if (PlaybackPolicyValues.permanentHttpStatuses.contains(status)) {
    return PlaybackFailureKind.permanent;
  }
  return PlaybackFailureKind.unknown;
}

bool isPlaybackAddressRefreshable(int? status) =>
    PlaybackPolicyValues.refreshableHttpStatuses.contains(status);

enum PlaybackPhase {
  preparing,
  playing,
  paused,
  buffering,
  recovering,
  ended,
  failed
}

PlaybackPhase resolvePlaybackPhase({
  required bool ready,
  required bool playing,
  required bool buffering,
  bool recovering = false,
  bool ended = false,
  bool failed = false,
}) {
  if (failed) return PlaybackPhase.failed;
  if (ended) return PlaybackPhase.ended;
  if (recovering) return PlaybackPhase.recovering;
  if (!ready) return PlaybackPhase.preparing;
  if (buffering) return PlaybackPhase.buffering;
  return playing ? PlaybackPhase.playing : PlaybackPhase.paused;
}

extension PlaybackPhasePresentation on PlaybackPhase {
  bool get showsLoading => switch (this) {
        PlaybackPhase.preparing ||
        PlaybackPhase.buffering ||
        PlaybackPhase.recovering =>
          true,
        _ => false,
      };
}

/// Kept by the playback session, not the disposable engine instance.
class PlaybackRecoveryBudget {
  int _attempts = 0;
  int get attempts => _attempts;

  bool take() {
    if (_attempts >= PlaybackPolicyValues.maxRuntimeRecoveries) return false;
    _attempts++;
    return true;
  }

  void reset() => _attempts = 0;
}
