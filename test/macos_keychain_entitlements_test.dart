import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:starflow/features/settings/data/cloud_credential_store.dart';

Map<String, dynamic> readPlist(String path) {
  final result =
      Process.runSync('plutil', ['-convert', 'json', '-o', '-', path]);
  expect(result.exitCode, 0, reason: result.stderr.toString());
  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('secure storage selects the legacy macOS Keychain', () {
    expect(
      const MacOsOptions(useDataProtectionKeyChain: false)
          .toMap()['useDataProtectionKeyChain'],
      'false',
    );
  });

  test('macOS Runner uses sandboxed legacy Keychain without group entitlement',
      () {
    final objects =
        readPlist('macos/Runner.xcodeproj/project.pbxproj')['objects'] as Map;
    final runner = objects.values.singleWhere((dynamic object) =>
            object['isa'] == 'PBXNativeTarget' && object['name'] == 'Runner')
        as Map;
    final configurations = objects[runner['buildConfigurationList']]
        ['buildConfigurations'] as List;
    final names = <String>[];
    for (final id in configurations) {
      final configuration = objects[id] as Map;
      names.add(configuration['name'] as String);
      final settings = configuration['buildSettings'] as Map;
      final entitlements =
          readPlist('macos/${settings['CODE_SIGN_ENTITLEMENTS']}');
      expect(entitlements.containsKey('keychain-access-groups'), isFalse);
      expect(entitlements['com.apple.security.app-sandbox'], isTrue);
      expect(entitlements['com.apple.security.network.client'], isTrue);
    }
    expect(names, unorderedEquals(['Debug', 'Profile', 'Release']));
    final project = objects.values
        .singleWhere((dynamic object) => object['isa'] == 'PBXProject') as Map;
    for (final id in objects[project['buildConfigurationList']]
        ['buildConfigurations'] as List) {
      expect(objects[id]['buildSettings']['CODE_SIGN_IDENTITY'], '-');
    }
  }, skip: !Platform.isMacOS);

  test('legacy entitlement failure does not block new secure storage',
      () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final method =
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    messenger.setMockMethodCallHandler(method, (call) async {
      final arguments = Map<String, dynamic>.from(call.arguments as Map);
      final options = Map<String, dynamic>.from(arguments['options'] as Map);
      if (options['useDataProtectionKeyChain'] == 'true') {
        throw PlatformException(
          code: 'Unexpected security result code',
          message:
              'Code: -34018, Message: A required entitlement is not present',
          details: -34018,
        );
      }
      if (call.method == 'read') return null;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(method, null));

    expect(await SecureCloudCredentialStore().read(), isNull);
  }, skip: !Platform.isMacOS);
}
