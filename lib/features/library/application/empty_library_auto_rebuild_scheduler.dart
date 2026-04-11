import 'dart:async';

typedef EmptyLibraryAutoRebuildTask = Future<void> Function();

class EmptyLibraryAutoRebuildScheduler {
  final Map<String, Future<void>> _inFlightByScope = <String, Future<void>>{};
  final Set<String> _attemptedScopes = <String>{};

  bool schedule({
    required String scopeKey,
    required EmptyLibraryAutoRebuildTask task,
  }) {
    final normalizedScopeKey = scopeKey.trim();
    if (normalizedScopeKey.isEmpty) {
      return false;
    }
    if (_attemptedScopes.contains(normalizedScopeKey)) {
      return false;
    }
    if (_inFlightByScope.containsKey(normalizedScopeKey)) {
      return false;
    }

    _attemptedScopes.add(normalizedScopeKey);
    final future = Future<void>(() async {
      var shouldKeepAttemptLock = true;
      try {
        await task();
      } catch (_) {
        // Best-effort background task: read path should not fail because of this.
        shouldKeepAttemptLock = false;
      } finally {
        _inFlightByScope.remove(normalizedScopeKey);
        if (!shouldKeepAttemptLock) {
          _attemptedScopes.remove(normalizedScopeKey);
        }
      }
    });
    _inFlightByScope[normalizedScopeKey] = future;
    unawaited(future);
    return true;
  }

  void markScopeHealthy(String scopeKey) {
    final normalizedScopeKey = scopeKey.trim();
    if (normalizedScopeKey.isEmpty) {
      return;
    }
    _attemptedScopes.remove(normalizedScopeKey);
  }
}
