import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/data/app_settings_repository.dart';
import 'package:starflow/features/settings/data/cloud_credential_store.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/domain/cloud_account.dart';
import 'package:starflow/features/settings/application/media_source_cache_lifecycle.dart';
import 'package:starflow/features/library/domain/media_models.dart';

class _Lifecycle implements MediaSourceCacheLifecycle {
  @override
  Future<void> clearAllIndexes() async {}
  @override
  Future<void> clearSource(String sourceId) async {}
  @override
  Future<void> reconcileSources(List<MediaSourceConfig> sources) async {}
}

class _Store extends Fake implements PreferencesStore {
  final values = <String, String>{};
  @override
  Future<String?> getString(String key) async => values[key];
  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}

class _Secure extends MemoryCloudCredentialStore {
  bool fail = false;
  @override
  Future<void> write(String value) async {
    if (fail) throw StateError('locked');
    await super.write(value);
  }
}

class _Repo extends Fake implements AppSettingsRepository {
  AppSettings settings = SeedData.defaultSettings;
  @override
  Future<AppSettings> load() async => settings;
  @override
  Future<void> save(AppSettings value) async {
    settings = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('starflow-account-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => directory.path);
  });
  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    await directory.delete(recursive: true);
  });
  test('migration verifies secure write before removing plaintext credentials',
      () async {
    final store = _Store();
    final raw = SeedData.defaultSettings.toJson();
    (raw['networkStorage'] as Map)['quarkCookie'] = 'quark-secret';
    store.values['starflow.settings.v3'] = jsonEncode(raw);
    store.values['starflow.local-credentials.cloud115-cookie.v1'] =
        '115-secret';
    store.values['starflow.local-credentials.aliyun-refresh-token.v1'] =
        'ali-secret';
    final before = Map.of(store.values);
    final secure = _Secure()..fail = true;
    final repo =
        LocalAppSettingsRepository(preferences: store, credentials: secure);
    await expectLater(repo.load(), throwsStateError);
    expect(store.values, before);
    secure.fail = false;
    final loaded = await repo.load();
    expect(loaded.networkStorage.quarkCookie, 'quark-secret');
    expect(loaded.networkStorage.cloud115Cookie, '115-secret');
    expect(loaded.networkStorage.aliyunRefreshToken, 'ali-secret');
    expect(store.values.keys, ['starflow.settings.v3']);
    expect(store.values.values.single, isNot(contains('secret')));
    expect(jsonEncode(loaded.toJson()), isNot(contains('secret')));
    expect((await repo.load()).networkStorage.quarkCookie, 'quark-secret');
  });

  for (final drive in CloudAccountDrive.values) {
    test('account identity and directory ownership: $drive', () async {
      final repo = _Repo();
      repo.settings = repo.settings.copyWith(
          networkStorage: const NetworkStorageConfig(
                  aliyunSaveFolderId: 'a',
                  cloud115SaveFolderId: '1',
                  quarkSaveFolderId: 'q',
                  syncDeleteAliyunEnabled: true,
                  syncDelete115Enabled: true,
                  syncDeleteQuarkEnabled: true,
                  smartStrmWebhookUrl: 'https://nas.test')
              .withCredential(drive, 'old')
              .withAccount(
                  drive,
                  CloudAccount(
                      id: 'one',
                      verified: true,
                      fingerprint: credentialFingerprint('old'))));
      final container = ProviderContainer(overrides: [
        appSettingsRepositoryProvider.overrideWithValue(repo),
        mediaSourceCacheLifecycleProvider.overrideWithValue(_Lifecycle())
      ]);
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.future);
      final controller = container.read(settingsControllerProvider.notifier);
      await controller.acceptCloudAccount(drive, 'old', 'rotated', 'one');
      expect(repo.settings.networkStorage.account(drive).directoryPending,
          isFalse);
      await controller.acceptCloudAccount(drive, 'rotated', 'new', 'two');
      final config = repo.settings.networkStorage;
      expect(config.account(drive).directoryPending, isTrue);
      expect(config.account(drive).status('new'), '可用');
      expect(config.account(drive).status('unverified'), '待验证');
      expect(config.smartStrmWebhookUrl, 'https://nas.test');
      await controller.saveNetworkStorage(config.copyWith(
          aliyunSaveFolderId: 'stale-a',
          cloud115SaveFolderId: '999',
          quarkSaveFolderId: 'stale-q',
          syncDeleteAliyunEnabled: true,
          syncDelete115Enabled: true,
          syncDeleteQuarkEnabled: true));
      final guarded = repo.settings.networkStorage;
      expect(
          switch (drive) {
            CloudAccountDrive.aliyun => guarded.aliyunSaveFolderId,
            CloudAccountDrive.cloud115 => guarded.cloud115SaveFolderId,
            CloudAccountDrive.quark => guarded.quarkSaveFolderId,
          },
          isEmpty);
      expect(
          switch (drive) {
            CloudAccountDrive.aliyun => config.aliyunSaveFolderId,
            CloudAccountDrive.cloud115 => config.cloud115SaveFolderId,
            CloudAccountDrive.quark => config.quarkSaveFolderId
          },
          isEmpty);
      await controller.markCloudAccountInvalid(drive, 'new');
      expect(repo.settings.networkStorage.account(drive).status('new'), '已失效');
      await expectLater(
          controller.acceptCloudAccount(drive, 'old', 'stale', 'three'),
          throwsStateError);
      expect(repo.settings.networkStorage.credential(drive), 'new');
      await controller.replaceAllSettings(SeedData.defaultSettings);
      expect(repo.settings.networkStorage.credential(drive), 'new');
    });
  }
}
