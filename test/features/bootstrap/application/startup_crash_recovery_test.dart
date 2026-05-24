import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/features/bootstrap/application/startup_crash_recovery.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/settings/data/app_settings_repository.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  test('beginStartup marks current launch when previous launch completed',
      () async {
    final preferences = _MemoryPreferencesStore();
    final repository = _MemorySettingsRepository(_settings());
    final recovery = StartupCrashRecovery(
      preferences: preferences,
      settingsRepository: repository,
    );

    final recovered = await recovery.beginStartup();

    expect(recovered, isFalse);
    expect(repository.saveCount, 0);
    expect(preferences.values, contains('starflow.startup.in_progress.v1'));

    await recovery.completeStartup();
    expect(
        preferences.values, isNot(contains('starflow.startup.in_progress.v1')));
  });

  test('beginStartup applies recovery preset after unclean startup', () async {
    final preferences = _MemoryPreferencesStore()
      ..values['starflow.startup.in_progress.v1'] = 'pending';
    final repository = _MemorySettingsRepository(
      _settings(
        homeStartupAutoRefreshEnabled: true,
        tmdbMetadataMatchEnabled: true,
        playbackBackgroundPlaybackEnabled: true,
      ),
    );
    final recovery = StartupCrashRecovery(
      preferences: preferences,
      settingsRepository: repository,
    );

    final recovered = await recovery.beginStartup();

    expect(recovered, isTrue);
    expect(repository.saveCount, 1);
    expect(repository.settings.highPerformanceModeEnabled, isTrue);
    expect(repository.settings.homeStartupAutoRefreshEnabled, isFalse);
    expect(repository.settings.tmdbMetadataMatchEnabled, isFalse);
    expect(repository.settings.playbackBackgroundPlaybackEnabled, isFalse);
    expect(preferences.values['starflow.startup.in_progress.v1'], isNotEmpty);
  });
}

AppSettings _settings({
  bool homeStartupAutoRefreshEnabled = false,
  bool tmdbMetadataMatchEnabled = false,
  bool playbackBackgroundPlaybackEnabled = false,
}) {
  return AppSettings(
    mediaSources: const [],
    searchProviders: const [],
    doubanAccount: const DoubanAccountConfig(enabled: false),
    homeModules: const [],
    homeStartupAutoRefreshEnabled: homeStartupAutoRefreshEnabled,
    tmdbMetadataMatchEnabled: tmdbMetadataMatchEnabled,
    playbackBackgroundPlaybackEnabled: playbackBackgroundPlaybackEnabled,
  );
}

class _MemorySettingsRepository implements AppSettingsRepository {
  _MemorySettingsRepository(this.settings);

  AppSettings settings;
  int saveCount = 0;

  @override
  Future<AppSettings> load() async => settings;

  @override
  Future<void> save(AppSettings settings) async {
    saveCount += 1;
    this.settings = settings;
  }
}

class _MemoryPreferencesStore implements PreferencesStore {
  final values = <String, String>{};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<List<String>?> getStringList(String key) async => null;

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> setStringList(String key, List<String> value) async {}
}
