import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/features/settings/data/app_settings_repository.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

const _startupInProgressKey = 'starflow.startup.in_progress.v1';

class StartupCrashRecovery {
  StartupCrashRecovery({
    PreferencesStore? preferences,
    AppSettingsRepository? settingsRepository,
  })  : _preferences = preferences ?? AppPreferencesStore(),
        _settingsRepository =
            settingsRepository ?? LocalAppSettingsRepository();

  final PreferencesStore _preferences;
  final AppSettingsRepository _settingsRepository;

  Future<bool> beginStartup() async {
    final previousStartupMarker =
        await _preferences.getString(_startupInProgressKey);
    final recovered = previousStartupMarker != null &&
        previousStartupMarker.trim().isNotEmpty;

    if (recovered) {
      final settings = await _settingsRepository.load();
      await _settingsRepository
          .save(settings.applyStartupCrashRecoveryPreset());
    }

    await _preferences.setString(
      _startupInProgressKey,
      DateTime.now().toUtc().toIso8601String(),
    );
    return recovered;
  }

  Future<void> completeStartup() async {
    await _preferences.remove(_startupInProgressKey);
  }
}

final startupCrashRecovery = StartupCrashRecovery();
