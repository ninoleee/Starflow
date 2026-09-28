import 'dart:convert';

/// Older libmpv builds expose this node as JSON, but cannot read its subpaths.
Future<int?> readMpvForwardCacheBytes(
  Future<String> Function(String) readProperty,
) async {
  try {
    final state = jsonDecode(await readProperty('demuxer-cache-state'));
    if (state is! Map<String, dynamic>) return null;
    final bytes = state['fw-bytes'];
    if (bytes is! num || !bytes.isFinite || bytes < 0) return null;
    return bytes.round();
  } catch (_) {
    return null;
  }
}
