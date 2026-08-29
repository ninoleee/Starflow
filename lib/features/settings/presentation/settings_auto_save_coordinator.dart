import 'dart:async';

class SettingsAutoSaveCoordinator {
  SettingsAutoSaveCoordinator({
    this.delay = const Duration(milliseconds: 250),
  });

  final Duration delay;
  Timer? _timer;
  Future<void> _saveTail = Future<void>.value();
  String? _savedFingerprint;
  String? _desiredFingerprint;
  String? _pendingFingerprint;
  Future<void> Function()? _pendingSave;
  int _queuedSaveCount = 0;
  bool _disposed = false;

  void markCurrentAsSaved(String fingerprint) {
    _savedFingerprint = fingerprint;
    _desiredFingerprint = fingerprint;
  }

  void schedule({
    required String fingerprint,
    required Future<void> Function() save,
  }) {
    if (_disposed || fingerprint == _desiredFingerprint) {
      return;
    }
    _timer?.cancel();
    if (fingerprint == _savedFingerprint && _queuedSaveCount == 0) {
      _desiredFingerprint = fingerprint;
      _pendingFingerprint = null;
      _pendingSave = null;
      return;
    }
    _desiredFingerprint = fingerprint;
    _pendingFingerprint = fingerprint;
    _pendingSave = save;
    _timer = Timer(delay, _enqueuePendingSave);
  }

  void flush({
    required String fingerprint,
    required Future<void> Function() save,
  }) {
    if (_disposed ||
        (fingerprint == _desiredFingerprint && _pendingSave == null)) {
      return;
    }
    _timer?.cancel();
    _desiredFingerprint = fingerprint;
    _pendingFingerprint = fingerprint;
    _pendingSave = save;
    _enqueuePendingSave();
  }

  void _enqueuePendingSave() {
    _timer?.cancel();
    _timer = null;
    final fingerprint = _pendingFingerprint;
    final save = _pendingSave;
    _pendingFingerprint = null;
    _pendingSave = null;
    if (fingerprint == null || save == null) {
      return;
    }
    _queuedSaveCount += 1;
    _saveTail = _saveTail.then((_) async {
      try {
        await save();
        _savedFingerprint = fingerprint;
      } catch (_) {
        // SettingsController records persistence failures in the structured log.
        // Keep the queue alive so a later edit can retry with a new snapshot.
        if (_desiredFingerprint == fingerprint) {
          _desiredFingerprint = _savedFingerprint;
        }
      } finally {
        _queuedSaveCount -= 1;
      }
    });
  }

  void cancelPending() {
    _timer?.cancel();
    _timer = null;
    _pendingFingerprint = null;
    _pendingSave = null;
    _desiredFingerprint = _savedFingerprint;
  }

  Future<void> drain() async {
    _enqueuePendingSave();
    await _saveTail;
  }

  void dispose() {
    _disposed = true;
    cancelPending();
  }
}
