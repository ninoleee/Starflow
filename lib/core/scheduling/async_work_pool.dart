import 'dart:async';
import 'dart:collection';

/// Slots belong to the operation, not to the lifetime of the calling widget.
class AsyncWorkPool {
  AsyncWorkPool(this.capacity) : assert(capacity > 0);

  final int capacity;
  final Queue<Completer<void>> _waiting = Queue();
  int _active = 0;

  Future<T> run<T>(Future<T> Function() operation) async {
    if (_active >= capacity) {
      final ready = Completer<void>();
      _waiting.add(ready);
      await ready.future;
    } else {
      _active++;
    }
    try {
      return await operation();
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _active--;
      }
    }
  }
}
