import 'dart:collection';

/// Retains recent lookups without extending an unbounded session heap.
class BoundedMemoryMap<K, V> extends MapBase<K, V> {
  BoundedMemoryMap(this.capacity) : assert(capacity > 0);

  final int capacity;
  final LinkedHashMap<K, V> _values = LinkedHashMap();

  @override
  V? operator [](Object? key) {
    if (!_values.containsKey(key)) return null;
    final value = _values.remove(key) as V;
    _values[key as K] = value;
    return value;
  }

  @override
  void operator []=(K key, V value) {
    _values.remove(key);
    _values[key] = value;
    while (_values.length > capacity) {
      _values.remove(_values.keys.first);
    }
  }

  @override
  bool containsKey(Object? key) => _values.containsKey(key);

  @override
  Iterable<K> get keys => List<K>.of(_values.keys, growable: false);

  @override
  V? remove(Object? key) => _values.remove(key);

  @override
  void clear() => _values.clear();
}
