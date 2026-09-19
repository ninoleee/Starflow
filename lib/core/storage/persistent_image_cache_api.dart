import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:starflow/core/storage/local_storage_models.dart';

abstract class PersistentImageCache {
  /// Release only compressed memory entries; disk and active loads survive.
  void clearMemory() {}

  Future<Uint8List> load(
    String url, {
    Map<String, String>? headers,
    bool persist = true,
    Future<void>? cancel,
  });

  Future<ImageProvider<Object>> resolveRasterProvider(
    String url, {
    Map<String, String>? headers,
    bool persist = true,
    Future<void>? cancel,
  });

  Future<void> evict(
    String url, {
    Map<String, String>? headers,
  });

  Future<LocalStorageCacheSummary> inspect();

  Future<void> clear();
}
