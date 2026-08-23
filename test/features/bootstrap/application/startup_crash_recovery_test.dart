import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/features/bootstrap/application/startup_crash_recovery.dart';

void main() {
  test(
    'beginStartup marks current launch when previous launch completed',
    () async {
      final preferences = _MemoryPreferencesStore();
      final recovery = StartupCrashRecovery(
        preferences: preferences,
      );

      final recovered = await recovery.beginStartup();

      expect(recovered, isFalse);
      expect(preferences.values, contains('starflow.startup.in_progress.v1'));

      await recovery.completeStartup();
      expect(
        preferences.values,
        isNot(contains('starflow.startup.in_progress.v1')),
      );
    },
  );

  test('beginStartup detects unclean startup without changing settings',
      () async {
    const savedSettings =
        '{"homeStartupAutoRefreshEnabled":true,"tmdbMetadataMatchEnabled":true}';
    final preferences = _MemoryPreferencesStore()
      ..values['starflow.startup.in_progress.v1'] = 'pending'
      ..values['flutter.starflow.settings.v1'] = savedSettings;
    final recovery = StartupCrashRecovery(
      preferences: preferences,
    );

    final recovered = await recovery.beginStartup();

    expect(recovered, isTrue);
    expect(
      preferences.values['flutter.starflow.settings.v1'],
      savedSettings,
    );
    expect(preferences.values['starflow.startup.in_progress.v1'], isNotEmpty);
  });
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
