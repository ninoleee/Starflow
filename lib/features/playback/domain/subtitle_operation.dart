import 'dart:async';

class SubtitleOperationCancelled implements Exception {
  const SubtitleOperationCancelled();

  @override
  String toString() => 'Subtitle operation cancelled';
}

/// One search/download owns its cancellation, never the shared HTTP client.
class SubtitleOperation {
  final _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }

  void throwIfCancelled() {
    if (isCancelled) throw const SubtitleOperationCancelled();
  }
}
