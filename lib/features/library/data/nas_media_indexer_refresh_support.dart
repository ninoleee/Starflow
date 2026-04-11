part of 'nas_media_indexer.dart';

class NasMediaIndexerConcurrencyLimits {
  const NasMediaIndexerConcurrencyLimits({
    this.sourceRefreshConcurrency = 1,
    this.collectionRefreshConcurrency = 2,
    this.enrichmentConcurrency = 2,
  });

  final int sourceRefreshConcurrency;
  final int collectionRefreshConcurrency;
  final int enrichmentConcurrency;

  int get normalizedSourceRefreshConcurrency =>
      sourceRefreshConcurrency < 1 ? 1 : sourceRefreshConcurrency;

  int get normalizedCollectionRefreshConcurrency =>
      collectionRefreshConcurrency < 1 ? 1 : collectionRefreshConcurrency;

  int get normalizedEnrichmentConcurrency =>
      enrichmentConcurrency < 1 ? 1 : enrichmentConcurrency;
}

class _RefreshPhaseResult {
  const _RefreshPhaseResult({
    required this.enrichmentCandidates,
  });

  final List<WebDavScannedItem> enrichmentCandidates;
}

enum _RefreshTaskMode {
  incremental,
  forceFull,
}

class _RefreshTaskHandle {
  const _RefreshTaskHandle({
    required this.future,
    required this.mode,
    required this.controller,
  });

  final Future<void> future;
  final _RefreshTaskMode mode;
  final _RefreshTaskController controller;

  void cancel() {
    controller.cancel();
  }
}

class _RefreshTaskController {
  bool _isCancelled = false;

  bool get cancelled => _isCancelled;

  bool Function() get isCancelled => () => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }

  void throwIfCancelled() {
    if (_isCancelled) {
      throw const _RefreshCancelledException();
    }
  }
}

class _RefreshCancelledException implements Exception {
  const _RefreshCancelledException();
}

class _ConcurrencyBudget {
  _ConcurrencyBudget(int maxParallelism)
      : _maxParallelism = maxParallelism < 1 ? 1 : maxParallelism;

  final int _maxParallelism;
  int _inFlight = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  Future<T> withPermit<T>(Future<T> Function() action) async {
    await _acquire();
    try {
      return await action();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() async {
    if (_inFlight < _maxParallelism) {
      _inFlight += 1;
      return;
    }
    final waiter = Completer<void>();
    _waiters.addLast(waiter);
    await waiter.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      final waiter = _waiters.removeFirst();
      if (!waiter.isCompleted) {
        waiter.complete();
      }
      return;
    }
    if (_inFlight > 0) {
      _inFlight -= 1;
    }
  }
}
