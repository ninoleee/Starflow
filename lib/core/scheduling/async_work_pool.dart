import 'dart:async';
import 'dart:collection';

/// Slots belong to the operation, not to the lifetime of the calling widget.
class AsyncWorkPool {
  AsyncWorkPool(int capacity)
      : _capacity = capacity,
        assert(capacity > 0);

  int _capacity;
  int get capacity => _capacity;
  set capacity(int value) {
    if (value < 1) throw ArgumentError.value(value, 'capacity');
    _capacity = value;
    _admitWaiting();
  }

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
      _active--;
      _admitWaiting();
    }
  }

  void _admitWaiting() {
    while (_active < capacity && _waiting.isNotEmpty) {
      _active++;
      _waiting.removeFirst().complete();
    }
  }
}
