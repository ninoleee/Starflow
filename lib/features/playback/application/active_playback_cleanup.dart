import 'dart:async';

typedef ActivePlaybackCleanupCallback = Future<void> Function(String reason);

class ActivePlaybackCleanupCoordinator {
  ActivePlaybackCleanupCoordinator._();

  static final Map<int, ActivePlaybackCleanupCallback> _callbacks =
      <int, ActivePlaybackCleanupCallback>{};
  static Future<void> _cleanupQueue = Future<void>.value();
  static int _nextToken = 0;

  static int register(ActivePlaybackCleanupCallback callback) {
    final token = ++_nextToken;
    _callbacks[token] = callback;
    return token;
  }

  static void unregister(int token) {
    _callbacks.remove(token);
  }

  static Future<void> cleanupAll({
    required String reason,
    int? exceptToken,
  }) async {
    final cleanup = _cleanupQueue.then((_) async {
      final callbacks = _callbacks.entries.toList(growable: false);
      for (final entry in callbacks) {
        if (exceptToken != null && entry.key == exceptToken) {
          continue;
        }
        final callback = _callbacks[entry.key];
        if (callback == null) {
          continue;
        }
        try {
          await callback(reason);
        } catch (_) {
          // Cleanup should be best-effort. A failed old session must not block
          // the next cleanup or the next playback request.
        }
      }
    });
    _cleanupQueue = cleanup.catchError((_) {});
    await cleanup;
  }
}
