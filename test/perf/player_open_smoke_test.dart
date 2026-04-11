import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_engine_router.dart';
import 'package:starflow/features/playback/application/playback_startup_coordinator.dart';
import 'package:starflow/features/playback/application/playback_startup_executor.dart';
import 'package:starflow/features/playback/application/playback_startup_routing.dart';
import 'package:starflow/features/playback/application/playback_target_resolver.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
import 'package:starflow/features/playback/domain/playback_memory_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('player open path exercises coordinator, resolver, and executor',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final memoryRepository = PlaybackMemoryRepository(sharedPreferences: prefs);

    const target = PlaybackTarget(
      title: 'Perf Episode',
      sourceId: 'emby-perf',
      streamUrl: 'https://example.com/stream.mkv',
      sourceName: 'Perf Emby',
      sourceKind: MediaSourceKind.emby,
      itemId: 'episode:1',
      itemType: 'episode',
      seriesId: 'series-42',
      seriesTitle: 'Perf Show',
      width: 3840,
      height: 2160,
      bitrate: 26000000,
      videoCodec: 'hevc',
    );

    await memoryRepository.saveProgress(
      target: target,
      position: const Duration(minutes: 3),
      duration: const Duration(minutes: 48),
    );
    await memoryRepository.saveSkipPreference(
      SeriesSkipPreference(
        seriesKey: buildSeriesKeyForTarget(target),
        updatedAt: DateTime(2026, 4, 10),
        seriesTitle: 'Perf Show',
        enabled: true,
        introDuration: const Duration(seconds: 8),
        outroDuration: const Duration(seconds: 6),
      ),
    );

    final settings = AppSettings.fromJson(const <String, dynamic>{}).copyWith(
      mediaSources: const [
        MediaSourceConfig(
          id: 'emby-perf',
          name: 'Perf Emby',
          kind: MediaSourceKind.emby,
          endpoint: 'https://perf.example',
          enabled: true,
          accessToken: 'token',
          userId: 'user',
        ),
      ],
      playbackEngine: PlaybackEngine.embeddedMpv,
      performanceAutoDowngradeHeavyPlaybackEnabled: true,
    );

    final container = ProviderContainer(
      overrides: [
        mediaRepositoryProvider.overrideWithValue(const _PerfMediaRepository()),
        playbackMemoryRepositoryProvider.overrideWithValue(memoryRepository),
        appSettingsProvider.overrideWithValue(settings),
      ],
    );
    addTearDown(container.dispose);

    final coordinator = PlaybackStartupCoordinator(
      read: container.read,
      targetResolver: PlaybackTargetResolver(read: container.read),
      engineRouter: const PlaybackEngineRouter(),
    );

    final outcome = await coordinator.start(
      initialTarget: target,
      isTelevision: true,
      isWeb: false,
    );

    expect(outcome.startupPreparation.resumeEntry, isNotNull);
    expect(outcome.startupPreparation.skipPreference?.enabled, isTrue);
    expect(
      outcome.startupPreparation.startupRoute,
      PlaybackStartupRouteAction.launchPerformanceFallback,
    );

    final actions = <String>[];
    final executor = PlaybackStartupExecutor(
      launchSystemPlayer: (_) async => actions.add('launch-system'),
      launchNativeContainer: (_) async => actions.add('launch-native'),
      launchPerformanceFallback: (_) async {
        actions.add('launch-performance');
        return false;
      },
    );

    final shouldOpenEmbedded = await executor.execute(
      outcome.routeAction,
      outcome.resolvedTarget,
    );

    expect(actions, ['launch-performance']);
    expect(shouldOpenEmbedded, isTrue);
  });
}

class _PerfMediaRepository implements MediaRepository {
  const _PerfMediaRepository();

  @override
  Future<void> cancelActiveWebDavRefreshes(
      {bool includeForceFull = false}) async {}

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
  }) async =>
      const [];

  @override
  Future<List<MediaItem>> fetchChildren({
    required String sourceId,
    required String parentId,
    String sectionId = '',
    String sectionName = '',
    int limit = 200,
  }) async =>
      const [];

  @override
  Future<List<MediaItem>> fetchLibrary({
    MediaSourceKind? kind,
    String? sourceId,
    String? sectionId,
    int limit = 200,
  }) async =>
      const [];

  @override
  Future<List<MediaItem>> fetchRecentlyAdded({
    MediaSourceKind? kind,
    int limit = 10,
  }) async =>
      const [];

  @override
  Future<List<MediaSourceConfig>> fetchSources() async => const [];

  @override
  Future<MediaItem?> findById(String id) async => null;

  @override
  Future<MediaItem?> matchTitle(String title) async => null;

  @override
  Future<void> refreshSource({
    required String sourceId,
    bool forceFullRescan = false,
  }) async {}
}
