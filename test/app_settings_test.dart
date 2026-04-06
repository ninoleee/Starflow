import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  test('app settings persist home hero style and visual effect switches', () {
    final settings = AppSettings.fromJson({
      'homeHeroStyle': 'borderless',
      'homeHeroBackgroundEnabled': false,
      'translucentEffectsEnabled': false,
      'playbackOpenTimeoutSeconds': 45,
      'playbackDefaultSpeed': 1.25,
      'playbackSubtitlePreference': 'off',
      'playbackSubtitleScale': 'large',
      'playbackBackgroundPlaybackEnabled': false,
      'playbackEngine': 'systemPlayer',
      'playbackDecodeMode': 'softwarePreferred',
    });

    expect(settings.homeHeroStyle, HomeHeroStyle.borderless);
    expect(settings.homeHeroBackgroundEnabled, isFalse);
    expect(settings.translucentEffectsEnabled, isFalse);
    expect(settings.playbackOpenTimeoutSeconds, 45);
    expect(settings.playbackDefaultSpeed, 1.25);
    expect(
      settings.playbackSubtitlePreference,
      PlaybackSubtitlePreference.off,
    );
    expect(settings.playbackSubtitleScale, PlaybackSubtitleScale.large);
    expect(settings.playbackBackgroundPlaybackEnabled, isFalse);
    expect(settings.playbackEngine, PlaybackEngine.systemPlayer);
    expect(
      settings.playbackDecodeMode,
      PlaybackDecodeMode.softwarePreferred,
    );
    expect(settings.toJson()['homeHeroStyle'], 'borderless');
    expect(settings.toJson()['homeHeroBackgroundEnabled'], isFalse);
    expect(settings.toJson()['translucentEffectsEnabled'], isFalse);
    expect(settings.toJson()['playbackOpenTimeoutSeconds'], 45);
    expect(settings.toJson()['playbackDefaultSpeed'], 1.25);
    expect(settings.toJson()['playbackSubtitlePreference'], 'off');
    expect(settings.toJson()['playbackSubtitleScale'], 'large');
    expect(settings.toJson()['playbackBackgroundPlaybackEnabled'], isFalse);
    expect(settings.toJson()['playbackEngine'], 'systemPlayer');
    expect(settings.toJson()['playbackDecodeMode'], 'softwarePreferred');
  });

  test('app settings default hero style is normal', () {
    final settings = AppSettings.fromJson(const {});

    expect(settings.homeHeroStyle, HomeHeroStyle.normal);
    expect(settings.homeHeroBackgroundEnabled, isTrue);
    expect(settings.translucentEffectsEnabled, isTrue);
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
    expect(settings.playbackSubtitleScale, PlaybackSubtitleScale.standard);
    expect(settings.playbackBackgroundPlaybackEnabled, isTrue);
    expect(settings.playbackEngine, PlaybackEngine.embeddedMpv);
    expect(settings.playbackDecodeMode, PlaybackDecodeMode.auto);
    expect(settings.detailAutoLibraryMatchEnabled, isFalse);
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

  test('legacy hero settings migrate to hero module', () {
    final settings = AppSettings.fromJson({
      'homeHeroEnabled': false,
      'homeHeroStyle': 'borderless',
      'homeModules': const [],
    });

    final heroModule = settings.homeModules
        .firstWhere((item) => item.type == HomeModuleType.hero);

    expect(heroModule.enabled, isFalse);
    expect(settings.homeHeroStyle, HomeHeroStyle.borderless);
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
}
