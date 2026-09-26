import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/domain/media_source_identity.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'cloud_credential_store.dart';
import 'package:starflow/features/settings/domain/cloud_account.dart';

abstract class AppSettingsRepository {
  Future<AppSettings> load();

  Future<void> save(AppSettings settings);
}

final appSettingsRepositoryProvider = Provider<AppSettingsRepository>(
  (ref) => LocalAppSettingsRepository(),
);

class LocalAppSettingsRepository implements AppSettingsRepository {
  LocalAppSettingsRepository(
      {PreferencesStore? preferences, CloudCredentialStore? credentials})
      : _preferences = preferences ?? AppPreferencesStore(),
        _credentials = credentials ?? SecureCloudCredentialStore();

  static const _settingsKey = 'starflow.settings.v3';
  static const _legacySettingsKeys = <String>[
    'starflow.settings.v2',
    'starflow.settings.v1',
  ];
  static const _cloud115CookieKey =
      'starflow.local-credentials.cloud115-cookie.v1';
  static const _aliyunTokenKey =
      'starflow.local-credentials.aliyun-refresh-token.v1';
  static const _bundledSettingsKey = 'assets/bootstrap/embedded_settings.json';
  final PreferencesStore _preferences;
  final CloudCredentialStore _credentials;

  @override
  Future<AppSettings> load() async {
    var sourceKey = _settingsKey;
    String? raw = await _preferences.getString(_settingsKey);
    if (raw == null || raw.isEmpty) {
      for (final legacyKey in _legacySettingsKeys) {
        final legacyRaw = await _preferences.getString(legacyKey);
        if (legacyRaw != null && legacyRaw.isNotEmpty) {
          sourceKey = legacyKey;
          raw = legacyRaw;
          break;
        }
      }
    }
    if (raw == null || raw.isEmpty) {
      final fallback = await _loadBundledOrDefaultSettings();
      final restored = await _restoreCredentials(fallback);
      await save(restored);
      return restored;
    }

    late final AppSettings parsed;
    late final Map<String, dynamic> decoded;
    try {
      decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      parsed = AppSettings.fromCompatibleJson(decoded);
    } catch (_) {
      // Preserve the original record and credentials for recovery/export.
      final fallback = await _loadBundledOrDefaultSettings();
      final secure = await _credentials.read();
      if (secure == null) return fallback;
      return _restoreCredentials(fallback);
    }
    final settings = await _restoreCredentials(parsed);
    final reconciled = reconcileSettingsMediaSourceReferences(settings);
    final needsCanonicalSave = sourceKey != _settingsKey ||
        jsonEncode(decoded) != jsonEncode(parsed.toJson());
    if (needsCanonicalSave ||
        jsonEncode(settings.toJson()) != jsonEncode(reconciled.toJson())) {
      await save(reconciled);
    }
    if (sourceKey != _settingsKey) {
      await _preferences.remove(sourceKey);
    }
    return reconciled;
  }

  @override
  Future<void> save(AppSettings settings) async {
    final config = settings.networkStorage;
    await _credentials.write(jsonEncode({
      'aliyun': config.aliyunRefreshToken.trim(),
      'aliyunOpen': config.aliyunOpenRefreshToken.trim(),
      'cloud115': config.cloud115Cookie.trim(),
      'quark': config.quarkCookie.trim(),
      'accounts': config.localCloudAccounts,
    }));
    await _preferences.setString(_settingsKey, jsonEncode(settings.toJson()));
    await _preferences.remove(_aliyunTokenKey);
    await _preferences.remove(_cloud115CookieKey);
  }

  Future<AppSettings> _restoreCredentials(AppSettings parsed) async {
    final secure = await _credentials.read();
    if (secure == null) {
      final migrated = parsed.copyWith(
          networkStorage: parsed.networkStorage.copyWith(
              cloud115Cookie:
                  await _preferences.getString(_cloud115CookieKey) ??
                      parsed.networkStorage.cloud115Cookie,
              aliyunRefreshToken:
                  await _preferences.getString(_aliyunTokenKey) ?? ''));
      await save(migrated);
      return migrated;
    }
    final data = jsonDecode(secure) as Map<String, dynamic>;
    final accounts = data['accounts'] as Map? ?? {};
    var config = parsed.networkStorage.copyWith(
        aliyunRefreshToken: data['aliyun'] as String? ?? '',
        aliyunOpenRefreshToken: data['aliyunOpen'] as String? ?? '',
        cloud115Cookie: data['cloud115'] as String? ?? '',
        quarkCookie: data['quark'] as String? ?? '',
        localCloudAccounts: accounts.map((key, value) =>
            MapEntry(key as String, Map<String, dynamic>.from(value as Map))));
    for (final drive in CloudAccountDrive.values) {
      if (config.account(drive).directoryPending) {
        config = config.invalidateDirectory(drive);
      }
    }
    return parsed.copyWith(networkStorage: config);
  }

  Future<AppSettings> _loadBundledOrDefaultSettings() async {
    try {
      final bundledRaw = await rootBundle.loadString(_bundledSettingsKey);
      if (bundledRaw.trim().isEmpty) {
        return SeedData.defaultSettings;
      }
      final decoded = Map<String, dynamic>.from(jsonDecode(bundledRaw) as Map);
      final settings = AppSettings.fromCompatibleJson(decoded);
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
  List<NetworkStorageWebDavDirectory> reconcileDirectories(
      List<NetworkStorageWebDavDirectory> input) {
    final directories = <NetworkStorageWebDavDirectory>[];
    for (final directory in input) {
      var source = mediaSourceById[directory.sourceId.trim()];
      if (source == null) {
        final nameMatches =
            sourcesByName[directory.sourceName.trim().toLowerCase()] ??
                const [];
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
    return directories;
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
      syncDeleteQuarkWebDavDirectories: reconcileDirectories(
          settings.networkStorage.syncDeleteQuarkWebDavDirectories),
      syncDelete115WebDavDirectories: reconcileDirectories(
          settings.networkStorage.syncDelete115WebDavDirectories),
      syncDeleteAliyunWebDavDirectories: reconcileDirectories(
          settings.networkStorage.syncDeleteAliyunWebDavDirectories),
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
