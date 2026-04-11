import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/navigation/retained_async_value.dart';

void main() {
  group('resolveRetainedAsyncValue', () {
    test('returns cached value when page is inactive', () {
      final resolved = resolveRetainedAsyncValue<int>(
        activeValue: null,
        cachedValue: const AsyncData<int>(7),
        cacheValue: (_) {},
        fallbackValue: const AsyncLoading<int>(),
      );

      expect(resolved.valueOrNull, 7);
    });

    test('returns fallback value when page is inactive and cache is empty', () {
      final resolved = resolveRetainedAsyncValue<int>(
        activeValue: null,
        cachedValue: null,
        cacheValue: (_) {},
        fallbackValue: const AsyncLoading<int>(),
      );

      expect(resolved, isA<AsyncLoading<int>>());
    });

    test('caches active value once data resolves', () {
      AsyncValue<int>? cached;
      final active = const AsyncData<int>(42);

      final resolved = resolveRetainedAsyncValue<int>(
        activeValue: active,
        cachedValue: null,
        cacheValue: (value) => cached = value,
        fallbackValue: const AsyncLoading<int>(),
      );

      expect(identical(resolved, active), isTrue);
      expect(cached?.valueOrNull, 42);
    });

    test('returns active loading when cache is empty and request is loading',
        () {
      var cacheWriteCount = 0;
      const active = AsyncLoading<int>();

      final resolved = resolveRetainedAsyncValue<int>(
        activeValue: active,
        cachedValue: null,
        cacheValue: (_) => cacheWriteCount += 1,
        fallbackValue: const AsyncData<int>(9),
      );

      expect(identical(resolved, active), isTrue);
      expect(cacheWriteCount, 0);
    });

    test('caches active error once request fails', () {
      AsyncValue<int>? cached;
      final active = AsyncError<int>('boom', StackTrace.empty);

      final resolved = resolveRetainedAsyncValue<int>(
        activeValue: active,
        cachedValue: null,
        cacheValue: (value) => cached = value,
        fallbackValue: const AsyncLoading<int>(),
      );

      expect(identical(resolved, active), isTrue);
      expect(identical(cached, active), isTrue);
    });

    test('overwrites cached data when active request fails', () {
      AsyncValue<int>? cached = const AsyncData<int>(3);
      final active = AsyncError<int>('boom', StackTrace.empty);

      final resolved = resolveRetainedAsyncValue<int>(
        activeValue: active,
        cachedValue: cached,
        cacheValue: (value) => cached = value,
        fallbackValue: const AsyncLoading<int>(),
      );

      expect(identical(resolved, active), isTrue);
      expect(identical(cached, active), isTrue);
    });

    test('uses cached value while active request is loading', () {
      var cacheWriteCount = 0;
      final resolved = resolveRetainedAsyncValue<int>(
        activeValue: const AsyncLoading<int>(),
        cachedValue: const AsyncData<int>(5),
        cacheValue: (_) => cacheWriteCount += 1,
        fallbackValue: const AsyncLoading<int>(),
      );

      expect(resolved.valueOrNull, 5);
      expect(cacheWriteCount, 0);
    });
  });
}
