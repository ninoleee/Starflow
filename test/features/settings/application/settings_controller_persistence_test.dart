import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/settings/domain/app_accent.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/settings/application/media_source_cache_lifecycle.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/data/app_settings_repository.dart';
import 'package:starflow/features/settings/data/webdav_sync_service.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/domain/network_storage_settings_scope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('scoped storage saves preserve newer common and other drive settings',
      () async {
    final repository = _OutOfOrderSettingsRepository(SeedData.defaultSettings);
    final container = ProviderContainer(overrides: [
      appSettingsRepositoryProvider.overrideWithValue(repository),
    ]);
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);
    final controller = container.read(settingsControllerProvider.notifier);
    final stale = repository.settings.networkStorage;
    await controller.saveNetworkStorage(stale.copyWith(
        aliyunRefreshToken: 'rotated',
        aliyunTo115Enabled: true,
        cloud115Cookie: 'fresh-115',
        cloud115SaveFolderId: '15',
        smartStrmWebhookUrl: 'https://fresh.test',
        smartStrmDelaySeconds: 10,
        refreshMediaSourceIds: ['nas'],
        refreshDelaySeconds: 30));
    await controller.saveNetworkStorageSection(
        stale.copyWith(
            quarkCookie: 'quark-new', quarkSaveFolderId: 'quark-dir'),
        NetworkStorageSettingsScope.quark);
    var config = repository.settings.networkStorage;
    expect(config.smartStrmWebhookUrl, 'https://fresh.test');
    expect(config.smartStrmDelaySeconds, 10);
    expect(config.refreshMediaSourceIds, ['nas']);
    expect(config.cloud115Cookie, 'fresh-115');
    expect(config.cloud115SaveFolderId, '15');
    expect(config.aliyunRefreshToken, 'rotated');
    expect(config.aliyunTo115Enabled, isTrue);
    await controller.saveNetworkStorageSection(
        stale.copyWith(
            smartStrmWebhookUrl: 'https://common.test',
            smartStrmDelaySeconds: 5,
            refreshDelaySeconds: 60,
            refreshMediaSourceIds: ['new-nas']),
        NetworkStorageSettingsScope.common);
    config = repository.settings.networkStorage;
    expect(config.smartStrmWebhookUrl, 'https://common.test');
    expect(config.smartStrmDelaySeconds, 5);
    expect(config.refreshDelaySeconds, 60);
    expect(config.refreshMediaSourceIds, ['new-nas']);
    expect(config.quarkCookie, 'quark-new');
    expect(config.quarkSaveFolderId, 'quark-dir');
    expect(config.cloud115Cookie, 'fresh-115');
    expect(config.aliyunRefreshToken, 'rotated');
    await controller.saveNetworkStorageSection(
        stale.copyWith(cloud115SmartStrmTaskName: '115-task'),
        NetworkStorageSettingsScope.cloud115);
    expect(repository.settings.networkStorage.smartStrmWebhookUrl,
        'https://common.test');
    expect(repository.settings.networkStorage.quarkCookie, 'quark-new');
    expect(repository.settings.networkStorage.cloud115SmartStrmTaskName,
        '115-task');
  });
  test('other storage drafts and imports preserve rotated Aliyun credential',
      () async {
    final repository =
        _OutOfOrderSettingsRepository(SeedData.defaultSettings.copyWith(
      networkStorage: const NetworkStorageConfig(aliyunRefreshToken: 'old'),
    ));
    final container = ProviderContainer(overrides: [
      appSettingsRepositoryProvider.overrideWithValue(repository),
      mediaSourceCacheLifecycleProvider
          .overrideWithValue(_RecordingMediaSourceCacheLifecycle()),
    ]);
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);
    final controller = container.read(settingsControllerProvider.notifier);
    final draft = container.read(appSettingsProvider).networkStorage;
    await controller.rotateAliyunCredential('old', 'rotated');
    await controller.saveNetworkStorage(draft.copyWith(
        aliyunRefreshToken: 'rotated',
        aliyunTo115Enabled: true,
        aliyunSaveFolderId: 'aliFolder',
        aliyunSmartStrmTaskName: 'ali-task',
        syncDeleteAliyunEnabled: true,
        syncDeleteAliyunWebDavDirectories: [
          const NetworkStorageWebDavDirectory(
              sourceId: 'nas', directoryId: '/ali')
        ]));
    await controller.saveNetworkStorage(
        draft.copyWith(cloud115SaveFolderId: '12'),
        preserveAliyunCredential: true);
    expect(repository.settings.networkStorage.aliyunRefreshToken, 'rotated');
    expect(repository.settings.networkStorage.aliyunTo115Enabled, isTrue);
    expect(repository.settings.networkStorage.aliyunSaveFolderId, 'aliFolder');
    expect(
        repository.settings.networkStorage.aliyunSmartStrmTaskName, 'ali-task');
    expect(repository.settings.networkStorage.syncDeleteAliyunEnabled, isTrue);
    expect(
        repository.settings.networkStorage.syncDeleteAliyunWebDavDirectories
            .single.directoryId,
        '/ali');
    expect(repository.settings.networkStorage.cloud115SaveFolderId, '12');
    await controller.replaceAllSettings(SeedData.defaultSettings);
    expect(repository.settings.networkStorage.aliyunRefreshToken, 'rotated');
    expect(repository.settings.networkStorage.aliyunTo115Enabled, isFalse);
  });
  test('navigation order persists through save, export and restart', () async {
    final repository = _OutOfOrderSettingsRepository(SeedData.defaultSettings);
    final container = ProviderContainer(overrides: [
      appSettingsRepositoryProvider.overrideWithValue(repository),
    ]);
    await container.read(settingsControllerProvider.future);
    const order = ['settings', 'live-tv', 'library', 'home'];
    await container
        .read(settingsControllerProvider.notifier)
        .setNavigationDestinationIds(order);
    expect(container.read(appSettingsProvider).navigationDestinationIds, order);
    expect(
        AppSettings.fromCurrentJson(repository.settings.toJson())
            .navigationDestinationIds,
        order);
    container.dispose();
    final restarted = ProviderContainer(overrides: [
      appSettingsRepositoryProvider.overrideWithValue(repository),
    ]);
    addTearDown(restarted.dispose);
    expect(
        (await restarted.read(settingsControllerProvider.future))
            .navigationDestinationIds,
        order);
  });
  test('hero auto play persists independently of simplified visuals', () async {
    final repository = _OutOfOrderSettingsRepository(SeedData.defaultSettings);
    final container = ProviderContainer(overrides: [
      appSettingsRepositoryProvider.overrideWithValue(repository),
    ]);
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);
    final controller = container.read(settingsControllerProvider.notifier);
    expect(repository.settings.homeHeroAutoPlayEnabled, isFalse);
    await controller.setHomeHeroAutoPlayEnabled(true);
    await controller.setSimplifiedHomeHeroEnabled(true);
    expect(repository.settings.homeHeroAutoPlayEnabled, isTrue);
    expect(
        AppSettings.fromCurrentJson(repository.settings.toJson())
            .homeHeroAutoPlayEnabled,
        isTrue);
    await controller.setHomeHeroAutoPlayEnabled(false);
    expect(repository.settings.homeHeroAutoPlayEnabled, isFalse);
    expect(AppSettings.fromJson({}).homeHeroAutoPlayEnabled, isFalse);
  });
  late Directory logDirectory;
  setUpAll(() async {
    logDirectory =
        await Directory.systemTemp.createTemp('starflow-settings-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => logDirectory.path);
  });
  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    await logDirectory.delete(recursive: true);
  });
  const syncConfig = WebDavSyncConfig(
    url: 'https://example.com/dav/',
    directory: 'Backups/Starflow',
    username: 'test-user',
    password: 'test-password',
    settings: false,
    favorites: true,
    autoFavorites: true,
  );

  test(
      'sync connection is saved with application settings and survives restart',
      () async {
    final repository = _OutOfOrderSettingsRepository(SeedData.defaultSettings);
    final container = ProviderContainer(overrides: [
      appSettingsRepositoryProvider.overrideWithValue(repository),
    ]);
    final preferences = container.read(webDavSyncPreferencesProvider);
    await preferences.save(syncConfig);
    expect(repository.settings.toJson()['webDavSync'], syncConfig.toJson());
    final exported = AppSettings.fromCurrentJson(repository.settings.toJson());
    expect(exported.webDavSync!.toJson(), syncConfig.toJson());
    container.dispose();
    final restarted = ProviderContainer(overrides: [
      appSettingsRepositoryProvider.overrideWithValue(repository),
    ]);
    addTearDown(restarted.dispose);
    expect(
        (await restarted.read(webDavSyncPreferencesProvider).load()).toJson(),
        syncConfig.toJson());
  });

  test('imports replace the sync connection', () async {
    final repository = _OutOfOrderSettingsRepository(
        SeedData.defaultSettings.copyWith(webDavSync: syncConfig));
    final container = ProviderContainer(overrides: [
      appSettingsRepositoryProvider.overrideWithValue(repository),
      mediaSourceCacheLifecycleProvider
          .overrideWithValue(_RecordingMediaSourceCacheLifecycle()),
    ]);
    addTearDown(container.dispose);
    final preferences = container.read(webDavSyncPreferencesProvider);
    await preferences.load();
    final controller = container.read(settingsControllerProvider.notifier);
    await controller.replaceAllSettings(SeedData.defaultSettings);
    expect(repository.settings.webDavSync, isNull);
    const imported = WebDavSyncConfig(
        url: 'https://new.example.com/dav/', password: 'new-password');
    final change = preferences.changes.first;
    await controller.replaceAllSettings(
        SeedData.defaultSettings.copyWith(webDavSync: imported));
    await change;
    expect((await preferences.load()).toJson(), imported.toJson());
    await controller.replaceAllSettings(SeedData.defaultSettings
        .copyWith(webDavSync: const WebDavSyncConfig()));
    expect((await preferences.load()).url, isEmpty);
  });

  test('accent changes are saved by the existing settings repository',
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
    for (final accent in AppAccent.values) {
      await controller.setAppAccent(accent);
      expect(repository.settings.appAccent, accent);
      expect(container.read(appSettingsProvider).appAccent, accent);
    }
  });

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
        syncDelete115WebDavDirectories: [
          NetworkStorageWebDavDirectory(
              sourceId: 'nas-main',
              sourceName: 'NAS',
              directoryId: 'https://old.example.com/movies/strm/115/'),
        ],
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
        repository.settings.networkStorage.syncDelete115WebDavDirectories.single
            .directoryId,
        'https://new.example.com/dav/strm/115/');
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
        syncDelete115WebDavDirectories: [
          NetworkStorageWebDavDirectory(
              sourceId: 'nas-main',
              directoryId: 'https://nas.example.com/dav/115/'),
        ],
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
    expect(repository.settings.networkStorage.syncDelete115WebDavDirectories,
        isEmpty);
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
