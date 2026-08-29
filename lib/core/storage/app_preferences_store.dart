import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kAndroidFlutterKeyPrefix = 'flutter.';

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

  static const SharedPreferencesOptions _options = SharedPreferencesOptions();

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
  SharedPreferencesStore(SharedPreferences preferences)
      : _preferences = preferences,
        _reloadBeforeRead = false;

  SharedPreferencesStore.reloading()
      : _preferences = null,
        _reloadBeforeRead = true;

  SharedPreferences? _preferences;
  final bool _reloadBeforeRead;

  @override
  Future<String?> getString(String key) async {
    return (await _resolvePreferences(forRead: true)).getString(key.trim());
  }

  @override
  Future<List<String>?> getStringList(String key) async {
    return (await _resolvePreferences(forRead: true)).getStringList(key.trim());
  }

  @override
  Future<void> setString(String key, String value) async {
    await (await _resolvePreferences()).setString(key.trim(), value);
  }

  @override
  Future<void> setStringList(String key, List<String> value) async {
    await (await _resolvePreferences()).setStringList(key.trim(), value);
  }

  @override
  Future<void> remove(String key) async {
    await (await _resolvePreferences()).remove(key.trim());
  }

  Future<SharedPreferences> _resolvePreferences({bool forRead = false}) async {
    final preferences = _preferences ??= await SharedPreferences.getInstance();
    if (forRead && _reloadBeforeRead) {
      await preferences.reload();
    }
    return preferences;
  }
}
