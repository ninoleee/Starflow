import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/navigation/retained_async_value.dart';

class RetainedAsyncController<T> {
  AsyncValue<T>? _cachedValue;

  AsyncValue<T>? get cachedValue => _cachedValue;

  void clear() {
    _cachedValue = null;
  }

  AsyncValue<T> resolve({
    required AsyncValue<T>? activeValue,
    required AsyncValue<T> fallbackValue,
  }) {
    return resolveRetainedAsyncValue(
      activeValue: activeValue,
      cachedValue: _cachedValue,
      cacheValue: (value) => _cachedValue = value,
      fallbackValue: fallbackValue,
    );
  }
}
