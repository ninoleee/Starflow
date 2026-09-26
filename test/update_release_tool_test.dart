import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:starflow/features/update/data/update_manifest_client.dart';
import 'package:starflow/features/update/data/update_manifest_parser.dart';
import 'package:starflow/features/update/domain/app_update.dart';

import '../tool/generate_update_manifest.dart' as tool;

void main() {
  final root = Directory.current.path;
  const version = '1.9.7';
  const versionCode = 108010007;
  const name = 'starflow-tv-$version.apk';
  const url = 'https://updates.example.com/releases/$versionCode/$name';
  const tools = (
    aapt: 'fixture-aapt',
    apksigner: 'fixture-apksigner',
    readelf: 'fixture-readelf'
  );
  final certificate = (jsonDecode(
          File(p.join(root, 'config/android_release.json')).readAsStringSync())
      as Map)['certificateSha256'] as String;
  late Directory temp;
  late File apk;
  late File notes;
  late Directory stage;
  late String badging;
  late String signature;
  late List<(String, List<String>)> commands;

  Future<void> writeApk(
      {List<String> abis = const ['armeabi-v7a', 'arm64-v8a'],
      bool embedded = false}) async {
    final archive = Archive();
    for (final abi in abis) {
      for (final lib in ['libflutter.so', 'libapp.so']) {
        archive.addFile(ArchiveFile('lib/$abi/$lib', 4, [1, 2, 3, 4]));
      }
    }
    if (embedded) {
      archive.addFile(ArchiveFile(
          'assets/flutter_assets/assets/bootstrap/embedded_settings.json',
          2,
          utf8.encode('{}')));
    }
    await apk.writeAsBytes(ZipEncoder().encode(archive));
  }

  Future<String> runner(String executable, List<String> args) async {
    commands.add((executable, args));
    if (executable == tools.aapt) return badging;
    if (executable == tools.apksigner) return signature;
    expect(
        executable,
        p.join(root, '.fvm/flutter_sdk/bin',
            Platform.isWindows ? 'dart.bat' : 'dart'));
    expect(args.first, p.join(root, 'tool/verify_tv_release.dart'));
    expect(args.last, version);
    expect(args, hasLength(3)); // No settings argument and no preflight/build.
    return 'TV APK static checks passed';
  }

  Future<String> generate(
          {tool.CommandRunner? commandRunner,
          String artifactUrl = url,
          File? output}) =>
      tool.generateUpdateRelease(
          root: root,
          apk: apk,
          notes: notes,
          artifactUrl: artifactUrl,
          stageDirectory: output == null ? stage : null,
          output: output,
          publishedAt: DateTime.parse('2026-09-26T08:30:00+08:00'),
          runner: commandRunner ?? runner,
          tools: tools);

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('starflow-update-test-');
    apk = File(p.join(temp.path, name));
    notes = File(p.join(temp.path, 'notes.txt'));
    stage = Directory(p.join(temp.path, 'stage'));
    await notes.writeAsString('First fix\n\n  Second fix  \r\n');
    badging =
        "package: name='com.example.starflow' versionCode='108010007' versionName='$version'\nsdkVersion:'23'\n";
    signature = '''Verified using v1 scheme (JAR signing): true
Verified using v2 scheme (APK Signature Scheme v2): true
Signer #1 certificate SHA-256 digest: $certificate
''';
    commands = [];
    await writeApk();
  });
  tearDown(() async => temp.delete(recursive: true));

  test('generated plain JSON is accepted by the parser and client without keys',
      () async {
    final result = await generate();
    final wireBytes = await File(result).readAsBytes();
    final parsed = parseUpdateManifest(
        jsonDecode(utf8.decode(wireBytes)) as Map<String, dynamic>);
    final transport = MockClient((request) async {
      expect(request.url.toString(),
          'https://updates.example.com/releases/latest.json');
      return http.Response.bytes(wireBytes, 200,
          headers: {'content-type': 'application/json'});
    });
    final client = UpdateManifestClient(client: transport);
    try {
      final fetched = await client
          .fetch(Uri.parse('https://updates.example.com/releases/latest.json'));
      expect(fetched.version, parsed.version);
      expect(fetched.versionCode, parsed.versionCode);
      expect(fetched.releaseNotes, parsed.releaseNotes);
      expect(fetched.artifacts.single.sha256, await tool.apkSha256(apk));
    } finally {
      client.close();
      transport.close();
    }
  });

  test('shared parser rejects too many or too-long notes before publication',
      () async {
    for (final value in [List.filled(101, 'note').join('\n'), 'a' * 4097]) {
      await notes.writeAsString(value);
      await expectLater(generate(), throwsA(isA<UpdateFailure>()));
      expect(await File(p.join(stage.path, 'latest.json')).exists(), isFalse);
    }
  });

  test('accepts individual note/count limits but rejects oversized JSON',
      () async {
    await notes.writeAsString(List.filled(100, 'note').join('\n'));
    await generate(output: File(p.join(temp.path, 'hundred.json')));
    await notes.writeAsString('a' * 4096);
    await generate(output: File(p.join(temp.path, 'long.json')));
    await notes.writeAsString(List.filled(100, 'a' * 4096).join('\n'));
    await expectLater(generate(), throwsA(isA<UpdateFailure>()));
    expect(await File(p.join(stage.path, 'latest.json')).exists(), isFalse);
  });

  test('wire limit counts exact UTF-8 bytes including the output newline',
      () async {
    final path = await generate();
    final payload = (jsonDecode(await File(path).readAsString()) as Map)
        .cast<String, Object>();
    final notes = List<String>.filled(70, 'a' * 3600);
    payload['releaseNotes'] = notes;
    final remaining = tool.maxUpdateManifestBytes -
        utf8.encode(tool.encodeUpdateManifest(payload)).length;
    var left = remaining;
    for (var i = 0; i < notes.length && left > 0; i++) {
      final add = left > 496 ? 496 : left;
      notes[i] += 'a' * add;
      left -= add;
    }
    expect(left, 0);
    expect(utf8.encode(tool.encodeUpdateManifest(payload)).length,
        tool.maxUpdateManifestBytes);
    notes.last += 'x';
    expect(() => tool.encodeUpdateManifest(payload), throwsStateError);
    notes.last = '${notes.last.substring(0, notes.last.length - 1)}\u4e2d';
    expect(() => tool.encodeUpdateManifest(payload),
        throwsA(isA<UpdateFailure>()));
  });

  test('stages exact plain schema, verified APK metadata and digest', () async {
    final result = await generate();
    final manifest = File(result);
    final payload = jsonDecode(await manifest.readAsString()) as Map;
    expect(payload, isNot(contains('payload')));
    expect(payload, isNot(contains('signature')));
    expect(payload, {
      'schemaVersion': 1,
      'appId': 'com.example.starflow',
      'channel': 'stable',
      'version': version,
      'versionCode': 108010007,
      'publishedAt': '2026-09-26T00:30:00.000Z',
      'releaseNotes': ['First fix', 'Second fix'],
      'artifacts': [
        {
          'platform': 'android',
          'variant': 'tv',
          'fileName': name,
          'url': url,
          'size': await apk.length(),
          'sha256': sha256.convert(await apk.readAsBytes()).toString(),
          'minSdk': 23,
          'certificateSha256': certificate,
        }
      ],
    });
    expect(await File(p.join(stage.path, 'latest.json')).readAsString(),
        await manifest.readAsString());
    expect(await File(p.join(stage.path, '$versionCode', name)).readAsBytes(),
        await apk.readAsBytes());
    expect(commands.map((c) => c.$1), [
      tools.aapt,
      tools.apksigner,
      p.join(root, '.fvm/flutter_sdk/bin',
          Platform.isWindows ? 'dart.bat' : 'dart')
    ]);
    expect(
        await stage
            .list(recursive: true)
            .map((e) => p.relative(e.path, from: stage.path))
            .toList(),
        unorderedEquals([
          '$versionCode',
          '$versionCode/$name',
          '$versionCode/manifest.json',
          'latest.json'
        ]));
  });

  test(
      'refuses an existing immutable versionCode without changing latest or APK',
      () async {
    final result = await generate();
    final before = await File(result).readAsString();
    await notes.writeAsString('Changed notes');
    await expectLater(generate(), throwsStateError);
    expect(await File(result).readAsString(), before);
    expect(
        await File(p.join(stage.path, 'latest.json')).readAsString(), before);
    expect(await File(p.join(stage.path, '.publish.lock')).exists(), isFalse);
  });

  test(
      'repeated display version with a later year code gets a distinct immutable release',
      () async {
    final first = await generate();
    final firstManifest = await File(first).readAsString();
    final firstApk = await apk.readAsBytes();
    const nextYearCode = 120010007;
    const nextUrl = 'https://updates.example.com/releases/$nextYearCode/$name';
    badging = badging.replaceFirst(
        "versionCode='$versionCode'", "versionCode='$nextYearCode'");
    await notes.writeAsString('Next year release');
    final second = await generate(artifactUrl: nextUrl);
    expect(first, p.join(stage.path, '$versionCode', 'manifest.json'));
    expect(second, p.join(stage.path, '$nextYearCode', 'manifest.json'));
    expect(await File(first).readAsString(), firstManifest);
    expect(await File(p.join(stage.path, '$versionCode', name)).readAsBytes(),
        firstApk);
    expect(
        await File(p.join(stage.path, '$nextYearCode', name)).exists(), isTrue);
    final secondManifest = await File(second).readAsString();
    final payload = jsonDecode(secondManifest) as Map;
    expect(payload['version'], version);
    expect(payload['versionCode'], nextYearCode);
    expect(
        (payload['artifacts'] as List).single, containsPair('fileName', name));
    expect((payload['artifacts'] as List).single, containsPair('url', nextUrl));
    expect(await File(p.join(stage.path, 'latest.json')).readAsString(),
        secondManifest);
    await expectLater(generate(artifactUrl: nextUrl), throwsStateError);
    expect(await File(second).readAsString(), secondManifest);
  });

  test('manifest-only output is atomic and never overwritten', () async {
    final output = File(p.join(temp.path, 'out', 'manifest.json'));
    await generate(output: output);
    final before = await output.readAsString();
    await expectLater(generate(output: output), throwsStateError);
    expect(await output.readAsString(), before);
    expect(await output.parent.list().map((e) => p.basename(e.path)).toList(),
        ['manifest.json']);
  });

  test('existing publish lock fails closed and is not removed', () async {
    await stage.create();
    final lock = File(p.join(stage.path, '.publish.lock'));
    await lock.writeAsString('another publisher');
    await expectLater(generate(), throwsA(isA<FileSystemException>()));
    expect(await lock.readAsString(), 'another publisher');
    expect(commands, isEmpty);
  });

  test('latest stays on prior release until verification and version commit',
      () async {
    await stage.create();
    final latest = File(p.join(stage.path, 'latest.json'));
    await latest.writeAsString('prior release');
    await generate(commandRunner: (exe, args) async {
      expect(await latest.readAsString(), 'prior release');
      expect(await Directory(p.join(stage.path, '$versionCode')).exists(),
          isFalse);
      return runner(exe, args);
    });
    expect(
        await latest.readAsString(),
        await File(p.join(stage.path, '$versionCode', 'manifest.json'))
            .readAsString());
  });

  test(
      'failed latest promotion preserves committed release and refuses overwrite',
      () async {
    final obstruction = Directory(p.join(stage.path, 'latest.json'));
    await obstruction.create(recursive: true);
    final marker = File(p.join(obstruction.path, 'keep'));
    await marker.writeAsString('keep');
    await expectLater(generate(), throwsA(isA<FileSystemException>()));
    expect(await marker.readAsString(), 'keep');
    expect(
        await File(p.join(stage.path, '$versionCode', 'manifest.json'))
            .exists(),
        isTrue);
    expect(await File(p.join(stage.path, '$versionCode', name)).readAsBytes(),
        await apk.readAsBytes());
    expect(await File(p.join(stage.path, '.publish.lock')).exists(), isFalse);
    await expectLater(generate(), throwsStateError);
  });

  test('existing versionCode symlink cannot redirect or overwrite a release',
      () async {
    await stage.create();
    final other = Directory(p.join(temp.path, 'other'));
    await other.create();
    await Link(p.join(stage.path, '$versionCode')).create(other.path);
    await expectLater(generate(), throwsStateError);
    expect(await other.list().toList(), isEmpty);
    expect(await File(p.join(stage.path, 'latest.json')).exists(), isFalse);
  }, skip: Platform.isWindows);

  for (final badUrl in [
    'http://example.com/$versionCode/$name',
    'https://u:p@example.com/$versionCode/$name',
    'https://example.com/$versionCode/$name#fragment',
    'https://example.com/$versionCode/wrong.apk',
    'https://example.com/$name',
    'https://example.com/$version/$name',
    'https://example.com/120010007/$name',
    'https://example.com/0$versionCode/$name',
    '/$name'
  ]) {
    test('rejects artifact URL $badUrl', () async {
      await expectLater(generate(artifactUrl: badUrl), throwsFormatException);
      expect(await File(p.join(stage.path, 'latest.json')).exists(), isFalse);
    });
  }

  for (final badName in [
    'app-release.apk',
    'app-debug.apk',
    'starflow-tv-config-$version.apk',
    'starflow-tv-1.9.8.apk'
  ]) {
    test('rejects APK filename $badName', () async {
      apk = await apk.rename(p.join(temp.path, badName));
      await expectLater(generate(), throwsStateError);
    });
  }

  test('rejects embedded settings even if renamed to normal release', () async {
    await writeApk(embedded: true);
    await expectLater(generate(), throwsStateError);
    expect(commands, isEmpty);
  });

  for (final abis in [
    <String>['arm64-v8a'],
    ['armeabi-v7a', 'arm64-v8a', 'x86_64']
  ]) {
    test('rejects incorrect ABI set $abis', () async {
      await writeApk(abis: abis);
      await expectLater(generate(), throwsStateError);
      expect(commands, isEmpty);
    });
  }

  for (final kind in [
    'debug',
    'appId',
    'minSdk',
    'versionCode',
    'versionName',
    'duplicate'
  ]) {
    test('rejects invalid actual APK metadata: $kind', () async {
      badging = switch (kind) {
        'debug' => '${badging}application-debuggable\n',
        'appId' => badging.replaceFirst('com.example.starflow', 'other.app'),
        'minSdk' => badging.replaceFirst("sdkVersion:'23'", "sdkVersion:'24'"),
        'versionCode' => badging.replaceFirst('108010007', '-1'),
        'versionName' => badging.replaceFirst(version, '1.09.7'),
        _ => '$badging$badging',
      };
      await expectLater(generate(), throwsStateError);
    });
  }

  for (final kind in [
    'unsigned',
    'wrong certificate',
    'missing v1',
    'multiple signers'
  ]) {
    test('rejects APK signature: $kind', () async {
      signature = switch (kind) {
        'unsigned' => '',
        'wrong certificate' => signature.replaceFirst(certificate, 'a' * 64),
        'missing v1' =>
          signature.replaceFirst('(JAR signing): true', '(JAR signing): false'),
        _ => '${signature}Signer #2 certificate SHA-256 digest: $certificate\n',
      };
      await expectLater(generate(), throwsStateError);
    });
  }

  test(
      'external verification failure leaves prior latest untouched and cleans staging',
      () async {
    await stage.create();
    final latest = File(p.join(stage.path, 'latest.json'));
    await latest.writeAsString('previous release');
    await expectLater(generate(commandRunner: (exe, args) async {
      if (exe != tools.aapt && exe != tools.apksigner) {
        throw StateError('Native API verification failed');
      }
      return runner(exe, args);
    }), throwsStateError);
    expect(await latest.readAsString(), 'previous release');
    expect(await stage.list().map((e) => p.basename(e.path)).toList(),
        ['latest.json']);
  });

  test('detects APK mutation by external verification before publication',
      () async {
    await expectLater(generate(commandRunner: (exe, args) async {
      if (exe != tools.aapt && exe != tools.apksigner) {
        await File(args[1]).writeAsBytes([0], mode: FileMode.append);
      }
      return runner(exe, args);
    }), throwsStateError);
    expect(await File(p.join(stage.path, 'latest.json')).exists(), isFalse);
  });

  test('readback rejects changed APK and manifest', () async {
    final result = await generate();
    final manifest = File(result);
    final contents = await manifest.readAsString();
    final publishedApk = File(p.join(stage.path, '$versionCode', name));
    await publishedApk.writeAsBytes([0], mode: FileMode.append);
    await expectLater(
        tool.verifyReleaseReadback(manifest, publishedApk, contents),
        throwsStateError);
    await apk.copy(publishedApk.path);
    await manifest.writeAsString(
        jsonEncode({...jsonDecode(contents) as Map, 'versionCode': 1}));
    await expectLater(
        tool.verifyReleaseReadback(manifest, publishedApk, contents),
        throwsStateError);
  });

  test('rejects empty and over-limit APKs before running Android tools',
      () async {
    await apk.writeAsBytes([]);
    await expectLater(generate(), throwsStateError);
    final handle = await apk.open(mode: FileMode.write);
    await handle.truncate(tool.maxUpdateApkBytes + 1);
    await handle.close();
    await expectLater(generate(), throwsStateError);
    expect(commands, isEmpty);
  });

  test('notes, UTC time, and command-line options fail closed', () {
    expect(() => tool.parseReleaseNotes(' \n'), throwsFormatException);
    expect(() => tool.parsePublishedAt('2026-09-26T12:00:00'),
        throwsFormatException);
    expect(tool.parsePublishedAt('2026-09-26T12:00:00Z').isUtc, isTrue);
    final args = [
      '--apk',
      apk.path,
      '--notes',
      notes.path,
      '--artifact-url',
      url,
      '--stage-dir',
      stage.path
    ];
    expect(tool.parseUpdateReleaseArguments(args)['--stage-dir'], stage.path);
    for (final invalid in [
      <String>[],
      [...args, '--output', 'x'],
      [...args, '--host', 'example.com'],
      [...args, '--seed', 'x'],
      [...args, '--seed-format', 'raw'],
      [...args, '--unknown']
    ]) {
      expect(
          () => tool.parseUpdateReleaseArguments(invalid), throwsArgumentError);
    }
  });

  test(
      'shell wrapper reports local-only behavior and refuses upload/manifest mode',
      () async {
    final script = p.join(root, 'scripts/publish_update_release.sh');
    final help = await Process.run('bash', [script, '--help']);
    expect(help.exitCode, 0);
    expect(help.stdout, contains('no build, version bump, or upload'));
    expect(help.stdout, contains('VERSION_CODE/starflow-tv-VERSION.apk'));
    expect(tool.updateReleaseUsage,
        contains('VERSION_CODE/starflow-tv-VERSION.apk'));
    expect((await Process.run('bash', [script, '--output', 'x'])).exitCode, 2);
    expect(
        (await Process.run('bash', [script, '--host', 'example.com'])).exitCode,
        2);
  }, skip: Platform.isWindows);

  test('TV build presets no longer require or forward manifest keys', () {
    for (final script in [
      'scripts/build_tv_apk.ps1',
      'scripts/build_tv_apk_to_icloud.sh',
    ]) {
      final contents = File(p.join(root, script)).readAsStringSync();
      expect(contents, isNot(contains('STARFLOW_UPDATE_PUBLIC_KEY')));
      expect(contents, isNot(contains('validate_update_build_config')));
      expect(contents, contains('verify_tv_release.dart'));
      expect(contents, contains('STARFLOW_BUILD_DATE'));
    }
  });
}
