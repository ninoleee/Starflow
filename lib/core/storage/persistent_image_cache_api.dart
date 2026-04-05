import 'dart:typed_data';

import 'package:starflow/core/storage/local_storage_models.dart';

abstract class PersistentImageCache {
  Future<Uint8List> load(
    String url, {
    Map<String, String>? headers,
  });

  Future<LocalStorageCacheSummary> inspect();

  Future<void> clear();
}
