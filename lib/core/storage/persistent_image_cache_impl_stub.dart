import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/core/network/starflow_http_client.dart';
import 'package:starflow/core/storage/local_storage_models.dart';
import 'package:starflow/core/storage/persistent_image_cache_api.dart';
import 'package:starflow/core/utils/network_image_headers.dart';

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
    bool persist = true,
  }) async {
    final response = await _client.get(Uri.parse(url), headers: headers);
    return validateNetworkImageHttpResponse(response, url: url);
  }

  @override
  Future<ImageProvider<Object>> resolveRasterProvider(
    String url, {
    Map<String, String>? headers,
    bool persist = true,
  }) async {
    return NetworkImage(
      url,
      headers: headers == null || headers.isEmpty ? null : headers,
    );
  }
}
