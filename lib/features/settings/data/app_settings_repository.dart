import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

abstract class AppSettingsRepository {
  Future<AppSettings> load();

  Future<void> save(AppSettings settings);
}

final appSettingsRepositoryProvider = Provider<AppSettingsRepository>(
  (ref) => LocalAppSettingsRepository(),
);

class LocalAppSettingsRepository implements AppSettingsRepository {
  static const _settingsKey = 'starflow.settings.v1';

  @override
  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    if (raw == null || raw.isEmpty) {
      return SeedData.defaultSettings;
    }

    try {
      final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return AppSettings.fromJson(decoded);
    } catch (_) {
      return SeedData.defaultSettings;
    }
  }

  @override
  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }
}
