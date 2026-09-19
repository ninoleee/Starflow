import 'dart:convert';

/// Lossless segment key within an already validated source. Encoded slashes
/// remain inside their segment; literal filesystem percent signs stay literal.
String resourcePathKey(String value) =>
    value.trim().isEmpty ? '' : jsonEncode(resourcePathSegments(value));

/// Compares paths within an already validated media source.
/// URL segments are decoded once; plain filesystem paths remain literal.
List<String> resourcePathSegments(String value) {
  final normalized = value.trim().replaceAll('\\', '/');
  if (normalized.isEmpty) return const [];
  final uri = Uri.tryParse(normalized);
  final isUrl = uri != null && uri.hasScheme && normalized.contains('://');
  final segments = isUrl ? uri.pathSegments : normalized.split('/');
  return segments
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
}

bool resourcePathsEqual(String candidate, String expected) {
  final left = resourcePathSegments(candidate);
  final right = resourcePathSegments(expected);
  return left.isNotEmpty &&
      left.length == right.length &&
      _startsWithSegments(left, right);
}

bool resourcePathIsWithinScope(String candidate, String scope) {
  final path = resourcePathSegments(candidate);
  final root = resourcePathSegments(scope);
  return root.isNotEmpty &&
      path.length >= root.length &&
      _startsWithSegments(path, root);
}

bool _startsWithSegments(List<String> path, List<String> root) {
  for (var index = 0; index < root.length; index++) {
    if (path[index] != root[index]) return false;
  }
  return true;
}
