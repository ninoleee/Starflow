import 'package:http/http.dart' as http;

bool isHttpUri(Uri uri) =>
    (uri.scheme == 'http' || uri.scheme == 'https') &&
    uri.host.isNotEmpty &&
    uri.userInfo.isEmpty;

bool isSameHttpOrigin(Uri left, Uri right) =>
    isHttpUri(left) &&
    isHttpUri(right) &&
    left.scheme == right.scheme &&
    left.host == right.host &&
    left.port == right.port;

/// Decoded segments prevent encoded separators/dot segments escaping the root.
bool isWithinHttpDirectory(Uri uri, Uri root) {
  if (!isSameHttpOrigin(uri, root)) return false;
  List<String>? segments(Uri value) {
    final result = <String>[];
    for (final part in value.pathSegments) {
      if (part.contains('/') ||
          part.contains('\\') ||
          part == '..' ||
          part == '.' ||
          RegExp(r'%2e|%2f|%5c', caseSensitive: false).hasMatch(part)) {
        return null;
      }
      if (part.isNotEmpty) result.add(part);
    }
    return result;
  }

  final path = segments(uri);
  final base = segments(root);
  return path != null &&
      base != null &&
      path.length >= base.length &&
      Iterable<int>.generate(base.length).every((i) => path[i] == base[i]);
}

bool hasOriginCredentials(http.BaseRequest request) =>
    request.url.userInfo.isNotEmpty ||
    request.headers.keys.any((key) => RegExp(
          r'authorization|authx|cookie|token|api[-_]?key|auth[-_]?key|secret',
          caseSensitive: false,
        ).hasMatch(key)) ||
    request.url.queryParameters.keys.any((key) => RegExp(
          r'token|api[-_]?key|auth[-_]?key|signature|credential',
          caseSensitive: false,
        ).hasMatch(key));
