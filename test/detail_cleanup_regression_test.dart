import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/utils/media_rating_labels.dart';
import 'package:starflow/features/details/application/detail_library_match_service.dart';
import 'package:starflow/features/details/application/detail_target_resolver.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/media_detail_page.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/metadata/data/wmdb_metadata_client.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('detail merge should agree with shared usable-rating policy', () {
    const primary = ['IMDb 0'];
    const secondary = ['IMDb 8.6'];
    expect(
      const DetailLibraryMatchService().mergeLabels(primary, secondary),
      mergeDistinctRatingLabels(primary, secondary),
    );
  });

  test('detail normalization should preserve the available valid rating', () {
    const target = MediaDetailTarget(
      title: 'Movie',
      posterUrl: '',
      overview: '',
      ratingLabels: ['IMDb 0', 'IMDb 8.6'],
    );
    expect(
      normalizeRatingLabelsInTarget(target).ratingLabels,
      const ['IMDb 8.6'],
    );
  });

  test('detail cache should clear encoded and decoded directory identities',
      () async {
    final repository = LocalStorageCacheRepository(
      sharedPreferences: await SharedPreferences.getInstance(),
    );
    addTearDown(repository.dispose);
    const seed = MediaDetailTarget(
      title: 'Movie',
      posterUrl: '',
      overview: '',
      tmdbId: '123',
    );
    final resolved = seed.copyWith(
      sourceId: 'nas',
      sourceKind: MediaSourceKind.nas,
      itemId: 'https://nas.example/dav/Show%20Name/movie.mkv',
      resourcePath: '/dav/Show Name/movie.mkv',
    );
    await repository.saveDetailTarget(
      seedTarget: seed,
      resolvedTarget: resolved,
    );
    await repository.clearDetailCacheForResource(
      sourceId: 'nas',
      resourcePath: 'https://nas.example/dav/Show%20Name/',
      treatAsScope: true,
    );
    final cached = await repository.loadDetailTarget(seed);
    expect(cached?.sourceId ?? '', isEmpty);
  });

  test('playback history should clear an equivalent encoded directory',
      () async {
    final repository = PlaybackMemoryRepository(
      sharedPreferences: await SharedPreferences.getInstance(),
    );
    const target = PlaybackTarget(
      title: 'Movie',
      sourceId: 'nas',
      streamUrl: 'https://nas.example/video',
      sourceName: 'NAS',
      sourceKind: MediaSourceKind.nas,
      actualAddress: '/dav/Show Name/movie.mkv',
      itemId: 'movie-id',
      itemType: 'movie',
    );
    await repository.saveProgress(
      target: target,
      position: const Duration(minutes: 10),
      duration: const Duration(hours: 2),
    );
    final otherSource = target.copyWith(sourceId: 'other-nas');
    final sibling = target.copyWith(
      itemId: 'sibling',
      actualAddress: '/dav/Show Name Extra/movie.mkv',
    );
    for (final kept in [otherSource, sibling]) {
      await repository.saveProgress(
        target: kept,
        position: const Duration(minutes: 10),
        duration: const Duration(hours: 2),
      );
    }
    await repository.clearEntriesForResource(
      sourceId: 'nas',
      resourcePath: 'https://nas.example/dav/Show%20Name/',
      treatAsScope: true,
    );
    expect(await repository.loadEntryForTarget(target), isNull);
    expect(await repository.loadEntryForTarget(otherSource), isNotNull);
    expect(await repository.loadEntryForTarget(sibling), isNotNull);
  });

  testWidgets('a failed overview refresh should not be persisted as success',
      (tester) async {
    final cache = _RecordingCache();
    final wmdb = _FailingWmdb();
    const target = MediaDetailTarget(
      title: 'Movie',
      posterUrl: '',
      overview: '',
      itemType: 'movie',
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        isTelevisionProvider.overrideWith((ref) => false),
        appSettingsProvider.overrideWithValue(AppSettings.fromJson({
          'mediaSources': const [],
          'searchProviders': const [],
          'homeModules': const [],
          'tmdbMetadataMatchEnabled': false,
          'wmdbMetadataMatchEnabled': true,
          'detailAutoLibraryMatchEnabled': false,
        })),
        localStorageCacheRepositoryProvider.overrideWithValue(cache),
        wmdbMetadataClientProvider.overrideWithValue(wmdb),
        enrichedDetailTargetProvider.overrideWith((ref, target) => target),
      ],
      child: const MaterialApp(home: MediaDetailPage(target: target)),
    ));
    for (var frame = 0; frame < 15; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(wmdb.calls, greaterThan(0));
    expect(cache.statuses, contains(DetailMetadataRefreshStatus.failed));
    expect(
        cache.statuses, isNot(contains(DetailMetadataRefreshStatus.succeeded)));
  });
}

class _RecordingCache extends LocalStorageCacheRepository {
  final statuses = <DetailMetadataRefreshStatus>[];

  @override
  Future<CachedDetailState?> loadDetailState(
    MediaDetailTarget seedTarget, {
    bool allowStructuralMismatch = false,
  }) async =>
      null;

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
    if (metadataRefreshStatus != null) statuses.add(metadataRefreshStatus);
  }
}

class _FailingWmdb extends WmdbMetadataClient {
  _FailingWmdb() : super(MockClient((_) async => http.Response('', 503)));

  int calls = 0;

  @override
  Future<MetadataMatchResult?> matchTitle({
    required String query,
    int year = 0,
    bool preferSeries = false,
    List<String> actors = const [],
  }) async {
    calls += 1;
    throw StateError('metadata unavailable');
  }
}
