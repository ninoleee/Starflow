import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';

const _startupInProgressKey = 'starflow.startup.in_progress.v1';

/// True only for the current process when the previous process did not finish
/// startup. Recovery must never overwrite persisted user settings.
final startupCrashRecoveryActiveProvider = Provider<bool>((ref) => false);

class StartupCrashRecovery {
  StartupCrashRecovery({
    PreferencesStore? preferences,
  }) : _preferences = preferences ?? AppPreferencesStore();

  final PreferencesStore _preferences;

  Future<bool> beginStartup() async {
    final previousStartupMarker =
        await _preferences.getString(_startupInProgressKey);
    final recovered = previousStartupMarker != null &&
        previousStartupMarker.trim().isNotEmpty;

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
