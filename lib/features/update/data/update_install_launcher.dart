import 'package:flutter/services.dart';

class UpdateDeviceInfo {
  const UpdateDeviceInfo(
      {required this.sdkInt,
      required this.abis,
      required this.versionCode,
      required this.packageName});
  final int sdkInt;
  final List<String> abis;
  final int versionCode;
  final String packageName;
}

class UpdateInstallLauncher {
  const UpdateInstallLauncher();
  static const _channel = MethodChannel('starflow/update');

  Future<UpdateDeviceInfo> deviceInfo() async {
    final info = await _channel.invokeMapMethod<String, dynamic>('deviceInfo');
    if (info == null) throw PlatformException(code: 'device_info');
    return UpdateDeviceInfo(
      sdkInt: info['sdkInt'] as int,
      abis: (info['abis'] as List).cast<String>(),
      versionCode: info['versionCode'] as int,
      packageName: info['packageName'] as String,
    );
  }

  Future<bool> canInstallUpdates() async =>
      await _channel.invokeMethod<bool>('canInstallUpdates') ?? false;

  Future<bool> openInstallPermissionSettings() async =>
      await _channel.invokeMethod<bool>('openInstallPermissionSettings') ??
      false;

  Future<bool> installApk(
          {required String path,
          required String sha256,
          required int versionCode,
          required String certificateSha256}) async =>
      await _channel.invokeMethod<bool>('installApk', {
        'path': path,
        'sha256': sha256,
        'versionCode': versionCode,
        'certificateSha256': certificateSha256,
      }) ??
      false;
}
