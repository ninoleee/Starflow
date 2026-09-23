import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/settings/data/app_settings_repository.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  test('keeps the 115 cookie outside the settings JSON', () async {
    final preferences = _MemoryPreferencesStore();
    final repository = LocalAppSettingsRepository(preferences: preferences);
    final settings = SeedData.defaultSettings.copyWith(
      networkStorage: const NetworkStorageConfig(
        cloud115Cookie: 'UID=current; CID=current; SEID=current',
      ),
    );

    await repository.save(settings);
    final loaded = await repository.load();
    expect(
      loaded.networkStorage.cloud115Cookie,
      'UID=current; CID=current; SEID=current',
    );

    final persisted = jsonDecode(
      (await preferences.getString('starflow.settings.v3'))!,
    ) as Map<String, dynamic>;
    expect(
      (persisted['networkStorage'] as Map<String, dynamic>),
      isNot(contains('cloud115Cookie')),
    );
    expect(
      await preferences.getString(
        'starflow.local-credentials.cloud115-cookie.v1',
      ),
      loaded.networkStorage.cloud115Cookie,
    );
    expect(jsonEncode(loaded.toJson()), isNot(contains('UID=current')));
  });

  test('reconciles old WebDAV references to the current media source root', () {
    const source = MediaSourceConfig(
      id: 'nas-main',
      name: 'NAS',
      kind: MediaSourceKind.nas,
      endpoint: 'https://openlist.example.com/dav/strm',
      libraryPath: 'https://openlist.example.com/dav/strm/',
      enabled: true,
    );
    final settings = SeedData.defaultSettings.copyWith(
      mediaSources: const [source],
      homeModules: const [
        HomeModuleConfig(
          id: 'quark-module',
          type: HomeModuleType.librarySection,
          title: 'quark',
          enabled: true,
          sourceId: 'nas-main',
          sourceName: 'NAS',
          sectionId: 'https://webdav.example.com/movies/strm/quark/',
          sectionName: 'quark',
        ),
      ],
      networkStorage: const NetworkStorageConfig(
        syncDeleteQuarkWebDavDirectories: [
          NetworkStorageWebDavDirectory(
            sourceId: 'nas-main',
            sourceName: 'NAS',
            directoryId: 'https://webdav.example.com/movies/strm/quark/',
          ),
        ],
      ),
    );

    final reconciled = reconcileSettingsMediaSourceReferences(settings);

    expect(
      reconciled.homeModules.single.sectionId,
      'https://openlist.example.com/dav/strm/quark/',
    );
    expect(
      reconciled
          .networkStorage.syncDeleteQuarkWebDavDirectories.single.directoryId,
      'https://openlist.example.com/dav/strm/quark/',
    );
  });

  test('removes settings references to media sources that no longer exist', () {
    final settings = SeedData.defaultSettings.copyWith(
      mediaSources: const [],
      homeModules: const [
        HomeModuleConfig(
          id: 'orphan-module',
          type: HomeModuleType.librarySection,
          title: 'orphan',
          enabled: true,
          sourceId: 'missing-source',
        ),
      ],
      libraryMatchSourceIds: const ['missing-source'],
      searchSourceIds: const ['source:missing-source'],
      networkStorage: const NetworkStorageConfig(
        refreshMediaSourceIds: ['missing-source'],
        syncDeleteQuarkWebDavDirectories: [
          NetworkStorageWebDavDirectory(
            sourceId: 'missing-source',
            directoryId: 'https://old.example.com/dav/',
          ),
        ],
      ),
    );

    final reconciled = reconcileSettingsMediaSourceReferences(settings);

    expect(reconciled.homeModules, isEmpty);
    expect(reconciled.libraryMatchSourceIds, isEmpty);
    expect(reconciled.searchSourceIds, isEmpty);
    expect(reconciled.networkStorage.refreshMediaSourceIds, isEmpty);
    expect(
      reconciled.networkStorage.syncDeleteQuarkWebDavDirectories,
      isEmpty,
    );
  });

  test('drops unmappable old sections instead of retaining their URL', () {
    const source = MediaSourceConfig(
      id: 'nas-main',
      name: 'NAS',
      kind: MediaSourceKind.nas,
      endpoint: 'https://new.example.com/dav/strm/',
      enabled: true,
      featuredSectionIds: ['https://old.example.com/unrelated/Shows/'],
    );
    final settings = SeedData.defaultSettings.copyWith(
      mediaSources: const [source],
      homeModules: const [
        HomeModuleConfig(
          id: 'old-section',
          type: HomeModuleType.librarySection,
          title: '旧分区',
          enabled: true,
          sourceId: 'nas-main',
          sectionId: 'https://old.example.com/unrelated/Shows/',
          sectionName: 'Shows',
        ),
      ],
      networkStorage: const NetworkStorageConfig(
        syncDeleteQuarkWebDavDirectories: [
          NetworkStorageWebDavDirectory(
            sourceId: 'nas-main',
            directoryId: 'https://old.example.com/unrelated/Shows/',
          ),
        ],
      ),
    );

    final reconciled = reconcileSettingsMediaSourceReferences(settings);

    expect(reconciled.mediaSources.single.featuredSectionIds, isEmpty);
    expect(reconciled.homeModules.single.sectionId, isEmpty);
    expect(reconciled.homeModules.single.sectionName, '全部内容');
    expect(
      reconciled.networkStorage.syncDeleteQuarkWebDavDirectories,
      isEmpty,
    );
  });
}

class _MemoryPreferencesStore implements PreferencesStore {
  final values = <String, Object>{};

  @override
  Future<String?> getString(String key) async => values[key] as String?;

  @override
  Future<List<String>?> getStringList(String key) async =>
      values[key] as List<String>?;

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> setStringList(String key, List<String> value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}
