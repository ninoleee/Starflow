import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/application/library_cached_items.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

void main() {
  test('library item cache merge uses batch detail lookup', () async {
    final repository = _TrackingLocalStorageCacheRepository(
      batchResults: const [
        MediaDetailTarget(
          title: 'Cached Title',
          posterUrl: 'https://cache.example.com/poster.jpg',
          overview: 'Cached overview',
          ratingLabels: ['豆瓣 9.0'],
        ),
        null,
      ],
    );
    final items = [
      MediaItem(
        id: 'movie-1',
        title: 'Original Title',
        overview: '',
        posterUrl: '',
        year: 2024,
        durationLabel: '',
        genres: const [],
        sourceId: 'emby-main',
        sourceName: 'Living Room',
        sourceKind: MediaSourceKind.emby,
        streamUrl: '',
        addedAt: DateTime(2026, 4, 10),
      ),
      MediaItem(
        id: 'movie-2',
        title: 'Untouched',
        overview: '',
        posterUrl: '',
        year: 2025,
        durationLabel: '',
        genres: const [],
        sourceId: 'emby-main',
        sourceName: 'Living Room',
        sourceKind: MediaSourceKind.emby,
        streamUrl: '',
        addedAt: DateTime(2026, 4, 10),
      ),
    ];

    final resolved = await resolveLibraryItemsWithCachedDetails(
      items: items,
      localStorageCacheRepository: repository,
    );

    expect(repository.batchCallCount, 1);
    expect(repository.singleCallCount, 0);
    expect(resolved[0].title, 'Cached Title');
    expect(resolved[0].posterUrl, 'https://cache.example.com/poster.jpg');
    expect(resolved[0].ratingLabels, ['豆瓣 9.0']);
    expect(resolved[1].title, 'Untouched');
  });
}

class _TrackingLocalStorageCacheRepository extends LocalStorageCacheRepository {
  _TrackingLocalStorageCacheRepository({
    required this.batchResults,
  });

  final List<MediaDetailTarget?> batchResults;
  int batchCallCount = 0;
  int singleCallCount = 0;

  @override
  Future<List<MediaDetailTarget?>> loadDetailTargetsBatch(
    Iterable<MediaDetailTarget> seedTargets,
  ) async {
    batchCallCount += 1;
    expect(seedTargets, hasLength(batchResults.length));
    return batchResults;
  }

  @override
  Future<MediaDetailTarget?> loadDetailTarget(
      MediaDetailTarget seedTarget) async {
    singleCallCount += 1;
    return null;
  }
}
