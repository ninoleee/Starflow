import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:starflow/features/update/application/update_controller.dart';
import 'package:starflow/features/update/data/update_install_launcher.dart';
import 'package:starflow/features/update/data/update_manifest_client.dart';
import 'package:starflow/features/update/data/update_package_downloader.dart';
import 'package:starflow/features/update/domain/app_update.dart';
import 'package:starflow/features/update/domain/update_source.dart';
import 'package:starflow/features/settings/domain/webdav_sync_config.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';

class SyncSettings extends SettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings(
      mediaSources: [],
      searchProviders: [],
      homeModules: [],
      doubanAccount: DoubanAccountConfig(enabled: false),
      webDavSync: WebDavSyncConfig(url: 'https://old.example/dav'));
  void replaceSync() {
    state = AsyncData(state.requireValue.copyWith(
        webDavSync: const WebDavSyncConfig(url: 'https://new.example/dav')));
  }
}

class FakeManifest extends UpdateManifestClient {
  Completer<AppUpdate>? pending;
  int calls = 0;
  Uri? lastUri;
  UpdateSource? lastSource;
  AppUpdate release = AppUpdate(
      appId: 'com.example.starflow',
      channel: 'stable',
      version: '1.1.0',
      versionCode: 200,
      publishedAt: DateTime.utc(2027),
      releaseNotes: const ['Fix'],
      artifacts: [artifact]);
  @override
  Future<AppUpdate> fetch(Uri uri, {UpdateSource? source}) async {
    calls++;
    lastUri = uri;
    lastSource = source;
    return pending?.future ?? release;
  }
}

final artifact = UpdateArtifact(
    platform: 'android',
    variant: 'tv',
    url: Uri.parse(
        'https://example.org/dav/Starflow/releases/200/starflow-tv-1.1.0.apk'),
    fileName: 'starflow-tv-1.1.0.apk',
    size: 10,
    sha256: 'a' * 64,
    minSdk: 23,
    certificateSha256: 'b' * 64);

class FakeDownloader extends UpdatePackageDownloader {
  Completer<String>? pending;
  bool cancelled = false;
  @override
  Future<String> download(UpdateArtifact artifact,
      {required void Function(int) onProgress,
      UpdateSource? source,
      required void Function() onVerifying}) async {
    onProgress(5);
    if (pending != null) return pending!.future;
    onVerifying();
    return '/private/updates/file.apk';
  }

  @override
  void cancel() => cancelled = true;
  @override
  Future<void> dispose() async {
    cancel();
  }
}

class FakeInstaller extends UpdateInstallLauncher {
  bool permission = true;
  bool launched = false;
  bool settingsOpened = false;
  List<String> abis = ['arm64-v8a'];
  int installedCode = 100;
  @override
  Future<UpdateDeviceInfo> deviceInfo() async => UpdateDeviceInfo(
      sdkInt: 23,
      abis: abis,
      versionCode: installedCode,
      packageName: 'com.example.starflow');
  @override
  Future<bool> canInstallUpdates() async => permission;
  @override
  Future<bool> openInstallPermissionSettings() async => settingsOpened = true;
  @override
  Future<bool> installApk(
      {required String path,
      required String sha256,
      required int versionCode,
      required String certificateSha256}) async {
    expect(versionCode, 200);
    expect(sha256, artifact.sha256);
    return launched = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeManifest manifest;
  late FakeDownloader downloader;
  late FakeInstaller installer;
  late UpdateController controller;
  setUp(() {
    manifest = FakeManifest();
    downloader = FakeDownloader();
    installer = FakeInstaller();
    controller = UpdateController(
        manifestClient: manifest,
        downloader: downloader,
        installer: installer,
        android: true,
        syncConfig: const WebDavSyncConfig(
            url: 'https://example.org/dav',
            username: 'user',
            password: 'secret'),
        packageInfo: () async => PackageInfo(
            appName: 'Starflow',
            packageName: 'com.example.starflow',
            version: '1.12.99',
            buildNumber: '100'));
  });
  tearDown(() => controller.dispose());

  test('saved sync change replaces and disposes old update owner', () async {
    final container = ProviderContainer(overrides: [
      settingsControllerProvider.overrideWith(SyncSettings.new),
    ]);
    final subscription = container.listen(updateControllerProvider, (_, __) {});
    try {
      await container.read(settingsControllerProvider.future);
      await container.pump();
      final old = container.read(updateControllerProvider);
      (container.read(settingsControllerProvider.notifier) as SyncSettings)
          .replaceSync();
      await container.pump();
      expect(identical(old, container.read(updateControllerProvider)), isFalse);
      await old.check();
      expect(old.state.phase, UpdatePhase.idle);
    } finally {
      subscription.close();
      container.dispose();
    }
  });

  test('WebDAV sync alone enables updates without a build-time key', () async {
    expect(controller.configured, isTrue);
    await controller.check();
    expect(manifest.lastUri.toString(),
        'https://example.org/dav/Starflow/releases/latest.json');
    expect(manifest.lastSource!.headersFor(manifest.lastUri!)['Authorization'],
        isNotEmpty);
  });

  test('cross-year release uses numeric APK code, not display version',
      () async {
    await controller.check();
    expect(controller.state.phase, UpdatePhase.available);
    expect(controller.state.update?.version, '1.1.0');
    expect(controller.state.currentVersion, '1.12.99');
  });
  test('same or older numeric code is up to date', () async {
    installer.installedCode = 200;
    await controller.check();
    expect(controller.state.phase, UpdatePhase.upToDate);
  });
  test('unsupported CPU never offers ARM package', () async {
    installer.abis = ['x86_64'];
    await controller.check();
    expect(controller.state.failure?.code, 'unsupportedPlatform');
    expect(controller.state.artifact, isNull);
  });
  test('repeated checks coalesce while pending', () async {
    manifest.pending = Completer<AppUpdate>();
    final first = controller.check();
    await Future<void>.delayed(Duration.zero);
    await controller.check();
    expect(manifest.calls, 1);
    manifest.pending!.complete(manifest.release);
    await first;
  });
  test('download verified then permission requested without auto install',
      () async {
    await controller.check();
    await controller.download();
    expect(controller.state.phase, UpdatePhase.readyToInstall);
    installer.permission = false;
    await controller.install();
    expect(controller.state.failure?.code, 'installPermissionRequired');
    expect(controller.state.packagePath, isNotNull);
    expect(installer.launched, isFalse);
    await controller.openInstallPermissionSettings();
    expect(installer.settingsOpened, isTrue);
    expect(installer.launched, isFalse);
    installer.permission = true;
    await controller.install();
    expect(installer.launched, isTrue);
    expect(controller.state.phase, UpdatePhase.readyToInstall);
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(controller.state.phase, UpdatePhase.readyToInstall);
  });
  test('background cancels and late completion cannot enable installation',
      () async {
    await controller.check();
    downloader.pending = Completer<String>();
    final task = controller.download();
    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(downloader.cancelled, isTrue);
    downloader.pending!.complete('/late.apk');
    await task;
    expect(controller.state.phase, UpdatePhase.available);
    expect(controller.state.packagePath, isNull);
    await controller.install();
    expect(installer.launched, isFalse);
  });
  test('unconfigured check makes no network call', () async {
    final unconfigured = UpdateController(
        android: true,
        manifestClient: manifest,
        downloader: FakeDownloader(),
        installer: installer,
        packageInfo: () async => PackageInfo(
            appName: '', packageName: '', version: '1', buildNumber: '1'));
    await unconfigured.check();
    expect(unconfigured.state.phase, UpdatePhase.unconfigured);
    expect(manifest.calls, 0);
    unconfigured.dispose();
  });
}
