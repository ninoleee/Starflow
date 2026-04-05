import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:starflow/core/storage/local_storage_models.dart';
import 'package:starflow/core/storage/persistent_image_cache_api.dart';

PersistentImageCache createPersistentImageCache() => _IoPersistentImageCache();

class _IoPersistentImageCache implements PersistentImageCache {
  _IoPersistentImageCache() : _client = http.Client();

  static const int _maxMemoryEntries = 96;

  final http.Client _client;
  final LinkedHashMap<String, Uint8List> _memoryCache = LinkedHashMap();
  final Map<String, Future<Uint8List>> _inflight = <String, Future<Uint8List>>{};
  Future<Directory>? _directoryFuture;

  @override
  Future<void> clear() async {
    _memoryCache.clear();
    final directory = await _cacheDirectory();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
    _directoryFuture = null;
  }

  @override
  Future<LocalStorageCacheSummary> inspect() async {
    final directory = await _cacheDirectory();
    if (!await directory.exists()) {
      return const LocalStorageCacheSummary(
        type: LocalStorageCacheType.images,
        entryCount: 0,
        totalBytes: 0,
      );
    }

    var count = 0;
    var bytes = 0;
    await for (final entity in directory.list()) {
      if (entity is! File) {
        continue;
      }
      count += 1;
      bytes += await entity.length();
    }

    return LocalStorageCacheSummary(
      type: LocalStorageCacheType.images,
      entryCount: count,
      totalBytes: bytes,
    );
  }

  @override
  Future<Uint8List> load(
    String url, {
    Map<String, String>? headers,
  }) async {
    final trimmedUrl = url.trim();
    final memoryCached = _memoryCache.remove(trimmedUrl);
    if (memoryCached != null) {
      _memoryCache[trimmedUrl] = memoryCached;
      return SynchronousFuture<Uint8List>(memoryCached);
    }

    final inflight = _inflight[trimmedUrl];
    if (inflight != null) {
      return inflight;
    }

    final future = _loadOrFetch(trimmedUrl, headers);
    _inflight[trimmedUrl] = future;
    future.whenComplete(() {
      _inflight.remove(trimmedUrl);
    });
    return future;
  }

  Future<Uint8List> _loadOrFetch(
    String url,
    Map<String, String>? headers,
  ) async {
    final file = await _cacheFile(url);
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      if (bytes.isNotEmpty) {
        _remember(url, bytes);
        return bytes;
      }
    }

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

    await file.writeAsBytes(bytes, flush: false);
    _remember(url, bytes);
    return bytes;
  }

  void _remember(String url, Uint8List bytes) {
    _memoryCache.remove(url);
    _memoryCache[url] = bytes;
    if (_memoryCache.length > _maxMemoryEntries) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
  }

  Future<File> _cacheFile(String url) async {
    final directory = await _cacheDirectory();
    return File('${directory.path}/${_stableHash(url)}.bin');
  }

  Future<Directory> _cacheDirectory() {
    return _directoryFuture ??= () async {
      final baseDirectory = await getApplicationSupportDirectory();
      final directory = Directory('${baseDirectory.path}/starflow-image-cache');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return directory;
    }();
  }
}

String _stableHash(String value) {
  var hash = 0xcbf29ce484222325;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
  }
  return hash.toRadixString(16);
}
