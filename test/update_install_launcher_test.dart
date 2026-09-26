import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/update/data/update_install_launcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('starflow/update');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test('typed native device and installation transport', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'deviceInfo') {
        return {
          'sdkInt': 23,
          'abis': ['armeabi-v7a'],
          'versionCode': 100,
          'packageName': 'com.example.starflow'
        };
      }
      return true;
    });
    const launcher = UpdateInstallLauncher();
    expect((await launcher.deviceInfo()).versionCode, 100);
    expect(await launcher.canInstallUpdates(), isTrue);
    expect(await launcher.openInstallPermissionSettings(), isTrue);
    expect(
        await launcher.installApk(
            path: '/private/updates/a.apk',
            sha256: 'a' * 64,
            versionCode: 101,
            certificateSha256: 'b' * 64),
        isTrue);
    expect(calls.last.arguments, {
      'path': '/private/updates/a.apk',
      'sha256': 'a' * 64,
      'versionCode': 101,
      'certificateSha256': 'b' * 64,
    });
  });
}
