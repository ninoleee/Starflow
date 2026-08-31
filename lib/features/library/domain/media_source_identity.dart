import 'package:starflow/features/library/domain/media_models.dart';

String mediaSourceResourceIdentity(MediaSourceConfig source) {
  return switch (source.kind) {
    MediaSourceKind.nas => <String>[
        source.kind.name,
        _normalizeLocation(source.endpoint),
        _normalizeLocation(source.libraryPath),
      ].join('|'),
    MediaSourceKind.quark => <String>[
        source.kind.name,
        source.quarkFolderId.trim(),
        _normalizePath(source.quarkFolderPath),
      ].join('|'),
    MediaSourceKind.emby => <String>[
        source.kind.name,
        _normalizeLocation(source.endpoint),
        source.userId.trim(),
        source.serverId.trim(),
      ].join('|'),
  };
}

bool legacyIndexScopeMatchesSource({
  required String scopeKey,
  required MediaSourceConfig source,
}) {
  final normalizedScopeKey = scopeKey.trim();
  if (normalizedScopeKey.isEmpty) {
    return false;
  }
  if (normalizedScopeKey.startsWith('root|')) {
    final markerIndex = normalizedScopeKey.indexOf('|structure:');
    final rawRoot = markerIndex < 0
        ? normalizedScopeKey.substring('root|'.length)
        : normalizedScopeKey.substring('root|'.length, markerIndex);
    final expectedRoot = source.libraryPath.trim().isNotEmpty
        ? source.libraryPath
        : source.endpoint;
    return _normalizeLocation(rawRoot) == _normalizeLocation(expectedRoot);
  }
  if (!normalizedScopeKey.startsWith('collections|')) {
    return false;
  }
  final markerIndex = normalizedScopeKey.indexOf('|structure:');
  if (markerIndex < 0) {
    return false;
  }
  final rawIds = normalizedScopeKey.substring(
    'collections|'.length,
    markerIndex,
  );
  final storedIds = rawIds
      .split(',')
      .map(_normalizeLocation)
      .where((item) => item.isNotEmpty)
      .toSet();
  final selectedIds = source.selectedSectionIds
      .map(_normalizeLocation)
      .where((item) => item.isNotEmpty)
      .toSet();
  return storedIds.isNotEmpty &&
      storedIds.length == selectedIds.length &&
      storedIds.containsAll(selectedIds);
}

String remapMediaSourceLocation(
  String value, {
  required MediaSourceConfig previous,
  required MediaSourceConfig current,
}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty ||
      previous.kind != MediaSourceKind.nas ||
      current.kind != MediaSourceKind.nas) {
    return trimmed;
  }
  final oldRoot = previous.libraryPath.trim().isNotEmpty
      ? previous.libraryPath
      : previous.endpoint;
  final newRoot = current.libraryPath.trim().isNotEmpty
      ? current.libraryPath
      : current.endpoint;
  final oldRootUri = Uri.tryParse(oldRoot.trim());
  final newRootUri = Uri.tryParse(newRoot.trim());
  final valueUri = Uri.tryParse(trimmed);
  if (newRootUri == null ||
      valueUri == null ||
      !_isAbsoluteNetworkUri(newRootUri) ||
      !_isAbsoluteNetworkUri(valueUri)) {
    return trimmed;
  }
  if (oldRootUri == null || !_isAbsoluteNetworkUri(oldRootUri)) {
    return alignMediaSourceLocationToCurrentRoot(trimmed, current);
  }
  final resolvedOldRootUri = oldRootUri;
  final resolvedNewRootUri = newRootUri;
  final resolvedValueUri = valueUri;
  final oldSegments = _decodedSegments(resolvedOldRootUri.path);
  final newSegments = _decodedSegments(resolvedNewRootUri.path);
  final valueSegments = _decodedSegments(resolvedValueUri.path);
  if (!_startsWith(valueSegments, oldSegments)) {
    return alignMediaSourceLocationToCurrentRoot(trimmed, current);
  }
  var relativeSegments = valueSegments.sublist(oldSegments.length);
  var overlap = 0;
  final maxOverlap = relativeSegments.length < newSegments.length
      ? relativeSegments.length
      : newSegments.length;
  for (var length = maxOverlap; length > 0; length--) {
    final newSuffix = newSegments.sublist(newSegments.length - length);
    final relativePrefix = relativeSegments.sublist(0, length);
    if (_sameSegments(newSuffix, relativePrefix)) {
      overlap = length;
      break;
    }
  }
  relativeSegments = relativeSegments.sublist(overlap);
  final trailingSlash = resolvedValueUri.path.endsWith('/');
  return resolvedNewRootUri.replace(
    pathSegments: <String>[
      ...newSegments,
      ...relativeSegments,
      if (trailingSlash) '',
    ],
    query: null,
    fragment: null,
  ).toString();
}

String alignMediaSourceLocationToCurrentRoot(
  String value,
  MediaSourceConfig source,
) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || source.kind != MediaSourceKind.nas) {
    return trimmed;
  }
  final root = source.libraryPath.trim().isNotEmpty
      ? source.libraryPath
      : source.endpoint;
  final rootUri = Uri.tryParse(root.trim());
  final valueUri = Uri.tryParse(trimmed);
  if (rootUri == null ||
      valueUri == null ||
      !_isAbsoluteNetworkUri(rootUri) ||
      !_isAbsoluteNetworkUri(valueUri)) {
    return trimmed;
  }
  final resolvedRootUri = rootUri;
  final resolvedValueUri = valueUri;
  final rootSegments = _decodedSegments(resolvedRootUri.path);
  final valueSegments = _decodedSegments(resolvedValueUri.path);
  if (resolvedRootUri.host.toLowerCase() ==
          resolvedValueUri.host.toLowerCase() &&
      _startsWith(valueSegments, rootSegments)) {
    return trimmed;
  }

  const stableBoundaryLabels = <String>{
    'media',
    'movies',
    'nas',
    'strm',
    'videos',
    'webdav',
  };
  for (var overlapLength = rootSegments.length;
      overlapLength > 0;
      overlapLength--) {
    final rootSuffix = rootSegments.sublist(
      rootSegments.length - overlapLength,
    );
    for (var start = 0;
        start + overlapLength <= valueSegments.length;
        start++) {
      final valueSlice = valueSegments.sublist(start, start + overlapLength);
      final stableSingleBoundary = overlapLength == 1 &&
          stableBoundaryLabels.contains(rootSuffix.single.toLowerCase());
      if (!_sameSegments(rootSuffix, valueSlice) ||
          (overlapLength == 1 && !stableSingleBoundary)) {
        continue;
      }
      final trailingSlash = resolvedValueUri.path.endsWith('/');
      return resolvedRootUri.replace(
        pathSegments: <String>[
          ...rootSegments,
          ...valueSegments.sublist(start + overlapLength),
          if (trailingSlash) '',
        ],
        query: null,
        fragment: null,
      ).toString();
    }
  }
  return '';
}

String _normalizeLocation(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) {
    return _normalizePath(trimmed);
  }
  final path = _normalizePath(uri.path);
  return uri
      .replace(
        scheme: uri.scheme.toLowerCase(),
        host: uri.host.toLowerCase(),
        path: path,
        query: null,
        fragment: null,
      )
      .toString();
}

String _normalizePath(String value) {
  final normalized = value.trim().replaceAll('\\', '/').replaceAll(
        RegExp(r'/+'),
        '/',
      );
  if (normalized == '/' || normalized.isEmpty) {
    return normalized;
  }
  return normalized.endsWith('/')
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
}

List<String> _decodedSegments(String path) {
  return path.split('/').where((segment) => segment.isNotEmpty).map((segment) {
    try {
      return Uri.decodeComponent(segment);
    } catch (_) {
      return segment;
    }
  }).toList(growable: false);
}

bool _isAbsoluteNetworkUri(Uri? uri) {
  return uri != null && uri.hasScheme && uri.host.trim().isNotEmpty;
}

bool _startsWith(List<String> value, List<String> prefix) {
  if (prefix.length > value.length) {
    return false;
  }
  for (var index = 0; index < prefix.length; index++) {
    if (value[index] != prefix[index]) {
      return false;
    }
  }
  return true;
}

bool _sameSegments(List<String> left, List<String> right) {
  return left.length == right.length && _startsWith(left, right);
}
