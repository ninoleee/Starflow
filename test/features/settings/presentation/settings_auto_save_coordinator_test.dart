import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/settings/presentation/settings_auto_save_coordinator.dart';

void main() {
  test('auto-save coalesces pending edits to the latest snapshot', () async {
    final coordinator = SettingsAutoSaveCoordinator(
      delay: const Duration(milliseconds: 20),
    );
    addTearDown(coordinator.dispose);
    coordinator.markCurrentAsSaved('initial');
    final saved = <String>[];

    coordinator.schedule(
      fingerprint: 'first',
      save: () async => saved.add('first'),
    );
    coordinator.schedule(
      fingerprint: 'latest',
      save: () async => saved.add('latest'),
    );

    await Future<void>.delayed(const Duration(milliseconds: 35));
    await coordinator.drain();

    expect(saved, ['latest']);
  });

  test('flush persists the latest snapshot without waiting for debounce',
      () async {
    final coordinator = SettingsAutoSaveCoordinator(
      delay: const Duration(seconds: 1),
    );
    addTearDown(coordinator.dispose);
    coordinator.markCurrentAsSaved('initial');
    final saved = <String>[];

    coordinator.schedule(
      fingerprint: 'pending',
      save: () async => saved.add('pending'),
    );
    coordinator.flush(
      fingerprint: 'final',
      save: () async => saved.add('final'),
    );
    await coordinator.drain();

    expect(saved, ['final']);
  });

  test('cancel prevents a pending draft from being recreated after delete',
      () async {
    final coordinator = SettingsAutoSaveCoordinator(
      delay: const Duration(milliseconds: 10),
    );
    addTearDown(coordinator.dispose);
    coordinator.markCurrentAsSaved('initial');
    var saveCount = 0;

    coordinator.schedule(
      fingerprint: 'pending',
      save: () async => saveCount += 1,
    );
    coordinator.cancelPending();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await coordinator.drain();

    expect(saveCount, 0);
  });
}
