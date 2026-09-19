import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/core/network/bounded_http_request.dart';
import 'package:starflow/core/scheduling/async_work_pool.dart';
import 'package:starflow/core/network/starflow_http_client.dart';
import 'package:starflow/core/network/starflow_http_transport.dart';
import 'package:starflow/core/storage/local_storage_models.dart';
import 'package:starflow/core/storage/persistent_image_cache_api.dart';
import 'package:starflow/core/utils/network_image_headers.dart';

PersistentImageCache createPersistentImageCache() => _StubPersistentImageCache(
      StarflowHttpClient(createStarflowTransportClient()),
    );

class _StubPersistentImageCache implements PersistentImageCache {
  _StubPersistentImageCache(this._client);

  final http.Client _client;
  final _downloads = AsyncWorkPool(4);

  @override
  Future<void> clear() async {}

  @override
  Future<void> evict(
    String url, {
    Map<String, String>? headers,
  }) async {}

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
    Future<void>? cancel,
  }) async {
    final response = await _downloads.run(() => sendBoundedRequest(
      _client, 'GET', Uri.parse(url), headers: headers, cancel: cancel,
      timeout: const Duration(seconds: 15), maxBytes: 32 * 1024 * 1024,
    ));
    return validateNetworkImageHttpResponse(response, url: url);
  }

  @override
  Future<ImageProvider<Object>> resolveRasterProvider(
    String url, {
    Map<String, String>? headers,
    bool persist = true,
    Future<void>? cancel,
  }) async {
    return MemoryImage(await load(url, headers: headers, persist: persist, cancel: cancel));
  }
}
