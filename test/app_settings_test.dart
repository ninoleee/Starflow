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
      'taskMaxConcurrency': 4,
      'metadataPrefetchInitialBatchSize': 18,
      'metadataPrefetchBatchDelayMs': 250,
      'metadataPrefetchForegroundResumeDelayMs': 500,
    });

    expect(settings.taskMaxConcurrency, 4);
    expect(settings.metadataPrefetchInitialBatchSize, 18);
    expect(settings.metadataPrefetchBatchDelayMs, 250);
    expect(settings.metadataPrefetchForegroundResumeDelayMs, 500);
    expect(settings.toJson()['schemaVersion'], kAppSettingsSchemaVersion);
    expect(settings.toJson()['taskMaxConcurrency'], 4);
    expect(settings.toJson()['metadataPrefetchInitialBatchSize'], 18);
    expect(settings.toJson()['metadataPrefetchBatchDelayMs'], 250);
    expect(
      settings.toJson()['metadataPrefetchForegroundResumeDelayMs'],
      500,
    );
    expect(
      AppSettings.fromJson(const <String, dynamic>{}).taskMaxConcurrency,
      kTaskMaxConcurrencyDefault,
    );
    expect(
      AppSettings.fromJson(const <String, dynamic>{})
          .metadataPrefetchInitialBatchSize,
      kMetadataPrefetchInitialBatchSizeDefault,
    );
    expect(
      AppSettings.fromJson(const <String, dynamic>{
        'taskMaxConcurrency': 99,
      }).taskMaxConcurrency,
      kTaskMaxConcurrencyMax,
    );
    expect(
      AppSettings.fromJson(const <String, dynamic>{
        'metadataPrefetchInitialBatchSize': 99,
      }).metadataPrefetchInitialBatchSize,
      kMetadataPrefetchInitialBatchSizeMax,
    );
    expect(
      settings.copyWith(taskMaxConcurrency: 0).taskMaxConcurrency,
      kTaskMaxConcurrencyMin,
    );
    expect(
      settings
          .copyWith(metadataPrefetchInitialBatchSize: 0)
          .metadataPrefetchInitialBatchSize,
      kMetadataPrefetchInitialBatchSizeMin,
    );
    final feedSettings = AppSettings.fromJson(const <String, dynamic>{
      'taskMaxConcurrency': 4,
      'homeFeedInitialBatchSize': 3,
      'homeFeedBatchDelayMs': 250,
    });

    expect(feedSettings.taskMaxConcurrency, 4);
    expect(feedSettings.homeFeedInitialBatchSize, 3);
    expect(feedSettings.homeFeedBatchDelayMs, 250);
    expect(feedSettings.toJson()['taskMaxConcurrency'], 4);
    expect(feedSettings.toJson(), isNot(contains('homeFeedMaxConcurrency')));
    expect(
      feedSettings.toJson(),
      isNot(contains('metadataPrefetchMaxConcurrency')),
    );
    expect(
      feedSettings.toJson(),
      isNot(contains('nasSourceRefreshConcurrency')),
    );
    expect(
      feedSettings.toJson(),
      isNot(contains('nasCollectionRefreshConcurrency')),
    );
    expect(
      feedSettings.toJson(),
      isNot(contains('nasEnrichmentConcurrency')),
    );
    expect(feedSettings.toJson()['homeFeedInitialBatchSize'], 3);
    expect(feedSettings.toJson()['homeFeedBatchDelayMs'], 250);
    expect(
      AppSettings.fromJson(const <String, dynamic>{}).taskMaxConcurrency,
      kTaskMaxConcurrencyDefault,
    );
    expect(
      AppSettings.fromJson(const <String, dynamic>{}).homeFeedInitialBatchSize,
      kHomeFeedInitialBatchSizeDefault,
    );
    expect(
      feedSettings.copyWith(taskMaxConcurrency: 99).taskMaxConcurrency,
      kTaskMaxConcurrencyMax,
    );
    expect(
      feedSettings
          .copyWith(homeFeedInitialBatchSize: 0)
          .homeFeedInitialBatchSize,
      kHomeFeedInitialBatchSizeMin,
    );
  });

  test('current settings schema rejects unversioned or mismatched JSON', () {
    expect(
      () => AppSettings.fromCurrentJson(const <String, dynamic>{}),
      throwsFormatException,
    );
    expect(
      () => AppSettings.fromCurrentJson(const <String, dynamic>{
        'schemaVersion': kAppSettingsSchemaVersion - 1,
      }),
      throwsFormatException,
    );
    expect(
      AppSettings.fromCurrentJson(const <String, dynamic>{
        'schemaVersion': kAppSettingsSchemaVersion,
      }).toJson()['schemaVersion'],
      kAppSettingsSchemaVersion,
    );
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
    expect(
      defaults.localLogRecordedLevels,
      <AppLogLevel>{
        AppLogLevel.info,
        AppLogLevel.warning,
        AppLogLevel.error,
      },
    );

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
      'playbackPrimarySubtitlePosition': 75,
      'playbackSecondarySubtitlePosition': 90,
      'playbackSecondarySubtitleScale': 70,
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
    expect(settings.playbackPrimarySubtitlePosition, 75.0);
    expect(settings.playbackSecondarySubtitlePosition, 90.0);
    expect(settings.playbackSecondarySubtitleScale, 70.0);
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
    expect(settings.toJson()['playbackPrimarySubtitlePosition'], 75.0);
    expect(settings.toJson()['playbackSecondarySubtitlePosition'], 90.0);
    expect(settings.toJson()['playbackSecondarySubtitleScale'], 70.0);
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
    expect(
      defaults.playbackDefaultSubtitle,
      PlaybackDefaultSubtitle.systemLanguage,
    );
    expect(
      defaults.playbackDualSubtitlePrimaryLanguage,
      PlaybackSubtitleLanguage.simplifiedChinese,
    );
    expect(
      defaults.playbackDualSubtitleSecondaryLanguage,
      PlaybackSubtitleLanguage.english,
    );
    expect(defaults.playbackSubtitleScale, 32.0);
    expect(
      defaults.playbackPrimarySubtitlePosition,
      kPlaybackPrimarySubtitlePositionDefault,
    );
    expect(
      defaults.playbackSecondarySubtitlePosition,
      kPlaybackSecondarySubtitlePositionDefault,
    );
    expect(
      defaults.playbackSecondarySubtitleScale,
      kPlaybackSecondarySubtitleScaleDefault,
    );
    expect(kPlaybackSecondarySubtitleScaleDefault, 50.0);
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

  test('app settings persist native playback container engine', () {
    final settings = AppSettings.fromJson({
      'playbackEngine': 'nativeContainer',
      'playbackDecodeMode': 'hardwarePreferred',
      'nativeAudioOutputMode': 'pcmCompatibility',
    });

    expect(settings.playbackEngine, PlaybackEngine.nativeContainer);
    expect(
      settings.playbackDecodeMode,
      PlaybackDecodeMode.hardwarePreferred,
    );
    expect(
      settings.nativeAudioOutputMode,
      NativeAudioOutputMode.pcmCompatibility,
    );
    expect(settings.toJson()['playbackEngine'], 'nativeContainer');
    expect(settings.toJson()['playbackDecodeMode'], 'hardwarePreferred');
    expect(settings.toJson()['nativeAudioOutputMode'], 'pcmCompatibility');
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
      'playbackPrimarySubtitlePosition': 0,
      'playbackSecondarySubtitlePosition': 200,
      'playbackSecondarySubtitleScale': 500,
    });

    expect(settings.playbackOpenTimeoutSeconds, 1);
    expect(settings.playbackDefaultSpeed, 2.0);
    expect(settings.playbackSubtitleScale, kPlaybackSubtitleScaleMax);
    expect(
        settings.playbackPrimarySubtitlePosition, kPlaybackSubtitlePositionMin);
    expect(settings.playbackSecondarySubtitlePosition,
        kPlaybackSubtitlePositionMax);
    expect(
      settings.playbackSecondarySubtitleScale,
      kPlaybackSecondarySubtitleScaleMax,
    );

    final copied = settings.copyWith(
      playbackOpenTimeoutSeconds: 900,
      playbackDefaultSpeed: 0.1,
      playbackSubtitleScale: -20,
    );

    expect(copied.playbackOpenTimeoutSeconds, 900);
    expect(copied.playbackDefaultSpeed, 0.75);
    expect(copied.playbackSubtitleScale, kPlaybackSubtitleScaleMin);
  });

  test('default subtitle falls back to system language for missing values', () {
    expect(
      AppSettings.fromJson(const {}).playbackDefaultSubtitle,
      PlaybackDefaultSubtitle.systemLanguage,
    );
    expect(
      AppSettings.fromJson(
        const {'playbackDefaultSubtitle': 'traditionalChinese'},
      ).playbackDefaultSubtitle,
      PlaybackDefaultSubtitle.traditionalChinese,
    );
    expect(
      AppSettings.fromJson(
        const {'playbackDefaultSubtitle': 'removed-option'},
      ).playbackDefaultSubtitle,
      PlaybackDefaultSubtitle.systemLanguage,
    );
    expect(
      AppSettings.fromJson(
        const {'playbackDefaultSubtitle': 'korean'},
      ).playbackDefaultSubtitle,
      PlaybackDefaultSubtitle.systemLanguage,
    );
    final dualLanguages = AppSettings.fromJson(const {
      'playbackDualSubtitlePrimaryLanguage': 'traditionalChinese',
      'playbackDualSubtitleSecondaryLanguage': 'japanese',
    });
    expect(
      dualLanguages.playbackDualSubtitlePrimaryLanguage,
      PlaybackSubtitleLanguage.traditionalChinese,
    );
    expect(
      dualLanguages.playbackDualSubtitleSecondaryLanguage,
      PlaybackSubtitleLanguage.japanese,
    );
    final removedKorean = AppSettings.fromJson(const {
      'playbackDualSubtitlePrimaryLanguage': 'korean',
      'playbackDualSubtitleSecondaryLanguage': 'ko',
    });
    expect(
      removedKorean.playbackDualSubtitlePrimaryLanguage,
      PlaybackSubtitleLanguage.simplifiedChinese,
    );
    expect(
      removedKorean.playbackDualSubtitleSecondaryLanguage,
      PlaybackSubtitleLanguage.english,
    );
  });

  test('legacy secondary subtitle default migrates once from 75 to 50', () {
    final migrated = AppSettings.fromJson(
      const {'playbackSecondarySubtitleScale': 75},
    );
    expect(migrated.playbackSecondarySubtitleScale, 50);

    final explicitAfterUpgrade = AppSettings.fromJson(const {
      'playbackSecondarySubtitleScale': 75,
      'playbackSubtitleStyleDefaultsVersion':
          kPlaybackSubtitleStyleDefaultsVersion,
    });
    expect(explicitAfterUpgrade.playbackSecondarySubtitleScale, 75);
    expect(
      migrated.toJson()['playbackSubtitleStyleDefaultsVersion'],
      kPlaybackSubtitleStyleDefaultsVersion,
    );
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
      taskMaxConcurrency: 3,
      metadataPrefetchInitialBatchSize: 18,
      metadataPrefetchBatchDelayMs: 250,
      metadataPrefetchForegroundResumeDelayMs: 500,
      homeFeedInitialBatchSize: 3,
      homeFeedBatchDelayMs: 250,
    ).applyStartupCrashRecoveryPreset();

    expect(
      schedulingSettings.performanceAggressivePlaybackTuningEnabled,
      isTrue,
    );
    expect(
      schedulingSettings.taskMaxConcurrency,
      3,
    );
    expect(
      schedulingSettings.metadataPrefetchInitialBatchSize,
      18,
    );
    expect(schedulingSettings.metadataPrefetchBatchDelayMs, 250);
    expect(schedulingSettings.metadataPrefetchForegroundResumeDelayMs, 500);
    expect(schedulingSettings.homeFeedInitialBatchSize, 3);
    expect(schedulingSettings.homeFeedBatchDelayMs, 250);

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
