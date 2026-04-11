import 'package:flutter_riverpod/flutter_riverpod.dart';

AsyncValue<T> resolveRetainedAsyncValue<T>({
  required AsyncValue<T>? activeValue,
  required AsyncValue<T>? cachedValue,
  required void Function(AsyncValue<T> value) cacheValue,
  required AsyncValue<T> fallbackValue,
}) {
  if (activeValue == null) {
    return cachedValue ?? fallbackValue;
  }
  if (activeValue.hasValue || activeValue.hasError) {
    cacheValue(activeValue);
    return activeValue;
  }
  return cachedValue ?? activeValue;
}
