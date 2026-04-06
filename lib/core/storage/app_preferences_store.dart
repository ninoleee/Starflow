import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_android/shared_preferences_android.dart';

const _kAndroidSharedPreferencesFileName = 'FlutterSharedPreferences';
const _kAndroidFlutterKeyPrefix = 'flutter.';

SharedPreferencesOptions _buildSharedPreferencesOptions() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return const SharedPreferencesAsyncAndroidOptions();
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
    SharedPreferences? sharedPreferences,
  })  : _preferences = preferences,
        _sharedPreferences = sharedPreferences;

  static final SharedPreferencesOptions _options =
      _buildSharedPreferencesOptions();

  SharedPreferencesAsync? _preferences;
  SharedPreferences? _sharedPreferences;

  @override
  Future<String?> getString(String key) async {
    final normalizedKey = normalizePreferencesKey(key);
    final asyncPreferences = _resolveAsyncPreferences();
    if (asyncPreferences != null) {
      return asyncPreferences.getString(normalizedKey);
    }
    return (await _resolveSharedPreferences()).getString(normalizedKey);
  }

  @override
  Future<List<String>?> getStringList(String key) async {
    final normalizedKey = normalizePreferencesKey(key);
    final asyncPreferences = _resolveAsyncPreferences();
    if (asyncPreferences != null) {
      return asyncPreferences.getStringList(normalizedKey);
    }
    return (await _resolveSharedPreferences()).getStringList(normalizedKey);
  }

  @override
  Future<void> setString(String key, String value) async {
    final normalizedKey = normalizePreferencesKey(key);
    final asyncPreferences = _resolveAsyncPreferences();
    if (asyncPreferences != null) {
      await asyncPreferences.setString(normalizedKey, value);
      return;
    }
    await (await _resolveSharedPreferences()).setString(normalizedKey, value);
  }

  @override
  Future<void> setStringList(String key, List<String> value) async {
    final normalizedKey = normalizePreferencesKey(key);
    final asyncPreferences = _resolveAsyncPreferences();
    if (asyncPreferences != null) {
      await asyncPreferences.setStringList(normalizedKey, value);
      return;
    }
    await (await _resolveSharedPreferences())
        .setStringList(normalizedKey, value);
  }

  @override
  Future<void> remove(String key) async {
    final normalizedKey = normalizePreferencesKey(key);
    final asyncPreferences = _resolveAsyncPreferences();
    if (asyncPreferences != null) {
      await asyncPreferences.remove(normalizedKey);
      return;
    }
    await (await _resolveSharedPreferences()).remove(normalizedKey);
  }

  SharedPreferencesAsync? _resolveAsyncPreferences() {
    if (_sharedPreferences != null) {
      return null;
    }
    final existing = _preferences;
    if (existing != null) {
      return existing;
    }
    try {
      final created = SharedPreferencesAsync(options: _options);
      _preferences = created;
      return created;
    } catch (_) {
      return null;
    }
  }

  Future<SharedPreferences> _resolveSharedPreferences() async {
    final existing = _sharedPreferences;
    if (existing != null) {
      return existing;
    }
    final created = await SharedPreferences.getInstance();
    _sharedPreferences = created;
    return created;
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
