import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/domain/media_source_identity.dart';
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
      final reconciled = reconcileSettingsMediaSourceReferences(settings);
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
      return reconcileSettingsMediaSourceReferences(settings);
    } catch (_) {
      return SeedData.defaultSettings;
    }
  }
}

AppSettings reconcileSettingsMediaSourceReferences(AppSettings settings) {
  final normalizedSources = settings.mediaSources
      .map(
        (source) => source.kind != MediaSourceKind.nas
            ? source
            : source.copyWith(
                featuredSectionIds: source.featuredSectionIds
                    .map(
                      (sectionId) => sectionId == kNoSectionsSelectedSentinel
                          ? sectionId
                          : alignMediaSourceLocationToCurrentRoot(
                              sectionId,
                              source,
                            ),
                    )
                    .where((sectionId) => sectionId.trim().isNotEmpty)
                    .toList(growable: false),
              ),
      )
      .toList(growable: false);

  final mediaSourceById = {
    for (final source in normalizedSources) source.id.trim(): source,
  };
  final validSourceIds = mediaSourceById.keys.toSet();
  final removedHomeModuleIds = <String>{};
  final homeModules = <HomeModuleConfig>[];
  for (final module in settings.homeModules) {
    if (module.type != HomeModuleType.librarySection) {
      homeModules.add(module);
      continue;
    }
    final source = mediaSourceById[module.sourceId.trim()];
    if (source == null) {
      removedHomeModuleIds.add(module.id);
      continue;
    }
    final sectionId = alignMediaSourceLocationToCurrentRoot(
      module.sectionId,
      source,
    );
    homeModules.add(
      module.copyWith(
        sourceName: source.name,
        sectionId: sectionId,
        sectionName: sectionId.isEmpty ? '全部内容' : module.sectionName,
      ),
    );
  }

  final sourcesByName = <String, List<MediaSourceConfig>>{};
  for (final source in normalizedSources) {
    final normalizedName = source.name.trim().toLowerCase();
    if (normalizedName.isNotEmpty) {
      sourcesByName.putIfAbsent(normalizedName, () => []).add(source);
    }
  }
  final directories = <NetworkStorageWebDavDirectory>[];
  for (final directory
      in settings.networkStorage.syncDeleteQuarkWebDavDirectories) {
    var source = mediaSourceById[directory.sourceId.trim()];
    if (source == null) {
      final nameMatches =
          sourcesByName[directory.sourceName.trim().toLowerCase()] ?? const [];
      if (nameMatches.length == 1) {
        source = nameMatches.single;
      }
    }
    if (source == null) {
      continue;
    }
    final directoryId = alignMediaSourceLocationToCurrentRoot(
      directory.directoryId,
      source,
    );
    if (directoryId.isEmpty) {
      continue;
    }
    directories.add(
      directory.copyWith(
        sourceId: source.id,
        sourceName: source.name,
        directoryId: directoryId,
        directoryLabel: _mediaSourceDirectoryLabel(directoryId),
      ),
    );
  }

  return settings.copyWith(
    mediaSources: normalizedSources,
    homeModules: homeModules,
    homeHeroSourceModuleId:
        removedHomeModuleIds.contains(settings.homeHeroSourceModuleId)
            ? ''
            : settings.homeHeroSourceModuleId,
    libraryMatchSourceIds: settings.libraryMatchSourceIds
        .where(validSourceIds.contains)
        .toList(growable: false),
    searchSourceIds: settings.searchSourceIds.where((id) {
      final normalized = id.trim();
      if (!normalized.startsWith('source:')) {
        return true;
      }
      return validSourceIds.contains(normalized.substring('source:'.length));
    }).toList(growable: false),
    networkStorage: settings.networkStorage.copyWith(
      syncDeleteQuarkWebDavDirectories: directories,
      refreshMediaSourceIds: settings.networkStorage.refreshMediaSourceIds
          .where(validSourceIds.contains)
          .toList(growable: false),
    ),
  );
}

String _mediaSourceDirectoryLabel(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || !uri.hasScheme) {
    return raw.trim();
  }
  return '${uri.host}${uri.path.isEmpty ? '/' : uri.path}';
}
