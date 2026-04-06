import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
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
      tmdbId: '1091',
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
    expect(loadedFromDoubanKey.tmdbId, '1091');
    expect(
        loadedFromDoubanKey.playbackTarget?.actualAddress, '/movies/英雄本色.mkv');
    expect(loadedFromLibraryKey?.posterUrl, 'https://image.example/poster.jpg');
    expect(
      (await repository.loadDetailTarget(
        const MediaDetailTarget(
          title: '英雄本色',
          posterUrl: '',
          overview: '',
          tmdbId: '1091',
        ),
      ))
          ?.imdbId,
      'tt0092263',
    );

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

  test('removes only the deleted resource from cached match choices', () async {
    final prefs = await SharedPreferences.getInstance();
    final repository = LocalStorageCacheRepository(sharedPreferences: prefs);

    const seedTarget = MediaDetailTarget(
      title: '星际穿越',
      posterUrl: '',
      overview: '',
      year: 2014,
      searchQuery: '星际穿越',
      doubanId: '1889243',
    );
    const deletedChoice = MediaDetailTarget(
      title: '星际穿越',
      posterUrl: '',
      overview: '',
      year: 2014,
      availabilityLabel: '资源已就绪：WebDAV · nas',
      sourceId: 'nas-main',
      itemId: 'https://nas.example.com/dav/Movies/Interstellar.mkv',
      itemType: 'movie',
      sectionId: 'https://nas.example.com/dav/Movies/',
      sectionName: 'Movies',
      resourcePath: '/dav/Movies/Interstellar.mkv',
      sourceKind: MediaSourceKind.nas,
      sourceName: 'nas',
    );
    const remainingChoice = MediaDetailTarget(
      title: '星际穿越',
      posterUrl: '',
      overview: '',
      year: 2014,
      availabilityLabel: '资源已就绪：WebDAV · nas',
      sourceId: 'nas-main',
      itemId: 'https://nas.example.com/dav/Movies/Interstellar-Alt.mkv',
      itemType: 'movie',
      sectionId: 'https://nas.example.com/dav/Movies/',
      sectionName: 'Movies',
      resourcePath: '/dav/Movies/Interstellar-Alt.mkv',
      sourceKind: MediaSourceKind.nas,
      sourceName: 'nas',
    );

    await repository.saveDetailTarget(
      seedTarget: seedTarget,
      resolvedTarget: deletedChoice,
      libraryMatchChoices: const [deletedChoice, remainingChoice],
      selectedLibraryMatchIndex: 0,
    );

    await repository.clearDetailCacheForResource(
      sourceId: 'nas-main',
      resourceId: 'https://nas.example.com/dav/Movies/Interstellar.mkv',
      resourcePath: '/dav/Movies/Interstellar.mkv',
    );

    final cachedState = await repository.loadDetailState(seedTarget);
    expect(cachedState, isNotNull);
    expect(cachedState!.target.itemId, remainingChoice.itemId);
    expect(cachedState.libraryMatchChoices.map((item) => item.itemId), [
      remainingChoice.itemId,
    ]);
    expect(cachedState.selectedLibraryMatchIndex, 0);
    expect(
      await repository.loadDetailTarget(
        const MediaDetailTarget(
          title: '',
          posterUrl: '',
          overview: '',
          sourceId: 'nas-main',
          itemId: 'https://nas.example.com/dav/Movies/Interstellar.mkv',
        ),
      ),
      isNull,
    );
  });

  test('strips resolved local state when deleted resource was the only match',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final repository = LocalStorageCacheRepository(sharedPreferences: prefs);

    const seedTarget = MediaDetailTarget(
      title: '黑客帝国',
      posterUrl: '',
      overview: '',
      year: 1999,
      searchQuery: '黑客帝国',
      tmdbId: '603',
    );
    final resolvedTarget = seedTarget.copyWith(
      availabilityLabel: '资源已就绪：WebDAV · nas',
      sourceId: 'nas-main',
      itemId: 'https://nas.example.com/dav/Movies/The%20Matrix.mkv',
      itemType: 'movie',
      sectionId: 'https://nas.example.com/dav/Movies/',
      sectionName: 'Movies',
      resourcePath: '/dav/Movies/The Matrix.mkv',
      sourceKind: MediaSourceKind.nas,
      sourceName: 'nas',
      playbackTarget: const PlaybackTarget(
        title: '黑客帝国',
        sourceId: 'nas-main',
        streamUrl: 'https://nas.example.com/dav/Movies/The%20Matrix.mkv',
        sourceName: 'nas',
        sourceKind: MediaSourceKind.nas,
        actualAddress: '/dav/Movies/The Matrix.mkv',
      ),
    );

    await repository.saveDetailTarget(
      seedTarget: seedTarget,
      resolvedTarget: resolvedTarget,
    );

    await repository.clearDetailCacheForResource(
      sourceId: 'nas-main',
      resourceId: 'https://nas.example.com/dav/Movies/The%20Matrix.mkv',
      resourcePath: '/dav/Movies/The Matrix.mkv',
    );

    final cached = await repository.loadDetailTarget(seedTarget);
    expect(cached, isNotNull);
    expect(cached!.sourceId, isEmpty);
    expect(cached.itemId, isEmpty);
    expect(cached.resourcePath, isEmpty);
    expect(cached.sourceName, isEmpty);
    expect(cached.playbackTarget, isNull);
    expect(cached.availabilityLabel, '无');
    expect(cached.tmdbId, '603');
    expect(
      await repository.loadDetailTarget(
        const MediaDetailTarget(
          title: '',
          posterUrl: '',
          overview: '',
          sourceId: 'nas-main',
          itemId: 'https://nas.example.com/dav/Movies/The%20Matrix.mkv',
        ),
      ),
      isNull,
    );
  });

  test('persists cached subtitle choices and selected subtitle index',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final repository = LocalStorageCacheRepository(sharedPreferences: prefs);

    const seedTarget = MediaDetailTarget(
      title: 'Planet Earth II',
      posterUrl: '',
      overview: '',
      year: 2016,
      searchQuery: 'Planet Earth II',
    );
    const resolvedTarget = MediaDetailTarget(
      title: 'Planet Earth II',
      posterUrl: '',
      overview: '',
      year: 2016,
      searchQuery: 'Planet Earth II',
      availabilityLabel: '资源已就绪：Emby · 客厅 Emby',
      sourceId: 'emby-main',
      itemId: 'planet-earth-ii',
      itemType: 'series',
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
    const subtitleChoices = [
      CachedSubtitleSearchOption(
        result: SubtitleSearchResult(
          id: 'sub-1',
          source: OnlineSubtitleSource.assrt,
          providerLabel: 'ASSRT',
          title: 'Planet Earth II S01E01',
          version: 'WEB-DL',
          formatLabel: 'ASS',
          languageLabel: '中英双语',
          sourceLabel: 'ASSRT',
          publishDateLabel: '2024-01-01',
          downloadCount: 12,
          ratingLabel: '评分 9',
          downloadUrl: 'https://assrt.net/download/1/subtitle.ass',
          detailUrl: 'https://assrt.net/sub/1',
          packageName: 'Planet.Earth.II.ass',
          packageKind: SubtitlePackageKind.subtitleFile,
        ),
      ),
      CachedSubtitleSearchOption(
        result: SubtitleSearchResult(
          id: 'sub-2',
          source: OnlineSubtitleSource.assrt,
          providerLabel: 'ASSRT',
          title: 'Planet Earth II S01E01 Alt',
          version: 'BluRay',
          formatLabel: 'SRT',
          languageLabel: '简体中文',
          sourceLabel: 'ASSRT',
          publishDateLabel: '2024-01-02',
          downloadCount: 8,
          ratingLabel: '',
          downloadUrl: 'https://assrt.net/download/2/subtitle.srt',
          detailUrl: 'https://assrt.net/sub/2',
          packageName: 'Planet.Earth.II.srt',
          packageKind: SubtitlePackageKind.subtitleFile,
        ),
        selection: SubtitleSearchSelection(
          cachedPath: '/cache/sub-2',
          displayName: 'Planet Earth II',
          subtitleFilePath: '/cache/sub-2/Planet.Earth.II.srt',
        ),
      ),
    ];

    await repository.saveDetailTarget(
      seedTarget: seedTarget,
      resolvedTarget: resolvedTarget,
      subtitleSearchChoices: subtitleChoices,
      selectedSubtitleSearchIndex: 1,
    );

    final cachedState = await repository.loadDetailState(seedTarget);
    expect(cachedState, isNotNull);
    expect(cachedState!.subtitleSearchChoices, hasLength(2));
    expect(cachedState.selectedSubtitleSearchIndex, 1);
    expect(cachedState.subtitleSearchChoices[1].result.id, 'sub-2');
    expect(
      cachedState.subtitleSearchChoices[1].selection?.subtitleFilePath,
      '/cache/sub-2/Planet.Earth.II.srt',
    );
  });
}
