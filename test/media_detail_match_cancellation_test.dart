import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/media_detail_page.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('disposing detail page stops queued local match tasks',
      (tester) async {
    final repository = _BlockingDetailMatchRepository(
      sectionIds: const ['s1', 's2', 's3', 's4', 's5', 's6'],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(
            AppSettings.fromJson({
              'mediaSources': [
                {
                  'id': 'emby-main',
                  'name': 'Home Emby',
                  'kind': 'emby',
                  'endpoint': 'https://media.example.com',
                  'enabled': true,
                  'username': 'alice',
                  'accessToken': 'token-789',
                  'userId': 'user-123',
                  'deviceId': 'device-456',
                },
              ],
              'searchProviders': const [],
              'doubanAccount': const {'enabled': false},
              'homeModules': const [],
              'tmdbMetadataMatchEnabled': false,
              'wmdbMetadataMatchEnabled': false,
              'imdbRatingMatchEnabled': false,
              'detailAutoLibraryMatchEnabled': false,
            }),
          ),
          mediaRepositoryProvider.overrideWithValue(repository),
          localStorageCacheRepositoryProvider.overrideWithValue(
            _NoopDetailCacheRepository(),
          ),
        ],
        child: MaterialApp(
          home: MediaDetailPage(
            target: const MediaDetailTarget(
              title: '测试影片',
              posterUrl: '',
              overview: '',
              year: 2026,
              availabilityLabel: '无',
              searchQuery: '测试影片',
              sourceName: '豆瓣',
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    final matchButton = find.ancestor(
      of: find.byIcon(Icons.link_rounded),
      matching: find.byType(TextButton),
    );
    await tester.ensureVisible(matchButton);
    await tester.pumpAndSettle();
    await tester.tap(matchButton);
    await tester.pump();

    expect(repository.startedSectionIds.length, 4);

    await tester.pumpWidget(const SizedBox.shrink());
    repository.completeStartedRequests();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(repository.startedSectionIds.length, 4);
    expect(repository.startedSectionIds, ['s1', 's2', 's3', 's4']);
  });
}

class _NoopDetailCacheRepository extends LocalStorageCacheRepository {
  _NoopDetailCacheRepository() : super(preferences: _MemoryPreferencesStore());
}

class _BlockingDetailMatchRepository implements MediaRepository {
  _BlockingDetailMatchRepository({required this.sectionIds})
      : _completers = {
          for (final sectionId in sectionIds)
            sectionId: Completer<List<MediaItem>>(),
        };

  final List<String> sectionIds;
  final Map<String, Completer<List<MediaItem>>> _completers;
  final List<String> startedSectionIds = [];

  void completeStartedRequests() {
    for (final sectionId in startedSectionIds) {
      final completer = _completers[sectionId];
      if (completer != null && !completer.isCompleted) {
        completer.complete(const <MediaItem>[]);
      }
    }
  }

  @override
  Future<void> cancelActiveWebDavRefreshes({
    bool includeForceFull = false,
  }) async {}

  @override
  Future<void> deleteResource({
    required String sourceId,
    required String resourcePath,
    String sectionId = '',
  }) async {}

  @override
  Future<List<MediaCollection>> fetchCollections({
    MediaSourceKind? kind,
    String? sourceId,
  }) async {
    if (kind != MediaSourceKind.emby || sourceId != 'emby-main') {
      return const <MediaCollection>[];
    }
    return sectionIds
        .map(
          (sectionId) => MediaCollection(
            id: sectionId,
            title: 'Section $sectionId',
            sourceId: 'emby-main',
            sourceName: 'Home Emby',
            sourceKind: MediaSourceKind.emby,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<MediaItem>> fetchChildren({
    required String sourceId,
    required String parentId,
    String sectionId = '',
    String sectionName = '',
    int limit = 200,
  }) async {
    return const <MediaItem>[];
  }

  @override
  Future<List<MediaItem>> fetchLibrary({
    MediaSourceKind? kind,
    String? sourceId,
    String? sectionId,
    int limit = 200,
  }) async {
    final normalizedSectionId = sectionId?.trim() ?? '';
    if (kind == MediaSourceKind.emby &&
        sourceId == 'emby-main' &&
        normalizedSectionId.isNotEmpty) {
      startedSectionIds.add(normalizedSectionId);
      return _completers[normalizedSectionId]!.future;
    }
    return const <MediaItem>[];
  }

  @override
  Future<List<MediaItem>> fetchRecentlyAdded({
    MediaSourceKind? kind,
    int limit = 10,
  }) async {
    return const <MediaItem>[];
  }

  @override
  Future<List<MediaSourceConfig>> fetchSources() async {
    return const <MediaSourceConfig>[];
  }

  @override
  Future<MediaItem?> findById(String id) async {
    return null;
  }

  @override
  Future<MediaItem?> matchTitle(String title) async {
    return null;
  }

  @override
  Future<void> refreshSource({
    required String sourceId,
    bool forceFullRescan = false,
  }) async {}
}

class _MemoryPreferencesStore implements PreferencesStore {
  final Map<String, Object> _values = <String, Object>{};

  @override
  Future<String?> getString(String key) async => _values[key] as String?;

  @override
  Future<List<String>?> getStringList(String key) async =>
      (_values[key] as List<String>?)?.toList(growable: false);

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> setString(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> setStringList(String key, List<String> value) async {
    _values[key] = value.toList(growable: false);
  }
}
