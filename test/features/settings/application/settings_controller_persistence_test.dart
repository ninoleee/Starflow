import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/data/app_settings_repository.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  test('rapid setting changes persist in user action order', () async {
    final repository = _OutOfOrderSettingsRepository(
      SeedData.defaultSettings.copyWith(
        homeStartupAutoRefreshEnabled: true,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        appSettingsRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);
    final controller = container.read(settingsControllerProvider.notifier);

    final first = controller.setHomeStartupAutoRefreshEnabled(false);
    final second = controller.setHomeStartupAutoRefreshEnabled(true);
    await Future.wait(<Future<void>>[first, second]);

    expect(repository.settings.homeStartupAutoRefreshEnabled, isTrue);
    expect(
      repository.savedValues,
      <bool>[false, true],
    );
  });

  test('home feed load limits persist through the settings controller',
      () async {
    final repository = _OutOfOrderSettingsRepository(SeedData.defaultSettings);
    final container = ProviderContainer(
      overrides: [
        appSettingsRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);
    final controller = container.read(settingsControllerProvider.notifier);

    await controller.setHomeFeedMaxConcurrency(4);
    await controller.setHomeFeedInitialBatchSize(3);

    expect(repository.settings.homeFeedMaxConcurrency, 4);
    expect(repository.settings.homeFeedInitialBatchSize, 3);
    expect(
      container.read(appSettingsProvider).homeFeedMaxConcurrency,
      4,
    );
    expect(
      container.read(appSettingsProvider).homeFeedInitialBatchSize,
      3,
    );
  });
}

class _OutOfOrderSettingsRepository implements AppSettingsRepository {
  _OutOfOrderSettingsRepository(this.settings);

  AppSettings settings;
  final List<bool> savedValues = <bool>[];

  @override
  Future<AppSettings> load() async => settings;

  @override
  Future<void> save(AppSettings settings) async {
    final enabled = settings.homeStartupAutoRefreshEnabled;
    await Future<void>.delayed(
      enabled
          ? const Duration(milliseconds: 1)
          : const Duration(milliseconds: 40),
    );
    savedValues.add(enabled);
    this.settings = settings;
  }
}
