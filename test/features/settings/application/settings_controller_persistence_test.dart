import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/settings/application/media_source_cache_lifecycle.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/data/app_settings_repository.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  test('rapid setting changes persist in user action order', () async {
    final repository = _OutOfOrderSettingsRepository(
      SeedData.defaultSettings.copyWith(
        homeStartupAutoRefreshEnabled: true,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        appSettingsRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);
    final controller = container.read(settingsControllerProvider.notifier);

    final first = controller.setHomeStartupAutoRefreshEnabled(false);
    final second = controller.setHomeStartupAutoRefreshEnabled(true);
    await Future.wait(<Future<void>>[first, second]);

    expect(repository.settings.homeStartupAutoRefreshEnabled, isTrue);
    expect(
      repository.savedValues,
      <bool>[false, true],
    );
  });

  test('home feed load limits persist through the settings controller',
      () async {
    final repository = _OutOfOrderSettingsRepository(SeedData.defaultSettings);
    final container = ProviderContainer(
      overrides: [
        appSettingsRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);
    final controller = container.read(settingsControllerProvider.notifier);

    await controller.setTaskMaxConcurrency(4);
    await controller.setHomeFeedInitialBatchSize(3);
    await controller.setHomeFeedBatchDelayMs(250);
    await controller.setMetadataPrefetchBatchDelayMs(300);
    await controller.setMetadataPrefetchForegroundResumeDelayMs(400);
    await controller.setSimplifiedVisualEffectsEnabled(true);
    await controller.setReducedInterfaceMotionEnabled(true);
    await controller.setSimplifiedHomeHeroEnabled(true);

    expect(repository.settings.taskMaxConcurrency, 4);
    expect(repository.settings.homeFeedInitialBatchSize, 3);
    expect(repository.settings.homeFeedBatchDelayMs, 250);
    expect(repository.settings.metadataPrefetchBatchDelayMs, 300);
    expect(repository.settings.metadataPrefetchForegroundResumeDelayMs, 400);
    expect(repository.settings.translucentEffectsEnabled, isFalse);
    expect(repository.settings.performanceReduceDecorationsEnabled, isTrue);
    expect(repository.settings.performanceReduceMotionEnabled, isTrue);
    expect(repository.settings.performanceStaticNavigationEnabled, isTrue);
    expect(repository.settings.performanceStaticHomeHeroEnabled, isTrue);
    expect(repository.settings.performanceLightweightHomeHeroEnabled, isTrue);
    expect(
      container.read(appSettingsProvider).taskMaxConcurrency,
      4,
    );
    expect(
      container.read(appSettingsProvider).homeFeedInitialBatchSize,
      3,
    );
  });

  test('home module movement keeps hero fixed and persists ordinary order',
      () async {
    final initial = SeedData.defaultSettings.copyWith(
      homeModules: const [
        HomeModuleConfig(
          id: HomeModuleConfig.heroModuleId,
          type: HomeModuleType.hero,
          title: 'Hero',
          enabled: true,
        ),
        HomeModuleConfig(
          id: 'module-a',
          type: HomeModuleType.recentlyAdded,
          title: 'A',
          enabled: true,
        ),
        HomeModuleConfig(
          id: 'module-b',
          type: HomeModuleType.recentPlayback,
          title: 'B',
          enabled: true,
        ),
        HomeModuleConfig(
          id: 'module-c',
          type: HomeModuleType.doubanList,
          title: 'C',
          enabled: true,
        ),
      ],
    );
    final repository = _OutOfOrderSettingsRepository(initial);
    final container = ProviderContainer(
      overrides: [
        appSettingsRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);
    final controller = container.read(settingsControllerProvider.notifier);

    await controller.moveHomeModule(1, 2);

    expect(
      repository.settings.homeModules.map((module) => module.id),
      [HomeModuleConfig.heroModuleId, 'module-a', 'module-c', 'module-b'],
    );
  });

  test('changing a media source root clears caches and remaps references',
      () async {
    const oldSource = MediaSourceConfig(
      id: 'nas-main',
      name: 'NAS',
      kind: MediaSourceKind.nas,
      endpoint: 'https://old.example.com/movies/',
      libraryPath: 'https://old.example.com/movies/',
      enabled: true,
    );
    const newSource = MediaSourceConfig(
      id: 'nas-main',
      name: '新 NAS',
      kind: MediaSourceKind.nas,
      endpoint: 'https://new.example.com/dav/strm',
      libraryPath: 'https://new.example.com/dav/strm/',
      enabled: true,
    );
    final initial = SeedData.defaultSettings.copyWith(
      mediaSources: const [oldSource],
      homeModules: const [
        HomeModuleConfig(
          id: 'quark-module',
          type: HomeModuleType.librarySection,
          title: 'quark',
          enabled: true,
          sourceId: 'nas-main',
          sourceName: 'NAS',
          sectionId: 'https://old.example.com/movies/strm/quark/',
          sectionName: 'quark',
        ),
      ],
      networkStorage: const NetworkStorageConfig(
        syncDeleteQuarkWebDavDirectories: [
          NetworkStorageWebDavDirectory(
            sourceId: 'nas-main',
            sourceName: 'NAS',
            directoryId: 'https://old.example.com/movies/strm/quark/',
          ),
        ],
      ),
    );
    final repository = _OutOfOrderSettingsRepository(initial);
    final lifecycle = _RecordingMediaSourceCacheLifecycle();
    final container = ProviderContainer(
      overrides: [
        appSettingsRepositoryProvider.overrideWithValue(repository),
        mediaSourceCacheLifecycleProvider.overrideWithValue(lifecycle),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);

    await container
        .read(settingsControllerProvider.notifier)
        .saveMediaSource(newSource);

    expect(lifecycle.clearedSourceIds, ['nas-main']);
    final remappedModule = repository.settings.homeModules.firstWhere(
      (module) => module.id == 'quark-module',
    );
    expect(
      remappedModule.sectionId,
      'https://new.example.com/dav/strm/quark/',
    );
    expect(remappedModule.sourceName, '新 NAS');
    expect(
      repository.settings.networkStorage.syncDeleteQuarkWebDavDirectories.single
          .directoryId,
      'https://new.example.com/dav/strm/quark/',
    );
  });

  test('removing a media source clears caches and stale settings references',
      () async {
    const source = MediaSourceConfig(
      id: 'nas-main',
      name: 'NAS',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/',
      enabled: true,
    );
    final initial = SeedData.defaultSettings.copyWith(
      mediaSources: const [source],
      homeModules: const [
        HomeModuleConfig(
          id: 'nas-module',
          type: HomeModuleType.librarySection,
          title: 'NAS',
          enabled: true,
          sourceId: 'nas-main',
        ),
      ],
      libraryMatchSourceIds: const ['nas-main'],
      searchSourceIds: const ['source:nas-main'],
      networkStorage: const NetworkStorageConfig(
        refreshMediaSourceIds: ['nas-main'],
        syncDeleteQuarkWebDavDirectories: [
          NetworkStorageWebDavDirectory(
            sourceId: 'nas-main',
            directoryId: 'https://nas.example.com/dav/quark/',
          ),
        ],
      ),
    );
    final repository = _OutOfOrderSettingsRepository(initial);
    final lifecycle = _RecordingMediaSourceCacheLifecycle();
    final container = ProviderContainer(
      overrides: [
        appSettingsRepositoryProvider.overrideWithValue(repository),
        mediaSourceCacheLifecycleProvider.overrideWithValue(lifecycle),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);

    await container
        .read(settingsControllerProvider.notifier)
        .removeMediaSource('nas-main');

    expect(lifecycle.clearedSourceIds, ['nas-main']);
    expect(repository.settings.mediaSources, isEmpty);
    expect(
      repository.settings.homeModules
          .where((module) => module.type == HomeModuleType.librarySection),
      isEmpty,
    );
    expect(repository.settings.libraryMatchSourceIds, isEmpty);
    expect(repository.settings.searchSourceIds, isEmpty);
    expect(repository.settings.networkStorage.refreshMediaSourceIds, isEmpty);
    expect(
      repository.settings.networkStorage.syncDeleteQuarkWebDavDirectories,
      isEmpty,
    );
  });

  test('subtitle preferences persist without replacing other playback fields',
      () async {
    final initial = SeedData.defaultSettings.copyWith(
      playbackOpenTimeoutSeconds: 90,
      playbackDefaultSpeed: 1.5,
    );
    final repository = _OutOfOrderSettingsRepository(initial);
    final container = ProviderContainer(
      overrides: [
        appSettingsRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);

    await container
        .read(settingsControllerProvider.notifier)
        .savePlaybackSubtitlePreferences(
          subtitlePreference: PlaybackSubtitlePreference.off,
          defaultSubtitle: PlaybackDefaultSubtitle.dual,
          dualSubtitlePrimaryLanguage:
              PlaybackSubtitleLanguage.traditionalChinese,
          dualSubtitleSecondaryLanguage: PlaybackSubtitleLanguage.japanese,
          subtitleScale: 40,
          primarySubtitlePosition: 75,
          secondarySubtitlePosition: 90,
          secondarySubtitleScale: 70,
          onlineSubtitleSources: const [OnlineSubtitleSource.assrt],
          assrtToken: ' token ',
          opensubtitlesEnabled: true,
          opensubtitlesUsername: ' user ',
          opensubtitlesPassword: 'password',
          subdlEnabled: true,
          subdlApiKey: ' key ',
          subtitlePreferredLanguages: const ['ZH-CN', 'en'],
          subtitleSearchMaxValidatedCandidates: 8,
        );

    expect(repository.settings.playbackSubtitlePreference,
        PlaybackSubtitlePreference.off);
    expect(
      repository.settings.playbackDefaultSubtitle,
      PlaybackDefaultSubtitle.dual,
    );
    expect(
      repository.settings.playbackDualSubtitlePrimaryLanguage,
      PlaybackSubtitleLanguage.traditionalChinese,
    );
    expect(
      repository.settings.playbackDualSubtitleSecondaryLanguage,
      PlaybackSubtitleLanguage.japanese,
    );
    expect(repository.settings.playbackSubtitleScale, 40);
    expect(repository.settings.playbackPrimarySubtitlePosition, 75);
    expect(repository.settings.playbackSecondarySubtitlePosition, 90);
    expect(repository.settings.playbackSecondarySubtitleScale, 70);
    expect(repository.settings.onlineSubtitleSources,
        const [OnlineSubtitleSource.assrt]);
    expect(repository.settings.assrtToken, 'token');
    expect(repository.settings.opensubtitlesUsername, 'user');
    expect(repository.settings.subdlApiKey, 'key');
    expect(repository.settings.subtitlePreferredLanguages, ['zh-cn', 'en']);
    expect(repository.settings.subtitleSearchMaxValidatedCandidates, 8);
    expect(repository.settings.playbackOpenTimeoutSeconds, 90);
    expect(repository.settings.playbackDefaultSpeed, 1.5);
  });

  test('subtitle style saves globally without replacing subtitle services',
      () async {
    final initial = SeedData.defaultSettings.copyWith(
      assrtToken: 'keep-token',
      playbackDefaultSpeed: 1.5,
    );
    final repository = _OutOfOrderSettingsRepository(initial);
    final container = ProviderContainer(
      overrides: [
        appSettingsRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);

    await container
        .read(settingsControllerProvider.notifier)
        .savePlaybackSubtitleStylePreferences(
          subtitleScale: 38,
          primarySubtitlePosition: 75,
          secondarySubtitlePosition: 85,
          secondarySubtitleScale: 55,
        );

    expect(repository.settings.playbackSubtitleScale, 38);
    expect(repository.settings.playbackPrimarySubtitlePosition, 75);
    expect(repository.settings.playbackSecondarySubtitlePosition, 85);
    expect(repository.settings.playbackSecondarySubtitleScale, 55);
    expect(repository.settings.assrtToken, 'keep-token');
    expect(repository.settings.playbackDefaultSpeed, 1.5);
    expect(
      container.read(appSettingsProvider).playbackSecondarySubtitleScale,
      55,
    );
  });
}

class _OutOfOrderSettingsRepository implements AppSettingsRepository {
  _OutOfOrderSettingsRepository(this.settings);

  AppSettings settings;
  final List<bool> savedValues = <bool>[];

  @override
  Future<AppSettings> load() async => settings;

  @override
  Future<void> save(AppSettings settings) async {
    final enabled = settings.homeStartupAutoRefreshEnabled;
    await Future<void>.delayed(
      enabled
          ? const Duration(milliseconds: 1)
          : const Duration(milliseconds: 40),
    );
    savedValues.add(enabled);
    this.settings = settings;
  }
}

class _RecordingMediaSourceCacheLifecycle implements MediaSourceCacheLifecycle {
  final List<String> clearedSourceIds = <String>[];

  @override
  Future<void> clearAllIndexes() async {}

  @override
  Future<void> clearSource(String sourceId) async {
    clearedSourceIds.add(sourceId);
  }

  @override
  Future<void> reconcileSources(List<MediaSourceConfig> sources) async {}
}
