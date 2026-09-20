import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

const _embeddedPath =
    'assets/flutter_assets/assets/bootstrap/embedded_settings.json';

Future<void> main(List<String> args) async {
  try {
    final root = p.dirname(p.dirname(Platform.script.toFilePath()));
    final policy = jsonDecode(
        await File(p.join(root, 'config/android_release.json'))
            .readAsString()) as Map;
    if (args.length == 1 && args.single == '--preflight') {
      final flutter = await run(Platform.isWindows ? 'flutter.bat' : 'flutter',
          ['--version', '--machine']);
      final version = jsonDecode(flutter) as Map;
      if (version['frameworkVersion'] != policy['flutterVersion'] ||
          version['engineRevision'] != policy['engineRevision']) {
        throw StateError(
            'TV release requires Flutter ${policy['flutterVersion']} / engine ${policy['engineRevision']}. Use the pinned SDK; do not raise minSdk.');
      }
      final signing = File(p.join(root, 'android/key.properties'));
      if (!await signing.exists()) {
        throw StateError(
            'Configure android/key.properties with the existing release signing identity before building.');
      }
      stdout.writeln(
          'TV release SDK and signing configuration preflight passed.');
      return;
    }
    if (args.length < 2 || args.length > 3) {
      throw ArgumentError(
          'Usage: dart tool/verify_tv_release.dart <apk> <expected-version> [settings.json], or --preflight');
    }
    final apk = File(args[0]);
    final archive = ZipDecoder().decodeBytes(await apk.readAsBytes());
    final names = archive.files.map((f) => f.name).toSet();
    final abiNames = names
        .where((n) => n.startsWith('lib/') && n.endsWith('.so'))
        .map((n) => n.split('/')[1])
        .toSet();
    final expectedAbis = (policy['abis'] as List).cast<String>().toSet();
    if (abiNames.length != expectedAbis.length ||
        !abiNames.containsAll(expectedAbis)) {
      throw StateError('Unexpected APK ABIs: $abiNames');
    }
    for (final abi in expectedAbis) {
      for (final library in ['libflutter.so', 'libapp.so']) {
        if (!names.contains('lib/$abi/$library')) {
          throw StateError('APK is missing $abi/$library.');
        }
      }
    }
    final embedded = archive.findFile(_embeddedPath);
    if (args.length == 2 && embedded != null) {
      throw StateError(
          'Normal APK contains embedded settings. Refusing delivery.');
    }
    if (args.length == 3) {
      if (embedded == null) {
        throw StateError('Configuration APK is missing embedded settings.');
      }
      final expected = await File(args[2]).readAsBytes();
      final actual = embedded.content;
      if (actual.length != expected.length ||
          Iterable<int>.generate(expected.length)
              .any((i) => expected[i] != actual[i])) {
        throw StateError('Embedded settings differ from the supplied file.');
      }
    }
    final sdk = androidSdk(root);
    final buildTools = newestDirectory(p.join(sdk, 'build-tools'));
    final badging = await run(
        p.join(buildTools, Platform.isWindows ? 'aapt.exe' : 'aapt'),
        ['dump', 'badging', apk.absolute.path]);
    if (!badging.contains("versionName='${args[1]}'") ||
        !badging.contains("sdkVersion:'${policy['minSdk']}'") ||
        !badging.contains("name='com.example.starflow'")) {
      throw StateError(
          'APK package, internal version, or minSdk differs from release policy.');
    }
    final signature = await run(
        p.join(buildTools, Platform.isWindows ? 'apksigner.bat' : 'apksigner'),
        [
          'verify',
          '--min-sdk-version',
          '${policy['minSdk']}',
          '--print-certs',
          apk.absolute.path
        ]);
    final certificates = RegExp(r'certificate SHA-256 digest: ([a-fA-F0-9]+)')
        .allMatches(signature)
        .map((m) => m[1]!.toLowerCase())
        .toList();
    if (certificates.length != 1 ||
        certificates.single != policy['certificateSha256']) {
      throw StateError(
          'APK signing certificate differs from the pinned installed-app identity.');
    }
    final ndk = newestDirectory(p.join(sdk, 'ndk'));
    final prebuilt = newestDirectory(p.join(ndk, 'toolchains/llvm/prebuilt'));
    final readelf = p.join(prebuilt, 'bin',
        Platform.isWindows ? 'llvm-readelf.exe' : 'llvm-readelf');
    final temp = await Directory.systemTemp.createTemp('starflow-apk-verify-');
    try {
      for (final entry in archive.files
          .where((f) => f.name.startsWith('lib/') && f.name.endsWith('.so'))) {
        final file = File(p.join(temp.path, entry.name));
        await file.parent.create(recursive: true);
        await file.writeAsBytes(entry.content);
        await verifyNativeApi23(readelf, file.path, entry.name);
      }
    } finally {
      await temp.delete(recursive: true);
    }
    stdout.writeln(
        'Verified TV APK: version ${args[1]}, API 23 native libraries, both ARM ABIs, embedded settings and pinned signature. Device playback still requires device testing.');
  } catch (error) {
    stderr.writeln('Release verification failed: $error');
    exitCode = 1;
  }
}

Future<void> verifyNativeApi23(
    String readelf, String path, String label) async {
  final symbols = await run(readelf, ['--dyn-syms', '--wide', path]);
  final incompatible = symbols.split('\n').where((line) =>
      line.contains('GLOBAL') &&
      line.contains('UND') &&
      RegExp(r'@(?:LIBC|LIBM|LIBDL|LIBANDROID)_(?:N(?:_|\b)|[O-Z](?:_|\b))')
          .hasMatch(line));
  if (incompatible.isNotEmpty) {
    throw StateError(
        '$label requires newer Android symbols: ${incompatible.join(', ')}');
  }
  final notes = await run(readelf, ['--notes', path]);
  final ident = RegExp(
          r'Android\s+0x[0-9a-fA-F]+[^\n]*\n\s*description data: ([0-9a-fA-F]{2}) ([0-9a-fA-F]{2}) ([0-9a-fA-F]{2}) ([0-9a-fA-F]{2})')
      .firstMatch(notes);
  if (ident != null) {
    final api =
        List.generate(4, (i) => int.parse(ident[i + 1]!, radix: 16) << (8 * i))
            .reduce((a, b) => a | b);
    if (api > 23) {
      throw StateError('$label was built for Android API $api, above 23.');
    }
  }
}

String androidSdk(String root) {
  final env = Platform.environment['ANDROID_SDK_ROOT'] ??
      Platform.environment['ANDROID_HOME'];
  if (env != null && env.isNotEmpty) return env;
  final properties = File(p.join(root, 'android/local.properties'));
  if (properties.existsSync()) {
    final match = RegExp(r'^sdk.dir=(.+)$', multiLine: true)
        .firstMatch(properties.readAsStringSync());
    if (match != null) {
      return match[1]!.trim().replaceAll(r'\:', ':').replaceAll(r'\\', r'\');
    }
  }
  throw StateError(
      'Set ANDROID_SDK_ROOT or sdk.dir in android/local.properties.');
}

String newestDirectory(String root) {
  final directories = Directory(root).listSync().whereType<Directory>().toList()
    ..sort((a, b) => _versionCompare(p.basename(a.path), p.basename(b.path)));
  if (directories.isEmpty) {
    throw StateError('Required Android SDK tools missing in $root');
  }
  return directories.last.path;
}

int _versionCompare(String a, String b) {
  final aa = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
  final bb = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
  for (var i = 0; i < aa.length || i < bb.length; i++) {
    final comparison =
        (i < aa.length ? aa[i] : 0).compareTo(i < bb.length ? bb[i] : 0);
    if (comparison != 0) return comparison;
  }
  return a.compareTo(b);
}

Future<String> run(String executable, List<String> args) async {
  final result =
      await Process.run(executable, args, runInShell: Platform.isWindows);
  if (result.exitCode != 0) {
    throw StateError('$executable failed: ${result.stderr}');
  }
  return result.stdout.toString();
}
