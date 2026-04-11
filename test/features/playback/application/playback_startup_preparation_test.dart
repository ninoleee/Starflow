import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_startup_preparation.dart';
import 'package:starflow/features/playback/application/playback_startup_routing.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
import 'package:starflow/features/playback/domain/playback_memory_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const baseEpisodeTarget = PlaybackTarget(
    title: 'Episode 1',
    sourceId: 'emby-main',
    streamUrl: 'https://emby.example/episode-1.mkv',
    sourceName: 'Emby',
    sourceKind: MediaSourceKind.emby,
    itemId: 'episode-1',
    itemType: 'episode',
    seriesId: 'series-1',
    seriesTitle: 'Show',
    seasonNumber: 1,
    episodeNumber: 1,
  );

  group('preparePlaybackStartup', () {
    test('loads resume and skip preference, then computes startup route',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final repository = PlaybackMemoryRepository(sharedPreferences: prefs);
      final resolvedTarget = baseEpisodeTarget.copyWith(
        width: 3840,
        height: 2160,
        bitrate: 26000000,
        videoCodec: 'hevc',
      );

      await repository.saveProgress(
        target: resolvedTarget,
        position: const Duration(minutes: 12),
        duration: const Duration(minutes: 48),
      );
      await repository.saveSkipPreference(
        SeriesSkipPreference(
          seriesKey: buildSeriesKeyForTarget(resolvedTarget),
          updatedAt: DateTime(2026, 4, 10),
          seriesTitle: 'Show',
          enabled: true,
          introDuration: const Duration(seconds: 88),
          outroDuration: const Duration(seconds: 70),
        ),
      );

      final result = await preparePlaybackStartup(
        PlaybackStartupPreparationInput(
          resolvedTarget: resolvedTarget,
          settings: AppSettings.fromJson(
            const <String, dynamic>{},
          ).copyWith(
            playbackEngine: PlaybackEngine.embeddedMpv,
            performanceAutoDowngradeHeavyPlaybackEnabled: true,
          ),
          isTelevision: true,
          isWeb: false,
        ),
        playbackMemoryRepository: repository,
      );

      expect(result.resolvedTarget, resolvedTarget);
      expect(result.resumeEntry, isNotNull);
      expect(result.resumeEntry!.target.itemId, 'episode-1');
      expect(result.skipPreference, isNotNull);
      expect(result.skipPreference!.enabled, isTrue);
      expect(
        result.startupRoute,
        PlaybackStartupRouteAction.launchPerformanceFallback,
      );
    });

    test('keeps embedded route when no heavy-tv fallback conditions', () async {
      final prefs = await SharedPreferences.getInstance();
      final repository = PlaybackMemoryRepository(sharedPreferences: prefs);
      final resolvedTarget = baseEpisodeTarget.copyWith(
        width: 1920,
        height: 1080,
        bitrate: 6000000,
        videoCodec: 'h264',
      );

      final result = await preparePlaybackStartup(
        PlaybackStartupPreparationInput(
          resolvedTarget: resolvedTarget,
          settings: AppSettings.fromJson(
            const <String, dynamic>{},
          ).copyWith(
            playbackEngine: PlaybackEngine.embeddedMpv,
            performanceAutoDowngradeHeavyPlaybackEnabled: true,
          ),
          isTelevision: false,
          isWeb: false,
        ),
        playbackMemoryRepository: repository,
      );

      expect(result.resumeEntry, isNull);
      expect(result.skipPreference, isNull);
      expect(result.startupRoute, PlaybackStartupRouteAction.openEmbeddedMpv);
    });
  });
}
