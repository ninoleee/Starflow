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
}
