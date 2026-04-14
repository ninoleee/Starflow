import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
import 'package:starflow/features/playback/domain/playback_memory_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('persists movie progress for resume', () async {
    final prefs = await SharedPreferences.getInstance();
    final repository = PlaybackMemoryRepository(sharedPreferences: prefs);
    const target = PlaybackTarget(
      title: '流浪地球',
      sourceId: 'emby-main',
      streamUrl: 'https://emby.example/movie.mkv',
      sourceName: '客厅 Emby',
      sourceKind: MediaSourceKind.emby,
      itemId: 'movie-1',
      itemType: 'movie',
      year: 2019,
    );

    await repository.saveProgress(
      target: target,
      position: const Duration(minutes: 36, seconds: 12),
      duration: const Duration(hours: 2),
    );

    final entry = await repository.loadEntryForTarget(target);

    expect(entry, isNotNull);
    expect(entry!.canResume, isTrue);
    expect(entry.position, const Duration(minutes: 36, seconds: 12));
    expect(entry.duration, const Duration(hours: 2));
    expect(entry.progress, closeTo(0.3016, 0.001));
  });

  test('stores series aggregate resume with latest episode target', () async {
    final prefs = await SharedPreferences.getInstance();
    final repository = PlaybackMemoryRepository(sharedPreferences: prefs);
    const episodeTarget = PlaybackTarget(
      title: '旧案重提',
      sourceId: 'emby-main',
      streamUrl: 'https://emby.example/episode-3.mkv',
      sourceName: '客厅 Emby',
      sourceKind: MediaSourceKind.emby,
      itemId: 'episode-3',
      itemType: 'episode',
      year: 2024,
      seriesId: 'series-42',
      seriesTitle: '9号秘事',
      seasonNumber: 2,
      episodeNumber: 3,
    );

    await repository.saveProgress(
      target: episodeTarget,
      position: const Duration(minutes: 11, seconds: 5),
      duration: const Duration(minutes: 26),
    );

    final resumeEntry = await repository.loadResumeForDetailTarget(
      const MediaDetailTarget(
        title: '9号秘事',
        posterUrl: '',
        overview: '',
        sourceId: 'emby-main',
        itemId: 'series-42',
        itemType: 'series',
        year: 2024,
      ),
    );

    expect(resumeEntry, isNotNull);
    expect(resumeEntry!.target.itemId, 'episode-3');
    expect(resumeEntry.target.seriesTitle, '9号秘事');
    expect(resumeEntry.target.episodeNumber, 3);
    expect(resumeEntry.canResume, isTrue);
  });

  test('keeps only the latest 20 recent playback entries', () async {
    final prefs = await SharedPreferences.getInstance();
    final repository = PlaybackMemoryRepository(sharedPreferences: prefs);

    for (var index = 0; index < 25; index++) {
      await repository.saveProgress(
        target: PlaybackTarget(
          title: 'Movie $index',
          sourceId: 'nas-main',
          streamUrl: 'https://nas.example/movie-$index.mp4',
          sourceName: '家庭 NAS',
          sourceKind: MediaSourceKind.nas,
          itemId: 'movie-$index',
          itemType: 'movie',
        ),
        position: Duration(minutes: index + 1),
        duration: const Duration(hours: 2),
      );
    }

    final recentEntries = await repository.loadRecentEntries(limit: 40);

    expect(recentEntries, hasLength(20));
    expect(recentEntries.first.target.itemId, 'movie-24');
    expect(
      await repository.loadEntryForTarget(
        const PlaybackTarget(
          title: 'Movie 0',
          sourceId: 'nas-main',
          streamUrl: 'https://nas.example/movie-0.mp4',
          sourceName: '家庭 NAS',
          sourceKind: MediaSourceKind.nas,
          itemId: 'movie-0',
          itemType: 'movie',
        ),
      ),
      isNull,
    );
  });

  test('persists series skip preference per show', () async {
    final prefs = await SharedPreferences.getInstance();
    final repository = PlaybackMemoryRepository(sharedPreferences: prefs);
    const target = PlaybackTarget(
      title: '第一集',
      sourceId: 'emby-main',
      streamUrl: 'https://emby.example/episode-1.mkv',
      sourceName: '客厅 Emby',
      sourceKind: MediaSourceKind.emby,
      itemId: 'episode-1',
      itemType: 'episode',
      seriesId: 'series-11',
      seriesTitle: '请回答1988',
      seasonNumber: 1,
      episodeNumber: 1,
    );

    await repository.saveSkipPreference(
      SeriesSkipPreference(
        seriesKey: buildSeriesKeyForTarget(target),
        updatedAt: DateTime(2026, 4, 6),
        seriesTitle: '请回答1988',
        enabled: true,
        introDuration: const Duration(seconds: 88),
        outroDuration: const Duration(seconds: 72),
      ),
    );

    final preference = await repository.loadSkipPreference(target);

    expect(preference, isNotNull);
    expect(preference!.enabled, isTrue);
    expect(preference.introDuration, const Duration(seconds: 88));
    expect(preference.outroDuration, const Duration(seconds: 72));
    expect(preference.seriesTitle, '请回答1988');
  });

  test('does not persist loopback relay url in playback history', () async {
    final prefs = await SharedPreferences.getInstance();
    final repository = PlaybackMemoryRepository(sharedPreferences: prefs);
    const target = PlaybackTarget(
      title: '夸克电影',
      sourceId: 'quark-main',
      streamUrl: 'http://127.0.0.1:55065/playback-relay/session/movie.mp4',
      sourceName: '夸克',
      sourceKind: MediaSourceKind.quark,
      actualAddress: 'https://webdav.example.com/quark/movie.strm',
      itemId: 'quark-movie-1',
      itemType: 'movie',
      headers: {'Cookie': 'stale-cookie'},
      container: 'mp4',
    );

    await repository.saveProgress(
      target: target,
      position: const Duration(minutes: 8),
      duration: const Duration(minutes: 90),
    );

    final entry = await repository.loadEntryForTarget(target);

    expect(entry, isNotNull);
    expect(entry!.target.streamUrl, isEmpty);
    expect(entry.target.headers, isEmpty);
    expect(entry.target.itemId, 'quark-movie-1');
    expect(entry.target.needsResolution, isTrue);
  });

  test('clears deleted playback entries by resource path', () async {
    final prefs = await SharedPreferences.getInstance();
    final repository = PlaybackMemoryRepository(sharedPreferences: prefs);
    const deletedTarget = PlaybackTarget(
      title: '要删除的电影',
      sourceId: 'nas-main',
      streamUrl: 'https://nas.example.com/deleted.mp4',
      sourceName: '家庭 NAS',
      sourceKind: MediaSourceKind.nas,
      actualAddress: '/movies/要删除的电影.mkv',
      itemId: 'deleted-movie-1',
      itemType: 'movie',
    );
    const keptTarget = PlaybackTarget(
      title: '保留的电影',
      sourceId: 'nas-main',
      streamUrl: 'https://nas.example.com/kept.mp4',
      sourceName: '家庭 NAS',
      sourceKind: MediaSourceKind.nas,
      actualAddress: '/movies/保留的电影.mkv',
      itemId: 'kept-movie-1',
      itemType: 'movie',
    );

    await repository.saveProgress(
      target: deletedTarget,
      position: const Duration(minutes: 10),
      duration: const Duration(hours: 2),
    );
    await repository.saveProgress(
      target: keptTarget,
      position: const Duration(minutes: 20),
      duration: const Duration(hours: 2),
    );

    await repository.clearEntriesForResource(
      sourceId: 'nas-main',
      resourcePath: '/movies/要删除的电影.mkv',
    );

    expect(await repository.loadEntryForTarget(deletedTarget), isNull);
    expect(await repository.loadEntryForTarget(keptTarget), isNotNull);
  });

  test('clears series playback aggregates for deleted directory scopes',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final repository = PlaybackMemoryRepository(sharedPreferences: prefs);
    const episodeTarget = PlaybackTarget(
      title: '第一集',
      sourceId: 'nas-main',
      streamUrl: 'https://nas.example.com/series-1-ep1.mp4',
      sourceName: '家庭 NAS',
      sourceKind: MediaSourceKind.nas,
      actualAddress: '/shows/示例剧/Season 1/Episode 01.mkv',
      itemId: 'episode-1',
      itemType: 'episode',
      seriesId: 'series-1',
      seriesTitle: '示例剧',
      seasonNumber: 1,
      episodeNumber: 1,
    );

    await repository.saveProgress(
      target: episodeTarget,
      position: const Duration(minutes: 12),
      duration: const Duration(minutes: 45),
    );
    await repository.saveSkipPreference(
      SeriesSkipPreference(
        seriesKey: buildSeriesKeyForTarget(episodeTarget),
        updatedAt: DateTime(2026, 4, 12),
        seriesTitle: '示例剧',
        enabled: true,
        introDuration: const Duration(seconds: 90),
      ),
    );

    await repository.clearEntriesForResource(
      sourceId: 'nas-main',
      resourcePath: '/shows/示例剧',
      treatAsScope: true,
    );

    expect(await repository.loadEntryForTarget(episodeTarget), isNull);
    expect(
      await repository.loadResumeForDetailTarget(
        const MediaDetailTarget(
          title: '示例剧',
          posterUrl: '',
          overview: '',
          sourceId: 'nas-main',
          itemId: 'series-1',
          itemType: 'series',
          year: 2026,
        ),
      ),
      isNull,
    );
    expect(await repository.loadSkipPreference(episodeTarget), isNull);
  });

  test('shared snapshot provider serves multiple playback selectors', () async {
    const target = PlaybackTarget(
      title: '共享快照',
      sourceId: 'nas-main',
      streamUrl: 'https://nas.example.com/shared.mkv',
      sourceName: '家庭 NAS',
      sourceKind: MediaSourceKind.nas,
      itemId: 'shared-1',
      itemType: 'movie',
    );
    final snapshot = PlaybackMemorySnapshot(
      items: {
        buildPlaybackItemKey(target): PlaybackProgressEntry(
          key: buildPlaybackItemKey(target),
          target: target,
          updatedAt: DateTime.utc(2026, 4, 14),
          position: const Duration(minutes: 12),
          duration: const Duration(hours: 2),
          progress: 0.1,
        ),
      },
    );
    final repository = _CountingPlaybackMemoryRepository(snapshot);
    final container = ProviderContainer(
      overrides: [
        playbackMemoryRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final mediaItem = MediaItem(
      id: 'shared-1',
      title: '共享快照',
      overview: '',
      posterUrl: '',
      year: 2026,
      durationLabel: '',
      genres: const [],
      sourceId: 'nas-main',
      sourceName: '家庭 NAS',
      sourceKind: MediaSourceKind.nas,
      streamUrl: 'https://nas.example.com/shared.mkv',
      playbackItemId: 'shared-1',
      itemType: 'movie',
      addedAt: DateTime.utc(2026, 4, 14),
    );
    const detailTarget = MediaDetailTarget(
      title: '共享快照',
      posterUrl: '',
      overview: '',
      playbackTarget: target,
      sourceId: 'nas-main',
      itemId: 'shared-1',
      itemType: 'movie',
    );

    final resume = await container.read(
      playbackResumeForDetailTargetProvider(detailTarget).future,
    );
    final entry = await container.read(
      playbackEntryForMediaItemProvider(mediaItem).future,
    );
    final recent =
        await container.read(recentPlaybackEntriesProvider(5).future);

    expect(resume, isNotNull);
    expect(entry, isNotNull);
    expect(recent, hasLength(1));
    expect(repository.loadSnapshotCount, 1);
  });
}

class _CountingPlaybackMemoryRepository extends PlaybackMemoryRepository {
  _CountingPlaybackMemoryRepository(this.snapshot);

  final PlaybackMemorySnapshot snapshot;
  int loadSnapshotCount = 0;

  @override
  Future<PlaybackMemorySnapshot> loadSnapshot() async {
    loadSnapshotCount += 1;
    return snapshot;
  }
}
