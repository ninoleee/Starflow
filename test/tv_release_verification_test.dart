import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/verify_tv_release.dart' as verifier;

void main() {
  late Directory temp;
  late File readelf;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('starflow-release-test-');
    readelf = File('${temp.path}/readelf');
  });
  tearDown(() async => temp.delete(recursive: true));

  Future<void> fixture(
      {String symbols = '0: 0 0 NOTYPE LOCAL DEFAULT UND',
      String notes = ''}) async {
    await readelf.writeAsString('''#!/bin/sh
case "\$1" in
  --dyn-syms) cat <<'SYMBOLS'
$symbols
SYMBOLS
;;
  --notes) cat <<'NOTES'
$notes
NOTES
;;
  *) exit 2 ;;
esac
''');
    await Process.run('chmod', ['+x', readelf.path]);
  }

  test('rejects strong Android N dynamic symbol imports', () async {
    await fixture(
        symbols: '93: 0 0 FUNC GLOBAL DEFAULT UND __fwrite_chk@LIBC_N');
    await expectLater(
        verifier.verifyNativeApi23(readelf.path, 'test.so', 'test'),
        throwsStateError);
  }, skip: Platform.isWindows);

  test('does not reject optional weak imports on an older API', () async {
    await fixture(
        symbols: '93: 0 0 FUNC WEAK DEFAULT UND getifaddrs@LIBC_N',
        notes:
            '  Android 0x00000084 NT_ANDROID_TYPE_IDENT\n   description data: 16 00 00 00 72 32');
    await verifier.verifyNativeApi23(readelf.path, 'test.so', 'test');
  }, skip: Platform.isWindows);

  test('rejects API 24 build notes even without versioned imports', () async {
    await fixture(
        notes:
            '  Android 0x00000084 NT_ANDROID_TYPE_IDENT\n   description data: 18 00 00 00 72 32');
    await expectLater(
        verifier.verifyNativeApi23(readelf.path, 'test.so', 'test'),
        throwsStateError);
  }, skip: Platform.isWindows);

  for (final suffix in ['O', 'N_MR1', '24', '29', '30', 'PRIVATE']) {
    test('rejects strong Android $suffix imports', () async {
      await fixture(
          symbols: '93: 0 0 FUNC GLOBAL DEFAULT UND new_api@LIBC_$suffix');
      await expectLater(
          verifier.verifyNativeApi23(readelf.path, 'test.so', 'test'),
          throwsStateError);
    }, skip: Platform.isWindows);
  }

  test('allows API 23 imports and defined newer API exports', () async {
    await fixture(symbols: '''0: 0 0 NOTYPE LOCAL DEFAULT UND
93: 0 0 FUNC GLOBAL DEFAULT UND old_api@LIBC_M
94: 0 0 FUNC GLOBAL DEFAULT 12 new_api@LIBC_N''');
    await verifier.verifyNativeApi23(readelf.path, 'test.so', 'test');
  }, skip: Platform.isWindows);

  test('rejects an empty dynamic symbol table', () async {
    await fixture(symbols: '');
    await expectLater(
        verifier.verifyNativeApi23(readelf.path, 'test.so', 'test'),
        throwsStateError);
  }, skip: Platform.isWindows);

  test('rejects an unreadable Android build note', () async {
    await fixture(notes: 'Android 0x00000084 NT_ANDROID_TYPE_IDENT\ninvalid');
    await expectLater(
        verifier.verifyNativeApi23(readelf.path, 'test.so', 'test'),
        throwsStateError);
  }, skip: Platform.isWindows);

  test('requires matching SDK version, framework, engine and FVM pin', () {
    final policy =
        jsonDecode(File('config/android_release.json').readAsStringSync())
            as Map;
    final version = {
      'frameworkVersion': policy['flutterVersion'],
      'frameworkRevision': policy['frameworkRevision'],
      'engineRevision': policy['engineRevision']
    };
    final fvm = jsonDecode(File('.fvmrc').readAsStringSync()) as Map;
    verifier.verifySdkVersion(version, policy, fvm);
    for (final key in version.keys) {
      expect(
          () => verifier
              .verifySdkVersion({...version, key: 'wrong'}, policy, fvm),
          throwsStateError);
    }
    expect(
        () => verifier.verifySdkVersion(version, policy, {'flutter': '3.41.6'}),
        throwsStateError);
  });

  test('parses Java signing properties without stripping password characters',
      () {
    final values = verifier.parseSigningProperties(r'''
# comment
! comment
storeFile = C\:\\keys\\old\ key.jks
storePassword = abc\=def\:ghi\u0021
keyAlias: old\
  Key
keyPassword password with trailing space\u0020
''');
    expect(values['storeFile'], r'C:\keys\old key.jks');
    expect(values['storePassword'], 'abc=def:ghi!');
    expect(values['keyAlias'], 'oldKey');
    expect(values['keyPassword'], 'password with trailing space ');
  });

  test('missing and incomplete signing config fails before keytool', () async {
    await expectLater(verifier.verifySigningConfiguration(temp.path, 'unused'),
        throwsStateError);
    final signing = File('${temp.path}/android/key.properties');
    await signing.parent.create();
    await signing
        .writeAsString('storeFile=missing.jks\nstorePassword=synthetic-secret');
    await expectLater(
        verifier.verifySigningConfiguration(temp.path, 'unused'),
        throwsA(predicate((e) =>
            e.toString().contains('keyAlias') &&
            !e.toString().contains('synthetic-secret'))));
  });

  const abis = {'armeabi-v7a', 'arm64-v8a'};
  const embeddedPath =
      'assets/flutter_assets/assets/bootstrap/embedded_settings.json';
  Archive apkFixture({List<int>? settings, String? omit}) {
    final archive = Archive();
    for (final abi in abis) {
      for (final library in ['libflutter.so', 'libapp.so']) {
        final name = 'lib/$abi/$library';
        if (name != omit) archive.add(ArchiveFile(name, 1, [1]));
      }
    }
    if (settings != null) {
      archive.add(ArchiveFile(embeddedPath, settings.length, settings));
    }
    return archive;
  }

  test('normal APK accepts both ARM ABIs and rejects embedded settings', () {
    verifier.verifyArchive(apkFixture(), abis, null);
    expect(() => verifier.verifyArchive(apkFixture(settings: [1]), abis, null),
        throwsStateError);
  });

  test('rejects duplicate ZIP directory entries before archive folding', () {
    final archive = Archive()
      ..add(ArchiveFile('first', 1, [1]))
      ..add(ArchiveFile('other', 1, [2]));
    final bytes = ZipEncoder().encode(archive);
    final from = ascii.encode('other');
    final to = ascii.encode('first');
    for (var i = 0; i <= bytes.length - from.length; i++) {
      if (List.generate(from.length, (j) => bytes[i + j] == from[j])
          .every((matches) => matches)) {
        bytes.setRange(i, i + to.length, to);
      }
    }
    expect(() => verifier.decodeApk(bytes), throwsStateError);
  });

  test('config APK requires exact settings bytes', () {
    verifier.verifyArchive(apkFixture(settings: [1, 2]), abis, [1, 2]);
    for (final settings in [
      null,
      <int>[],
      [1],
      [1, 3]
    ]) {
      expect(
          () => verifier
              .verifyArchive(apkFixture(settings: settings), abis, [1, 2]),
          throwsStateError);
    }
  });

  test('rejects missing engine and extra x86_64 ABI', () {
    expect(
        () => verifier.verifyArchive(
            apkFixture(omit: 'lib/arm64-v8a/libflutter.so'), abis, null),
        throwsStateError);
    final archive = apkFixture()
      ..add(ArchiveFile('lib/x86_64/libflutter.so', 1, [1]));
    expect(() => verifier.verifyArchive(archive, abis, null), throwsStateError);
  });

  for (final path in [
    'lib/arm64-v8a/../../../escape.so',
    '/escape.so',
    r'lib\arm64-v8a\escape.so',
    'lib/arm64-v8a/nested/escape.so'
  ]) {
    test('rejects unsafe APK entry $path', () {
      final archive = apkFixture()..add(ArchiveFile(path, 1, [1]));
      expect(
          () => verifier.verifyArchive(archive, abis, null), throwsStateError);
    });
  }

  test('validates package fields on the package line only', () {
    const good =
        "package: name='com.example.starflow' versionCode='108010174' versionName='1.9.174'\nsdkVersion:'23'\n";
    verifier.verifyBadging(good, '1.9.174', 23);
    verifier.verifyBadging(good, '1.9.174', 23, expectedVersionCode: 108010174);
    expect(
        () => verifier.verifyBadging(good, '1.9.174', 23,
            expectedVersionCode: 108010175),
        throwsStateError);
    expect(() => verifier.verifyBadging(good, '1.9.175', 23), throwsStateError);
    expect(() => verifier.verifyBadging(good, '1.9.174', 24), throwsStateError);
    final spoofed =
        "${good.replaceFirst('com.example.starflow', 'other.app')}uses-permission: name='com.example.starflow'\n";
    expect(
        () => verifier.verifyBadging(spoofed, '1.9.174', 23), throwsStateError);
  });

  test('requires pinned certificate, single signer and v1 plus v2', () {
    const signature = '''Verified using v1 scheme (JAR signing): true
Verified using v2 scheme (APK Signature Scheme v2): true
Signer #1 certificate SHA-256 digest: abcd
''';
    verifier.verifySignature(signature, 'abcd');
    expect(() => verifier.verifySignature(signature, '1234'), throwsStateError);
    expect(
        () => verifier.verifySignature(
            signature.replaceFirst('true', 'false'), 'abcd'),
        throwsStateError);
    expect(
        () => verifier.verifySignature(
            signature.replaceFirst('v2): true', 'v2): false'), 'abcd'),
        throwsStateError);
    expect(
        () => verifier.verifySignature(
            '${signature}Signer #2 certificate SHA-256 digest: abcd\n', 'abcd'),
        throwsStateError);
  });

  test('SkipBuild rejection precedes every release mutation', () {
    final script = File('scripts/build_tv_apk.ps1').readAsStringSync();
    expect(script.indexOf('if (\$SkipBuild)'),
        lessThan(script.indexOf('function Update-PubspecVersion')));
    expect(script, contains('SkipBuild cannot produce a release artifact'));
    expect(
        script.indexOf('& \$dart @preflightArgs'),
        lessThan(
            script.indexOf('\$version = Update-PubspecVersion \$pubspecPath')));
  });

  test('invalid settings preflight does not print JSON credentials', () async {
    final settings = File('${temp.path}/invalid.json')
      ..writeAsStringSync('{"password":"synthetic-secret",invalid}');
    final result = await Process.run(
        'dart', ['tool/verify_tv_release.dart', '--preflight', settings.path]);
    expect(result.exitCode, isNot(0));
    expect(
        result.stderr, contains('Settings JSON must contain a valid object'));
    expect('${result.stdout}${result.stderr}',
        isNot(contains('synthetic-secret')));
  });

  test(
      'bash preflight failure cannot mutate version, settings or deliver old APK',
      () async {
    final root = Directory('${temp.path}/project')..createSync();
    final script = File('${root.path}/scripts/build_tv_apk_to_icloud.sh');
    script.parent.createSync();
    script.writeAsStringSync(
        File('scripts/build_tv_apk_to_icloud.sh').readAsStringSync());
    final pubspec = File('${root.path}/pubspec.yaml')
      ..writeAsStringSync('version: 1.9.174\n');
    final embedded =
        File('${root.path}/assets/bootstrap/embedded_settings.json');
    embedded.parent.createSync(recursive: true);
    embedded.writeAsStringSync('{"keep":true}');
    final sdk = Directory('${temp.path}/fake-sdk/bin')
      ..createSync(recursive: true);
    final dart = File('${sdk.path}/dart')
      ..writeAsStringSync('#!/bin/sh\nexit 9\n');
    await Process.run('chmod', ['+x', dart.path]);
    final result = await Process.run('bash', [
      script.path
    ], environment: {
      'STARFLOW_FLUTTER_SDK': sdk.parent.path,
      'ICLOUD_INSTALLER_DIR': '${temp.path}/delivery'
    });
    expect(result.exitCode, 9);
    expect(pubspec.readAsStringSync(), 'version: 1.9.174\n');
    expect(embedded.readAsStringSync(), '{"keep":true}');
    expect(Directory('${temp.path}/delivery').existsSync(), isFalse);
  }, skip: Platform.isWindows);

  for (final config in [false, true]) {
    test(
        'bash failed ${config ? 'config' : 'normal'} build restores local settings',
        () async {
      final root = Directory('${temp.path}/project')..createSync();
      final script = File('${root.path}/scripts/build_tv_apk_to_icloud.sh');
      script.parent.createSync();
      script.writeAsStringSync(
          File('scripts/build_tv_apk_to_icloud.sh').readAsStringSync());
      File('${root.path}/pubspec.yaml').writeAsStringSync('version: 1.9.174\n');
      final embedded =
          File('${root.path}/assets/bootstrap/embedded_settings.json');
      embedded.parent.createSync(recursive: true);
      embedded.writeAsStringSync('{"keep":true}');
      final sdk = Directory('${temp.path}/fake-sdk/bin')
        ..createSync(recursive: true);
      final dart = File('${sdk.path}/dart')..writeAsStringSync('''#!/bin/sh
case "\$1" in
  */verify_tv_release.dart) exit 0 ;;
  */release_version.dart) echo 1.9.175 ;;
  *) exit 99 ;;
esac
''');
      final flutter = File('${sdk.path}/flutter')
        ..writeAsStringSync('''#!/bin/sh
if [ "$config" = true ]; then
  test -f assets/bootstrap/embedded_settings.json || exit 98
else
  test ! -f assets/bootstrap/embedded_settings.json || exit 98
fi
exit 7
''');
      await Process.run('chmod', ['+x', dart.path, flutter.path]);
      // Supplying the bootstrap itself must not delete the input before copying.
      final result = await Process.run('bash', [
        script.path,
        if (config) embedded.path
      ], environment: {
        'STARFLOW_FLUTTER_SDK': sdk.parent.path,
        'ICLOUD_INSTALLER_DIR': '${temp.path}/delivery'
      });
      expect(result.exitCode, 7, reason: '${result.stdout}\n${result.stderr}');
      expect(embedded.readAsStringSync(), '{"keep":true}');
      expect(Directory('${temp.path}/delivery').existsSync(), isFalse);
    }, skip: Platform.isWindows);
  }

  test('iOS verification refuses a non-app directory', () async {
    final result = await Process.run(
        'bash', ['scripts/verify_ios_device_frameworks.sh', temp.path]);
    expect(result.exitCode, isNot(0));
  }, skip: !Platform.isMacOS);

  test('iOS verification refuses a bundle without required frameworks',
      () async {
    final app = Directory('${temp.path}/Test.app')..createSync();
    await File('${app.path}/Info.plist')
        .writeAsString('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleExecutable</key><string>Test</string></dict></plist>''');
    await File('${app.path}/Test').writeAsString('synthetic');
    final result = await Process.run(
        'bash', ['scripts/verify_ios_device_frameworks.sh', app.path]);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('Frameworks directory is missing'));
  }, skip: !Platform.isMacOS);
}
