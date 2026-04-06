import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/media_detail_page.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('detail page restores cached multiple library match choices',
      (tester) async {
    const seedTarget = MediaDetailTarget(
      title: '测试影片',
      posterUrl: '',
      overview: '',
      year: 2026,
      availabilityLabel: '无',
      searchQuery: '测试影片',
      sourceName: '豆瓣',
    );
    const choiceA = MediaDetailTarget(
      title: '测试影片',
      posterUrl: '',
      overview: '',
      year: 2026,
      availabilityLabel: '资源已就绪：WebDAV · nas-A',
      searchQuery: '测试影片',
      sourceId: 'nas-a',
      itemId: 'movie-a',
      itemType: 'movie',
      sectionName: '版本A',
      sourceKind: MediaSourceKind.nas,
      sourceName: 'nas-A',
    );
    const choiceB = MediaDetailTarget(
      title: '测试影片',
      posterUrl: '',
      overview: '',
      year: 2026,
      availabilityLabel: '资源已就绪：WebDAV · nas-B',
      searchQuery: '测试影片',
      sourceId: 'nas-b',
      itemId: 'movie-b',
      itemType: 'movie',
      sectionName: '版本B',
      sourceKind: MediaSourceKind.nas,
      sourceName: 'nas-B',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(
            AppSettings.fromJson({
              'mediaSources': const [],
              'searchProviders': const [],
              'doubanAccount': const {'enabled': false},
              'homeModules': const [],
              'tmdbMetadataMatchEnabled': false,
              'wmdbMetadataMatchEnabled': false,
              'imdbRatingMatchEnabled': false,
              'detailAutoLibraryMatchEnabled': false,
            }),
          ),
          mediaRepositoryProvider.overrideWithValue(
            const _NoopMediaRepository(),
          ),
          localStorageCacheRepositoryProvider.overrideWithValue(
            _FakeRestoreCacheRepository(
              cachedState: const CachedDetailState(
                target: choiceB,
                libraryMatchChoices: [choiceA, choiceB],
                selectedLibraryMatchIndex: 1,
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: MediaDetailPage(target: seedTarget),
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('本地资源'), findsOneWidget);
    expect(find.text('nas-B · 测试影片 · 版本B'), findsOneWidget);
  });

  testWidgets('detail page restores cached subtitle choice for playable target',
      (tester) async {
    const seedTarget = MediaDetailTarget(
      title: 'Planet Earth II',
      posterUrl: '',
      overview: '',
      year: 2016,
      availabilityLabel: '无',
      searchQuery: 'Planet Earth II',
      sourceName: '豆瓣',
    );
    const playableTarget = MediaDetailTarget(
      title: 'Planet Earth II',
      posterUrl: '',
      overview: '',
      year: 2016,
      availabilityLabel: '资源已就绪：Emby · 客厅 Emby',
      searchQuery: 'Planet Earth II',
      sourceId: 'emby-main',
      itemId: 'planet-earth-ii',
      itemType: 'episode',
      sourceKind: MediaSourceKind.emby,
      sourceName: '客厅 Emby',
      playbackTarget: PlaybackTarget(
        title: 'Planet Earth II',
        sourceId: 'emby-main',
        streamUrl: 'https://emby.example/Items/1/stream.mkv',
        sourceName: '客厅 Emby',
        sourceKind: MediaSourceKind.emby,
        itemId: 'planet-earth-ii',
        itemType: 'episode',
        seriesTitle: 'Planet Earth II',
        seasonNumber: 1,
        episodeNumber: 1,
      ),
    );
    const subtitleChoice = CachedSubtitleSearchOption(
      result: SubtitleSearchResult(
        id: 'subtitle-1',
        source: OnlineSubtitleSource.assrt,
        providerLabel: 'ASSRT',
        title: 'Planet Earth II S01E01',
        version: 'WEB-DL',
        formatLabel: 'ASS',
        languageLabel: '中英双语',
        sourceLabel: 'ASSRT',
        publishDateLabel: '2024-01-01',
        downloadCount: 21,
        ratingLabel: '评分 9',
        downloadUrl: 'https://assrt.net/download/1/subtitle.ass',
        detailUrl: 'https://assrt.net/sub/1',
        packageName: 'Planet.Earth.II.ass',
        packageKind: SubtitlePackageKind.subtitleFile,
      ),
      selection: SubtitleSearchSelection(
        cachedPath: '/cache/subtitle-1',
        displayName: 'Planet Earth II',
        subtitleFilePath: '/cache/subtitle-1/Planet.Earth.II.ass',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(
            AppSettings.fromJson({
              'mediaSources': const [],
              'searchProviders': const [],
              'doubanAccount': const {'enabled': false},
              'homeModules': const [],
              'tmdbMetadataMatchEnabled': false,
              'wmdbMetadataMatchEnabled': false,
              'imdbRatingMatchEnabled': false,
              'detailAutoLibraryMatchEnabled': false,
              'onlineSubtitleSources': ['assrt'],
            }),
          ),
          mediaRepositoryProvider.overrideWithValue(
            const _NoopMediaRepository(),
          ),
          localStorageCacheRepositoryProvider.overrideWithValue(
            _FakeRestoreCacheRepository(
              cachedState: const CachedDetailState(
                target: playableTarget,
                subtitleSearchChoices: [subtitleChoice],
                selectedSubtitleSearchIndex: 0,
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: MediaDetailPage(target: seedTarget),
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('外挂字幕'), findsOneWidget);
    expect(find.textContaining('Planet Earth II S01E01'), findsOneWidget);
  });
}

class _FakeRestoreCacheRepository extends LocalStorageCacheRepository {
  _FakeRestoreCacheRepository({required this.cachedState})
      : super(preferences: _MemoryPreferencesStore());

  final CachedDetailState? cachedState;

  @override
  Future<CachedDetailState?> loadDetailState(MediaDetailTarget seedTarget) async {
    return cachedState;
  }

  @override
  Future<MediaDetailTarget?> loadDetailTarget(MediaDetailTarget seedTarget) async {
    return cachedState?.target;
  }
}

class _NoopMediaRepository implements MediaRepository {
  const _NoopMediaRepository();

  @override
  Future<void> cancelActiveWebDavRefreshes() async {}

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
    return const [];
  }

  @override
  Future<List<MediaItem>> fetchChildren({
    required String sourceId,
    required String parentId,
    String sectionId = '',
    String sectionName = '',
    int limit = 200,
  }) async {
    return const [];
  }

  @override
  Future<List<MediaItem>> fetchLibrary({
    MediaSourceKind? kind,
    String? sourceId,
    String? sectionId,
    int limit = 200,
  }) async {
    return const [];
  }

  @override
  Future<List<MediaItem>> fetchRecentlyAdded({
    MediaSourceKind? kind,
    int limit = 10,
  }) async {
    return const [];
  }

  @override
  Future<List<MediaSourceConfig>> fetchSources() async {
    return const [];
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
