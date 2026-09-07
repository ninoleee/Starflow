import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/home/application/home_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final failFirst in [false, true]) {
    test('waits for all modules, first failure: $failFirst', () async {
      final first = Completer<HomeSectionViewModel?>();
      final second = Completer<HomeSectionViewModel?>();
      final gate = Provider<Future<void>>((ref) => waitForHomeModules(ref));
      final container = ProviderContainer(overrides: [
        homeEnabledModulesProvider.overrideWithValue(const [
          HomeModuleConfig(
              id: 'a',
              type: HomeModuleType.recentlyAdded,
              title: 'A',
              enabled: true),
          HomeModuleConfig(
              id: 'b',
              type: HomeModuleType.recentPlayback,
              title: 'B',
              enabled: true),
        ]),
        homeSectionProvider('a').overrideWith((ref) => first.future),
        homeSectionProvider('b').overrideWith((ref) => second.future),
      ]);
      addTearDown(container.dispose);
      var complete = false;
      final result = container.read(gate).then((_) => complete = true);
      if (failFirst) {
        first.completeError(StateError('source unavailable'));
      } else {
        first.complete(null);
      }
      await Future<void>.delayed(Duration.zero);
      expect(complete, isFalse);
      second.complete(null);
      await result;
      expect(complete, isTrue);
    });
  }

  test('times out without cancelling the module load', () async {
    final module = Completer<HomeSectionViewModel?>();
    final gate = Provider<Future<void>>((ref) => waitForHomeModules(
          ref,
          timeout: const Duration(milliseconds: 10),
        ));
    final container = ProviderContainer(overrides: [
      homeEnabledModulesProvider.overrideWithValue(const [
        HomeModuleConfig(
            id: 'a',
            type: HomeModuleType.recentlyAdded,
            title: 'A',
            enabled: true),
      ]),
      homeSectionProvider('a').overrideWith((ref) => module.future),
    ]);
    addTearDown(container.dispose);
    await expectLater(
        container.read(gate), throwsA(isA<TimeoutException>()));
    module.complete(null);
    expect(await container.read(homeSectionProvider('a').future), isNull);
  });

  test('empty home completes immediately', () async {
    final gate = Provider<Future<void>>((ref) => waitForHomeModules(ref));
    final container = ProviderContainer(overrides: [
      homeEnabledModulesProvider.overrideWithValue(const []),
    ]);
    addTearDown(container.dispose);
    await container.read(gate);
  });
}
