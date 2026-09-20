import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'release_version.dart';

const _embeddedPath =
    'assets/flutter_assets/assets/bootstrap/embedded_settings.json';

Future<void> main(List<String> args) async {
  try {
    final root = p.dirname(p.dirname(Platform.script.toFilePath()));
    final policy = jsonDecode(
        await File(p.join(root, 'config/android_release.json'))
            .readAsString()) as Map;
    if (args.isNotEmpty && args.first == '--preflight' && args.length <= 2) {
      if (args.length == 2) {
        try {
          if (jsonDecode(await File(args[1]).readAsString()) is! Map) {
            throw const FormatException();
          }
        } on FormatException {
          // A JSON parse exception includes source text, which may contain secrets.
          throw const FormatException(
              'Settings JSON must contain a valid object.');
        }
      }
      final flutter =
          await run(flutterExecutable(), ['--version', '--machine']);
      final version = jsonDecode(flutter) as Map;
      verifySdkVersion(version, policy,
          jsonDecode(await File(p.join(root, '.fvmrc')).readAsString()) as Map);
      await verifySigningConfiguration(
          root, policy['certificateSha256'] as String);
      final tools = releaseTools(root);
      await run(tools.aapt, ['version']);
      await run(tools.apksigner, ['version']);
      await run(tools.readelf, ['--version']);
      if (Platform.environment['STARFLOW_RELEASE_VERSION']?.isNotEmpty ==
          true) {
        throw StateError(
            'TV releases must use automatic monthly version stepping; unset STARFLOW_RELEASE_VERSION.');
      }
      stdout.writeln(
          'TV release SDK and signing configuration preflight passed.');
      return;
    }
    if (args.length < 2 || args.length > 3) {
      throw ArgumentError(
          'Usage: dart tool/verify_tv_release.dart <apk> <expected-version> [settings.json], or --preflight [settings.json]');
    }
    final apk = File(args[0]);
    final archive = decodeApk(await apk.readAsBytes());
    verifyArchive(archive, (policy['abis'] as List).cast<String>().toSet(),
        args.length == 3 ? await File(args[2]).readAsBytes() : null);
    final tools = releaseTools(root);
    final badging =
        await run(tools.aapt, ['dump', 'badging', apk.absolute.path]);
    final versionPolicy = jsonDecode(
        await File(p.join(root, 'config/release_version.json'))
            .readAsString()) as Map<String, dynamic>;
    verifyBadging(badging, args[1], policy['minSdk'] as int,
        expectedVersionCode: ReleaseVersion.parse(args[1])
            .androidCode(DateTime.now().year, versionPolicy));
    final signature = await run(tools.apksigner, [
      'verify',
      '--min-sdk-version',
      '${policy['minSdk']}',
      '--print-certs',
      '--verbose',
      apk.absolute.path
    ]);
    verifySignature(signature, policy['certificateSha256'] as String);
    final temp = await Directory.systemTemp.createTemp('starflow-apk-verify-');
    try {
      for (final entry in archive.files
          .where((f) => f.name.startsWith('lib/') && f.name.endsWith('.so'))) {
        final file = File(p.join(temp.path, entry.name));
        await file.parent.create(recursive: true);
        await file.writeAsBytes(entry.content);
        await verifyNativeApi23(tools.readelf, file.path, entry.name);
      }
    } finally {
      await temp.delete(recursive: true);
    }
    stdout.writeln(
        'TV APK static checks passed: version ${args[1]}, both ARM ABIs, embedded settings and pinned v1/v2 signature; no detected newer-API native imports/build notes. API 23 startup and playback remain unverified until device testing.');
  } catch (error) {
    stderr.writeln('Release verification failed: $error');
    exitCode = 1;
  }
}

String flutterExecutable() {
  final sdk = Platform.environment['STARFLOW_FLUTTER_SDK'];
  return sdk == null || sdk.isEmpty
      ? (Platform.isWindows ? 'flutter.bat' : 'flutter')
      : p.join(sdk, 'bin', Platform.isWindows ? 'flutter.bat' : 'flutter');
}

void verifySdkVersion(Map version, Map policy, Map fvm) {
  if (version['frameworkVersion'] != policy['flutterVersion'] ||
      version['frameworkRevision'] != policy['frameworkRevision'] ||
      version['engineRevision'] != policy['engineRevision'] ||
      fvm['flutter'] != policy['flutterVersion']) {
    throw StateError(
        'TV release requires Flutter ${policy['flutterVersion']} / engine ${policy['engineRevision']}. Select the pinned SDK with STARFLOW_FLUTTER_SDK; do not raise minSdk.');
  }
}

// Match java.util.Properties escaping, including continued lines and Unicode.
Map<String, String> parseSigningProperties(String source) {
  final result = <String, String>{};
  String unescape(String value) =>
      value.replaceAllMapped(RegExp(r'\\(u[0-9a-fA-F]{4}|.)'), (m) {
        final escape = m[1]!;
        if (escape.startsWith('u') && escape.length == 5) {
          return String.fromCharCode(int.parse(escape.substring(1), radix: 16));
        }
        return {'t': '\t', 'n': '\n', 'r': '\r', 'f': '\f'}[escape] ?? escape;
      });
  var pending = '';
  for (var line in const LineSplitter().convert(source)) {
    line = line.replaceFirst(RegExp(r'^[ \t\f]+'), '');
    if (pending.isEmpty && (line.startsWith('#') || line.startsWith('!'))) {
      continue;
    }
    pending += line;
    final slashes = RegExp(r'\\+$').firstMatch(pending)?[0]?.length ?? 0;
    if (slashes.isOdd) {
      pending = pending.substring(0, pending.length - 1);
      continue;
    }
    final match = RegExp(r'^((?:\\.|[^\s:=])+)[ \t\f]*(?:[:=][ \t\f]*)?(.*)$')
        .firstMatch(pending);
    if (match != null) result[unescape(match[1]!)] = unescape(match[2]!);
    pending = '';
  }
  if (pending.isNotEmpty) {
    throw const FormatException('Incomplete signing properties line.');
  }
  return result;
}

Future<void> verifySigningConfiguration(
    String root, String expectedDigest) async {
  final signing = File(p.join(root, 'android/key.properties'));
  if (!await signing.exists()) {
    throw StateError(
        'Configure android/key.properties with the existing signing identity before building.');
  }
  final values = parseSigningProperties(await signing.readAsString());
  for (final field in [
    'storeFile',
    'storePassword',
    'keyAlias',
    'keyPassword'
  ]) {
    if (values[field]?.isNotEmpty != true ||
        values[field] == 'replace-locally') {
      throw StateError('Signing configuration requires a valid $field.');
    }
  }
  final store = p.isAbsolute(values['storeFile']!)
      ? values['storeFile']!
      : p.join(root, 'android', values['storeFile']!);
  if (!await File(store).exists()) {
    throw StateError(
        'Configured signing keystore is missing. Restore the existing key; do not generate a replacement.');
  }
  final javaHome = Platform.environment['JAVA_HOME'];
  final keytoolName = Platform.isWindows ? 'keytool.exe' : 'keytool';
  final keytool =
      javaHome == null ? keytoolName : p.join(javaHome, 'bin', keytoolName);
  final common = [
    '-keystore',
    store,
    '-alias',
    values['keyAlias']!,
    '-storepass:env',
    'STARFLOW_VERIFY_STORE_PASSWORD'
  ];
  final environment = {
    'STARFLOW_VERIFY_STORE_PASSWORD': values['storePassword']!,
    'STARFLOW_VERIFY_KEY_PASSWORD': values['keyPassword']!
  };
  // Passwords stay out of argv and diagnostics; neither command writes the keystore.
  final cert = await Process.run(keytool, ['-exportcert', ...common],
      environment: environment, stdoutEncoding: null);
  if (cert.exitCode != 0) {
    throw StateError(
        'Cannot read signing certificate; check local keystore, alias and password.');
  }
  if (sha256.convert(cert.stdout as List<int>).toString() != expectedDigest) {
    throw StateError(
        'Signing certificate differs from the pinned installed-app identity. Restore the existing key.');
  }
  final request = await Process.run(keytool,
      ['-certreq', ...common, '-keypass:env', 'STARFLOW_VERIFY_KEY_PASSWORD'],
      environment: environment);
  if (request.exitCode != 0) {
    throw StateError(
        'Cannot access the configured signing private key; check keyPassword.');
  }
}

Archive decodeApk(List<int> bytes) {
  final decoder = ZipDecoder();
  final archive = decoder.decodeBytes(bytes);
  // ZipDecoder folds duplicate names; inspect the central directory as well.
  final names = <String>{};
  for (final header in decoder.directory.fileHeaders) {
    if (!names.add(header.filename)) {
      throw StateError('APK contains duplicate ZIP entries.');
    }
  }
  return archive;
}

void verifyArchive(
    Archive archive, Set<String> expectedAbis, List<int>? expectedSettings) {
  final names = <String>{};
  for (final entry in archive.files) {
    final name = entry.name;
    if (!names.add(name) ||
        name.startsWith('/') ||
        name.contains('\\') ||
        name.split('/').any((part) => part == '..' || part == '.') ||
        RegExp(r'^[A-Za-z]:').hasMatch(name) ||
        entry.isSymbolicLink) {
      throw StateError('APK contains duplicate or unsafe ZIP entries.');
    }
    if (name.startsWith('lib/') &&
        entry.isFile &&
        !RegExp(r'^lib/[^/]+/[^/]+\.so$').hasMatch(name)) {
      throw StateError('Unexpected native library path.');
    }
  }
  final abiNames = names
      .where((n) => n.startsWith('lib/') && n.endsWith('.so'))
      .map((n) => n.split('/')[1])
      .toSet();
  if (abiNames.length != expectedAbis.length ||
      !abiNames.containsAll(expectedAbis)) {
    throw StateError('Unexpected APK ABIs: $abiNames');
  }
  for (final abi in expectedAbis) {
    for (final library in ['libflutter.so', 'libapp.so']) {
      final entry = archive.findFile('lib/$abi/$library');
      if (entry == null || !entry.isFile || entry.size == 0) {
        throw StateError('APK is missing $abi/$library.');
      }
    }
  }
  final embedded = archive.findFile(_embeddedPath);
  if (expectedSettings == null) {
    if (embedded != null) {
      throw StateError(
          'Normal APK contains embedded settings. Refusing delivery.');
    }
  } else if (embedded == null ||
      !embedded.isFile ||
      embedded.content.length != expectedSettings.length ||
      Iterable<int>.generate(expectedSettings.length)
          .any((i) => embedded.content[i] != expectedSettings[i])) {
    throw StateError(
        'Embedded settings missing or different from the supplied file.');
  }
}

void verifyBadging(String badging, String version, int minSdk,
    {int? expectedVersionCode}) {
  final package =
      RegExp(r'^package: (.+)$', multiLine: true).firstMatch(badging);
  final fields = {
    for (final m in RegExp(r"(\w+)='([^']*)'").allMatches(package?[1] ?? ''))
      m[1]: m[2]
  };
  final sdk = RegExp(r"^sdkVersion:'(\d+)'\r?$", multiLine: true)
      .firstMatch(badging)?[1];
  if (fields['name'] != 'com.example.starflow' ||
      fields['versionName'] != version ||
      (expectedVersionCode != null &&
          fields['versionCode'] != '$expectedVersionCode') ||
      sdk != '$minSdk') {
    throw StateError(
        'APK package, internal version, or minSdk differs from release policy.');
  }
}

void verifySignature(String signature, String certificateSha256) {
  final certificates = RegExp(
          r'^Signer #\d+ certificate SHA-256 digest: ([a-fA-F0-9]+)\r?$',
          multiLine: true)
      .allMatches(signature)
      .map((m) => m[1]!.toLowerCase())
      .toList();
  if (certificates.length != 1 ||
      certificates.single != certificateSha256 ||
      !signature.contains('Verified using v1 scheme (JAR signing): true') ||
      !signature.contains(
          'Verified using v2 scheme (APK Signature Scheme v2): true')) {
    throw StateError(
        'APK requires the pinned installed-app certificate and valid v1/v2 signatures.');
  }
}

({String aapt, String apksigner, String readelf}) releaseTools(String root) {
  final sdk = androidSdk(root);
  final buildTools = newestDirectory(p.join(sdk, 'build-tools'));
  final ndk = newestDirectory(p.join(sdk, 'ndk'));
  final prebuilt = newestDirectory(p.join(ndk, 'toolchains/llvm/prebuilt'));
  final readelf = p.join(prebuilt, 'bin',
      Platform.isWindows ? 'llvm-readelf.exe' : 'llvm-readelf');
  return (
    aapt: p.join(buildTools, Platform.isWindows ? 'aapt.exe' : 'aapt'),
    apksigner:
        p.join(buildTools, Platform.isWindows ? 'apksigner.bat' : 'apksigner'),
    readelf: readelf
  );
}

Future<void> verifyNativeApi23(
    String readelf, String path, String label) async {
  final symbols = await run(readelf, ['--dyn-syms', '--wide', path]);
  if (!RegExp(r'\b\d+:.*\bUND\b').hasMatch(symbols)) {
    throw StateError('$label has no readable dynamic symbol table.');
  }
  final incompatible = symbols.split('\n').where((line) =>
      RegExp(r'\bGLOBAL\b.*\bUND\b').hasMatch(line) &&
      RegExp(r'@(?:LIBC|LIBM|LIBDL|LIBANDROID)_(?:N(?:_|\b)|[O-Z](?:_|\b)|(?:2[4-9]|[3-9]\d|\d{3,})(?:_|\b)|PRIVATE\b)')
          .hasMatch(line));
  if (incompatible.isNotEmpty) {
    throw StateError(
        '$label requires newer Android symbols: ${incompatible.join(', ')}');
  }
  final notes = await run(readelf, ['--notes', path]);
  final ident = RegExp(
          r'Android\s+0x[0-9a-fA-F]+[^\n]*\n\s*description data: ([0-9a-fA-F]{2}) ([0-9a-fA-F]{2}) ([0-9a-fA-F]{2}) ([0-9a-fA-F]{2})')
      .firstMatch(notes);
  if (notes.contains('NT_ANDROID_TYPE_IDENT') && ident == null) {
    throw StateError('$label has an unreadable Android build note.');
  }
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
    final sdk =
        parseSigningProperties(properties.readAsStringSync())['sdk.dir'];
    if (sdk != null && sdk.isNotEmpty) return sdk;
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
