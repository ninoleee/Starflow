import 'dart:convert';

import '../domain/app_update.dart';

const _maxManifestBytes = 256 * 1024;
const _invalidManifest = UpdateFailure(
  'invalid_manifest',
  'The update manifest is invalid or unsupported.',
);

/// Validates manifest metadata; APK identity is checked again before installation.
AppUpdate parseUpdateManifest(Map<String, dynamic> json) {
  try {
    return _parseUpdateManifest(json);
  } on FormatException {
    throw _invalidManifest;
  }
}

AppUpdate _parseUpdateManifest(Map<String, dynamic> json) {
  _keys(json, const {
    'schemaVersion',
    'appId',
    'channel',
    'version',
    'versionCode',
    'publishedAt',
    'releaseNotes',
    'artifacts',
  });
  if (json['schemaVersion'] is! int ||
      json['schemaVersion'] != 1 ||
      json['appId'] != 'com.example.starflow' ||
      json['channel'] != 'stable') {
    throw _invalidManifest;
  }
  final version = _text(json['version'], 32);
  if (!RegExp(r'^(0|[1-9][0-9]?)\.([1-9]|1[0-2])\.(0|[1-9][0-9]{0,3})$')
      .hasMatch(version)) {
    throw _invalidManifest;
  }
  final versionCode = _positiveInt(json['versionCode'], 2100000000);
  final publishedAt = _utcDate(json['publishedAt']);
  final notes = json['releaseNotes'];
  if (notes is! List || notes.length > 100) throw _invalidManifest;
  final releaseNotes = <String>[
    for (final note in notes) _text(note, 4096),
  ];
  final rawArtifacts = json['artifacts'];
  if (rawArtifacts is! List ||
      rawArtifacts.isEmpty ||
      rawArtifacts.length > 16) {
    throw _invalidManifest;
  }
  final artifacts = <UpdateArtifact>[];
  final identities = <String>{};
  for (final raw in rawArtifacts) {
    if (raw is! Map<String, dynamic>) throw _invalidManifest;
    _keys(raw, const {
      'platform',
      'variant',
      'fileName',
      'url',
      'size',
      'sha256',
      'minSdk',
      'certificateSha256',
    });
    if (raw['platform'] != 'android' ||
        raw['variant'] != 'tv' ||
        raw['minSdk'] is! int ||
        raw['minSdk'] != 23 ||
        !identities.add('${raw['platform']}/${raw['variant']}')) {
      throw _invalidManifest;
    }
    final fileName = _text(raw['fileName'], 80);
    if (fileName != 'starflow-tv-$version.apk') throw _invalidManifest;
    final urlText = _text(raw['url'], 8192);
    final url = Uri.tryParse(urlText);
    if (url == null ||
        url.scheme != 'https' ||
        !url.hasAuthority ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.authority.contains('@') ||
        url.hasFragment ||
        url.port < 1 ||
        url.port > 65535 ||
        RegExp(r'^https://[^/?#]*@', caseSensitive: false).hasMatch(urlText) ||
        RegExp(r'[\x00-\x20\x7f\\]').hasMatch(urlText)) {
      throw _invalidManifest;
    }
    // A valid fileName must not disguise a settings-embedded download URL.
    if (url.pathSegments
        .any((part) => part.toLowerCase().contains('starflow-tv-config-'))) {
      throw _invalidManifest;
    }
    artifacts.add(UpdateArtifact(
      platform: 'android',
      variant: 'tv',
      url: url,
      fileName: fileName,
      size: _positiveInt(raw['size'], 512 * 1024 * 1024),
      sha256: _hash(raw['sha256']),
      minSdk: 23,
      certificateSha256: _hash(raw['certificateSha256']),
    ));
  }
  // All nested shapes and individual fields are bounded before serialization.
  if (utf8.encode(jsonEncode(json)).length > _maxManifestBytes) {
    throw _invalidManifest;
  }
  return AppUpdate(
    appId: 'com.example.starflow',
    channel: 'stable',
    version: version,
    versionCode: versionCode,
    publishedAt: publishedAt,
    releaseNotes: List.unmodifiable(releaseNotes),
    artifacts: List.unmodifiable(artifacts),
  );
}

void _keys(Map<String, dynamic> json, Set<String> expected) {
  if (json.length != expected.length || !json.keys.every(expected.contains)) {
    throw _invalidManifest;
  }
}

String _text(Object? value, int maxLength) {
  if (value is! String ||
      value.isEmpty ||
      value.length > maxLength ||
      value.trim().isEmpty ||
      value.contains('\u0000')) {
    throw _invalidManifest;
  }
  return value;
}

int _positiveInt(Object? value, int max) {
  if (value is! int || value <= 0 || value > max) throw _invalidManifest;
  return value;
}

String _hash(Object? value) {
  final text = _text(value, 64);
  if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(text)) throw _invalidManifest;
  return text.toLowerCase();
}

DateTime _utcDate(Object? value) {
  final text = _text(value, 40);
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(?:Z|\+00:00)$',
  ).firstMatch(text);
  final date = DateTime.tryParse(text);
  if (match == null || date == null || !date.isUtc || date.year == 0) {
    throw _invalidManifest;
  }
  final actual = [
    date.year,
    date.month,
    date.day,
    date.hour,
    date.minute,
    date.second
  ];
  for (var i = 0; i < actual.length; i++) {
    if (actual[i] != int.parse(match.group(i + 1)!)) throw _invalidManifest;
  }
  return date;
}
