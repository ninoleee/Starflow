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
  static const _settingsKey = 'starflow.settings.v1';
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
      final settings = AppSettings.fromJson(decoded);
      final migrated = _migrateLegacyNetworkStorage(settings);
      final sanitized = _stripLegacyDemoData(migrated);
      final reconciled = _reconcileSyncDeleteWebDavDirectories(sanitized);
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
      final settings = AppSettings.fromJson(decoded);
      return _reconcileSyncDeleteWebDavDirectories(
        _stripLegacyDemoData(_migrateLegacyNetworkStorage(settings)),
      );
    } catch (_) {
      return SeedData.defaultSettings;
    }
  }

  AppSettings _migrateLegacyNetworkStorage(AppSettings settings) {
    if (settings.networkStorage.hasAnyConfigured) {
      return settings;
    }

    for (final provider in settings.searchProviders) {
      final hasLegacyConfig = provider.quarkCookie.trim().isNotEmpty ||
          provider.smartStrmWebhookUrl.trim().isNotEmpty ||
          provider.smartStrmTaskName.trim().isNotEmpty ||
          provider.quarkSaveFolderId.trim() != '0' ||
          provider.quarkSaveFolderPath.trim() != '/';
      if (!hasLegacyConfig) {
        continue;
      }
      return settings.copyWith(
        networkStorage: NetworkStorageConfig(
          quarkCookie: provider.quarkCookie,
          quarkSaveFolderId: provider.quarkSaveFolderId,
          quarkSaveFolderPath: provider.quarkSaveFolderPath,
          smartStrmWebhookUrl: provider.smartStrmWebhookUrl,
          smartStrmTaskName: provider.smartStrmTaskName,
        ),
      );
    }

    return settings;
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
    final homeModules = settings.homeModules.where((module) {
      if (module.id == 'module-douban-recommendations' ||
          module.id == 'module-douban-wish' ||
          module.id == 'module-emby-library' ||
          module.id == 'module-nas-library') {
        return false;
      }
      if (module.type == HomeModuleType.doubanCarousel) {
        return false;
      }
      if (module.type == HomeModuleType.librarySection &&
          (!module.enabled ||
              module.sectionId.trim().isEmpty ||
              module.sourceId.trim().isEmpty)) {
        return false;
      }
      return true;
    }).toList();

    return settings.copyWith(
      mediaSources: mediaSources,
      searchProviders: searchProviders,
      doubanAccount: isDemoDouban
          ? SeedData.defaultSettings.doubanAccount
          : settings.doubanAccount,
      homeModules: homeModules,
    );
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
