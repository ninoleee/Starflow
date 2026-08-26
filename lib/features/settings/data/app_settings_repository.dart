import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

abstract class AppSettingsRepository {
  Future<AppSettings> load();

  Future<void> save(AppSettings settings);
}

final appSettingsRepositoryProvider = Provider<AppSettingsRepository>(
  (ref) => LocalAppSettingsRepository(),
);

class LocalAppSettingsRepository implements AppSettingsRepository {
  static const _settingsKey = 'starflow.settings.v2';
  static const _bundledSettingsKey = 'assets/bootstrap/embedded_settings.json';
  final AppPreferencesStore _preferences = AppPreferencesStore();

  @override
  Future<AppSettings> load() async {
    final raw = await _preferences.getString(_settingsKey);
    if (raw == null || raw.isEmpty) {
      final fallback = await _loadBundledOrDefaultSettings();
      await save(fallback);
      return fallback;
    }

    try {
      final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final settings = AppSettings.fromCurrentJson(decoded);
      final reconciled = _reconcileSyncDeleteWebDavDirectories(settings);
      if (jsonEncode(settings.toJson()) != jsonEncode(reconciled.toJson())) {
        await save(reconciled);
      }
      return reconciled;
    } catch (_) {
      final fallback = await _loadBundledOrDefaultSettings();
      await save(fallback);
      return fallback;
    }
  }

  @override
  Future<void> save(AppSettings settings) async {
    await _preferences.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  Future<AppSettings> _loadBundledOrDefaultSettings() async {
    try {
      final bundledRaw = await rootBundle.loadString(_bundledSettingsKey);
      if (bundledRaw.trim().isEmpty) {
        return SeedData.defaultSettings;
      }
      final decoded = Map<String, dynamic>.from(jsonDecode(bundledRaw) as Map);
      final settings = AppSettings.fromCurrentJson(decoded);
      return _reconcileSyncDeleteWebDavDirectories(settings);
    } catch (_) {
      return SeedData.defaultSettings;
    }
  }

  AppSettings _reconcileSyncDeleteWebDavDirectories(AppSettings settings) {
    final directories =
        settings.networkStorage.syncDeleteQuarkWebDavDirectories;
    if (directories.isEmpty) {
      return settings;
    }

    final mediaSourceById = {
      for (final source in settings.mediaSources) source.id.trim(): source,
    };
    final mediaSourcesByName = <String, List<MediaSourceConfig>>{};
    for (final source in settings.mediaSources) {
      final normalizedName = source.name.trim().toLowerCase();
      if (normalizedName.isEmpty) {
        continue;
      }
      mediaSourcesByName.putIfAbsent(normalizedName, () => []).add(source);
    }

    var changed = false;
    final reconciled = <NetworkStorageWebDavDirectory>[];
    for (final directory in directories) {
      final sourceId = directory.sourceId.trim();
      final currentSource = mediaSourceById[sourceId];
      if (currentSource != null) {
        final updated = directory.copyWith(sourceName: currentSource.name);
        if (updated.sourceName != directory.sourceName) {
          changed = true;
        }
        reconciled.add(updated);
        continue;
      }

      final normalizedName = directory.sourceName.trim().toLowerCase();
      final nameMatches = mediaSourcesByName[normalizedName] ?? const [];
      if (nameMatches.length == 1) {
        final matchedSource = nameMatches.single;
        reconciled.add(
          directory.copyWith(
            sourceId: matchedSource.id,
            sourceName: matchedSource.name,
          ),
        );
        changed = true;
        continue;
      }

      reconciled.add(directory);
    }

    if (!changed) {
      return settings;
    }
    return settings.copyWith(
      networkStorage: settings.networkStorage.copyWith(
        syncDeleteQuarkWebDavDirectories: reconciled,
      ),
    );
  }
}
