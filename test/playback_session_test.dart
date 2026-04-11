import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/application/playback_session.dart';

void main() {
  group('background work suspension providers', () {
    test('default state keeps all dimensions enabled', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(backgroundAnimationsSuspendedProvider), isFalse);
      expect(container.read(backgroundImageLoadingSuspendedProvider), isFalse);
      expect(container.read(backgroundEnrichmentSuspendedProvider), isFalse);
      expect(container.read(backgroundWorkSuspendedProvider), isFalse);
    });

    test('playback performance mode suspends all dimensions', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(playbackPerformanceModeProvider.notifier).state = true;

      expect(container.read(backgroundAnimationsSuspendedProvider), isTrue);
      expect(container.read(backgroundImageLoadingSuspendedProvider), isTrue);
      expect(container.read(backgroundEnrichmentSuspendedProvider), isTrue);
      expect(container.read(backgroundWorkSuspendedProvider), isTrue);
    });
  });
}
