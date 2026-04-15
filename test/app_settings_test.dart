import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  test('app settings persist home hero display mode, style and switches', () {
    final settings = AppSettings.fromJson({
      'homeHeroDisplayMode': 'borderless',
      'homeHeroStyle': 'poster',
      'homeHeroBackgroundEnabled': false,
      'translucentEffectsEnabled': false,
      'autoHideNavigationBarEnabled': false,
      'performanceLiveItemHeroOverlayEnabled': false,
      'playbackOpenTimeoutSeconds': 45,
      'playbackDefaultSpeed': 1.25,
      'playbackSubtitlePreference': 'off',
      'playbackSubtitleScale': 'large',
      'onlineSubtitleSources': ['assrt'],
      'opensubtitlesEnabled': true,
      'opensubtitlesUsername': 'opensub-user',
      'opensubtitlesPassword': 'opensub-pass',
      'subdlEnabled': true,
      'subdlApiKey': 'subdl-key',
      'subtitlePreferredLanguages': ['zh-cn', 'en', 'zh-cn'],
      'subtitleHearingImpairedPreferred': true,
      'subtitleSearchMaxValidatedCandidates': 9,
      'subtitleAllowLegacyProvidersFallback': false,
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
      'playbackTraceEnabled': true,
      'subtitleSearchTraceEnabled': true,
    });

    expect(settings.homeHeroDisplayMode, HomeHeroDisplayMode.borderless);
    expect(settings.homeHeroStyle, HomeHeroStyle.poster);
    expect(settings.homeHeroBackgroundEnabled, isFalse);
    expect(settings.translucentEffectsEnabled, isFalse);
    expect(settings.autoHideNavigationBarEnabled, isFalse);
    expect(settings.performanceLiveItemHeroOverlayEnabled, isFalse);
    expect(settings.playbackOpenTimeoutSeconds, 45);
    expect(settings.playbackDefaultSpeed, 1.25);
    expect(
      settings.playbackSubtitlePreference,
      PlaybackSubtitlePreference.off,
    );
    expect(settings.playbackSubtitleScale, 36.0);
    expect(settings.onlineSubtitleSources, [OnlineSubtitleSource.assrt]);
    expect(settings.opensubtitlesEnabled, isTrue);
    expect(settings.opensubtitlesUsername, 'opensub-user');
    expect(settings.opensubtitlesPassword, 'opensub-pass');
    expect(settings.subdlEnabled, isTrue);
    expect(settings.subdlApiKey, 'subdl-key');
    expect(settings.subtitlePreferredLanguages, ['zh-cn', 'en']);
    expect(settings.subtitleHearingImpairedPreferred, isTrue);
    expect(settings.subtitleSearchMaxValidatedCandidates, 9);
    expect(settings.subtitleAllowLegacyProvidersFallback, isFalse);
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
    expect(settings.performanceAutoDowngradeHeavyPlaybackEnabled, isTrue);
    expect(settings.playbackTraceEnabled, isTrue);
    expect(settings.subtitleSearchTraceEnabled, isTrue);
    expect(settings.toJson()['homeHeroDisplayMode'], 'borderless');
    expect(settings.toJson()['homeHeroStyle'], 'poster');
    expect(settings.toJson()['homeHeroBackgroundEnabled'], isFalse);
    expect(settings.toJson()['translucentEffectsEnabled'], isFalse);
    expect(settings.toJson()['autoHideNavigationBarEnabled'], isFalse);
    expect(settings.toJson()['performanceLiveItemHeroOverlayEnabled'], isFalse);
    expect(settings.toJson()['playbackOpenTimeoutSeconds'], 45);
    expect(settings.toJson()['playbackDefaultSpeed'], 1.25);
    expect(settings.toJson()['playbackSubtitlePreference'], 'off');
    expect(settings.toJson()['playbackSubtitleScale'], 36.0);
    expect(settings.toJson()['onlineSubtitleSources'], ['assrt']);
    expect(settings.toJson()['opensubtitlesEnabled'], isTrue);
    expect(settings.toJson()['opensubtitlesUsername'], 'opensub-user');
    expect(settings.toJson()['opensubtitlesPassword'], 'opensub-pass');
    expect(settings.toJson()['subdlEnabled'], isTrue);
    expect(settings.toJson()['subdlApiKey'], 'subdl-key');
    expect(settings.toJson()['subtitlePreferredLanguages'], ['zh-cn', 'en']);
    expect(settings.toJson()['subtitleHearingImpairedPreferred'], isTrue);
    expect(settings.toJson()['subtitleSearchMaxValidatedCandidates'], 9);
    expect(
      settings.toJson()['subtitleAllowLegacyProvidersFallback'],
      isFalse,
    );
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
      settings.toJson()['performanceAutoDowngradeHeavyPlaybackEnabled'],
      isTrue,
    );
    expect(settings.toJson()['playbackTraceEnabled'], isTrue);
    expect(settings.toJson()['subtitleSearchTraceEnabled'], isTrue);
  });

  test('app settings default hero display mode and style', () {
    final settings = AppSettings.fromJson(const {});

    expect(settings.homeHeroDisplayMode, HomeHeroDisplayMode.normal);
    expect(settings.homeHeroStyle, HomeHeroStyle.composite);
    expect(settings.homeHeroBackgroundEnabled, isTrue);
    expect(settings.translucentEffectsEnabled, isTrue);
    expect(settings.autoHideNavigationBarEnabled, isTrue);
    expect(settings.performanceLiveItemHeroOverlayEnabled, isTrue);
    expect(
      settings.homeModules
          .firstWhere((item) => item.type == HomeModuleType.hero)
          .enabled,
      isTrue,
    );
    expect(settings.playbackOpenTimeoutSeconds, 20);
    expect(settings.playbackDefaultSpeed, 1.0);
    expect(
      settings.playbackSubtitlePreference,
      PlaybackSubtitlePreference.auto,
    );
    expect(settings.playbackSubtitleScale, 32.0);
    expect(settings.onlineSubtitleSources, [OnlineSubtitleSource.assrt]);
    expect(settings.opensubtitlesEnabled, isFalse);
    expect(settings.opensubtitlesUsername, isEmpty);
    expect(settings.opensubtitlesPassword, isEmpty);
    expect(settings.subdlEnabled, isFalse);
    expect(settings.subdlApiKey, isEmpty);
    expect(settings.subtitlePreferredLanguages, isEmpty);
    expect(settings.subtitleHearingImpairedPreferred, isFalse);
    expect(
      settings.subtitleSearchMaxValidatedCandidates,
      kSubtitleSearchMaxValidatedCandidatesDefault,
    );
    expect(settings.subtitleAllowLegacyProvidersFallback, isTrue);
    expect(settings.playbackBackgroundPlaybackEnabled, isTrue);
    expect(settings.playbackEngine, PlaybackEngine.embeddedMpv);
    expect(settings.playbackDecodeMode, PlaybackDecodeMode.auto);
    expect(
      settings.playbackMpvQualityPreset,
      PlaybackMpvQualityPreset.performanceFirst,
    );
    expect(settings.playbackMpvDoubleTapToSeekEnabled, isTrue);
    expect(settings.playbackMpvSwipeToSeekEnabled, isTrue);
    expect(settings.playbackMpvLongPressSpeedBoostEnabled, isTrue);
    expect(settings.playbackMpvStallAutoRecoveryEnabled, isTrue);
    expect(settings.performanceAggressivePlaybackTuningEnabled, isFalse);
    expect(settings.performanceAutoDowngradeHeavyPlaybackEnabled, isFalse);
    expect(settings.playbackTraceEnabled, isFalse);
    expect(settings.subtitleSearchTraceEnabled, isFalse);
    expect(settings.detailAutoLibraryMatchEnabled, isFalse);
  });

  test(
      'high performance preset marker no longer overrides runtime effective settings',
      () {
    final settings = AppSettings.fromJson({
      'highPerformanceModeEnabled': true,
      'translucentEffectsEnabled': true,
      'autoHideNavigationBarEnabled': true,
      'performanceReduceMotionEnabled': false,
      'performanceStaticNavigationEnabled': false,
      'performanceLeanPlaybackUiEnabled': false,
    });

    expect(settings.effectiveUiPerformanceTier, AppUiPerformanceTier.rich);
    expect(settings.effectiveTranslucentEffectsEnabled, isTrue);
    expect(settings.effectiveNavigationAutoHideEnabled, isTrue);
    expect(
      settings.effectiveLeanPlaybackUiEnabled(isTelevision: false),
      isFalse,
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

  test('app settings persist network storage config', () {
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
  });

  test('app settings default network storage config is empty', () {
    final settings = AppSettings.fromJson(const {});

    expect(settings.networkStorage.quarkCookie, isEmpty);
    expect(settings.networkStorage.quarkSaveFolderId, '0');
    expect(settings.networkStorage.quarkSaveFolderPath, '/');
    expect(settings.networkStorage.syncDeleteQuarkEnabled, isFalse);
    expect(settings.networkStorage.syncDeleteQuarkWebDavDirectories, isEmpty);
    expect(settings.networkStorage.smartStrmWebhookUrl, isEmpty);
    expect(settings.networkStorage.smartStrmTaskName, isEmpty);
    expect(settings.networkStorage.refreshMediaSourceIds, isEmpty);
    expect(settings.networkStorage.refreshDelaySeconds, 1);
    expect(settings.networkStorage.hasAnyConfigured, isFalse);
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

  test('unknown subtitle source list falls back to assrt only', () {
    final settings = AppSettings.fromJson({
      'onlineSubtitleSources': ['invalid-source'],
    });

    expect(settings.onlineSubtitleSources, [OnlineSubtitleSource.assrt]);
  });

  test('subtitle provider settings are normalized and clamped', () {
    final settings = AppSettings.fromJson({
      'subtitlePreferredLanguages': [' zh-CN ', 'en', '', 'EN'],
      'subtitleSearchMaxValidatedCandidates': 99,
    });

    expect(settings.subtitlePreferredLanguages, ['zh-cn', 'en']);
    expect(
      settings.subtitleSearchMaxValidatedCandidates,
      kSubtitleSearchMaxValidatedCandidatesMax,
    );

    final copied = settings.copyWith(
      subtitlePreferredLanguages: ['zh-tw', 'zh-tw', 'ja'],
      subtitleSearchMaxValidatedCandidates: 0,
    );

    expect(copied.subtitlePreferredLanguages, ['zh-tw', 'zh-tw', 'ja']);
    expect(
      copied.subtitleSearchMaxValidatedCandidates,
      kSubtitleSearchMaxValidatedCandidatesMin,
    );
  });

  test('high performance preset turns on playback tuning flags', () {
    final settings = const AppSettings(
      mediaSources: [],
      searchProviders: [],
      doubanAccount: DoubanAccountConfig(enabled: false),
      homeModules: [],
    ).applyHighPerformancePreset();

    expect(settings.performanceAggressivePlaybackTuningEnabled, isTrue);
    expect(settings.performanceAutoDowngradeHeavyPlaybackEnabled, isTrue);
    expect(
        settings.effectiveUiPerformanceTier, AppUiPerformanceTier.performance);
    expect(settings.effectiveStartupProbeEnabled, isFalse);
  });
}
