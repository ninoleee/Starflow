import 'dart:async';

import 'mpv_subtitle_session.dart';

/// Resources for one installed MPV player, never for its replacement.
/// Startup deadlines and page-wide recovery budgets have separate owners.
class MpvPlaybackLifecycle {
  final subtitles = MpvSubtitleSession();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _closed = false;
  Future<void>? _closing;

  bool get isClosed => _closed;

  void retain(StreamSubscription<dynamic> subscription) {
    if (_closed) {
      unawaited(subscription.cancel());
    } else {
      _subscriptions.add(subscription);
    }
  }

  void listen<T>(Stream<T> stream, void Function(T) onData) {
    if (_closed) return;
    retain(stream.listen((value) {
      if (!_closed) onData(value);
    }));
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    final subscriptions = List.of(_subscriptions);
    _subscriptions.clear();
    // Start every cleanup even if another resource fails to release.
    return _closing = Future.wait<void>([
      subtitles.close(),
      for (final subscription in subscriptions)
        Future<void>.sync(subscription.cancel),
    ]);
  }
}
