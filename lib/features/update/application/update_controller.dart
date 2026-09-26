import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/features/update/data/update_install_launcher.dart';
import 'package:starflow/features/update/data/update_manifest_client.dart';
import 'package:starflow/features/update/data/update_package_downloader.dart';
import 'package:starflow/features/update/domain/app_update.dart';
import 'package:starflow/features/update/domain/update_source.dart';
import 'package:starflow/features/settings/domain/webdav_sync_config.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

final updateControllerProvider =
    ChangeNotifierProvider.autoDispose<UpdateController>(
  (ref) => UpdateController(
      syncConfig: ref.watch(settingsControllerProvider
          .select((state) => state.value?.webDavSync))),
);

class UpdateController extends ChangeNotifier with WidgetsBindingObserver {
  UpdateController({
    UpdateManifestClient? manifestClient,
    UpdatePackageDownloader? downloader,
    UpdateInstallLauncher? installer,
    Future<PackageInfo> Function()? packageInfo,
    bool? android,
    WebDavSyncConfig? syncConfig,
  })  : _manifestClient = manifestClient ?? UpdateManifestClient(),
        _downloader = downloader ?? UpdatePackageDownloader(),
        _installer = installer ?? const UpdateInstallLauncher(),
        _packageInfo = packageInfo ?? PackageInfo.fromPlatform,
        _syncConfig = syncConfig,
        isAndroid = android ??
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadCurrentVersion());
  }

  final UpdateManifestClient _manifestClient;
  final UpdatePackageDownloader _downloader;
  final UpdateInstallLauncher _installer;
  final Future<PackageInfo> Function() _packageInfo;
  final WebDavSyncConfig? _syncConfig;
  UpdateSource? _source;
  final bool isAndroid;
  UpdateState _state = const UpdateState();
  UpdateState get state => _state;
  bool get configured => _syncConfig?.url.trim().isNotEmpty == true;
  bool _disposed = false;
  bool _busy = false;
  bool get busy => _busy;
  bool _foreground = true;
  bool _downloadActive = false;
  bool _installActive = false;
  int _generation = 0;

  Future<void> _loadCurrentVersion() async {
    try {
      final info = await _packageInfo().timeout(const Duration(seconds: 5));
      if (!_disposed) {
        _set(_state.phase,
            currentVersion: info.version,
            failure: _state.failure,
            currentVersionCode: int.tryParse(info.buildNumber) ?? 0);
      }
    } catch (_) {
      // A manual check will surface a version lookup failure explicitly.
    }
  }

  void _set(UpdatePhase phase,
      {AppUpdate? update,
      UpdateArtifact? artifact,
      int? receivedBytes,
      String? packagePath,
      UpdateFailure? failure,
      String? currentVersion,
      int? currentVersionCode,
      bool clearPackage = false,
      bool clearRelease = false}) {
    if (_disposed) return;
    _state = UpdateState(
        phase: phase,
        update: clearRelease ? null : update ?? _state.update,
        artifact: clearRelease ? null : artifact ?? _state.artifact,
        receivedBytes: receivedBytes ?? _state.receivedBytes,
        packagePath: clearRelease || clearPackage
            ? null
            : packagePath ?? _state.packagePath,
        failure: failure,
        currentVersion: currentVersion ?? _state.currentVersion,
        currentVersionCode: currentVersionCode ?? _state.currentVersionCode);
    notifyListeners();
  }

  Future<void> check() async {
    if (_busy || _disposed) return;
    if (!isAndroid) {
      _set(UpdatePhase.failed,
          failure:
              const UpdateFailure('unsupportedPlatform', '此平台暂未配置应用更新渠道。'));
      return;
    }
    if (!configured) {
      _set(UpdatePhase.unconfigured);
      return;
    }
    _busy = true;
    final generation = ++_generation;
    _set(UpdatePhase.checking, clearRelease: true, receivedBytes: 0);
    try {
      final source = UpdateSource.fromSync(_syncConfig!);
      _source = source;
      final device = await _installer.deviceInfo();
      if (_disposed || generation != _generation) return;
      final release =
          await _manifestClient.fetch(source.manifestUri, source: source);
      if (_disposed || generation != _generation) return;
      if (release.appId != device.packageName || release.channel != 'stable') {
        throw const UpdateFailure('packageInvalid', '更新包与当前应用不匹配。');
      }
      if (release.versionCode <= device.versionCode) {
        _set(UpdatePhase.upToDate, currentVersionCode: device.versionCode);
        return;
      }
      final candidates = release.artifacts.where((a) =>
          a.platform == 'android' &&
          a.variant == 'tv' &&
          a.minSdk <= device.sdkInt);
      if (candidates.length != 1 ||
          !device.abis
              .any((abi) => abi == 'armeabi-v7a' || abi == 'arm64-v8a')) {
        throw const UpdateFailure('unsupportedPlatform', '新版本不支持当前设备。');
      }
      source.validate(candidates.single.url);
      _set(UpdatePhase.available,
          update: release,
          artifact: candidates.single,
          currentVersionCode: device.versionCode);
    } catch (error) {
      if (!_disposed && generation == _generation) {
        _fail(error, 'checkFailed', '检查更新失败，请重试。');
      }
    } finally {
      if (generation == _generation) {
        _busy = false;
        if (!_disposed) notifyListeners();
      }
    }
  }

  Future<void> download() async {
    final artifact = _state.artifact;
    if (_busy || _disposed || !_foreground || artifact == null || !isAndroid) {
      return;
    }
    _busy = true;
    _downloadActive = true;
    final generation = ++_generation;
    _set(UpdatePhase.downloading, receivedBytes: 0);
    try {
      final path = await _downloader.download(artifact, source: _source,
          onProgress: (bytes) {
        if (generation == _generation) {
          _set(UpdatePhase.downloading, receivedBytes: bytes);
        }
      }, onVerifying: () {
        if (generation == _generation) _set(UpdatePhase.verifying);
      });
      if (!_disposed && generation == _generation) {
        _set(UpdatePhase.readyToInstall, packagePath: path);
      }
    } catch (error) {
      if (!_disposed && generation == _generation) {
        _fail(error, 'downloadFailed', '更新下载失败，请重试。');
      }
    } finally {
      _downloadActive = false;
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  void cancel() {
    if (!_downloadActive || _disposed) return;
    ++_generation;
    _downloader.cancel();
    _set(UpdatePhase.available, receivedBytes: 0);
    // The downloader keeps ownership until file and network cleanup finishes.
  }

  Future<void> install() async {
    final release = _state.update;
    final artifact = _state.artifact;
    final path = _state.packagePath;
    if (_busy ||
        _disposed ||
        !_foreground ||
        !isAndroid ||
        release == null ||
        artifact == null ||
        path == null) {
      return;
    }
    _busy = true;
    _installActive = true;
    notifyListeners();
    try {
      if (!await _installer.canInstallUpdates()) {
        throw const UpdateFailure(
            'installPermissionRequired', '请先允许 Starflow 安装应用。');
      }
      if (_disposed || !_foreground) return;
      final launched = await _installer.installApk(
          path: path,
          sha256: artifact.sha256,
          versionCode: release.versionCode,
          certificateSha256: artifact.certificateSha256);
      if (!launched) {
        throw const UpdateFailure('installerUnavailable', '无法打开系统安装器。');
      }
      _set(_foreground ? UpdatePhase.readyToInstall : UpdatePhase.installing);
    } catch (error) {
      _fail(error, 'installFailed', '无法安装更新，请重试。');
    } finally {
      _busy = false;
      _installActive = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> openInstallPermissionSettings() async {
    if (_busy || _disposed || !isAndroid) return;
    try {
      if (!await _installer.openInstallPermissionSettings()) {
        throw const UpdateFailure(
            'permissionSettingsUnavailable', '请在系统设置中允许安装未知来源应用。');
      }
    } catch (error) {
      _fail(error, 'permissionSettingsUnavailable', '无法打开系统安装权限设置。');
    }
  }

  void _fail(Object error, String code, String message) {
    final failure = error is PlatformException
        ? UpdateFailure(
            error.code,
            switch (error.code) {
              'installPermissionRequired' ||
              'install_permission_required' =>
                '请先允许 Starflow 安装应用。',
              'not_foreground' => '请回到 Starflow 后再次安装。',
              'hash_mismatch' || 'invalid_apk' => '安装包校验失败，请重新下载。',
              'file_unavailable' || 'invalid_path' => '安装包已不可用，请重新下载。',
              'signature_mismatch' ||
              'package_mismatch' =>
                '更新包签名或包名不匹配，已拒绝安装。',
              'not_newer' || 'version_mismatch' => '安装包版本不匹配，请重新检查更新。',
              'update_storage_full' => '安装验证副本数量已达上限，请稍后重试。',
              'installer_unavailable' => '设备无法打开系统安装器。',
              _ => message,
            })
        : error is UpdateFailure
            ? _localizedFailure(error)
            : UpdateFailure(code, message);
    appLogWarning('app.update', 'Update action failed',
        fields: {'code': failure.code});
    _set(UpdatePhase.failed,
        failure: failure,
        clearPackage: const {
          'hash_mismatch',
          'invalid_apk',
          'file_unavailable',
          'invalid_path',
        }.contains(failure.code));
  }

  UpdateFailure _localizedFailure(UpdateFailure error) {
    final message = switch (error.code) {
      'invalid_manifest' || 'manifest_too_large' => '更新清单无效或不受支持。',
      'update_timeout' || 'timeout' => '更新请求超时，请重试。',
      'update_failed' ||
      'http_error' ||
      'http' ||
      'download' =>
        '更新服务请求失败，请重试。',
      'checksum' => '安装包校验失败，请重新下载。',
      'length' ||
      'overflow' ||
      'encoding' ||
      'artifact' =>
        '安装包不完整或与清单不符，请重新下载。',
      'storage' => '无法保存安装包，请检查剩余空间。',
      'cancelled' || 'background' => '下载已取消，可重新下载。',
      'invalid_redirect' ||
      'invalid_url' ||
      'redirect' ||
      'url' =>
        '更新下载地址未通过安全检查。',
      _ => error.message,
    };
    return UpdateFailure(error.code, message);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) cancel();
    if (_foreground &&
        !_installActive &&
        _state.phase == UpdatePhase.installing) {
      _set(UpdatePhase.readyToInstall);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    _manifestClient.close();
    unawaited(_downloader.dispose());
    super.dispose();
  }
}
