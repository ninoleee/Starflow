import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> readPlist(String path) {
  final result = Process.runSync('plutil', ['-convert', 'json', '-o', '-', path]);
  expect(result.exitCode, 0, reason: result.stderr.toString());
  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
}

void main() {
  test('all iOS Runner configurations enable the app keychain group', () {
    final project = readPlist('ios/Runner.xcodeproj/project.pbxproj');
    final objects = project['objects'] as Map;
    final runner = objects.values.singleWhere((dynamic object) =>
        object['isa'] == 'PBXNativeTarget' && object['name'] == 'Runner') as Map;
    final configurations = objects[runner['buildConfigurationList']]
        ['buildConfigurations'] as List;
    final names = <String>[];
    for (final id in configurations) {
      final configuration = objects[id] as Map;
      names.add(configuration['name'] as String);
      final settings = configuration['buildSettings'] as Map;
      expect(settings['CODE_SIGN_ENTITLEMENTS'], 'Runner/Runner.entitlements');
      final entitlements = readPlist('ios/${settings['CODE_SIGN_ENTITLEMENTS']}');
      expect(entitlements['keychain-access-groups'],
          [r'$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)']);
    }
    expect(names, unorderedEquals(['Debug', 'Profile', 'Release']));
  }, skip: !Platform.isMacOS);
}
