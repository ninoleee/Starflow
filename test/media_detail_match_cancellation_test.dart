import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/features/details/application/detail_external_episode_variant_service.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/media_detail_page.dart';
import 'package:starflow/features/details/presentation/widgets/detail_resource_info_section.dart';
import 'package:starflow/features/library/data/media_repository.dart';
import 'package:starflow/features/library/data/media_server_client.dart';
import 'package:starflow/features/library/data/nas_media_indexer.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  for (final action in ['dispose', 'cancel', 'restart', 'restart-error']) {
    testWidgets('$action during final expansion cannot commit stale choices',
        (tester) async {
      final variants = _BlockingVariants();
      final cache = _RecordingCache();
      final repository = _ImmediateMatchRepository();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(AppSettings.fromJson({
            'mediaSources': [
              {
                'id': 'emby-main',
                'name': 'Home Emby',
                'kind': 'emby',
                'endpoint': 'https://example.test',
                'enabled': true
              },
            ],
            'searchProviders': const [],
            'doubanAccount': const {'enabled': false},
            'homeModules': const [],
            'tmdbMetadataMatchEnabled': false,
            'wmdbMetadataMatchEnabled': false,
            'imdbRatingMatchEnabled': false,
            'detailAutoLibraryMatchEnabled': false,
          })),
          mediaRepositoryProvider.overrideWithValue(repository),
          localStorageCacheRepositoryProvider.overrideWithValue(cache),
          detailExternalEpisodeVariantServiceProvider
              .overrideWithValue(variants),
          enrichedDetailTargetProvider.overrideWith((ref, target) => target),
        ],
        child: const MaterialApp(
            home: MediaDetailPage(
                target: MediaDetailTarget(
          title: 'Probe',
          posterUrl: '',
          overview: '',
          itemType: 'movie',
          sourceName: 'Metadata',
        ))),
      ));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      Future<void> startMatch() async {
        final button = find.ancestor(
            of: find.byIcon(Icons.link_rounded),
            matching: find.byType(TextButton));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pump();
      }

      await startMatch();
      expect(variants.pending, isNotNull);
      expect(variants.calls, 1);
      final writesBeforeCancel = cache.writes.length;
      if (action == 'dispose') {
        await tester.pumpWidget(const SizedBox.shrink());
      } else {
        // Exercise the page's actual lifecycle cancellation while its last
        // variant request is held, without disposing its state/notifiers.
        final dynamic page = tester.state(find.byType(MediaDetailPage));
        page.onPageBecameInactive();
        await tester.pump();
        if (action.startsWith('restart')) {
          repository.prefix = 'fresh';
          await startMatch();
          await tester.pumpAndSettle();
          expect(cache.writes.last.itemId, 'fresh-1');
        }
      }
      final writesBeforeCompletion = cache.writes.length;
      final callsBeforeCompletion = variants.calls;
      final visibleBeforeCompletion = action == 'dispose'
          ? null
          : tester.widget<DetailResourceInfoSection>(
              find.byType(DetailResourceInfoSection));
      if (action == 'restart-error') {
        variants.pending!.completeError(StateError('Late expansion failure'));
      } else {
        variants.pending!.complete(DetailExternalEpisodeVariantState(
          choices: [
            variants.blockedTarget!.copyWith(itemId: 'stale-expanded-1'),
            variants.blockedTarget!.copyWith(itemId: 'stale-expanded-2'),
          ],
          selectedIndex: 0,
        ));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(variants.calls, callsBeforeCompletion,
          reason: 'Cancellation must stop the remaining expansion iterations');
      expect(cache.writes.length, writesBeforeCompletion);
      if (visibleBeforeCompletion != null) {
        final visible = tester.widget<DetailResourceInfoSection>(
            find.byType(DetailResourceInfoSection));
        expect(visible.target.itemId, visibleBeforeCompletion.target.itemId);
        expect(
            visible.libraryView.choices.map((choice) => choice.itemId),
            visibleBeforeCompletion.libraryView.choices
                .map((choice) => choice.itemId));
      }
      expect(cache.writes.any((target) => target.itemId.startsWith('stale-')),
          isFalse);
      if (!action.startsWith('restart')) {
        expect(cache.writes.length, writesBeforeCancel);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

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

class _BlockingVariants extends DetailExternalEpisodeVariantService {
  Completer<DetailExternalEpisodeVariantState?>? pending;
  MediaDetailTarget? blockedTarget;
  int calls = 0;

  @override
  Future<DetailExternalEpisodeVariantState?> loadChoices({
    required MediaDetailTarget target,
    required AppSettings settings,
    required NasMediaIndexer nasMediaIndexer,
    required MediaServerClient embyApiClient,
  }) async {
    if (target.sourceId.isEmpty) return null;
    calls++;
    if (pending == null) {
      blockedTarget = target;
      pending = Completer<DetailExternalEpisodeVariantState?>();
      return pending!.future;
    }
    return null;
  }
}

class _ImmediateMatchRepository extends _BlockingDetailMatchRepository {
  _ImmediateMatchRepository() : super(sectionIds: const []);
  String prefix = 'old';

  @override
  Future<List<MediaItem>> loadLibraryMatchItems({
    required MediaSourceConfig source,
    String doubanId = '',
    String imdbId = '',
    String tmdbId = '',
    String tvdbId = '',
    String wikidataId = '',
    Iterable<String> titles = const [],
    int year = 0,
    int limit = 2000,
  }) async =>
      [
        for (var i = 1; i <= 2; i++)
          MediaItem(
              id: '$prefix-$i',
              title: 'Probe',
              overview: '',
              posterUrl: '',
              year: 2026,
              durationLabel: '',
              genres: const [],
              itemType: 'movie',
              sourceId: source.id,
              sourceName: source.name,
              sourceKind: source.kind,
              streamUrl: '',
              addedAt: DateTime.utc(2026, 9, 20)),
      ];
}

class _RecordingCache extends _NoopDetailCacheRepository {
  final writes = <MediaDetailTarget>[];

  @override
  Future<void> saveDetailTarget({
    required MediaDetailTarget seedTarget,
    required MediaDetailTarget resolvedTarget,
    DetailMetadataRefreshStatus? metadataRefreshStatus,
    List<MediaDetailTarget>? libraryMatchChoices,
    int? selectedLibraryMatchIndex,
    List<CachedSubtitleSearchOption>? subtitleSearchChoices,
    int? selectedSubtitleSearchIndex,
  }) async {
    writes.add(resolvedTarget);
  }
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

  @override
  Future<List<MediaItem>> loadLibraryMatchItems({
    required MediaSourceConfig source,
    String doubanId = '',
    String imdbId = '',
    String tmdbId = '',
    String tvdbId = '',
    String wikidataId = '',
    Iterable<String> titles = const <String>[],
    int year = 0,
    int limit = 2000,
  }) async {
    if (source.kind != MediaSourceKind.emby || source.id != 'emby-main') {
      return const <MediaItem>[];
    }
    final pendingSectionIds = sectionIds.take(4).toList(growable: false);
    startedSectionIds.addAll(pendingSectionIds);
    await Future.wait(
      pendingSectionIds.map((sectionId) => _completers[sectionId]!.future),
    );
    return const <MediaItem>[];
  }

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
