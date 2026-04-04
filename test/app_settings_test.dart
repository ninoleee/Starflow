import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  test('app settings persist home hero style', () {
    final settings = AppSettings.fromJson({
      'homeHeroStyle': 'borderless',
    });

    expect(settings.homeHeroStyle, HomeHeroStyle.borderless);
    expect(settings.toJson()['homeHeroStyle'], 'borderless');
  });

  test('app settings default hero style is normal', () {
    final settings = AppSettings.fromJson(const {});

    expect(settings.homeHeroStyle, HomeHeroStyle.normal);
  });

  test('app settings persist metadata match preferences', () {
    final settings = AppSettings.fromJson({
      'tmdbMetadataMatchEnabled': true,
      'wmdbMetadataMatchEnabled': true,
      'metadataMatchPriority': 'wmdb',
    });

    expect(settings.tmdbMetadataMatchEnabled, isTrue);
    expect(settings.wmdbMetadataMatchEnabled, isTrue);
    expect(settings.metadataMatchPriority, MetadataMatchProvider.wmdb);
    expect(settings.toJson()['metadataMatchPriority'], 'wmdb');
  });

  test('app settings persist network storage config', () {
    final settings = AppSettings.fromJson({
      'networkStorage': {
        'quarkCookie': 'foo=bar',
        'quarkSaveFolderId': '123',
        'quarkSaveFolderPath': '/影视',
        'smartStrmWebhookUrl': 'http://localhost:8024/webhook/abc',
        'smartStrmTaskName': 'movie_task',
      },
    });

    expect(settings.networkStorage.quarkCookie, 'foo=bar');
    expect(settings.networkStorage.quarkSaveFolderId, '123');
    expect(settings.networkStorage.quarkSaveFolderPath, '/影视');
    expect(
      settings.networkStorage.smartStrmWebhookUrl,
      'http://localhost:8024/webhook/abc',
    );
    expect(settings.networkStorage.smartStrmTaskName, 'movie_task');

    final json = settings.toJson()['networkStorage'] as Map<String, dynamic>;
    expect(json['quarkCookie'], 'foo=bar');
    expect(json['quarkSaveFolderId'], '123');
    expect(json['quarkSaveFolderPath'], '/影视');
    expect(json['smartStrmWebhookUrl'], 'http://localhost:8024/webhook/abc');
    expect(json['smartStrmTaskName'], 'movie_task');
  });

  test('app settings default network storage config is empty', () {
    final settings = AppSettings.fromJson(const {});

    expect(settings.networkStorage.quarkCookie, isEmpty);
    expect(settings.networkStorage.quarkSaveFolderId, '0');
    expect(settings.networkStorage.quarkSaveFolderPath, '/');
    expect(settings.networkStorage.smartStrmWebhookUrl, isEmpty);
    expect(settings.networkStorage.smartStrmTaskName, isEmpty);
    expect(settings.networkStorage.hasAnyConfigured, isFalse);
  });
}
