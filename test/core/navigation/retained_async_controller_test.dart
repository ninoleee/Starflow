import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/navigation/retained_async_controller.dart';

void main() {
  group('RetainedAsyncController', () {
    test('retains resolved value while inactive', () {
      final controller = RetainedAsyncController<int>();

      final active = controller.resolve(
        activeValue: const AsyncData<int>(7),
        fallbackValue: const AsyncLoading<int>(),
      );
      final inactive = controller.resolve(
        activeValue: null,
        fallbackValue: const AsyncLoading<int>(),
      );

      expect(active.valueOrNull, 7);
      expect(inactive.valueOrNull, 7);
    });

    test('retains error while inactive', () {
      final controller = RetainedAsyncController<int>();
      final error = AsyncError<int>('boom', StackTrace.empty);

      final active = controller.resolve(
        activeValue: error,
        fallbackValue: const AsyncLoading<int>(),
      );
      final inactive = controller.resolve(
        activeValue: null,
        fallbackValue: const AsyncLoading<int>(),
      );

      expect(identical(active, error), isTrue);
      expect(identical(inactive, error), isTrue);
    });

    test('clears cached value explicitly', () {
      final controller = RetainedAsyncController<int>();

      controller.resolve(
        activeValue: const AsyncData<int>(3),
        fallbackValue: const AsyncLoading<int>(),
      );
      controller.clear();
      final resolved = controller.resolve(
        activeValue: null,
        fallbackValue: const AsyncLoading<int>(),
      );

      expect(resolved, isA<AsyncLoading<int>>());
      expect(controller.cachedValue, isNull);
    });
  });
}
