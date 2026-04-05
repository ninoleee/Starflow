import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('persists matched and enriched detail targets for later reuse',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final repository = LocalStorageCacheRepository(sharedPreferences: prefs);

    const seedTarget = MediaDetailTarget(
      title: '英雄本色',
      posterUrl: '',
      overview: '',
      year: 1986,
      searchQuery: '英雄本色',
      doubanId: '1297574',
    );
    final resolvedTarget = seedTarget.copyWith(
      posterUrl: 'https://image.example/poster.jpg',
      overview: '这是缓存下来的简介。',
      ratingLabels: const ['豆瓣 8.7', 'IMDb 7.5'],
      sourceId: 'emby-main',
      itemId: 'movie-1',
      sourceName: '客厅 Emby',
      sourceKind: MediaSourceKind.emby,
      imdbId: 'tt0092263',
      playbackTarget: const PlaybackTarget(
        title: '英雄本色',
        sourceId: 'emby-main',
        streamUrl: 'https://emby.example/stream',
        sourceName: '客厅 Emby',
        sourceKind: MediaSourceKind.emby,
        actualAddress: '/movies/英雄本色.mkv',
        itemId: 'movie-1',
      ),
    );

    await repository.saveDetailTarget(
      seedTarget: seedTarget,
      resolvedTarget: resolvedTarget,
    );

    final loadedFromDoubanKey = await repository.loadDetailTarget(seedTarget);
    final loadedFromLibraryKey = await repository.loadDetailTarget(
      const MediaDetailTarget(
        title: '英雄本色',
        posterUrl: '',
        overview: '',
        sourceId: 'emby-main',
        itemId: 'movie-1',
      ),
    );

    expect(loadedFromDoubanKey, isNotNull);
    expect(loadedFromDoubanKey!.imdbId, 'tt0092263');
    expect(
        loadedFromDoubanKey.playbackTarget?.actualAddress, '/movies/英雄本色.mkv');
    expect(loadedFromLibraryKey?.posterUrl, 'https://image.example/poster.jpg');

    final summary = await repository.inspectDetailCache();
    expect(summary.entryCount, 1);
    expect(summary.totalBytes, greaterThan(0));
  });

  test('clears persisted detail cache', () async {
    final prefs = await SharedPreferences.getInstance();
    final repository = LocalStorageCacheRepository(sharedPreferences: prefs);

    await repository.saveDetailTarget(
      seedTarget: const MediaDetailTarget(
        title: '示例',
        posterUrl: '',
        overview: '',
      ),
      resolvedTarget: const MediaDetailTarget(
        title: '示例',
        posterUrl: 'https://image.example/poster.jpg',
        overview: 'ok',
      ),
    );

    await repository.clearDetailCache();

    final loaded = await repository.loadDetailTarget(
      const MediaDetailTarget(
        title: '示例',
        posterUrl: '',
        overview: '',
      ),
    );
    final summary = await repository.inspectDetailCache();

    expect(loaded, isNull);
    expect(summary.entryCount, 0);
  });
}
