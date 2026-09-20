import 'dart:async';

import '../domain/playback_models.dart';
import 'playback_auto_skip_policy.dart';

typedef PlaybackEpisodeResolver = Future<PlaybackTarget> Function();

class PlaybackEpisodePreparationResult {
  const PlaybackEpisodePreparationResult({
    required this.target,
    required this.wasPrepared,
  });

  final PlaybackTarget target;

  /// True for both completed preparation and a promoted background request.
  /// The caller can refresh an expired playback address using its original
  /// source target, which must be retained separately from [target].
  final bool wasPrepared;
}

/// Address-only preparation, with no player or automatic-navigation ownership.
///
/// Keys must bind the queue, current target and settings session. Each key gets
/// at most one background attempt and one foreground attempt until [reset].
/// Promotion counts as that foreground attempt and never starts another request.
/// Cancel automatic intent in the caller, not here: a resolved address can still
/// be cached while the caller's intent token prevents navigation.
class PlaybackEpisodePreparation {
  PlaybackEpisodePreparation({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Map<Object, _EpisodeEntry> _entries = {};

  /// Safe to leave unawaited: background failure and reset are absorbed.
  Future<void> prepare({
    required Object key,
    required PlaybackEpisodeResolver resolver,
  }) async {
    final entry = _entries.putIfAbsent(key, _EpisodeEntry.new);
    if (entry.backgroundStarted || entry.foregroundStarted) return;
    entry.backgroundStarted = true;
    final request = _start(entry, resolver, wasPrepared: true);
    await request.completion.future;
  }

  /// Reuses a fresh address or the in-flight request. An expired or previously
  /// failed background attempt permits one fresh foreground resolution.
  /// Only an explicit manual action may set [retryFailed] to retry a failed or
  /// expired foreground result. In-flight requests are still shared.
  Future<PlaybackEpisodePreparationResult> resolve({
    required Object key,
    required PlaybackEpisodeResolver resolver,
    bool retryFailed = false,
  }) async {
    final entry = _entries.putIfAbsent(key, _EpisodeEntry.new);
    var request = entry.request;
    if (request != null &&
        !request.completion.isCompleted &&
        !_clock().isBefore(request.deadline)) {
      _expire(request);
    }
    final outcome = request?.outcome;
    final age = outcome?.resolvedAt == null
        ? null
        : _clock().difference(outcome!.resolvedAt!);
    if (outcome?.target != null &&
        age != null &&
        !age.isNegative &&
        age < kPlaybackPreparedEpisodeTtl) {
      return PlaybackEpisodePreparationResult(
        target: outcome!.target!,
        wasPrepared: request!.wasPrepared,
      );
    }

    if (request != null && !request.completion.isCompleted) {
      if (request.wasPrepared && !entry.foregroundStarted) {
        entry.foregroundStarted = true;
        // Only the first foreground consumer establishes the promotion deadline.
        _armDeadline(request);
      }
    } else if (!entry.foregroundStarted) {
      entry.foregroundStarted = true;
      request = _start(entry, resolver, wasPrepared: false);
    } else if (retryFailed) {
      request = _start(entry, resolver, wasPrepared: false);
    } else if (outcome?.error != null) {
      Error.throwWithStackTrace(outcome!.error!, outcome.stackTrace!);
    } else {
      throw TimeoutException(
        'Episode address expired; reset the preparation session to retry.',
        kPlaybackPreparedEpisodeTtl,
      );
    }

    final resolved = await request.completion.future;
    if (resolved.error != null) {
      Error.throwWithStackTrace(resolved.error!, resolved.stackTrace!);
    }
    return PlaybackEpisodePreparationResult(
      target: resolved.target!,
      wasPrepared: request.wasPrepared,
    );
  }

  /// Invalidates the session, settles waiters and cancels deadline timers.
  /// Resolver futures cannot be cancelled, but their late results are ignored.
  void reset() {
    for (final entry in _entries.values) {
      final request = entry.request;
      if (request != null && !request.completion.isCompleted) {
        _finish(
          request,
          _EpisodeOutcome.failure(
            StateError('Episode preparation session was reset.'),
            StackTrace.current,
          ),
        );
      }
    }
    _entries.clear();
  }

  _EpisodeRequest _start(
    _EpisodeEntry entry,
    PlaybackEpisodeResolver resolver, {
    required bool wasPrepared,
  }) {
    final request = _EpisodeRequest(wasPrepared: wasPrepared);
    entry.request = request;
    _armDeadline(request);
    // Internal futures always settle with a value, so an abandoned background
    // attempt or late resolver failure cannot become an unhandled async error.
    unawaited(Future<PlaybackTarget>.sync(resolver).then<void>(
      (target) {
        if (request.completion.isCompleted) return;
        if (!_clock().isBefore(request.deadline)) {
          _expire(request);
          return;
        }
        _finish(request, _EpisodeOutcome.success(target, _clock()));
      },
      onError: (Object error, StackTrace stackTrace) {
        _finish(request, _EpisodeOutcome.failure(error, stackTrace));
      },
    ));
    return request;
  }

  void _armDeadline(_EpisodeRequest request) {
    request.timer?.cancel();
    request.deadline = _clock().add(kPlaybackEpisodeResolveTimeout);
    request.timer =
        Timer(kPlaybackEpisodeResolveTimeout, () => _expire(request));
  }

  void _expire(_EpisodeRequest request) {
    _finish(
      request,
      _EpisodeOutcome.failure(
        TimeoutException(
          'Episode address resolution timed out.',
          kPlaybackEpisodeResolveTimeout,
        ),
        StackTrace.current,
      ),
    );
  }

  void _finish(_EpisodeRequest request, _EpisodeOutcome outcome) {
    if (request.completion.isCompleted) return;
    request.timer?.cancel();
    request.timer = null;
    request.outcome = outcome;
    request.completion.complete(outcome);
  }
}

class _EpisodeEntry {
  bool backgroundStarted = false;
  bool foregroundStarted = false;
  _EpisodeRequest? request;
}

class _EpisodeRequest {
  _EpisodeRequest({required this.wasPrepared});

  final bool wasPrepared;
  final Completer<_EpisodeOutcome> completion = Completer<_EpisodeOutcome>();
  Timer? timer;
  late DateTime deadline;
  _EpisodeOutcome? outcome;
}

class _EpisodeOutcome {
  _EpisodeOutcome.success(PlaybackTarget this.target, DateTime this.resolvedAt)
      : error = null,
        stackTrace = null;

  _EpisodeOutcome.failure(Object this.error, StackTrace this.stackTrace)
      : target = null,
        resolvedAt = null;

  final PlaybackTarget? target;
  final DateTime? resolvedAt;
  final Object? error;
  final StackTrace? stackTrace;
}
