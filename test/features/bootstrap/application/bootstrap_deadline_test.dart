import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/bootstrap/application/bootstrap_controller.dart';
import 'package:starflow/features/home/application/home_controller.dart';
import 'package:starflow/features/home/application/home_metadata_auto_refresh.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/settings/application/media_source_cache_lifecycle.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

final _settings = AppSettings.fromJson(const <String, dynamic>{
  'mediaSources': <Object>[],
  'searchProviders': <Object>[],
  'homeModules': <Object>[],
  'homeStartupAutoRefreshEnabled': false,
});

class _Settings extends SettingsController {
  _Settings(this.result);
  final Future<AppSettings> result;

  @override
  Future<AppSettings> build() => result;
}

class _CacheLifecycle implements MediaSourceCacheLifecycle {
  final pending = Completer<void>();
  int calls = 0;

  @override
  Future<void> reconcileSources(List<MediaSourceConfig> sources) {
    calls++;
    return pending.future;
  }

  @override
  Future<void> clearAllIndexes() async {}

  @override
  Future<void> clearSource(String sourceId) async {}
}

void main() {
  for (final failLate in [false, true]) {
    testWidgets('cache stall exits at 10s and ignores late failure=$failLate',
        (tester) async {
      final cache = _CacheLifecycle();
      final container = ProviderContainer(overrides: [
        settingsControllerProvider
            .overrideWith(() => _Settings(Future.value(_settings))),
        appSettingsProvider.overrideWithValue(_settings),
        mediaSourceCacheLifecycleProvider.overrideWithValue(cache),
        homeEnabledModulesProvider.overrideWithValue([]),
      ]);
      addTearDown(container.dispose);
      final controller = container.read(bootstrapControllerProvider.notifier);
      var returned = false;
      final startup = controller.start().then((_) => returned = true);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pump(const Duration(milliseconds: 40));
      expect(cache.calls, 1);
      await tester.pump(const Duration(milliseconds: 9919));
      expect(container.read(bootstrapControllerProvider).isComplete, isFalse);
      expect(returned, isFalse);
      await tester.pump(const Duration(milliseconds: 1));
      await startup;
      final completed = container.read(bootstrapControllerProvider);
      expect(completed.isComplete, isTrue);
      expect(completed.progress, 1);
      expect(returned, isTrue);
      final revision = container.read(homeExplicitRefreshRevisionProvider);

      if (failLate) {
        cache.pending.completeError(StateError('late cache failure'));
      } else {
        cache.pending.complete();
      }
      await tester.pump(const Duration(seconds: 1));
      await controller.start();
      expect(container.read(bootstrapControllerProvider), same(completed));
      expect(container.read(homeExplicitRefreshRevisionProvider), revision);
      expect(cache.calls, 1);
    });
  }

  testWidgets('total deadline is not reset when home loading begins',
      (tester) async {
    final cache = _CacheLifecycle();
    final home = Completer<HomeSectionViewModel?>();
    final container = ProviderContainer(overrides: [
      settingsControllerProvider
          .overrideWith(() => _Settings(Future.value(_settings))),
      appSettingsProvider.overrideWithValue(_settings),
      mediaSourceCacheLifecycleProvider.overrideWithValue(cache),
      homeEnabledModulesProvider.overrideWithValue(const [
        HomeModuleConfig(
          id: 'pending',
          type: HomeModuleType.recentPlayback,
          title: 'Pending',
          enabled: true,
        ),
      ]),
      homeSectionProvider('pending').overrideWith((ref) => home.future),
    ]);
    addTearDown(container.dispose);
    final startup =
        container.read(bootstrapControllerProvider.notifier).start();
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 7920));
    cache.pending.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(container.read(bootstrapControllerProvider).currentStep, 2);
    await tester.pump(const Duration(milliseconds: 1969));
    expect(container.read(bootstrapControllerProvider).isComplete, isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    await startup;
    final completed = container.read(bootstrapControllerProvider);
    expect(completed.isComplete, isTrue);
    home.complete(null);
    await tester.pump();
    expect(container.read(bootstrapControllerProvider), same(completed));
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('settings stall retains its shorter timeout', (tester) async {
    final pendingSettings = Completer<AppSettings>();
    final cache = _CacheLifecycle();
    final container = ProviderContainer(overrides: [
      settingsControllerProvider
          .overrideWith(() => _Settings(pendingSettings.future)),
      appSettingsProvider.overrideWithValue(_settings),
      mediaSourceCacheLifecycleProvider.overrideWithValue(cache),
      homeEnabledModulesProvider.overrideWithValue([]),
    ]);
    addTearDown(container.dispose);
    final startup =
        container.read(bootstrapControllerProvider.notifier).start();
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pump(const Duration(milliseconds: 40));
    await startup;
    expect(container.read(bootstrapControllerProvider).isComplete, isTrue);
    expect(cache.calls, 0);
    pendingSettings.complete(_settings);
    await tester.pump();
    expect(cache.calls, 0);
  });

  testWidgets('disposing startup releases the deadline and ignores late work',
      (tester) async {
    final cache = _CacheLifecycle();
    final container = ProviderContainer(overrides: [
      settingsControllerProvider
          .overrideWith(() => _Settings(Future.value(_settings))),
      mediaSourceCacheLifecycleProvider.overrideWithValue(cache),
    ]);
    final startup =
        container.read(bootstrapControllerProvider.notifier).start();
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 40));
    expect(cache.calls, 1);
    container.dispose();
    await tester.pump();
    await startup;
    cache.pending.complete();
    await tester.pump();
  });
}
