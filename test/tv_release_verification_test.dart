import 'dart:io';

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

  Future<void> fixture({String symbols = '', String notes = ''}) async {
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
