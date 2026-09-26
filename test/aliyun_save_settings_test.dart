import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/data/app_settings_repository.dart';
import 'package:starflow/features/settings/data/aliyun_login_client.dart';
import 'package:starflow/features/search/application/aliyun_to115_workflow.dart';
import 'package:starflow/features/search/data/aliyun_transfer_client.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/domain/cloud_account.dart';
import 'package:starflow/features/settings/presentation/aliyun_transfer_settings_page.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';

class _Repository extends Fake implements AppSettingsRepository {
  AppSettings settings = SeedData.defaultSettings;
  @override
  Future<AppSettings> load() async => settings;
  @override
  Future<void> save(AppSettings value) async => settings = value;
}

class _LoginClient extends Fake implements AliyunLoginClient {
  final result = Completer<AliyunQrResult>();
  @override
  Future<AliyunQrToken> createToken() async => const AliyunQrToken(
      t: '123',
      ck: 'session',
      qrcode: 'https://passport.aliyundrive.com/qrcodeCheck.htm?code=test');
  @override
  Future<AliyunQrResult> status(AliyunQrToken token) => result.future;
}

class _Workflow extends Fake implements AliyunTo115Workflow {
  _Workflow(this.aliyun, this.persistToken);
  @override
  final AliyunTransferClient aliyun;
  @override
  final Future<void> Function(String, String) persistToken;
}

class _Aliyun extends Fake implements AliyunTransferClient {
  _Aliyun(this.validate);
  final Future<void> Function() validate;
  final tokens = <String>[];
  @override
  Future<AliyunTransferSession> login(String refreshToken,
      {required Future<void> Function(String) persistToken,
      bool open = false}) async {
    tokens.add(refreshToken);
    await persistToken('rotated');
    await validate();
    return AliyunTransferSession(
        userId: 'user',
        accessToken: 'access',
        driveId: 'drive',
        deviceId: 'device',
        signature: 'signature');
  }
}

void main() {
  for (final outcome in [
    'success',
    'device-failure',
    'account-changed',
    'manual'
  ]) {
    testWidgets('login validates session and saves rotated token: $outcome',
        (tester) async {
      final repository = _Repository();
      repository.settings = repository.settings.copyWith(
          networkStorage: const NetworkStorageConfig(
                  aliyunRefreshToken: 'original',
                  aliyunSaveFolderId: 'folder',
                  aliyunSmartStrmTaskName: 'task',
                  cloud115Cookie: '115-cookie')
              .withAccount(
                  CloudAccountDrive.aliyun,
                  CloudAccount(
                      id: 'user',
                      fingerprint: credentialFingerprint('original'),
                      verified: true)));
      late ProviderContainer container;
      final login = _LoginClient();
      final client = _Aliyun(() async {
        expect(
            repository.settings.networkStorage.aliyunRefreshToken, 'original');
        if (outcome == 'account-changed') {
          await container
              .read(settingsControllerProvider.notifier)
              .saveNetworkStorage(repository.settings.networkStorage
                  .copyWith(aliyunRefreshToken: 'new-account'));
        }
        if (outcome == 'device-failure') {
          throw const QuarkSaveException('设备授权失败');
        }
      });
      final workflow = _Workflow(client, (previous, next) async {
        final config = container.read(appSettingsProvider).networkStorage;
        if (config.aliyunRefreshToken != previous) {
          throw const QuarkSaveException('阿里账号配置已变化，请重新发起转存');
        }
        await container
            .read(settingsControllerProvider.notifier)
            .saveNetworkStorage(config.copyWith(aliyunRefreshToken: next));
      });
      container = ProviderContainer(overrides: [
        appSettingsRepositoryProvider.overrideWithValue(repository),
        isTelevisionProvider.overrideWith((ref) => false),
        aliyunLoginClientProvider.overrideWithValue(login),
        aliyunTo115WorkflowProvider.overrideWithValue(workflow),
      ]);
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.future);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AliyunTransferSettingsPage())));
      await tester.pumpAndSettle();
      expect(find.text('阿里 Refresh Token'), findsOneWidget);
      expect(find.text('通用设置'), findsNothing);
      if (outcome == 'manual') {
        await tester.scrollUntilVisible(find.text('保存并验证'), 250,
            scrollable: find.byType(Scrollable).first);
        await tester.ensureVisible(find.text('保存并验证'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('保存并验证'));
      } else {
        await tester.tap(find.text('扫码登录'));
        await tester.pumpAndSettle();
        login.result.complete(const AliyunQrResult(AliyunQrStatus.confirmed,
            refreshToken: 'scanned'));
      }
      await tester.pumpAndSettle();
      expect(client.tokens, [outcome == 'manual' ? 'original' : 'scanned']);
      expect(
          repository.settings.networkStorage.aliyunRefreshToken,
          outcome == 'success' || outcome == 'manual'
              ? 'rotated'
              : outcome == 'account-changed'
                  ? 'new-account'
                  : 'original');
      expect(repository.settings.networkStorage.aliyunSaveFolderId,
          outcome == 'account-changed' ? '' : 'folder');
      expect(
          repository.settings.networkStorage.aliyunSmartStrmTaskName, 'task');
      expect(repository.settings.networkStorage.cloud115Cookie, '115-cookie');
      final save = find.text('保存');
      await tester.scrollUntilVisible(save, 250,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(
          repository.settings.networkStorage.aliyunRefreshToken,
          outcome == 'success' || outcome == 'manual'
              ? 'rotated'
              : outcome == 'account-changed'
                  ? 'new-account'
                  : 'original');
      expect(tester.takeException(), isNull);
    });
  }
  test('transfer is opt-in and survives JSON while credentials stay local', () {
    expect(NetworkStorageConfig.fromJson({}).aliyunTo115Enabled, isFalse);
    const config = NetworkStorageConfig(
        aliyunRefreshToken: 'secret',
        aliyunTo115Enabled: true,
        aliyunSaveFolderId: 'folder',
        aliyunSaveFolderPath: '/Ali',
        aliyunSmartStrmTaskName: 'ali-task',
        aliyunSanitizeSavedNamesEnabled: true,
        syncDeleteAliyunEnabled: true,
        syncDeleteAliyunWebDavDirectories: [
          NetworkStorageWebDavDirectory(sourceId: 'nas', directoryId: '/ali')
        ]);
    final restored = NetworkStorageConfig.fromJson(config.toJson());
    expect(restored.aliyunTo115Enabled, isTrue);
    expect(restored.aliyunRefreshToken, isEmpty);
    expect(restored.aliyunSaveFolderId, 'folder');
    expect(restored.aliyunSaveFolderPath, '/Ali');
    expect(restored.aliyunSmartStrmTaskName, 'ali-task');
    expect(restored.aliyunSanitizeSavedNamesEnabled, isTrue);
    expect(restored.syncDeleteAliyunEnabled, isTrue);
    expect(
        restored.syncDeleteAliyunWebDavDirectories.single.directoryId, '/ali');
    expect(
        config.copyWith(aliyunTo115Enabled: false).aliyunTo115Enabled, isFalse);
  });

  test('Open auth mode persists while both token slots stay local', () {
    const config = NetworkStorageConfig(
        aliyunAuthMode: AliyunAuthMode.open,
        aliyunRefreshToken: 'consumer-secret',
        aliyunOpenRefreshToken: 'open.jwt.token',
        aliyunSaveFolderId: 'folder');
    final json = config.toJson();
    expect(json['aliyunAuthMode'], 'open');
    expect(json.toString(), isNot(contains('consumer-secret')));
    expect(json.toString(), isNot(contains('open.jwt.token')));
    final restored = NetworkStorageConfig.fromJson(json);
    expect(restored.aliyunAuthMode, AliyunAuthMode.open);
    expect(restored.aliyunRefreshToken, isEmpty);
    expect(restored.aliyunOpenRefreshToken, isEmpty);
    expect(restored.activeAliyunRefreshToken, isEmpty);
    expect(
        restored
            .copyWith(aliyunOpenRefreshToken: 'open.jwt.token')
            .activeAliyunRefreshToken,
        'open.jwt.token');
  });

  for (final tv in [false, true]) {
    testWidgets('Aliyun independent toggle persists on ${tv ? 'TV' : 'mobile'}',
        (tester) async {
      tester.view.physicalSize =
          tv ? const Size(1920, 1080) : const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _Repository();
      final container = ProviderContainer(overrides: [
        appSettingsRepositoryProvider.overrideWithValue(repository),
        isTelevisionProvider.overrideWith((ref) => tv),
      ]);
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.future);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AliyunTransferSettingsPage())));
      await tester.pumpAndSettle();
      final toggle = find.byWidgetPredicate(
          (w) => w is SettingsToggleTile && w.title == '保存时转到 115 并删除阿里副本');
      expect(tester.widget<SettingsToggleTile>(toggle).value, isFalse);
      await tester.ensureVisible(toggle);
      await tester.tap(find.text('保存时转到 115 并删除阿里副本'));
      await tester.pumpAndSettle();
      expect(repository.settings.networkStorage.aliyunTo115Enabled, isTrue);
      expect(find.text('115 账号未配置'), findsOneWidget);
      await tester.tap(find.text('保存时转到 115 并删除阿里副本'));
      await tester.pumpAndSettle();
      expect(repository.settings.networkStorage.aliyunTo115Enabled, isFalse);
      expect(find.text('115 账号未配置'), findsNothing);
      expect(find.text('阿里保存目录'), findsOneWidget);
      expect(find.text('同步删除阿里目录'), findsOneWidget);
      expect(find.text('使用通用名称规则'), findsNothing);
      expect(find.text('修正保存名称'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('rotated token is not overwritten by a later settings save',
      (tester) async {
    final repository = _Repository();
    repository.settings = repository.settings.copyWith(
        networkStorage: const NetworkStorageConfig(
            aliyunRefreshToken: 'old',
            aliyunSaveFolderPath: '/Ali',
            aliyunSmartStrmTaskName: 'ali-task'));
    final container = ProviderContainer(overrides: [
      appSettingsRepositoryProvider.overrideWithValue(repository),
      isTelevisionProvider.overrideWith((ref) => false),
    ]);
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AliyunTransferSettingsPage())));
    await tester.pumpAndSettle();
    await container
        .read(settingsControllerProvider.notifier)
        .rotateAliyunCredential('old', 'rotated');
    await tester.pumpAndSettle();
    final save = find.text('保存');
    await tester.scrollUntilVisible(save, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(repository.settings.networkStorage.aliyunRefreshToken, 'rotated');
    expect(repository.settings.networkStorage.aliyunSaveFolderPath, '/Ali');
    expect(
        repository.settings.networkStorage.aliyunSmartStrmTaskName, 'ali-task');
  });
}
