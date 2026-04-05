import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:starflow/core/storage/local_storage_models.dart';
import 'package:starflow/core/storage/persistent_image_cache_api.dart';

PersistentImageCache createPersistentImageCache() => _StubPersistentImageCache();

class _StubPersistentImageCache implements PersistentImageCache {
  _StubPersistentImageCache() : _client = http.Client();

  final http.Client _client;

  @override
  Future<void> clear() async {}

  @override
  Future<LocalStorageCacheSummary> inspect() async {
    return const LocalStorageCacheSummary(
      type: LocalStorageCacheType.images,
      entryCount: 0,
      totalBytes: 0,
    );
  }

  @override
  Future<Uint8List> load(
    String url, {
    Map<String, String>? headers,
  }) async {
    final response = await _client.get(Uri.parse(url), headers: headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'HTTP request failed, statusCode: ${response.statusCode}, $url',
      );
    }
    final bytes = response.bodyBytes;
    if (bytes.isEmpty) {
      throw StateError('Image response body is empty: $url');
    }
    return bytes;
  }
}
