import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:starflow/core/storage/local_storage_models.dart';
import 'package:starflow/core/storage/persistent_image_cache_api.dart';
import 'package:starflow/core/utils/network_image_headers.dart';

PersistentImageCache createPersistentImageCache() => _IoPersistentImageCache();

class _IoPersistentImageCache implements PersistentImageCache {
  _IoPersistentImageCache() : _client = http.Client();

  static const int _maxMemoryEntries = 256;
  static const int _maxMemoryBytes = 72 * 1024 * 1024;
  static const Duration _diskEntryMaxAge = Duration(days: 30);

  final http.Client _client;
  final LinkedHashMap<String, _MemoryImageEntry> _memoryCache = LinkedHashMap();
  final Map<String, Future<Uint8List>> _inflight =
      <String, Future<Uint8List>>{};
  Future<Directory>? _directoryFuture;
  int _memoryBytes = 0;

  @override
  Future<void> clear() async {
    _memoryCache.clear();
    _memoryBytes = 0;
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
      if (!entity.path.toLowerCase().endsWith('.bin')) {
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
    bool persist = true,
  }) async {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) {
      throw StateError('Image URL is empty.');
    }
    if (!persist) {
      return _fetchNetworkBytes(
        url: trimmedUrl,
        headers: headers,
      );
    }
    final cacheKey = _cacheIdentity(trimmedUrl, headers);
    final memoryCached = _memoryCache.remove(cacheKey);
    if (memoryCached != null) {
      _memoryCache[cacheKey] = memoryCached;
      return SynchronousFuture<Uint8List>(memoryCached.bytes);
    }

    final inflight = _inflight[cacheKey];
    if (inflight != null) {
      return inflight;
    }

    final future = _loadOrFetch(
      cacheKey: cacheKey,
      url: trimmedUrl,
      headers: headers,
    );
    _inflight[cacheKey] = future;
    future.whenComplete(() {
      _inflight.remove(cacheKey);
    });
    return future;
  }

  Future<Uint8List> _loadOrFetch({
    required String cacheKey,
    required String url,
    required Map<String, String>? headers,
  }) async {
    final file = await _cacheFile(cacheKey);
    final metadataFile = await _cacheMetadataFile(cacheKey);
    final metadata = await _loadMetadata(metadataFile);
    final diskBytes = await _readDiskImage(file);
    final isFresh = _isDiskEntryFresh(metadata, file);

    if (diskBytes != null && isFresh) {
      _remember(cacheKey, diskBytes);
      return diskBytes;
    }

    final staleBytes = diskBytes;
    if (await file.exists()) {
      await _deleteIfExists(file);
      await _deleteIfExists(metadataFile);
    }

    try {
      final bytes = await _fetchNetworkBytes(
        url: url,
        headers: headers,
      );
      await file.writeAsBytes(bytes, flush: false);
      await _saveMetadata(metadataFile, _buildMetadata());
      _remember(cacheKey, bytes);
      return bytes;
    } catch (_) {
      if (staleBytes != null && staleBytes.isNotEmpty) {
        _remember(cacheKey, staleBytes);
        return staleBytes;
      }
      rethrow;
    }
  }

  Future<Uint8List?> _readDiskImage(File file) async {
    if (!await file.exists()) {
      return null;
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || !looksLikeNetworkImageBytes(bytes)) {
      await _deleteIfExists(file);
      return null;
    }
    return bytes;
  }

  Future<Uint8List> _fetchNetworkBytes({
    required String url,
    required Map<String, String>? headers,
  }) async {
    final response = await _client.get(Uri.parse(url), headers: headers);
    return validateNetworkImageHttpResponse(response, url: url);
  }

  void _remember(String cacheKey, Uint8List bytes) {
    final existing = _memoryCache.remove(cacheKey);
    if (existing != null) {
      _memoryBytes -= existing.bytes.lengthInBytes;
    }
    final entry = _MemoryImageEntry(bytes);
    _memoryCache[cacheKey] = entry;
    _memoryBytes += entry.bytes.lengthInBytes;
    while (_memoryCache.length > _maxMemoryEntries ||
        _memoryBytes > _maxMemoryBytes) {
      final oldestKey = _memoryCache.keys.first;
      final removed = _memoryCache.remove(oldestKey);
      if (removed != null) {
        _memoryBytes -= removed.bytes.lengthInBytes;
      }
    }
  }

  Future<File> _cacheFile(String cacheKey) async {
    final directory = await _cacheDirectory();
    return File('${directory.path}/${_stableHash(cacheKey)}.bin');
  }

  Future<File> _cacheMetadataFile(String cacheKey) async {
    final directory = await _cacheDirectory();
    return File('${directory.path}/${_stableHash(cacheKey)}.json');
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

  String _cacheIdentity(String url, Map<String, String>? headers) {
    final normalizedHeaders = _normalizeHeaders(headers);
    if (normalizedHeaders.isEmpty) {
      return url;
    }
    final buffer = StringBuffer(url);
    for (final entry in normalizedHeaders.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key))) {
      buffer
        ..write('\n')
        ..write(entry.key)
        ..write(':')
        ..write(entry.value);
    }
    return buffer.toString();
  }

  Map<String, String> _normalizeHeaders(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) {
      return const <String, String>{};
    }
    final normalized = <String, String>{};
    for (final entry in headers.entries) {
      final key = entry.key.trim().toLowerCase();
      final value = entry.value.trim();
      if (key.isEmpty || value.isEmpty) {
        continue;
      }
      normalized[key] = value;
    }
    return normalized;
  }

  Future<Map<String, dynamic>?> _loadMetadata(File metadataFile) async {
    if (!await metadataFile.exists()) {
      return null;
    }
    try {
      final raw = await metadataFile.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      await _deleteIfExists(metadataFile);
    }
    return null;
  }

  Map<String, dynamic> _buildMetadata() {
    return <String, dynamic>{
      'updatedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
    };
  }

  Future<void> _saveMetadata(
    File metadataFile,
    Map<String, dynamic> metadata,
  ) async {
    await metadataFile.writeAsString(
      jsonEncode(metadata),
      flush: false,
    );
  }

  bool _isDiskEntryFresh(Map<String, dynamic>? metadata, File file) {
    final now = DateTime.now().toUtc();
    final updatedAt = _resolveEntryUpdatedAt(metadata, file);
    return now.difference(updatedAt) <= _diskEntryMaxAge;
  }

  DateTime _resolveEntryUpdatedAt(Map<String, dynamic>? metadata, File file) {
    final updatedAtMillis = (metadata?['updatedAt'] as num?)?.toInt() ?? 0;
    if (updatedAtMillis > 0) {
      return DateTime.fromMillisecondsSinceEpoch(
        updatedAtMillis,
        isUtc: true,
      );
    }
    final stat = file.statSync();
    return stat.modified.toUtc();
  }

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}

class _MemoryImageEntry {
  const _MemoryImageEntry(this.bytes);

  final Uint8List bytes;
}

String _stableHash(String value) {
  var hash = 0xcbf29ce484222325;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
  }
  return hash.toRadixString(16);
}
