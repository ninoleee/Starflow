import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:riverpod/misc.dart';
import 'package:sembast/sembast.dart' show Database;
import 'package:sembast/sembast_io.dart' show databaseFactoryIo;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/app/app.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/media_detail_page.dart';
import 'package:starflow/features/home/application/home_controller.dart';
import 'package:starflow/features/home/presentation/home_page.dart';
import 'package:starflow/features/library/application/webdav_scrape_progress.dart';
import 'package:starflow/features/library/data/nas_media_index_store.dart';
import 'package:starflow/features/library/data/nas_media_indexer.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/metadata/data/imdb_rating_client.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';
import 'package:starflow/features/metadata/data/wmdb_metadata_client.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/presentation/player_page.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

const _runId =
    String.fromEnvironment('STARFLOW_PERF_RUN_ID', defaultValue: '1');
const _frameBudgetMicros = int.fromEnvironment(
  'STARFLOW_PERF_FRAME_BUDGET_US',
  defaultValue: 16667,
);
const _scenarioNames = <String>[
  'startup',
  'home_first_frame',
  'detail_open',
  'player_open',
  'media_index',
];

final _settings = SeedData.defaultSettings.copyWith(
  mediaSources: const [],
  searchProviders: const [],
  homeModules: const [
    HomeModuleConfig(
      id: 'perf-home-1',
      type: HomeModuleType.doubanList,
      title: '性能基线 · 最近更新',
      enabled: true,
      doubanListUrl: 'local://perf/home-1',
    ),
    HomeModuleConfig(
      id: 'perf-home-2',
      type: HomeModuleType.doubanList,
      title: '性能基线 · 高分电影',
      enabled: true,
      doubanListUrl: 'local://perf/home-2',
    ),
  ],
  homeHeroBackgroundEnabled: false,
  homeStartupAutoRefreshEnabled: false,
  detailAutoLibraryMatchEnabled: false,
  wmdbMetadataMatchEnabled: false,
  tmdbMetadataMatchEnabled: false,
  imdbRatingMatchEnabled: false,
  playbackEngine: PlaybackEngine.embeddedMpv,
);

final _detailTarget = MediaDetailTarget(
  title: '星际性能基线',
  posterUrl: '',
  backdropUrl: '',
  overview: '这是一个完全本地、固定内容的详情页场景，用于测量布局和首屏渲染。',
  year: 2026,
  durationLabel: '128 分钟',
  ratingLabels: const ['IMDb 8.8', '豆瓣 9.1'],
  genres: const ['剧情', '科幻', '冒险'],
  directors: const ['Baseline Director'],
  actors: const [
    'Actor One',
    'Actor Two',
    'Actor Three',
    'Actor Four',
  ],
  availabilityLabel: '本地性能夹具',
  searchQuery: '星际性能基线',
  itemId: 'perf-detail-1',
  sourceId: 'perf-source',
  itemType: 'movie',
  sectionId: 'perf-section',
  sectionName: '性能基线',
  sourceKind: MediaSourceKind.nas,
  sourceName: '本地性能夹具',
);

final _homeSections = List<HomeSectionViewModel>.generate(2, (sectionIndex) {
  final sectionId = 'perf-home-${sectionIndex + 1}';
  return HomeSectionViewModel(
    id: sectionId,
    title: sectionIndex == 0 ? '最近更新' : '高分电影',
    subtitle: '固定本地数据',
    emptyMessage: '',
    layout: HomeSectionLayout.posterRail,
    items: List<HomeCardViewModel>.generate(16, (itemIndex) {
      return HomeCardViewModel(
        id: '$sectionId-item-$itemIndex',
        title: '影片 ${sectionIndex + 1}-${itemIndex + 1}',
        subtitle:
            '${2026 - itemIndex % 8} · ${(8.0 + itemIndex / 20).toStringAsFixed(1)}',
        posterUrl: '',
        detailTarget: _detailTarget,
      );
    }),
  );
});

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets('profile device performance baseline', (tester) async {
    expect(kProfileMode, isTrue,
        reason: 'Performance baselines must run in profile mode.');
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final scenarios = <String, Map<String, Object?>>{};

    scenarios['startup'] = await _measureScenario(
      binding: binding,
      name: 'startup',
      action: () async {
        final stopwatch = Stopwatch()..start();
        await tester.pumpWidget(_buildStartupApp(preferences));
        await _pumpUntil(
          tester,
          find.byKey(const ValueKey<String>('home:section-slot:perf-home-1')),
          timeout: const Duration(seconds: 20),
        );
        final ready = stopwatch.elapsed;
        await _pumpFrames(tester, 12);
        return ready;
      },
    );
    await _unmount(tester);

    scenarios['home_first_frame'] = await _measureScenario(
      binding: binding,
      name: 'home_first_frame',
      action: () async {
        final stopwatch = Stopwatch()..start();
        await tester.pumpWidget(_buildPage(const HomePage(), preferences));
        await _pumpUntil(
          tester,
          find.byKey(const ValueKey<String>('home:section-slot:perf-home-1')),
          timeout: const Duration(seconds: 12),
        );
        final ready = stopwatch.elapsed;
        await _pumpFrames(tester, 12);
        return ready;
      },
    );
    await _unmount(tester);

    scenarios['detail_open'] = await _measureScenario(
      binding: binding,
      name: 'detail_open',
      action: () async {
        final stopwatch = Stopwatch()..start();
        await tester.pumpWidget(
          _buildPage(MediaDetailPage(target: _detailTarget), preferences),
        );
        await _pumpUntil(
          tester,
          find.text(_detailTarget.title),
          timeout: const Duration(seconds: 12),
        );
        final ready = stopwatch.elapsed;
        await _pumpFrames(tester, 12);
        return ready;
      },
    );
    await _unmount(tester);

    final video = await _createVideoFixture();
    try {
      scenarios['player_open'] = await _measureScenario(
        binding: binding,
        name: 'player_open',
        action: () async {
          final stopwatch = Stopwatch()..start();
          await tester.pumpWidget(
            _buildPage(
              PlayerPage(
                target: PlaybackTarget(
                  title: '本地 H.264 性能夹具',
                  sourceId: 'perf-source',
                  streamUrl: Uri.file(video.path).toString(),
                  actualAddress: video.path,
                  sourceName: '本地性能夹具',
                  sourceKind: MediaSourceKind.nas,
                  itemId: 'perf-video-1',
                  itemType: 'movie',
                  container: 'mp4',
                  videoCodec: 'h264',
                  width: 320,
                  height: 180,
                  allowResume: false,
                ),
              ),
              preferences,
            ),
          );
          await _pumpUntil(
            tester,
            find.byKey(const ValueKey<String>('player:first-frame')),
            timeout: const Duration(seconds: 30),
          );
          final ready = stopwatch.elapsed;
          await _pumpFrames(tester, 8);
          return ready;
        },
      );
    } finally {
      await _unmount(tester);
      final directory = video.parent;
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }

    scenarios['media_index'] = await _measureScenario(
      binding: binding,
      name: 'media_index',
      action: () async {
        final stopwatch = Stopwatch()..start();
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          ),
        );
        await tester.pump();
        final indexedCount = await _runMediaIndexFixture();
        expect(indexedCount, greaterThanOrEqualTo(600));
        final ready = stopwatch.elapsed;
        await _pumpFrames(tester, 8);
        return ready;
      },
    );
    await _unmount(tester);

    expect(scenarios.keys.toList(), orderedEquals(_scenarioNames));
    binding.reportData = <String, Object?>{
      'schemaVersion': 1,
      'runId': _runId,
      'mode': 'profile',
      'platform': defaultTargetPlatform.name,
      'frameBudgetMicros': _frameBudgetMicros,
      'scenarios': scenarios,
    };
  }, timeout: const Timeout(Duration(minutes: 5)));
}

Widget _buildStartupApp(SharedPreferences preferences) {
  return ProviderScope(
    overrides: _providerOverrides(preferences),
    child: const StarflowApp(),
  );
}

Widget _buildPage(Widget page, SharedPreferences preferences) {
  return ProviderScope(
    overrides: _providerOverrides(preferences),
    child: MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: page,
    ),
  );
}

List<Override> _providerOverrides(SharedPreferences preferences) {
  return <Override>[
    settingsControllerProvider.overrideWith(
      () => _PerformanceSettingsController(_settings),
    ),
    isTelevisionProvider.overrideWith((ref) async => false),
    playbackMemoryRepositoryProvider.overrideWithValue(
      PlaybackMemoryRepository(sharedPreferences: preferences),
    ),
    homeResolvedSectionsProvider.overrideWith(
      (ref) => HomeResolvedSectionsState(sections: _homeSections),
    ),
    homeSectionProvider.overrideWith((ref, moduleId) async {
      return _homeSections
          .where((section) => section.id == moduleId)
          .firstOrNull;
    }),
  ];
}

class _PerformanceSettingsController extends SettingsController {
  _PerformanceSettingsController(this.settings);

  final AppSettings settings;

  @override
  FutureOr<AppSettings> build() => settings;
}

Future<Map<String, Object?>> _measureScenario({
  required IntegrationTestWidgetsFlutterBinding binding,
  required String name,
  required Future<Duration> Function() action,
}) async {
  final reportKey = 'frames_$name';
  var rssStart = 0;
  var rssPeak = 0;
  var rssEnd = 0;
  var readyDuration = Duration.zero;
  Timer? sampler;

  await binding.watchPerformance(() async {
    rssStart = ProcessInfo.currentRss;
    rssPeak = rssStart;
    sampler = Timer.periodic(const Duration(milliseconds: 20), (_) {
      final current = ProcessInfo.currentRss;
      if (current > rssPeak) {
        rssPeak = current;
      }
    });
    try {
      readyDuration = await action();
    } finally {
      sampler?.cancel();
      rssEnd = ProcessInfo.currentRss;
      if (rssEnd > rssPeak) {
        rssPeak = rssEnd;
      }
    }
  }, reportKey: reportKey);

  final raw = Map<String, dynamic>.from(
    binding.reportData?[reportKey] as Map? ?? const <String, dynamic>{},
  );
  final buildTimes = _numberList(raw['frame_build_times']);
  final rasterTimes = _numberList(raw['frame_rasterizer_times']);
  final frameCount = raw['frame_count'] as int? ??
      (buildTimes.length > rasterTimes.length
          ? buildTimes.length
          : rasterTimes.length);
  var slowFrames = 0;
  for (var index = 0; index < frameCount; index += 1) {
    final build = index < buildTimes.length ? buildTimes[index] : 0;
    final raster = index < rasterTimes.length ? rasterTimes[index] : 0;
    if (build > _frameBudgetMicros || raster > _frameBudgetMicros) {
      slowFrames += 1;
    }
  }
  binding.reportData?.remove(reportKey);

  return <String, Object?>{
    'durationMs': _round(readyDuration.inMicroseconds / 1000),
    'frameCount': frameCount,
    'slowFrameCount': slowFrames,
    'slowFrameRate': frameCount == 0 ? 0.0 : _round(slowFrames / frameCount),
    'frameBudgetMs': _round(_frameBudgetMicros / 1000),
    'rssStartMiB': _mib(rssStart),
    'rssPeakMiB': _mib(rssPeak),
    'rssEndMiB': _mib(rssEnd),
    'rssDeltaMiB': _round((rssEnd - rssStart) / (1024 * 1024)),
    'missedBuildBudgetCount': raw['missed_frame_build_budget_count'] ?? 0,
    'missedRasterBudgetCount': raw['missed_frame_rasterizer_budget_count'] ?? 0,
  };
}

List<num> _numberList(Object? value) {
  return value is List
      ? value.whereType<num>().toList(growable: false)
      : const [];
}

double _mib(int bytes) => _round(bytes / (1024 * 1024));

double _round(num value) => double.parse(value.toStringAsFixed(3));

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  required Duration timeout,
}) async {
  final stopwatch = Stopwatch()..start();
  while (finder.evaluate().isEmpty && stopwatch.elapsed < timeout) {
    await Future<void>.delayed(const Duration(milliseconds: 16));
    await tester.pump();
  }
  if (finder.evaluate().isEmpty) {
    final visibleText = find
        .byType(Text)
        .evaluate()
        .map((element) => (element.widget as Text).data)
        .whereType<String>()
        .where((text) => text.trim().isNotEmpty)
        .take(20)
        .join(' | ');
    debugPrint('Timeout diagnostics: $visibleText');
  }
  expect(finder, findsWidgets,
      reason: 'Timed out after $timeout waiting for $finder.');
}

Future<void> _pumpFrames(WidgetTester tester, int count) async {
  for (var index = 0; index < count; index += 1) {
    await Future<void>.delayed(const Duration(milliseconds: 16));
    await tester.pump();
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await Future<void>.delayed(const Duration(milliseconds: 100));
}

Future<File> _createVideoFixture() async {
  final bytes = await rootBundle.load('assets/perf/baseline.mp4');
  final directory =
      await Directory.systemTemp.createTemp('starflow-perf-video-');
  final file = File('${directory.path}/baseline.mp4');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file;
}

Future<int> _runMediaIndexFixture() async {
  final temp = await Directory.systemTemp.createTemp('starflow-perf-index-');
  Database? database;
  NasMediaIndexer? indexer;
  try {
    database = await databaseFactoryIo.openDatabase('${temp.path}/index.db');
    final items = _buildIndexItems();
    final settings = _settings.copyWith(
      mediaSources: const [],
      wmdbMetadataMatchEnabled: false,
      tmdbMetadataMatchEnabled: false,
      imdbRatingMatchEnabled: false,
    );
    final failingClient = MockClient((request) async => http.Response('', 500));
    final store =
        SembastNasMediaIndexStore(databaseOpener: () async => database!);
    indexer = NasMediaIndexer(
      store: store,
      webDavNasClient: _FixtureWebDavNasClient(items),
      wmdbMetadataClient: WmdbMetadataClient(failingClient),
      tmdbMetadataClient: TmdbMetadataClient(failingClient),
      imdbRatingClient: ImdbRatingClient(failingClient),
      readSettings: () => settings,
      progressController: WebDavScrapeProgressController(),
    );
    const source = MediaSourceConfig(
      id: 'perf-index-source',
      name: '性能索引夹具',
      kind: MediaSourceKind.nas,
      endpoint: 'https://perf.invalid/Shows/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
    );
    const collection = MediaCollection(
      id: 'https://perf.invalid/Shows/',
      title: '剧集',
      sourceId: 'perf-index-source',
      sourceName: '性能索引夹具',
      sourceKind: MediaSourceKind.nas,
    );
    await indexer.refreshSource(
      source,
      scopedCollections: const [collection],
      limitPerCollection: items.length,
      forceFullRescan: true,
    );
    final records = await store.loadSourceRecords(source.id);
    return records.length;
  } finally {
    await indexer?.dispose();
    await database?.close();
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  }
}

List<WebDavScannedItem> _buildIndexItems() {
  final baseTime = DateTime.utc(2026, 1, 1);
  return List<WebDavScannedItem>.generate(600, (index) {
    final series = index ~/ 20 + 1;
    final season = index % 20 ~/ 10 + 1;
    final episode = index % 10 + 1;
    final id =
        'series-$series-s${season.toString().padLeft(2, '0')}-e${episode.toString().padLeft(2, '0')}';
    final path =
        'https://perf.invalid/Shows/Series $series/Season ${season.toString().padLeft(2, '0')}/Episode ${episode.toString().padLeft(2, '0')}.mkv';
    return WebDavScannedItem(
      resourceId: id,
      fileName: 'Episode ${episode.toString().padLeft(2, '0')}.mkv',
      actualAddress: path,
      sectionId: 'https://perf.invalid/Shows/',
      sectionName: '剧集',
      streamUrl: path,
      streamHeaders: const {},
      addedAt: baseTime.add(Duration(minutes: index)),
      modifiedAt: baseTime.add(Duration(minutes: index)),
      fileSizeBytes: 1024 * 1024 * 700,
      metadataSeed: WebDavMetadataSeed(
        title: '第 $episode 集',
        overview: '',
        posterUrl: '',
        posterHeaders: const {},
        backdropUrl: '',
        backdropHeaders: const {},
        logoUrl: '',
        logoHeaders: const {},
        bannerUrl: '',
        bannerHeaders: const {},
        extraBackdropUrls: const [],
        extraBackdropHeaders: const {},
        year: 2026,
        durationLabel: '45 分钟',
        genres: const [],
        directors: const [],
        actors: const [],
        itemType: 'episode',
        seasonNumber: season,
        episodeNumber: episode,
        imdbId: '',
        tmdbId: '',
        container: 'mkv',
        videoCodec: 'h264',
        audioCodec: 'aac',
        width: 1920,
        height: 1080,
        bitrate: 8000000,
        hasSidecarMatch: false,
      ),
    );
  });
}

class _FixtureWebDavNasClient extends WebDavNasClient {
  _FixtureWebDavNasClient(this.items)
      : super(MockClient((request) async => http.Response('', 200)));

  final List<WebDavScannedItem> items;

  @override
  Future<List<WebDavScannedItem>> scanLibrary(
    MediaSourceConfig source, {
    String? sectionId,
    String sectionName = '',
    int limit = 200,
    bool? loadSidecarMetadata,
    bool resolvePlayableStreams = true,
    bool resetCaches = true,
    bool Function()? shouldCancel,
  }) async {
    return items.take(limit).toList(growable: false);
  }
}
