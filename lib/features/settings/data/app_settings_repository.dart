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
      final settings = AppSettings.fromJson(decoded);
      final sanitized = _stripLegacyDemoData(settings);
      if (jsonEncode(settings.toJson()) != jsonEncode(sanitized.toJson())) {
        await save(sanitized);
      }
      return sanitized;
    } catch (_) {
      return SeedData.defaultSettings;
    }
  }

  @override
  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  AppSettings _stripLegacyDemoData(AppSettings settings) {
    final mediaSources = settings.mediaSources
        .where(
          (item) =>
              item.id != 'emby-main' &&
              item.id != 'nas-living-room' &&
              !item.endpoint.contains('example.com'),
        )
        .toList();
    final searchProviders = settings.searchProviders
        .where(
          (item) =>
              item.id == 'pansou-api' || !item.endpoint.contains('example.com'),
        )
        .toList();
    final isDemoDouban = settings.doubanAccount.userId == 'demo-user';

    return settings.copyWith(
      mediaSources: mediaSources,
      searchProviders: searchProviders,
      doubanAccount: isDemoDouban
          ? SeedData.defaultSettings.doubanAccount
          : settings.doubanAccount,
    );
  }
}
