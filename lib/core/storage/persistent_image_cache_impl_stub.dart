import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:starflow/core/network/starflow_http_client.dart';
import 'package:starflow/core/storage/local_storage_models.dart';
import 'package:starflow/core/storage/persistent_image_cache_api.dart';

PersistentImageCache createPersistentImageCache() =>
    _StubPersistentImageCache(StarflowHttpClient(http.Client()));

class _StubPersistentImageCache implements PersistentImageCache {
  _StubPersistentImageCache(this._client);

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
    final contentType = response.headers['content-type'] ?? '';
    if (!_looksLikeImageResponse(contentType, bytes)) {
      throw StateError('Image response is not a decodable image: $url');
    }
    return bytes;
  }
}

bool _looksLikeImageResponse(String contentType, Uint8List bytes) {
  final normalized = contentType.toLowerCase();
  if (normalized.startsWith('image/')) {
    return true;
  }
  return _looksLikeImageBytes(bytes);
}

bool _looksLikeImageBytes(Uint8List bytes) {
  if (bytes.length < 12) {
    return false;
  }

  final isJpeg =
      bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
  final isPng = bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47;
  final isGif = bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x38;
  final isBmp = bytes[0] == 0x42 && bytes[1] == 0x4D;
  final isWebp = bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50;
  final isAvif = bytes.length >= 12 &&
      bytes[4] == 0x66 &&
      bytes[5] == 0x74 &&
      bytes[6] == 0x79 &&
      bytes[7] == 0x70 &&
      ((bytes[8] == 0x61 &&
              bytes[9] == 0x76 &&
              bytes[10] == 0x69 &&
              bytes[11] == 0x66) ||
          (bytes[8] == 0x61 &&
              bytes[9] == 0x76 &&
              bytes[10] == 0x69 &&
              bytes[11] == 0x73));
  return isJpeg || isPng || isGif || isBmp || isWebp || isAvif;
}
