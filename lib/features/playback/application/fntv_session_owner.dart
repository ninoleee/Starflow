import 'package:starflow/features/playback/domain/playback_models.dart';

/// Owns active and pending sessions, including results arriving after exit.
class FntvSessionOwner {
  FntvSessionOwner(this.releaseSession);

  final Future<void> Function(PlaybackTarget) releaseSession;
  final Map<String, PlaybackTarget> _sessions = {};
  bool _closed = false;

  String _key(PlaybackTarget target) =>
      '${target.sourceId}\n${target.fntvSessionLink}';

  Future<void> retain(PlaybackTarget target) async {
    if (!target.isFntvTranscoding) return;
    if (_closed) {
      await _release(target);
    } else {
      _sessions[_key(target)] = target;
    }
  }

  Future<void> release(PlaybackTarget target) async {
    final owned = _sessions.remove(_key(target));
    if (owned != null) await _release(owned);
  }

  Future<void> _release(PlaybackTarget target) async {
    try {
      await releaseSession(target);
    } catch (_) {
      // The protocol client logs a sanitized failure; exit must still finish.
    }
  }

  Future<void> close() async {
    _closed = true;
    final targets = _sessions.values.toList();
    _sessions.clear();
    await Future.wait(targets.map(_release));
  }
}
