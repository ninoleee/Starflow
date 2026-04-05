import 'package:starflow/core/storage/persistent_image_cache_api.dart';
import 'package:starflow/core/storage/persistent_image_cache_impl_stub.dart'
    if (dart.library.io) 'package:starflow/core/storage/persistent_image_cache_impl_io.dart'
    as impl;

PersistentImageCache get persistentImageCache => impl.createPersistentImageCache();
