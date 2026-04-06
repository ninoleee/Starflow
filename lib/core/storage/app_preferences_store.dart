import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_android/shared_preferences_android.dart';

const _kAndroidSharedPreferencesFileName = 'FlutterSharedPreferences';
const _kAndroidFlutterKeyPrefix = 'flutter.';

SharedPreferencesOptions _buildSharedPreferencesOptions() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return const SharedPreferencesAsyncAndroidOptions(
      backend: SharedPreferencesAndroidBackendLibrary.SharedPreferences,
      originalSharedPreferencesOptions: AndroidSharedPreferencesStoreOptions(
        fileName: _kAndroidSharedPreferencesFileName,
      ),
    );
  }
  return const SharedPreferencesOptions();
}

abstract class PreferencesStore {
  Future<String?> getString(String key);

  Future<List<String>?> getStringList(String key);

  Future<void> setString(String key, String value);

  Future<void> setStringList(String key, List<String> value);

  Future<void> remove(String key);
}

String normalizePreferencesKey(String key) {
  final trimmed = key.trim();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return '$_kAndroidFlutterKeyPrefix$trimmed';
  }
  return trimmed;
}

class AppPreferencesStore implements PreferencesStore {
  AppPreferencesStore({
    SharedPreferencesAsync? preferences,
  }) : _preferences = preferences ?? SharedPreferencesAsync(options: _options);

  static final SharedPreferencesOptions _options =
      _buildSharedPreferencesOptions();

  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> getString(String key) {
    return _preferences.getString(normalizePreferencesKey(key));
  }

  @override
  Future<List<String>?> getStringList(String key) {
    return _preferences.getStringList(normalizePreferencesKey(key));
  }

  @override
  Future<void> setString(String key, String value) {
    return _preferences.setString(normalizePreferencesKey(key), value);
  }

  @override
  Future<void> setStringList(String key, List<String> value) {
    return _preferences.setStringList(normalizePreferencesKey(key), value);
  }

  @override
  Future<void> remove(String key) {
    return _preferences.remove(normalizePreferencesKey(key));
  }
}

class SharedPreferencesStore implements PreferencesStore {
  SharedPreferencesStore(this._preferences);

  final SharedPreferences _preferences;

  @override
  Future<String?> getString(String key) async {
    return _preferences.getString(normalizePreferencesKey(key));
  }

  @override
  Future<List<String>?> getStringList(String key) async {
    return _preferences.getStringList(normalizePreferencesKey(key));
  }

  @override
  Future<void> setString(String key, String value) async {
    await _preferences.setString(normalizePreferencesKey(key), value);
  }

  @override
  Future<void> setStringList(String key, List<String> value) async {
    await _preferences.setStringList(normalizePreferencesKey(key), value);
  }

  @override
  Future<void> remove(String key) async {
    await _preferences.remove(normalizePreferencesKey(key));
  }
}
