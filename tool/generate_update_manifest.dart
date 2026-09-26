import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:starflow/features/update/data/update_manifest_parser.dart';

import 'release_version.dart';
import 'verify_tv_release.dart' as verifier;

const maxUpdateApkBytes = 512 * 1024 * 1024;
const maxUpdateManifestBytes = 256 * 1024;
typedef CommandRunner = Future<String> Function(String, List<String>);
typedef AndroidReleaseTools = ({String aapt, String apksigner, String readelf});

const updateReleaseUsage = '''Usage (no builds or uploads):
  .fvm/flutter_sdk/bin/dart tool/generate_update_manifest.dart \\
    --apk /path/starflow-tv-VERSION.apk --notes /path/notes.txt \\
    --artifact-url https://host/releases/VERSION_CODE/starflow-tv-VERSION.apk \\
    (--output /path/manifest.json | --stage-dir /path/local-release-root)

Notes are UTF-8 text, one nonblank line per release note.
At most 100 notes, each at most 4096 characters; manifest at most 256 KiB.
Optional --published-at must be an ISO-8601 UTC timestamp ending in Z.
The APK is reverified with the existing TV verifier and pinned release policy.
--output never overwrites an existing file. --stage-dir creates immutable
VERSION_CODE/{starflow-tv-VERSION.apk,manifest.json}, then atomically switches
latest.json last. The stage root must be local, trusted, and on one filesystem.
VERSION_CODE is the actual numeric APK versionCode, not its display version.
The artifact URL's immediate parent directory must equal VERSION_CODE.
A stale .publish.lock after interruption requires manual inspection/removal.
No host deployment is performed. No manifest signing key is needed.

The app uses its WebDAV sync directory + releases/latest.json for checks.
Artifact URLs must be within that same HTTPS WebDAV releases directory.
Android APK signing and verification remain required.
''';

Future<void> main(List<String> args) async {
  try {
    if (args.length == 1 && args.single == '--help') {
      stdout.write(updateReleaseUsage);
      return;
    }
    final options = parseUpdateReleaseArguments(args);
    final root = p.dirname(p.dirname(Platform.script.toFilePath()));
    final result = await generateUpdateRelease(
      root: root,
      apk: File(options['--apk']!),
      notes: File(options['--notes']!),
      artifactUrl: options['--artifact-url']!,
      output: options['--output'] == null ? null : File(options['--output']!),
      stageDirectory: options['--stage-dir'] == null
          ? null
          : Directory(options['--stage-dir']!),
      publishedAt: options['--published-at'] == null
          ? null
          : parsePublishedAt(options['--published-at']!),
    );
    stdout.writeln('Manifest=$result');
    if (options.containsKey('--stage-dir')) {
      stdout
          .writeln('Local staging complete; no external deployment performed.');
    }
  } catch (error) {
    stderr.writeln('Update release failed: $error');
    exitCode = 1;
  }
}

Map<String, String> parseUpdateReleaseArguments(List<String> args) {
  const required = ['--apk', '--notes', '--artifact-url'];
  const optional = ['--output', '--stage-dir', '--published-at'];
  final result = <String, String>{};
  for (var i = 0; i < args.length; i += 2) {
    final key = args[i];
    if ((!required.contains(key) && !optional.contains(key)) ||
        result.containsKey(key) ||
        i + 1 == args.length ||
        args[i + 1].isEmpty ||
        args[i + 1].startsWith('--')) {
      throw ArgumentError(updateReleaseUsage);
    }
    result[key] = args[i + 1];
  }
  if (required.any((key) => !result.containsKey(key)) ||
      result.containsKey('--output') == result.containsKey('--stage-dir')) {
    throw ArgumentError(updateReleaseUsage);
  }
  return result;
}

DateTime parsePublishedAt(String value) {
  final date = DateTime.tryParse(value);
  if (!value.endsWith('Z') || date == null || !date.isUtc) {
    throw const FormatException(
        'publishedAt must be an ISO-8601 UTC timestamp ending in Z.');
  }
  return date;
}

List<String> parseReleaseNotes(String text) {
  final notes = const LineSplitter()
      .convert(text)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (notes.isEmpty) {
    throw const FormatException('Release notes must not be empty.');
  }
  return notes;
}

void validateArtifactUrl(String value, String fileName, int versionCode) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      uri.pathSegments.length < 2 ||
      uri.pathSegments[uri.pathSegments.length - 2] != '$versionCode' ||
      uri.pathSegments.last != fileName ||
      RegExp(r'\s').hasMatch(value)) {
    throw const FormatException(
        'Artifact URL must be HTTPS, without credentials or a fragment, and end in VERSION_CODE/APK_FILENAME matching the actual APK.');
  }
}

({String version, int versionCode}) readApkMetadata(String badging) {
  final packages = RegExp(r'^package: (.+)\r?$', multiLine: true)
      .allMatches(badging)
      .toList();
  if (packages.length != 1 ||
      RegExp(r'^application-debuggable(?:\s|$)', multiLine: true)
          .hasMatch(badging)) {
    throw StateError('APK must be a non-debuggable release with one package.');
  }
  final fields = <String, String>{};
  for (final match
      in RegExp(r"(\w+)='([^']*)'").allMatches(packages.single[1]!)) {
    if (fields.containsKey(match[1])) {
      throw StateError('Duplicate APK metadata.');
    }
    fields[match[1]!] = match[2]!;
  }
  final version = fields['versionName'] ?? '';
  if (ReleaseVersion.parse(version).toString() != version) {
    throw StateError('APK versionName must be canonical major.month.sequence.');
  }
  final code = int.tryParse(fields['versionCode'] ?? '');
  if (code == null ||
      code <= 0 ||
      code > 2100000000 ||
      fields['versionCode'] != '$code') {
    throw StateError('APK versionCode must be a positive Android integer.');
  }
  verifier.verifyBadging(badging, version, 23, expectedVersionCode: code);
  return (version: version, versionCode: code);
}

Future<String> apkSha256(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Future<void> copyBoundedApk(File source, File target) async {
  final size = await source.length();
  if (size <= 0 || size > maxUpdateApkBytes) {
    throw StateError('APK size must be between 1 byte and 512 MiB.');
  }
  final sink = await target.open(mode: FileMode.write);
  var copied = 0;
  try {
    await for (final bytes in source.openRead()) {
      copied += bytes.length;
      if (copied > maxUpdateApkBytes) throw StateError('APK exceeds 512 MiB.');
      await sink.writeFrom(bytes);
    }
    if (copied != size) throw StateError('APK changed size during staging.');
    await sink.flush();
  } finally {
    await sink.close();
  }
}

Future<Map<String, Object>> inspectUpdateApk({
  required String root,
  required File apk,
  required String artifactUrl,
  required List<String> releaseNotes,
  required DateTime publishedAt,
  CommandRunner runner = verifier.run,
  AndroidReleaseTools? tools,
}) async {
  final policy = jsonDecode(
      await File(p.join(root, 'config/android_release.json'))
          .readAsString()) as Map;
  final certificate = policy['certificateSha256'] as String;
  if (policy['minSdk'] != 23 ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(certificate) ||
      (policy['abis'] as List).length != 2 ||
      !(policy['abis'] as List).contains('armeabi-v7a') ||
      !(policy['abis'] as List).contains('arm64-v8a')) {
    throw StateError('Unexpected TV release policy.');
  }
  final size = await apk.length();
  if (size <= 0 || size > maxUpdateApkBytes) {
    throw StateError('Invalid APK size.');
  }
  final digest = await apkSha256(apk);
  verifier.verifyArchive(verifier.decodeApk(await apk.readAsBytes()),
      (policy['abis'] as List).cast<String>().toSet(), null);
  final android = tools ?? verifier.releaseTools(root);
  final metadata = readApkMetadata(
      await runner(android.aapt, ['dump', 'badging', apk.absolute.path]));
  final fileName = 'starflow-tv-${metadata.version}.apk';
  if (p.basename(apk.path) != fileName) {
    throw StateError(
        'Only the normal, correctly named TV release APK is publishable.');
  }
  validateArtifactUrl(artifactUrl, fileName, metadata.versionCode);
  final signature = await runner(android.apksigner, [
    'verify',
    '--min-sdk-version',
    '23',
    '--print-certs',
    '--verbose',
    apk.absolute.path
  ]);
  verifier.verifySignature(signature, certificate);
  // Keep the existing verifier authoritative, including native API and version-code checks.
  await runner(
      p.join(root, '.fvm/flutter_sdk/bin',
          Platform.isWindows ? 'dart.bat' : 'dart'),
      [
        p.join(root, 'tool/verify_tv_release.dart'),
        apk.absolute.path,
        metadata.version
      ]);
  if (await apk.length() != size || await apkSha256(apk) != digest) {
    throw StateError('APK changed while it was being verified.');
  }
  return {
    'schemaVersion': 1,
    'appId': 'com.example.starflow',
    'channel': 'stable',
    'version': metadata.version,
    'versionCode': metadata.versionCode,
    'publishedAt': publishedAt.toUtc().toIso8601String(),
    'releaseNotes': releaseNotes,
    'artifacts': [
      {
        'platform': 'android',
        'variant': 'tv',
        'fileName': fileName,
        'url': artifactUrl,
        'size': size,
        'sha256': digest,
        'minSdk': 23,
        'certificateSha256': certificate,
      }
    ],
  };
}

String encodeUpdateManifest(Map<String, Object> manifest) {
  parseUpdateManifest(manifest);
  final contents = '${jsonEncode(manifest)}\n';
  if (utf8.encode(contents).length > maxUpdateManifestBytes) {
    throw StateError('Update manifest exceeds the client limit of 256 KiB.');
  }
  return contents;
}

Future<void> verifyReleaseReadback(
    File manifest, File apk, String expected) async {
  final contents = await manifest.readAsString();
  if (contents != expected) {
    throw StateError('Manifest readback differs from generated output.');
  }
  final release =
      parseUpdateManifest(jsonDecode(contents) as Map<String, dynamic>);
  final artifact = release.artifacts.single;
  if (await apk.length() != artifact.size ||
      await apkSha256(apk) != artifact.sha256) {
    throw StateError('APK hash/size readback failed.');
  }
}

Future<bool> _exists(String path) async =>
    await FileSystemEntity.type(path, followLinks: false) !=
    FileSystemEntityType.notFound;

Future<void> _atomicManifest(File target, String contents) async {
  final temp = await target.parent.createTemp('.manifest-');
  try {
    final file = File(p.join(temp.path, 'manifest.json'));
    await file.writeAsString(contents, flush: true);
    if (await file.readAsString() != contents) {
      throw StateError('Manifest write failed.');
    }
    await file.rename(target.path);
  } finally {
    await temp.delete(recursive: true);
  }
}

/// All publishing is local. Injected runners/tools allow tests without a release build.
Future<String> generateUpdateRelease({
  required String root,
  required File apk,
  required File notes,
  required String artifactUrl,
  File? output,
  Directory? stageDirectory,
  DateTime? publishedAt,
  CommandRunner runner = verifier.run,
  AndroidReleaseTools? tools,
}) async {
  if ((output == null) == (stageDirectory == null)) {
    throw ArgumentError('Specify exactly one of output or stageDirectory.');
  }
  final releaseNotes = parseReleaseNotes(await notes.readAsString());
  final parent = stageDirectory ?? output!.absolute.parent;
  await parent.create(recursive: true);
  final lock = File(stageDirectory == null
      ? '${output!.absolute.path}.lock'
      : p.join(parent.path, '.publish.lock'));
  await lock.create(exclusive: true);
  Directory? pending;
  try {
    if (output != null && await _exists(output.path)) {
      throw StateError('Refusing to overwrite existing manifest.');
    }
    pending = await parent.createTemp('.release-');
    final snapshot = File(p.join(pending.path, p.basename(apk.path)));
    await copyBoundedApk(apk, snapshot);
    final payload = await inspectUpdateApk(
        root: root,
        apk: snapshot,
        artifactUrl: artifactUrl,
        releaseNotes: releaseNotes,
        publishedAt: publishedAt ?? DateTime.now().toUtc(),
        runner: runner,
        tools: tools);
    final contents = encodeUpdateManifest(payload);
    final manifest = File(p.join(pending.path, 'manifest.json'));
    await _atomicManifest(manifest, contents);
    await verifyReleaseReadback(manifest, snapshot, contents);
    late String manifestPath;
    if (stageDirectory == null) {
      await _atomicManifest(output!, contents);
      manifestPath = output.absolute.path;
    } else {
      final destination = p.join(parent.path, '${payload['versionCode']}');
      if (await _exists(destination)) {
        throw StateError(
            'Release versionCode already exists; immutable releases cannot be overwritten.');
      }
      await pending.rename(destination);
      pending = null;
      final committed = File(p.join(destination, 'manifest.json'));
      await verifyReleaseReadback(
          committed, File(p.join(destination, p.basename(apk.path))), contents);
      // Only after the immutable APK and manifest are committed and read back.
      final latest = File(p.join(parent.path, 'latest.json'));
      await _atomicManifest(latest, contents);
      manifestPath = committed.absolute.path;
    }
    return manifestPath;
  } finally {
    try {
      if (pending != null) await pending.delete(recursive: true);
    } finally {
      await lock.delete();
    }
  }
}
