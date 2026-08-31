part of 'nas_media_indexer.dart';

class NasMediaIndexerConcurrencyLimits {
  const NasMediaIndexerConcurrencyLimits({
    this.sourceRefreshConcurrency = 1,
    this.collectionRefreshConcurrency = 1,
    this.enrichmentConcurrency = 1,
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
  _RefreshTaskController({bool Function()? isExternallyCancelled})
      : _isExternallyCancelled = isExternallyCancelled;

  bool _isCancelled = false;
  final bool Function()? _isExternallyCancelled;

  bool get cancelled =>
      _isCancelled || (_isExternallyCancelled?.call() ?? false);

  bool Function() get isCancelled => () => cancelled;

  void cancel() {
    _isCancelled = true;
  }

  void throwIfCancelled() {
    if (cancelled) {
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

  int _maxParallelism;
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

  void updateMaxParallelism(int maxParallelism) {
    _maxParallelism = maxParallelism < 1 ? 1 : maxParallelism;
    _drainWaiters();
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
    if (_inFlight > 0) {
      _inFlight -= 1;
    }
    _drainWaiters();
  }

  void _drainWaiters() {
    while (_inFlight < _maxParallelism && _waiters.isNotEmpty) {
      final waiter = _waiters.removeFirst();
      if (waiter.isCompleted) {
        continue;
      }
      _inFlight += 1;
      waiter.complete();
    }
  }
}
