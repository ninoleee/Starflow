import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/logging/app_log_api.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  test('app settings persist and clamp scheduling limits', () {
    final settings = AppSettings.fromJson(const <String, dynamic>{
      'metadataPrefetchMaxConcurrency': 4,
      'metadataPrefetchInitialBatchSize': 18,
      'metadataPrefetchBatchDelayMs': 250,
      'metadataPrefetchForegroundResumeDelayMs': 500,
    });

    expect(settings.metadataPrefetchMaxConcurrency, 4);
    expect(settings.metadataPrefetchInitialBatchSize, 18);
    expect(settings.metadataPrefetchBatchDelayMs, 250);
    expect(settings.metadataPrefetchForegroundResumeDelayMs, 500);
    expect(settings.toJson()['metadataPrefetchMaxConcurrency'], 4);
    expect(settings.toJson()['metadataPrefetchInitialBatchSize'], 18);
    expect(settings.toJson()['metadataPrefetchBatchDelayMs'], 250);
    expect(
      settings.toJson()['metadataPrefetchForegroundResumeDelayMs'],
      500,
    );
    expect(
      AppSettings.fromJson(const <String, dynamic>{})
          .metadataPrefetchMaxConcurrency,
      kMetadataPrefetchMaxConcurrencyDefault,
    );
    expect(
      AppSettings.fromJson(const <String, dynamic>{})
          .metadataPrefetchInitialBatchSize,
      kMetadataPrefetchInitialBatchSizeDefault,
    );
    expect(
      AppSettings.fromJson(const <String, dynamic>{
        'metadataPrefetchMaxConcurrency': 99,
      }).metadataPrefetchMaxConcurrency,
      kMetadataPrefetchMaxConcurrencyMax,
    );
    expect(
      AppSettings.fromJson(const <String, dynamic>{
        'metadataPrefetchInitialBatchSize': 99,
      }).metadataPrefetchInitialBatchSize,
      kMetadataPrefetchInitialBatchSizeMax,
    );
    expect(
      settings
          .copyWith(metadataPrefetchMaxConcurrency: 0)
          .metadataPrefetchMaxConcurrency,
      kMetadataPrefetchMaxConcurrencyMin,
    );
    expect(
      settings
          .copyWith(metadataPrefetchInitialBatchSize: 0)
          .metadataPrefetchInitialBatchSize,
      kMetadataPrefetchInitialBatchSizeMin,
    );
    final feedSettings = AppSettings.fromJson(const <String, dynamic>{
      'homeFeedMaxConcurrency': 4,
      'homeFeedInitialBatchSize': 3,
      'homeFeedBatchDelayMs': 250,
      'nasSourceRefreshConcurrency': 2,
      'nasCollectionRefreshConcurrency': 3,
      'nasEnrichmentConcurrency': 4,
    });

    expect(feedSettings.homeFeedMaxConcurrency, 4);
    expect(feedSettings.homeFeedInitialBatchSize, 3);
    expect(feedSettings.homeFeedBatchDelayMs, 250);
    expect(feedSettings.nasSourceRefreshConcurrency, 2);
    expect(feedSettings.nasCollectionRefreshConcurrency, 3);
    expect(feedSettings.nasEnrichmentConcurrency, 4);
    expect(feedSettings.toJson()['homeFeedMaxConcurrency'], 4);
    expect(feedSettings.toJson()['homeFeedInitialBatchSize'], 3);
    expect(feedSettings.toJson()['homeFeedBatchDelayMs'], 250);
    expect(feedSettings.toJson()['nasSourceRefreshConcurrency'], 2);
    expect(feedSettings.toJson()['nasCollectionRefreshConcurrency'], 3);
    expect(feedSettings.toJson()['nasEnrichmentConcurrency'], 4);
    expect(
      AppSettings.fromJson(const <String, dynamic>{}).homeFeedMaxConcurrency,
      kHomeFeedMaxConcurrencyDefault,
    );
    expect(
      AppSettings.fromJson(const <String, dynamic>{}).homeFeedInitialBatchSize,
      kHomeFeedInitialBatchSizeDefault,
    );
    expect(
      feedSettings.copyWith(homeFeedMaxConcurrency: 99).homeFeedMaxConcurrency,
      kHomeFeedMaxConcurrencyMax,
    );
    expect(
      feedSettings
          .copyWith(homeFeedInitialBatchSize: 0)
          .homeFeedInitialBatchSize,
      kHomeFeedInitialBatchSizeMin,
    );
  });

  test('legacy high performance minimum scheduling migrates to balanced', () {
    final migrated = AppSettings.fromJson(const <String, dynamic>{
      'highPerformanceModeEnabled': true,
      'metadataPrefetchMaxConcurrency': 1,
      'metadataPrefetchInitialBatchSize': 6,
      'homeFeedMaxConcurrency': 1,
      'homeFeedInitialBatchSize': 1,
    });

    expect(
      migrated.metadataPrefetchMaxConcurrency,
      kMetadataPrefetchMaxConcurrencyDefault,
    );
    expect(
      migrated.metadataPrefetchInitialBatchSize,
      kMetadataPrefetchInitialBatchSizeDefault,
    );
    expect(migrated.homeFeedMaxConcurrency, kHomeFeedMaxConcurrencyDefault);
    expect(migrated.homeFeedInitialBatchSize, kHomeFeedInitialBatchSizeDefault);

    final explicitNewSettings = AppSettings.fromJson(const <String, dynamic>{
      'highPerformanceModeEnabled': true,
      'metadataPrefetchMaxConcurrency': 1,
      'metadataPrefetchInitialBatchSize': 6,
      'metadataPrefetchBatchDelayMs': 300,
      'homeFeedMaxConcurrency': 1,
      'homeFeedInitialBatchSize': 1,
    });
    expect(explicitNewSettings.metadataPrefetchMaxConcurrency, 1);
    expect(explicitNewSettings.homeFeedMaxConcurrency, 1);
  });

  test('app settings persist local logging preferences', () {
    final settings = AppSettings.fromJson(const <String, dynamic>{
      'localLoggingEnabled': false,
      'localLogMaxSizeMb': 50,
      'localLogRecordedLevels': ['info', 'error'],
      'localLogVisibleLevels': ['warning', 'error'],
    });

    expect(settings.localLoggingEnabled, isFalse);
    expect(settings.localLogMaxSizeMb, 50);
    expect(
      settings.localLogRecordedLevels,
      <AppLogLevel>{AppLogLevel.info, AppLogLevel.error},
    );
    expect(
      settings.localLogVisibleLevels,
      <AppLogLevel>{AppLogLevel.warning, AppLogLevel.error},
    );
    expect(settings.toJson()['localLoggingEnabled'], isFalse);
    expect(settings.toJson()['localLogMaxSizeMb'], 50);
    expect(settings.toJson()['localLogRecordedLevels'], ['info', 'error']);
    expect(
      settings.toJson()['localLogVisibleLevels'],
      ['warning', 'error'],
    );

    final defaults = AppSettings.fromJson(const <String, dynamic>{});
    expect(defaults.localLoggingEnabled, isTrue);
    expect(defaults.localLogMaxSizeMb, kLocalLogMaxSizeMbDefault);
    expect(defaults.localLogRecordedLevels, kDefaultLocalLogRecordedLevels);
    expect(defaults.localLogVisibleLevels, kDefaultLocalLogVisibleLevels);

    final invalid = AppSettings.fromJson(const <String, dynamic>{
      'localLogMaxSizeMb': 999,
    });
    expect(invalid.localLogMaxSizeMb, kLocalLogMaxSizeMbDefault);

    final noLevels = AppSettings.fromJson(const <String, dynamic>{
      'localLogRecordedLevels': <String>[],
      'localLogVisibleLevels': <String>[],
    });
    expect(noLevels.localLogRecordedLevels, isEmpty);
    expect(noLevels.localLogVisibleLevels, isEmpty);
  });

  test('app settings persist and default home and playback options', () {
    final settings = AppSettings.fromJson({
      'homeHeroDisplayMode': 'borderless',
      'homeHeroStyle': 'poster',
      'homeHeroBackgroundEnabled': false,
      'translucentEffectsEnabled': false,
      'autoHideNavigationBarEnabled': false,
      'homeNavigationSingleTapCleanupEnabled': false,
      'performanceLiveItemHeroOverlayEnabled': false,
      'playbackOpenTimeoutSeconds': 45,
      'playbackDefaultSpeed': 1.25,
      'playbackSubtitlePreference': 'off',
      'playbackSubtitleScale': 'large',
      'onlineSubtitleSources': ['assrt'],
      'assrtToken': 'assrt-token',
      'opensubtitlesEnabled': true,
      'opensubtitlesUsername': 'opensub-user',
      'opensubtitlesPassword': 'opensub-pass',
      'subdlEnabled': true,
      'subdlApiKey': 'subdl-key',
      'subtitlePreferredLanguages': ['zh-cn', 'en', 'zh-cn'],
      'subtitleSearchMaxValidatedCandidates': 9,
      'playbackBackgroundPlaybackEnabled': false,
      'playbackEngine': 'systemPlayer',
      'playbackDecodeMode': 'softwarePreferred',
      'playbackMpvQualityPreset': 'performanceFirst',
      'playbackMpvDoubleTapToSeekEnabled': false,
      'playbackMpvSwipeToSeekEnabled': false,
      'playbackMpvLongPressSpeedBoostEnabled': false,
      'playbackMpvStallAutoRecoveryEnabled': false,
      'performanceAggressivePlaybackTuningEnabled': true,
      'performanceAutoDowngradeHeavyPlaybackEnabled': true,
    });

    expect(settings.homeHeroDisplayMode, HomeHeroDisplayMode.borderless);
    expect(settings.homeHeroStyle, HomeHeroStyle.poster);
    expect(settings.homeHeroBackgroundEnabled, isFalse);
    expect(settings.translucentEffectsEnabled, isFalse);
    expect(settings.autoHideNavigationBarEnabled, isFalse);
    expect(settings.homeNavigationSingleTapCleanupEnabled, isFalse);
    expect(settings.performanceLiveItemHeroOverlayEnabled, isFalse);
    expect(settings.playbackOpenTimeoutSeconds, 45);
    expect(settings.playbackDefaultSpeed, 1.25);
    expect(
      settings.playbackSubtitlePreference,
      PlaybackSubtitlePreference.off,
    );
    expect(settings.playbackSubtitleScale, 36.0);
    expect(settings.onlineSubtitleSources, [OnlineSubtitleSource.assrt]);
    expect(settings.assrtToken, 'assrt-token');
    expect(settings.opensubtitlesEnabled, isTrue);
    expect(settings.opensubtitlesUsername, 'opensub-user');
    expect(settings.opensubtitlesPassword, 'opensub-pass');
    expect(settings.subdlEnabled, isTrue);
    expect(settings.subdlApiKey, 'subdl-key');
    expect(settings.subtitlePreferredLanguages, ['zh-cn', 'en']);
    expect(settings.subtitleSearchMaxValidatedCandidates, 9);
    expect(
      settings.configuredStructuredSubtitleSources,
      [
        OnlineSubtitleSource.assrt,
        OnlineSubtitleSource.opensubtitles,
        OnlineSubtitleSource.subdl,
      ],
    );
    expect(settings.playbackBackgroundPlaybackEnabled, isFalse);
    expect(settings.playbackEngine, PlaybackEngine.systemPlayer);
    expect(
      settings.playbackDecodeMode,
      PlaybackDecodeMode.softwarePreferred,
    );
    expect(
      settings.playbackMpvQualityPreset,
      PlaybackMpvQualityPreset.performanceFirst,
    );
    expect(settings.playbackMpvDoubleTapToSeekEnabled, isFalse);
    expect(settings.playbackMpvSwipeToSeekEnabled, isFalse);
    expect(settings.playbackMpvLongPressSpeedBoostEnabled, isFalse);
    expect(settings.playbackMpvStallAutoRecoveryEnabled, isFalse);
    expect(settings.performanceAggressivePlaybackTuningEnabled, isTrue);
    expect(settings.toJson()['homeHeroDisplayMode'], 'borderless');
    expect(settings.toJson()['homeHeroStyle'], 'poster');
    expect(settings.toJson()['homeHeroBackgroundEnabled'], isFalse);
    expect(settings.toJson()['translucentEffectsEnabled'], isFalse);
    expect(settings.toJson()['autoHideNavigationBarEnabled'], isFalse);
    expect(
      settings.toJson()['homeNavigationSingleTapCleanupEnabled'],
      isFalse,
    );
    expect(settings.toJson()['performanceLiveItemHeroOverlayEnabled'], isFalse);
    expect(settings.toJson()['playbackOpenTimeoutSeconds'], 45);
    expect(settings.toJson()['playbackDefaultSpeed'], 1.25);
    expect(settings.toJson()['playbackSubtitlePreference'], 'off');
    expect(settings.toJson()['playbackSubtitleScale'], 36.0);
    expect(settings.toJson()['onlineSubtitleSources'], ['assrt']);
    expect(settings.toJson()['assrtToken'], 'assrt-token');
    expect(settings.toJson()['opensubtitlesEnabled'], isTrue);
    expect(settings.toJson()['opensubtitlesUsername'], 'opensub-user');
    expect(settings.toJson()['opensubtitlesPassword'], 'opensub-pass');
    expect(settings.toJson()['subdlEnabled'], isTrue);
    expect(settings.toJson()['subdlApiKey'], 'subdl-key');
    expect(settings.toJson()['subtitlePreferredLanguages'], ['zh-cn', 'en']);
    expect(settings.toJson()['subtitleSearchMaxValidatedCandidates'], 9);
    expect(settings.toJson()['playbackBackgroundPlaybackEnabled'], isFalse);
    expect(settings.toJson()['playbackEngine'], 'systemPlayer');
    expect(settings.toJson()['playbackDecodeMode'], 'softwarePreferred');
    expect(settings.toJson()['playbackMpvQualityPreset'], 'performanceFirst');
    expect(settings.toJson()['playbackMpvDoubleTapToSeekEnabled'], isFalse);
    expect(settings.toJson()['playbackMpvSwipeToSeekEnabled'], isFalse);
    expect(
      settings.toJson()['playbackMpvLongPressSpeedBoostEnabled'],
      isFalse,
    );
    expect(settings.toJson()['playbackMpvStallAutoRecoveryEnabled'], isFalse);
    expect(
      settings.toJson()['performanceAggressivePlaybackTuningEnabled'],
      isTrue,
    );
    expect(
      settings.toJson().containsKey(
            'performanceAutoDowngradeHeavyPlaybackEnabled',
          ),
      isFalse,
    );
    final defaults = AppSettings.fromJson(const {});

    expect(defaults.homeHeroDisplayMode, HomeHeroDisplayMode.normal);
    expect(defaults.homeHeroStyle, HomeHeroStyle.composite);
    expect(defaults.homeHeroBackgroundEnabled, isTrue);
    expect(defaults.translucentEffectsEnabled, isTrue);
    expect(defaults.autoHideNavigationBarEnabled, isTrue);
    expect(defaults.homeNavigationSingleTapCleanupEnabled, isTrue);
    expect(defaults.performanceLiveItemHeroOverlayEnabled, isTrue);
    expect(
      defaults.homeModules
          .firstWhere((item) => item.type == HomeModuleType.hero)
          .enabled,
      isTrue,
    );
    expect(defaults.playbackOpenTimeoutSeconds, 20);
    expect(defaults.playbackDefaultSpeed, 1.0);
    expect(
      defaults.playbackSubtitlePreference,
      PlaybackSubtitlePreference.auto,
    );
    expect(defaults.playbackSubtitleScale, 32.0);
    expect(defaults.onlineSubtitleSources, [OnlineSubtitleSource.assrt]);
    expect(defaults.assrtToken, isEmpty);
    expect(defaults.opensubtitlesEnabled, isFalse);
    expect(defaults.opensubtitlesUsername, isEmpty);
    expect(defaults.opensubtitlesPassword, isEmpty);
    expect(defaults.subdlEnabled, isFalse);
    expect(defaults.subdlApiKey, isEmpty);
    expect(defaults.subtitlePreferredLanguages, isEmpty);
    expect(
      defaults.subtitleSearchMaxValidatedCandidates,
      kSubtitleSearchMaxValidatedCandidatesDefault,
    );
    expect(defaults.configuredStructuredSubtitleSources, isEmpty);
    expect(defaults.playbackBackgroundPlaybackEnabled, isTrue);
    expect(defaults.playbackEngine, PlaybackEngine.embeddedMpv);
    expect(defaults.playbackDecodeMode, PlaybackDecodeMode.auto);
    expect(
      defaults.playbackMpvQualityPreset,
      PlaybackMpvQualityPreset.performanceFirst,
    );
    expect(defaults.playbackMpvDoubleTapToSeekEnabled, isTrue);
    expect(defaults.playbackMpvSwipeToSeekEnabled, isTrue);
    expect(defaults.playbackMpvLongPressSpeedBoostEnabled, isTrue);
    expect(defaults.playbackMpvStallAutoRecoveryEnabled, isTrue);
    expect(defaults.performanceAggressivePlaybackTuningEnabled, isFalse);
    expect(defaults.detailAutoLibraryMatchEnabled, isFalse);
  });

  test('legacy high performance marker is ignored at runtime and export', () {
    final settings = AppSettings.fromJson({
      'highPerformanceModeEnabled': true,
      'translucentEffectsEnabled': true,
      'autoHideNavigationBarEnabled': true,
      'performanceReduceMotionEnabled': false,
      'performanceStaticNavigationEnabled': false,
      'performanceLeanPlaybackUiEnabled': true,
      'playbackStartupProbeEnabled': false,
    });

    expect(settings.effectiveTranslucentEffectsEnabled, isTrue);
    expect(settings.effectiveNavigationAutoHideEnabled, isTrue);
    expect(
      settings.effectiveLeanPlaybackUiEnabled(isTelevision: false),
      isFalse,
    );
    expect(
      settings.toJson().containsKey('performanceLeanPlaybackUiEnabled'),
      isFalse,
    );
    expect(
      settings.toJson().containsKey('playbackStartupProbeEnabled'),
      isFalse,
    );
    expect(
        settings.toJson().containsKey('highPerformanceModeEnabled'), isFalse);
  });

  test('performance switches are independent and TV protections stay fixed',
      () {
    final settings = AppSettings.fromJson(const <String, dynamic>{
      'performanceReduceMotionEnabled': true,
      'performanceStaticNavigationEnabled': false,
      'performanceLightweightHomeHeroEnabled': false,
      'performanceSlimDetailHeroEnabled': true,
      'performanceLeanPlaybackUiEnabled': true,
    });

    expect(settings.effectiveReduceMotionEnabled, isTrue);
    expect(settings.effectiveStaticNavigationEnabled, isFalse);
    expect(
      settings.effectiveLightweightHomeHeroEnabled(isTelevision: false),
      isFalse,
    );
    expect(settings.effectiveSlimDetailHeroEnabled(isTelevision: true), isTrue);
    expect(settings.effectiveLeanPlaybackUiEnabled(isTelevision: true), isTrue);
    expect(
      settings.effectiveSlimDetailHeroEnabled(isTelevision: false),
      isFalse,
    );
    expect(
      settings.effectiveLeanPlaybackUiEnabled(isTelevision: false),
      isFalse,
    );
    expect(
      settings.effectiveLightweightTvFocusEnabled(isTelevision: true),
      isTrue,
    );
  });

  test(
      'tv-safe effective overlay and background playback stay off until non-tv is confirmed',
      () {
    final settings = AppSettings.fromJson({
      'performanceLiveItemHeroOverlayEnabled': true,
      'playbackBackgroundPlaybackEnabled': true,
    });

    expect(
      settings.effectivePerformanceLiveItemHeroOverlayEnabled(
        isTelevision: null,
      ),
      isFalse,
    );
    expect(
      settings.effectivePerformanceLiveItemHeroOverlayEnabled(
        isTelevision: true,
      ),
      isFalse,
    );
    expect(
      settings.effectivePerformanceLiveItemHeroOverlayEnabled(
        isTelevision: false,
      ),
      isTrue,
    );
    expect(
      settings.effectiveBackgroundPlaybackEnabled(isTelevision: null),
      isFalse,
    );
    expect(
      settings.effectiveBackgroundPlaybackEnabled(isTelevision: true),
      isFalse,
    );
    expect(
      settings.effectiveBackgroundPlaybackEnabled(isTelevision: false),
      isTrue,
    );
  });

  test('legacy poster hero style migrates to poster artwork style', () {
    final settings = AppSettings.fromJson({
      'homeHeroStyle': 'poster',
    });

    expect(settings.homeHeroStyle, HomeHeroStyle.poster);
    expect(settings.homeHeroDisplayMode, HomeHeroDisplayMode.normal);
    expect(settings.toJson()['homeHeroStyle'], 'poster');
    expect(settings.toJson()['homeHeroDisplayMode'], 'normal');
  });

  test('app settings persist native playback container engine', () {
    final settings = AppSettings.fromJson({
      'playbackEngine': 'nativeContainer',
      'playbackDecodeMode': 'hardwarePreferred',
    });

    expect(settings.playbackEngine, PlaybackEngine.nativeContainer);
    expect(
      settings.playbackDecodeMode,
      PlaybackDecodeMode.hardwarePreferred,
    );
    expect(settings.toJson()['playbackEngine'], 'nativeContainer');
    expect(settings.toJson()['playbackDecodeMode'], 'hardwarePreferred');
  });

  test('legacy hero display mode and module settings migrate', () {
    final settings = AppSettings.fromJson({
      'homeHeroEnabled': false,
      'homeHeroStyle': 'borderless',
      'homeModules': const [],
    });

    final heroModule = settings.homeModules
        .firstWhere((item) => item.type == HomeModuleType.hero);

    expect(heroModule.enabled, isFalse);
    expect(settings.homeHeroDisplayMode, HomeHeroDisplayMode.borderless);
    expect(settings.homeHeroStyle, HomeHeroStyle.composite);
  });

  test('app settings persist metadata match preferences', () {
    final settings = AppSettings.fromJson({
      'tmdbMetadataMatchEnabled': true,
      'wmdbMetadataMatchEnabled': true,
      'metadataMatchPriority': 'wmdb',
      'detailAutoLibraryMatchEnabled': true,
      'libraryMatchSourceIds': ['emby-main', 'nas-main', 'emby-main'],
      'searchSourceIds': [
        'source:emby-main',
        'provider:pansou',
        'source:emby-main'
      ],
    });

    expect(settings.tmdbMetadataMatchEnabled, isTrue);
    expect(settings.wmdbMetadataMatchEnabled, isTrue);
    expect(settings.metadataMatchPriority, MetadataMatchProvider.wmdb);
    expect(settings.detailAutoLibraryMatchEnabled, isTrue);
    expect(settings.libraryMatchSourceIds, ['emby-main', 'nas-main']);
    expect(settings.searchSourceIds, ['source:emby-main', 'provider:pansou']);
    expect(settings.toJson()['metadataMatchPriority'], 'wmdb');
    expect(settings.toJson()['detailAutoLibraryMatchEnabled'], isTrue);
    expect(
      settings.toJson()['libraryMatchSourceIds'],
      ['emby-main', 'nas-main'],
    );
    expect(
      settings.toJson()['searchSourceIds'],
      ['source:emby-main', 'provider:pansou'],
    );
  });

  test('search source setting ids are normalized by helper builders', () {
    expect(
      searchSourceSettingIdForMediaSource(' emby-main '),
      'source:emby-main',
    );
    expect(
      searchSourceSettingIdForProvider(' pansou-api '),
      'provider:pansou-api',
    );
  });

  test('app settings persist and default network storage config', () {
    final settings = AppSettings.fromJson({
      'networkStorage': {
        'quarkCookie': 'foo=bar',
        'quarkSaveFolderId': '123',
        'quarkSaveFolderPath': '/影视',
        'syncDeleteQuarkEnabled': true,
        'syncDeleteQuarkWebDavDirectories': [
          {
            'sourceId': 'nas-main',
            'sourceName': '家庭 NAS',
            'directoryId': 'https://nas.example.com/dav/movies/',
            'directoryLabel': 'nas.example.com/dav/movies/',
          },
        ],
        'smartStrmWebhookUrl': 'http://localhost:8024/webhook/abc',
        'smartStrmTaskName': 'movie_task',
        'refreshMediaSourceIds': ['emby-a', 'webdav-b'],
        'refreshDelaySeconds': 8,
      },
    });

    expect(settings.networkStorage.quarkCookie, 'foo=bar');
    expect(settings.networkStorage.quarkSaveFolderId, '123');
    expect(settings.networkStorage.quarkSaveFolderPath, '/影视');
    expect(settings.networkStorage.syncDeleteQuarkEnabled, isTrue);
    expect(
      settings.networkStorage.syncDeleteQuarkWebDavDirectories,
      hasLength(1),
    );
    expect(
      settings.networkStorage.syncDeleteQuarkWebDavDirectories.single.sourceId,
      'nas-main',
    );
    expect(
      settings
          .networkStorage.syncDeleteQuarkWebDavDirectories.single.directoryId,
      'https://nas.example.com/dav/movies/',
    );
    expect(
      settings.networkStorage.smartStrmWebhookUrl,
      'http://localhost:8024/webhook/abc',
    );
    expect(settings.networkStorage.smartStrmTaskName, 'movie_task');
    expect(
      settings.networkStorage.refreshMediaSourceIds,
      ['emby-a', 'webdav-b'],
    );
    expect(settings.networkStorage.refreshDelaySeconds, 8);

    final json = settings.toJson()['networkStorage'] as Map<String, dynamic>;
    expect(json['quarkCookie'], 'foo=bar');
    expect(json['quarkSaveFolderId'], '123');
    expect(json['quarkSaveFolderPath'], '/影视');
    expect(json['syncDeleteQuarkEnabled'], isTrue);
    expect(
      json['syncDeleteQuarkWebDavDirectories'],
      [
        {
          'sourceId': 'nas-main',
          'sourceName': '家庭 NAS',
          'directoryId': 'https://nas.example.com/dav/movies/',
          'directoryLabel': 'nas.example.com/dav/movies/',
        },
      ],
    );
    expect(json['smartStrmWebhookUrl'], 'http://localhost:8024/webhook/abc');
    expect(json['smartStrmTaskName'], 'movie_task');
    expect(json['refreshMediaSourceIds'], ['emby-a', 'webdav-b']);
    expect(json['refreshDelaySeconds'], 8);
    final defaults = AppSettings.fromJson(const {});

    expect(defaults.networkStorage.quarkCookie, isEmpty);
    expect(defaults.networkStorage.quarkSaveFolderId, '0');
    expect(defaults.networkStorage.quarkSaveFolderPath, '/');
    expect(defaults.networkStorage.syncDeleteQuarkEnabled, isFalse);
    expect(defaults.networkStorage.syncDeleteQuarkWebDavDirectories, isEmpty);
    expect(defaults.networkStorage.smartStrmWebhookUrl, isEmpty);
    expect(defaults.networkStorage.smartStrmTaskName, isEmpty);
    expect(defaults.networkStorage.refreshMediaSourceIds, isEmpty);
    expect(defaults.networkStorage.refreshDelaySeconds, 1);
    expect(defaults.networkStorage.hasAnyConfigured, isFalse);
  });

  test('seed defaults enable douban and preload built-in douban modules', () {
    final settings = SeedData.defaultSettings;

    expect(settings.doubanAccount.enabled, isTrue);
    expect(settings.homeModules.length, 4);
    expect(settings.homeModules.first.type, HomeModuleType.hero);
    expect(settings.performanceLiveItemHeroOverlayEnabled, isTrue);
    expect(
      settings.homeModules.skip(1).map((item) => item.title).toList(),
      ['热播新剧', '豆瓣热门电影', '热播综艺'],
    );
    expect(
      settings.homeModules.skip(1).map((item) => item.doubanListUrl).toList(),
      [
        'https://m.douban.com/subject_collection/tv_hot',
        'https://m.douban.com/subject_collection/movie_hot_gaia',
        'https://m.douban.com/subject_collection/show_hot',
      ],
    );
  });

  test('playback numeric settings are clamped to safe bounds', () {
    final settings = AppSettings.fromJson({
      'playbackOpenTimeoutSeconds': 0,
      'playbackDefaultSpeed': 5.0,
      'playbackSubtitleScale': 100,
    });

    expect(settings.playbackOpenTimeoutSeconds, 1);
    expect(settings.playbackDefaultSpeed, 2.0);
    expect(settings.playbackSubtitleScale, kPlaybackSubtitleScaleMax);

    final copied = settings.copyWith(
      playbackOpenTimeoutSeconds: 900,
      playbackDefaultSpeed: 0.1,
      playbackSubtitleScale: -20,
    );

    expect(copied.playbackOpenTimeoutSeconds, 900);
    expect(copied.playbackDefaultSpeed, 0.75);
    expect(copied.playbackSubtitleScale, kPlaybackSubtitleScaleMin);
  });

  test('subtitle provider settings normalize invalid and missing values', () {
    final unknownSources = AppSettings.fromJson({
      'onlineSubtitleSources': ['invalid-source'],
    });

    expect(unknownSources.onlineSubtitleSources, [OnlineSubtitleSource.assrt]);

    final normalized = AppSettings.fromJson({
      'subtitlePreferredLanguages': [' zh-CN ', 'en', '', 'EN'],
      'subtitleSearchMaxValidatedCandidates': 99,
    });

    expect(normalized.subtitlePreferredLanguages, ['zh-cn', 'en']);
    expect(
      normalized.subtitleSearchMaxValidatedCandidates,
      kSubtitleSearchMaxValidatedCandidatesMax,
    );

    final copied = normalized.copyWith(
      subtitlePreferredLanguages: ['zh-tw', 'zh-tw', 'ja'],
      subtitleSearchMaxValidatedCandidates: 0,
    );

    expect(copied.subtitlePreferredLanguages, ['zh-tw', 'zh-tw', 'ja']);
    expect(
      copied.subtitleSearchMaxValidatedCandidates,
      kSubtitleSearchMaxValidatedCandidatesMin,
    );
    final withoutToken = AppSettings.fromJson({
      'onlineSubtitleSources': ['assrt'],
    });

    expect(withoutToken.assrtApiSearchEnabled, isFalse);
    expect(withoutToken.configuredStructuredSubtitleSources, isEmpty);
    expect(withoutToken.effectiveOnlineSubtitleSources, isEmpty);
  });

  test('startup crash recovery applies one consistent safe preset', () {
    final schedulingSettings = const AppSettings(
      mediaSources: [],
      searchProviders: [],
      doubanAccount: DoubanAccountConfig(enabled: false),
      homeModules: [],
      metadataPrefetchMaxConcurrency: 3,
      metadataPrefetchInitialBatchSize: 18,
      metadataPrefetchBatchDelayMs: 250,
      metadataPrefetchForegroundResumeDelayMs: 500,
      homeFeedMaxConcurrency: 3,
      homeFeedInitialBatchSize: 3,
      homeFeedBatchDelayMs: 250,
      nasSourceRefreshConcurrency: 2,
      nasCollectionRefreshConcurrency: 3,
      nasEnrichmentConcurrency: 2,
    ).applyStartupCrashRecoveryPreset();

    expect(
      schedulingSettings.performanceAggressivePlaybackTuningEnabled,
      isTrue,
    );
    expect(
      schedulingSettings.metadataPrefetchMaxConcurrency,
      3,
    );
    expect(
      schedulingSettings.metadataPrefetchInitialBatchSize,
      18,
    );
    expect(schedulingSettings.metadataPrefetchBatchDelayMs, 250);
    expect(schedulingSettings.metadataPrefetchForegroundResumeDelayMs, 500);
    expect(schedulingSettings.homeFeedMaxConcurrency, 3);
    expect(schedulingSettings.homeFeedInitialBatchSize, 3);
    expect(schedulingSettings.homeFeedBatchDelayMs, 250);
    expect(schedulingSettings.nasSourceRefreshConcurrency, 2);
    expect(schedulingSettings.nasCollectionRefreshConcurrency, 3);
    expect(schedulingSettings.nasEnrichmentConcurrency, 2);

    final safeSettings = const AppSettings(
      mediaSources: [],
      searchProviders: [],
      doubanAccount: DoubanAccountConfig(enabled: false),
      homeModules: [],
      homeStartupAutoRefreshEnabled: true,
      homeStartupAutoRefreshEmbyEnabled: true,
      tmdbMetadataMatchEnabled: true,
      wmdbMetadataMatchEnabled: true,
      imdbRatingMatchEnabled: true,
      detailAutoLibraryMatchEnabled: true,
      playbackBackgroundPlaybackEnabled: true,
      playbackMpvDoubleTapToSeekEnabled: true,
      playbackMpvSwipeToSeekEnabled: true,
      playbackMpvLongPressSpeedBoostEnabled: true,
      playbackMpvStallAutoRecoveryEnabled: true,
    ).applyStartupCrashRecoveryPreset();

    expect(safeSettings.homeStartupAutoRefreshEnabled, isFalse);
    expect(safeSettings.homeStartupAutoRefreshEmbyEnabled, isFalse);
    expect(safeSettings.tmdbMetadataMatchEnabled, isTrue);
    expect(safeSettings.wmdbMetadataMatchEnabled, isTrue);
    expect(safeSettings.imdbRatingMatchEnabled, isTrue);
    expect(safeSettings.detailAutoLibraryMatchEnabled, isTrue);
    expect(safeSettings.playbackBackgroundPlaybackEnabled, isFalse);
    expect(safeSettings.playbackMpvDoubleTapToSeekEnabled, isFalse);
    expect(safeSettings.playbackMpvSwipeToSeekEnabled, isFalse);
    expect(safeSettings.playbackMpvLongPressSpeedBoostEnabled, isFalse);
    expect(safeSettings.playbackMpvStallAutoRecoveryEnabled, isFalse);

    const cleanupSettings = AppSettings(
      mediaSources: [],
      searchProviders: [],
      doubanAccount: DoubanAccountConfig(enabled: false),
      homeModules: [],
      homeNavigationSingleTapCleanupEnabled: false,
    );
    expect(
      cleanupSettings
          .applyStartupCrashRecoveryPreset()
          .homeNavigationSingleTapCleanupEnabled,
      isFalse,
    );
  });

  test('navigation destinations persist favorites without changing defaults',
      () {
    const settings = AppSettings(
      mediaSources: [],
      searchProviders: [],
      doubanAccount: DoubanAccountConfig(enabled: false),
      homeModules: [],
      navigationDestinationIds: [
        kNavigationDestinationHome,
        kNavigationDestinationFavorites,
        kNavigationDestinationSettings,
      ],
    );

    final restored = AppSettings.fromJson(settings.toJson());

    expect(restored.navigationDestinationIds, [
      kNavigationDestinationHome,
      kNavigationDestinationFavorites,
      kNavigationDestinationSettings,
    ]);
    expect(
      AppSettings.fromJson(const {}).navigationDestinationIds,
      kDefaultNavigationDestinationIds,
    );
    expect(
      normalizeNavigationDestinationIds(const [
        kNavigationDestinationFavorites,
      ]),
      const [
        kNavigationDestinationFavorites,
        kNavigationDestinationSettings,
      ],
    );
  });
}
