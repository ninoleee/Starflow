import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:starflow/core/network/starflow_http_client.dart';
import 'package:starflow/core/network/bounded_http_request.dart';
import 'package:starflow/core/scheduling/async_work_pool.dart';
import 'package:starflow/core/network/starflow_http_transport.dart';
import 'package:starflow/core/storage/local_storage_models.dart';
import 'package:starflow/core/storage/persistent_image_cache_api.dart';
import 'package:starflow/core/utils/network_image_headers.dart';

PersistentImageCache createPersistentImageCache() => _IoPersistentImageCache();

class _IoPersistentImageCache implements PersistentImageCache {
  _IoPersistentImageCache()
      : _client = StarflowHttpClient(
          createStarflowTransportClient(),
          requestTimeout: _networkRequestTimeout,
        );

  static const int _maxMemoryEntries = 256;
  static const int _maxMemoryBytes = 72 * 1024 * 1024;
  static const Duration _diskEntryMaxAge = Duration(days: 30);
  static const Duration _networkRequestTimeout = Duration(seconds: 15);

  final http.Client _client;
  final _downloads = AsyncWorkPool(4);
  final Map<String, _ImageLoadLease> _loadLeases = {};

  Future<T> _withLoadLease<T>(String key, Future<void>? cancel,
      Future<T> Function(Future<void> abort) operation, VoidCallback onUnused) {
    final lease = _loadLeases.putIfAbsent(key, _ImageLoadLease.new);
    lease.users++;
    var released = false;
    void release() {
      if (released) return;
      released = true;
      lease.users--;
      if (lease.users == 0) {
        if (identical(_loadLeases[key], lease)) {
          _loadLeases.remove(key);
          onUnused();
        }
        if (!lease.abort.isCompleted) lease.abort.complete();
      }
    }
    if (cancel != null) unawaited(cancel.then((_) => release()));
    return operation(lease.abort.future).whenComplete(release);
  }
  final LinkedHashMap<String, _MemoryImageEntry> _memoryCache = LinkedHashMap();
  final Map<String, Future<Uint8List>> _inflight =
      <String, Future<Uint8List>>{};
  final Map<String, Future<ImageProvider<Object>>> _rasterProviderInflight =
      <String, Future<ImageProvider<Object>>>{};
  Future<Directory>? _directoryFuture;
  int _memoryBytes = 0;
  DateTime? _lastMaintenance;

  void _scheduleDiskMaintenance() {
    final now = DateTime.now();
    if (_lastMaintenance != null &&
        now.difference(_lastMaintenance!) < const Duration(hours: 1)) {
      return;
    }
    _lastMaintenance = now;
    unawaited(_pruneDisk().catchError((Object _) {}));
  }

  Future<void> _pruneDisk() async {
    final directory = await _cacheDirectory();
    final entries = <({File file, FileStat stat})>[];
    var total = 0;
    final now = DateTime.now();
    await for (final entry in directory.list()) {
      if (entry is! File || !entry.path.endsWith('.bin')) continue;
      final stat = await entry.stat();
      entries.add((file: entry, stat: stat));
      total += stat.size;
    }
    entries.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
    for (final entry in entries) {
      final age = now.difference(entry.stat.modified);
      if (age < const Duration(minutes: 5)) continue;
      if (total <= 512 * 1024 * 1024 && age <= _diskEntryMaxAge) continue;
      await _deleteIfExists(entry.file);
      await _deleteIfExists(File(entry.file.path.replaceFirst(RegExp(r'\.bin$'), '.json')));
      total -= entry.stat.size;
    }
  }

  @override
  Future<void> clear() async {
    _memoryCache.clear();
    _inflight.clear();
    _rasterProviderInflight.clear();
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
  Future<void> evict(
    String url, {
    Map<String, String>? headers,
  }) async {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) {
      return;
    }
    final cacheKey = _cacheIdentity(trimmedUrl, headers);
    final memoryEntry = _memoryCache.remove(cacheKey);
    if (memoryEntry != null) {
      _memoryBytes -= memoryEntry.bytes.lengthInBytes;
    }
    _inflight.remove(cacheKey);
    _rasterProviderInflight.remove(cacheKey);
    await _deleteIfExists(await _cacheFile(cacheKey));
    await _deleteIfExists(await _cacheMetadataFile(cacheKey));
  }

  @override
  Future<Uint8List> load(
    String url, {
    Map<String, String>? headers,
    bool persist = true,
    Future<void>? cancel,
  }) => _withLoadLease('bytes:$persist:${_cacheIdentity(url.trim(), headers)}', cancel,
      (abort) => _loadBytes(url, headers: headers, persist: persist, cancel: abort),
      () { if (persist) _inflight.remove(_cacheIdentity(url.trim(), headers)); });

  Future<Uint8List> _loadBytes(
    String url, {
    Map<String, String>? headers,
    bool persist = true,
    required Future<void> cancel,
  }) async {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) {
      throw StateError('Image URL is empty.');
    }
    if (!persist) {
      return _fetchNetworkBytes(
        url: trimmedUrl,
        headers: headers,
        cancel: cancel,
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
      cancel: cancel,
    );
    _inflight[cacheKey] = future;
    unawaited(
      future.then<void>(
        (_) {
          if (identical(_inflight[cacheKey], future)) {
            _inflight.remove(cacheKey);
          }
        },
        onError: (Object _, StackTrace __) {
          if (identical(_inflight[cacheKey], future)) {
            _inflight.remove(cacheKey);
          }
        },
      ),
    );
    return future;
  }

  @override
  Future<ImageProvider<Object>> resolveRasterProvider(
    String url, {
    Map<String, String>? headers,
    bool persist = true,
    Future<void>? cancel,
  }) => _withLoadLease('raster:$persist:${_cacheIdentity(url.trim(), headers)}', cancel,
      (abort) => _resolveRaster(url, headers: headers, persist: persist, cancel: abort),
      () { if (persist) _rasterProviderInflight.remove(_cacheIdentity(url.trim(), headers)); });

  Future<ImageProvider<Object>> _resolveRaster(
    String url, {
    Map<String, String>? headers,
    bool persist = true,
    required Future<void> cancel,
  }) async {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) {
      throw StateError('Image URL is empty.');
    }
    final normalizedHeaders = _normalizeHeaders(headers);
    if (!persist) {
      final bytes = await _fetchNetworkBytes(
        url: trimmedUrl,
        headers: normalizedHeaders,
        cancel: cancel,
      );
      return MemoryImage(bytes);
    }

    final cacheKey = _cacheIdentity(trimmedUrl, normalizedHeaders);
    final inflight = _rasterProviderInflight[cacheKey];
    if (inflight != null) {
      return inflight;
    }

    final future = _resolvePersistentRasterProvider(
      cacheKey: cacheKey,
      url: trimmedUrl,
      headers: normalizedHeaders,
      cancel: cancel,
    );
    _rasterProviderInflight[cacheKey] = future;
    unawaited(
      future.then<void>(
        (_) {
          if (identical(_rasterProviderInflight[cacheKey], future)) {
            _rasterProviderInflight.remove(cacheKey);
          }
        },
        onError: (Object _, StackTrace __) {
          if (identical(_rasterProviderInflight[cacheKey], future)) {
            _rasterProviderInflight.remove(cacheKey);
          }
        },
      ),
    );
    return future;
  }

  Future<Uint8List> _loadOrFetch({
    required Future<void> cancel,
    required String cacheKey,
    required String url,
    required Map<String, String>? headers,
  }) async {
    final file = await _cacheFile(cacheKey);
    final metadataFile = await _cacheMetadataFile(cacheKey);
    final metadata = await _loadMetadata(metadataFile);
    final diskBytes = await _readDiskImage(file);
    final isFresh = await _isDiskEntryFresh(metadata, file);

    if (diskBytes != null && isFresh) {
      _remember(cacheKey, diskBytes);
      return diskBytes;
    }

    final staleBytes = diskBytes;

    try {
      final bytes = await _fetchNetworkBytes(
        url: url,
        headers: headers,
        cancel: cancel,
      );
      await file.writeAsBytes(bytes, flush: false);
      await _saveMetadata(metadataFile, _buildMetadata());
      _scheduleDiskMaintenance();
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

  Future<ImageProvider<Object>> _resolvePersistentRasterProvider({
    required Future<void> cancel,
    required String cacheKey,
    required String url,
    required Map<String, String> headers,
  }) async {
    final file = await _ensurePersistentFile(
      cancel: cancel,
      cacheKey: cacheKey,
      url: url,
      headers: headers,
    );
    return FileImage(file);
  }

  Future<File> _ensurePersistentFile({
    required Future<void> cancel,
    required String cacheKey,
    required String url,
    required Map<String, String> headers,
  }) async {
    final file = await _cacheFile(cacheKey);
    final metadataFile = await _cacheMetadataFile(cacheKey);
    final metadata = await _loadMetadata(metadataFile);
    final hasDiskEntry = await file.exists();
    final isFresh = hasDiskEntry && await _isDiskEntryFresh(metadata, file);

    if (isFresh) {
      return file;
    }

    final staleFile = hasDiskEntry ? file : null;

    try {
      final bytes = await _fetchNetworkBytes(
        url: url,
        headers: headers,
        cancel: cancel,
      );
      await file.writeAsBytes(bytes, flush: false);
      await _saveMetadata(metadataFile, _buildMetadata());
      _scheduleDiskMaintenance();
      return file;
    } catch (_) {
      if (staleFile != null && await staleFile.exists()) {
        return staleFile;
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
    required Future<void> cancel,
    required String url,
    required Map<String, String>? headers,
  }) async {
    var cancelled = false;
    unawaited(cancel.then((_) => cancelled = true));
    return _downloads.run(() async {
      if (cancelled) throw http.RequestAbortedException(Uri.parse(url));
      final response = await sendBoundedRequest(
        _client, 'GET', Uri.parse(url), headers: headers,
        timeout: _networkRequestTimeout, maxBytes: 32 * 1024 * 1024,
        cancel: cancel,
      );
      return validateNetworkImageHttpResponse(response, url: url);
    });
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

  Future<bool> _isDiskEntryFresh(Map<String, dynamic>? metadata, File file) async {
    final now = DateTime.now().toUtc();
    final updatedAt = await _resolveEntryUpdatedAt(metadata, file);
    return now.difference(updatedAt) <= _diskEntryMaxAge;
  }

  Future<DateTime> _resolveEntryUpdatedAt(Map<String, dynamic>? metadata, File file) async {
    final updatedAtMillis = (metadata?['updatedAt'] as num?)?.toInt() ?? 0;
    if (updatedAtMillis > 0) {
      return DateTime.fromMillisecondsSinceEpoch(
        updatedAtMillis,
        isUtc: true,
      );
    }
    final stat = await file.stat();
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

class _ImageLoadLease {
  final abort = Completer<void>();
  int users = 0;
}

String _stableHash(String value) {
  var hash = 0xcbf29ce484222325;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
  }
  return hash.toRadixString(16);
}
