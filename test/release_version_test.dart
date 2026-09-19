import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../tool/release_version.dart';

void main() {
  final policy =
      jsonDecode(File('config/release_version.json').readAsStringSync())
          as Map<String, dynamic>;
  test('monthly version stepping and monotonic Android migration', () {
    final current = ReleaseVersion.parse('1.9.164+42');
    expect(current.next(DateTime(2026, 9)).toString(), '1.9.165');
    expect(current.next(DateTime(2026, 10)).toString(), '1.10.0');
    expect(current.androidCode(2026, policy), greaterThan(26101064));
    expect(ReleaseVersion(1, 10, 0).androidCode(2026, policy),
        greaterThan(ReleaseVersion(99, 9, 9999).androidCode(2026, policy)));
    expect(ReleaseVersion(1, 1, 0).androidCode(2027, policy),
        greaterThan(ReleaseVersion(99, 12, 9999).androidCode(2026, policy)));
    expect(() => ReleaseVersion(1, 9, 10000).androidCode(2026, policy),
        throwsRangeError);
    expect(() => ReleaseVersion.parse('1.13.0'), throwsFormatException);
    expect(() => current.androidCode(2300, policy), throwsRangeError);
  });
  test('CLI fixed batch version preserves CRLF and rejects invalid versions',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('starflow-version-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/pubspec.yaml');
    const input = 'name: fixture\r\nversion: 1.9.164+2\r\n\r\nenvironment:\r\n';
    await file.writeAsString(input);
    final dart = '${File(Platform.resolvedExecutable).parent.path}/dart';
    final executable = File(dart).existsSync() ? dart : 'dart';
    final result = await Process.run(
        executable, ['tool/release_version.dart', file.path],
        environment: {'STARFLOW_RELEASE_VERSION': '1.10.0'});
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, '1.10.0\n');
    final updated = await file.readAsString();
    expect(updated, input.replaceFirst('1.9.164+2', '1.10.0'));
    final invalid = await Process.run(
        executable, ['tool/release_version.dart', file.path],
        environment: {'STARFLOW_RELEASE_VERSION': '1.13.0'});
    expect(invalid.exitCode, 1);
    expect(await file.readAsString(), updated);
  });
}
