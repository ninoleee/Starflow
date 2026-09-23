import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_completion_state.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
import 'package:starflow/features/playback/domain/playback_memory_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('explicit auto-skip completion', () {
    const target = PlaybackTarget(
      title: 'Episode 1',
      sourceId: 'emby-main',
      streamUrl: 'https://emby.example/episode-1.mkv',
      sourceName: 'Emby',
      sourceKind: MediaSourceKind.emby,
      itemId: 'episode-1',
      itemType: 'episode',
      seriesId: 'series-1',
      seriesTitle: 'Series',
      seasonNumber: 1,
      episodeNumber: 1,
    );

    test('repeated 60 percent saves preserve position and the JSON schema',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final repository = PlaybackMemoryRepository(sharedPreferences: prefs);
      final itemKey = buildPlaybackItemKey(target);
      final seriesKey = buildSeriesKeyForTarget(target);
      final state = PlaybackCompletionState()
        ..startMedia(itemKey)
        ..markCompletedByAutoSkip();

      for (var index = 0; index < 3; index++) {
        state.startMedia(itemKey, isRecovery: true);
        await repository.saveProgress(
          target: target,
          position: const Duration(minutes: 6),
          duration: const Duration(minutes: 10),
          completedByAutoSkip: state.completedByAutoSkip,
        );
        final restored = PlaybackMemoryRepository(sharedPreferences: prefs);
        final entry = (await restored.loadEntryForTarget(target))!;
        expect(entry.completed, isTrue);
        expect(entry.canResume, isFalse);
        expect(entry.position, const Duration(minutes: 6));
        expect(entry.duration, const Duration(minutes: 10));
        expect(entry.progress, 0.6);
        final seriesEntry = (await restored.loadSnapshot()).series[seriesKey]!;
        expect(seriesEntry.completed, isTrue);
        expect(seriesEntry.position, entry.position);
        expect(seriesEntry.progress, entry.progress);
      }

      final json = jsonDecode(prefs.getString('starflow.playback.memory.v2')!)
          as Map<String, dynamic>;
      expect(
        json.keys,
        unorderedEquals([
          'items',
          'series',
          'skipPreferences',
          'subtitlePreferences',
        ]),
      );
      final entryJson = (json['items'] as Map)[itemKey] as Map;
      expect(
        entryJson.keys,
        unorderedEquals([
          'key',
          'target',
          'updatedAt',
          'seriesKey',
          'seriesTitle',
          'positionMs',
          'durationMs',
          'progress',
          'completed',
        ]),
      );
      expect(entryJson['completed'], isTrue);
      expect(entryJson['positionMs'], 360000);
      expect(entryJson['durationMs'], 600000);
      expect(entryJson['progress'], 0.6);
      expect((json['series'] as Map)[seriesKey], entryJson);
    });

    test('manual seek clears explicit completion in item and series', () async {
      final repository = PlaybackMemoryRepository(
        sharedPreferences: await SharedPreferences.getInstance(),
      );
      final state = PlaybackCompletionState()
        ..startMedia(buildPlaybackItemKey(target))
        ..markCompletedByAutoSkip();
      await repository.saveProgress(
        target: target,
        position: const Duration(minutes: 6),
        duration: const Duration(minutes: 10),
        completedByAutoSkip: state.completedByAutoSkip,
      );
      state.clearForManualSeek();
      await repository.saveProgress(
        target: target,
        position: const Duration(minutes: 3),
        duration: const Duration(minutes: 10),
        completedByAutoSkip: state.completedByAutoSkip,
      );
      repository.invalidateSnapshotCache();
      final entry = (await repository.loadEntryForTarget(target))!;
      expect(entry.completed, isFalse);
      expect(entry.canResume, isTrue);
      expect(entry.position, const Duration(minutes: 3));
      expect(entry.progress, 0.3);
      final seriesEntry = (await repository.loadSnapshot())
          .series[buildSeriesKeyForTarget(target)]!;
      expect(seriesEntry.completed, isFalse);
    });

    test('omitting the flag never inherits stored completion', () async {
      final repository = PlaybackMemoryRepository(
        sharedPreferences: await SharedPreferences.getInstance(),
      );
      await repository.saveProgress(
        target: target,
        position: const Duration(minutes: 6),
        duration: const Duration(minutes: 10),
        completedByAutoSkip: true,
      );
      await repository.saveProgress(
        target: target,
        position: const Duration(minutes: 6),
        duration: const Duration(minutes: 10),
      );
      final entry = (await repository.loadEntryForTarget(target))!;
      expect(entry.completed, isFalse);
      expect(entry.canResume, isTrue);
    });

    test('new episode is independent of the previous completed episode',
        () async {
      final repository = PlaybackMemoryRepository(
        sharedPreferences: await SharedPreferences.getInstance(),
      );
      final next = target.copyWith(itemId: 'episode-2', episodeNumber: 2);
      final state = PlaybackCompletionState()
        ..startMedia(buildPlaybackItemKey(target))
        ..markCompletedByAutoSkip();
      await repository.saveProgress(
        target: target,
        position: const Duration(minutes: 6),
        duration: const Duration(minutes: 10),
        completedByAutoSkip: state.completedByAutoSkip,
      );
      state.startMedia(buildPlaybackItemKey(next));
      await repository.saveProgress(
        target: next,
        position: const Duration(minutes: 6),
        duration: const Duration(minutes: 10),
        completedByAutoSkip: state.completedByAutoSkip,
      );
      expect((await repository.loadEntryForTarget(target))!.completed, isTrue);
      expect((await repository.loadEntryForTarget(next))!.completed, isFalse);
      final seriesEntry = (await repository.loadSnapshot())
          .series[buildSeriesKeyForTarget(target)]!;
      expect(seriesEntry.target.itemId, 'episode-2');
      expect(seriesEntry.completed, isFalse);
    });

    test('normal completion still uses percentage or remaining time', () async {
      final repository = PlaybackMemoryRepository(
        sharedPreferences: await SharedPreferences.getInstance(),
      );
      for (final sample in [
        (position: 5910, duration: 6000, completed: true),
        (position: 92, duration: 100, completed: true),
        (position: 91, duration: 100, completed: false),
        (position: 60, duration: 100, completed: false),
        (position: 60, duration: 0, completed: false),
      ]) {
        await repository.saveProgress(
          target: target,
          position: Duration(seconds: sample.position),
          duration: Duration(seconds: sample.duration),
        );
        final entry = (await repository.loadEntryForTarget(target))!;
        expect(entry.completed, sample.completed);
        expect(entry.position, Duration(seconds: sample.position));
        expect(entry.duration, Duration(seconds: sample.duration));
      }
    });
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

  test('cached FNTV history drops active transcode sessions', () async {
    final repository = PlaybackMemoryRepository(
        sharedPreferences: await SharedPreferences.getInstance());
    const target = PlaybackTarget(
        title: 'Film',
        sourceId: 'nas',
        streamUrl: 'https://nas/session.m3u8',
        sourceName: 'NAS',
        sourceKind: MediaSourceKind.fntv,
        itemId: 'film',
        fntvSessionLink: '/session.m3u8',
        fntvStartPositionMs: 42000,
        preferredPlaybackQualityIndex: -1);
    await repository.saveProgress(
        target: target,
        position: const Duration(seconds: 42),
        duration: const Duration(minutes: 90));
    final saved = (await repository.loadRecentEntries()).single;
    expect(saved.target.fntvSessionLink, '');
    expect(saved.target.streamUrl, '');
    expect(saved.target.preferredPlaybackQualityIndex, 0);
    expect(saved.position.inSeconds, 42);
  });

  test('reads playback progress written by the Android native player',
      () async {
    const target = PlaybackTarget(
      title: '原生播放测试',
      sourceId: 'emby-main',
      streamUrl: 'https://emby.example/native.mkv',
      sourceName: '客厅 Emby',
      sourceKind: MediaSourceKind.emby,
      itemId: 'native-movie-1',
      itemType: 'movie',
    );
    final itemKey = buildPlaybackItemKey(target);
    final snapshot = PlaybackMemorySnapshot(
      items: {
        itemKey: PlaybackProgressEntry(
          key: itemKey,
          target: target,
          updatedAt: DateTime.utc(2026, 8, 29, 12),
          position: const Duration(minutes: 17, seconds: 24),
          duration: const Duration(hours: 2),
          progress: 0.145,
        ),
      },
    );
    SharedPreferences.setMockInitialValues({
      'flutter.starflow.playback.memory.v2': jsonEncode(snapshot.toJson()),
    });
    final preferences = await SharedPreferences.getInstance();
    final repository = PlaybackMemoryRepository(
      sharedPreferences: preferences,
    );

    final entry = await repository.loadEntryForTarget(target);

    expect(entry, isNotNull);
    expect(entry!.position, const Duration(minutes: 17, seconds: 24));
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

  test('persists subtitle choice per series without affecting other shows',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final repository = PlaybackMemoryRepository(sharedPreferences: prefs);
    const firstEpisode = PlaybackTarget(
      title: '第一集',
      sourceId: 'emby-main',
      streamUrl: 'https://emby.example/series-11-episode-1.mkv',
      sourceName: '客厅 Emby',
      sourceKind: MediaSourceKind.emby,
      itemId: 'episode-1',
      itemType: 'episode',
      seriesId: 'series-11',
      seriesTitle: '请回答1988',
      seasonNumber: 1,
      episodeNumber: 1,
    );
    const secondEpisode = PlaybackTarget(
      title: '第二集',
      sourceId: 'emby-main',
      streamUrl: 'https://emby.example/series-11-episode-2.mkv',
      sourceName: '客厅 Emby',
      sourceKind: MediaSourceKind.emby,
      itemId: 'episode-2',
      itemType: 'episode',
      seriesId: 'series-11',
      seriesTitle: '请回答1988',
      seasonNumber: 1,
      episodeNumber: 2,
    );
    const otherSeries = PlaybackTarget(
      title: '第一集',
      sourceId: 'emby-main',
      streamUrl: 'https://emby.example/series-12-episode-1.mkv',
      sourceName: '客厅 Emby',
      sourceKind: MediaSourceKind.emby,
      itemId: 'other-episode-1',
      itemType: 'episode',
      seriesId: 'series-12',
      seriesTitle: '机智医生生活',
      seasonNumber: 1,
      episodeNumber: 1,
    );
    final seriesKey = buildSeriesKeyForTarget(firstEpisode);
    await repository.saveSubtitlePreference(
      SeriesSubtitlePreference(
        seriesKey: seriesKey,
        updatedAt: DateTime.utc(2026, 8, 30),
        mode: SeriesSubtitlePreferenceMode.dual,
        primary: const SeriesSubtitleTrackPreference(
          label: '简体中文',
          language: 'zh-CN',
        ),
        secondary: const SeriesSubtitleTrackPreference(
          label: 'English',
          language: 'en',
        ),
      ),
    );

    await repository.saveProgress(
      target: firstEpisode,
      position: const Duration(minutes: 8),
      duration: const Duration(minutes: 45),
    );

    final restored = await repository.loadSubtitlePreference(secondEpisode);
    expect(restored, isNotNull);
    expect(restored!.mode, SeriesSubtitlePreferenceMode.dual);
    expect(restored.primary?.language, 'zh-CN');
    expect(restored.secondary?.language, 'en');
    expect(await repository.loadSubtitlePreference(otherSeries), isNull);

    await repository.removeSubtitlePreference(secondEpisode);
    expect(await repository.loadSubtitlePreference(firstEpisode), isNull);
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

  test('serves repeated reads from the cached snapshot', () async {
    const target = PlaybackTarget(
      title: '缓存测试',
      sourceId: 'emby-main',
      streamUrl: 'https://emby.example/cache.mkv',
      sourceName: '客厅 Emby',
      sourceKind: MediaSourceKind.emby,
      itemId: 'cache-movie-1',
      itemType: 'movie',
    );
    final store = _CountingPreferencesStore();
    final repository = PlaybackMemoryRepository(preferences: store);

    await repository.saveProgress(
      target: target,
      position: const Duration(minutes: 5),
      duration: const Duration(hours: 2),
    );
    final readsAfterSave = store.reads;

    await repository.loadEntryForTarget(target);
    await repository.loadSnapshot();
    await repository.saveProgress(
      target: target,
      position: const Duration(minutes: 6),
      duration: const Duration(hours: 2),
    );

    expect(store.reads, readsAfterSave);
    final entry = await repository.loadEntryForTarget(target);
    expect(entry!.position, const Duration(minutes: 6));
  });

  test('re-reads storage after the snapshot cache is invalidated', () async {
    const target = PlaybackTarget(
      title: '失效测试',
      sourceId: 'emby-main',
      streamUrl: 'https://emby.example/invalidate.mkv',
      sourceName: '客厅 Emby',
      sourceKind: MediaSourceKind.emby,
      itemId: 'invalidate-movie-1',
      itemType: 'movie',
    );
    final store = _CountingPreferencesStore();
    final repository = PlaybackMemoryRepository(preferences: store);

    await repository.saveProgress(
      target: target,
      position: const Duration(minutes: 5),
      duration: const Duration(hours: 2),
    );

    // Simulate the native player writing while Flutter was backgrounded.
    final itemKey = buildPlaybackItemKey(target);
    final externalSnapshot = PlaybackMemorySnapshot(
      items: {
        itemKey: PlaybackProgressEntry(
          key: itemKey,
          target: target,
          updatedAt: DateTime.utc(2026, 9, 1, 12),
          position: const Duration(minutes: 42),
          duration: const Duration(hours: 2),
          progress: 0.35,
        ),
      },
    );
    await store.setString(
      'starflow.playback.memory.v2',
      jsonEncode(externalSnapshot.toJson()),
    );

    expect(
      (await repository.loadEntryForTarget(target))!.position,
      const Duration(minutes: 5),
    );

    repository.invalidateSnapshotCache();

    expect(
      (await repository.loadEntryForTarget(target))!.position,
      const Duration(minutes: 42),
    );
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
      playbackResumeForDetailTargetProvider(
        PlaybackResumeDetailLookup(detailTarget),
      ).future,
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

  test('resume detail lookup ignores metadata-only target changes', () async {
    const target = PlaybackTarget(
      title: '共享快照',
      sourceId: 'nas-main',
      streamUrl: 'https://nas.example.com/shared.mkv',
      sourceName: '家庭 NAS',
      sourceKind: MediaSourceKind.nas,
      itemId: 'shared-1',
      itemType: 'movie',
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
    final itemKey = buildPlaybackItemKey(target);
    final snapshot = PlaybackMemorySnapshot(
      items: {
        itemKey: PlaybackProgressEntry(
          key: itemKey,
          target: target,
          updatedAt: DateTime.utc(2026, 8, 29, 12),
          position: const Duration(minutes: 17, seconds: 24),
          duration: const Duration(hours: 2),
          progress: 0.145,
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

    final initial = PlaybackResumeDetailLookup(detailTarget);
    final enriched = PlaybackResumeDetailLookup(
      detailTarget.copyWith(
        posterUrl: 'https://images.example.com/poster.jpg',
        overview: '补充后的简介',
        ratingLabels: const ['豆瓣 8.8'],
      ),
    );

    expect(initial, enriched);
    expect(initial.hashCode, enriched.hashCode);

    final initialEntry = await container.read(
      playbackResumeForDetailTargetProvider(initial).future,
    );
    final enrichedEntry = await container.read(
      playbackResumeForDetailTargetProvider(enriched).future,
    );

    expect(initialEntry, isNotNull);
    expect(initialEntry!.target.itemId, 'shared-1');
    expect(enrichedEntry, isNotNull);
    expect(enrichedEntry!.target.itemId, 'shared-1');
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

class _CountingPreferencesStore extends _MemoryPreferencesStore {
  int reads = 0;

  @override
  Future<String?> getString(String key) {
    reads += 1;
    return super.getString(key);
  }
}

class _MemoryPreferencesStore implements PreferencesStore {
  _MemoryPreferencesStore([Map<String, Object>? initialValues])
      : values = <String, Object>{...?initialValues};

  final Map<String, Object> values;

  @override
  Future<String?> getString(String key) async => values[key] as String?;

  @override
  Future<List<String>?> getStringList(String key) async {
    return (values[key] as List?)?.cast<String>();
  }

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> setStringList(String key, List<String> value) async {
    values[key] = List<String>.from(value);
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}
