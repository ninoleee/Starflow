import 'package:starflow/features/library/data/nfo_metadata.dart';
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/core/network/starflow_http_client.dart';
import 'package:starflow/core/network/bounded_http_request.dart';
import 'package:starflow/core/network/http_origin_policy.dart';
import 'package:starflow/features/library/data/season_folder_label_parser.dart';
import 'package:starflow/features/library/data/nas_media_path_policy.dart';
import 'package:starflow/features/library/data/external_media_structure.dart';
import 'package:starflow/features/library/data/webdav_directory_cache_store.dart';
import 'package:starflow/features/library/domain/media_naming.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/domain/nas_media_recognition.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:xml/xml.dart';

part 'webdav_nas_client_sidecar.dart';
part 'webdav_nas_client_structure.dart';
part 'webdav_nas_client_models.dart';
part 'webdav_nas_client_background.dart';

final webDavNasClientProvider = Provider<WebDavNasClient>((ref) {
  final client = ref.watch(starflowHttpClientProvider);
  return WebDavNasClient(
    client,
    directoryCacheStore: ref.read(webDavDirectoryCacheStoreProvider),
  );
});

class WebDavNasClient {
  WebDavNasClient(
    this._client, {
    WebDavDirectoryCacheStore? directoryCacheStore,
  }) : _directoryCacheStore = directoryCacheStore;

  static const int _maxConcurrentDirectoryWalks = 2;
  static const int _maxConcurrentFilePreparations = 4;

  final http.Client _client;
  final WebDavDirectoryCacheStore? _directoryCacheStore;
  final Map<String, ParsedNfoMetadata?> _nfoCache =
      <String, ParsedNfoMetadata?>{};
  final Map<String, Future<ParsedNfoMetadata?>> _nfoInflight =
      <String, Future<ParsedNfoMetadata?>>{};
  final Map<String, List<_WebDavEntry>> _directoryCache =
      <String, List<_WebDavEntry>>{};
  final Map<String, Future<List<_WebDavEntry>>> _directoryInflight =
      <String, Future<List<_WebDavEntry>>>{};
  final Map<String, _WebDavSidecarDirectoryContext> _sidecarDirectoryCache =
      <String, _WebDavSidecarDirectoryContext>{};
  final Map<String, Future<_WebDavSidecarDirectoryContext>>
      _sidecarDirectoryInflight =
      <String, Future<_WebDavSidecarDirectoryContext>>{};
  final Map<String, _DirectorySubtreeCacheEntry> _directorySubtreeCache =
      <String, _DirectorySubtreeCacheEntry>{};

  void clearMemoryCaches() {
    _resetScanCaches();
  }

  Future<List<MediaCollection>> fetchCollections(
    MediaSourceConfig source, {
    String? directoryId,
  }) async {
    final endpoint = source.endpoint.trim();
    if (endpoint.isEmpty) {
      return const [];
    }

    final rootUri = Uri.parse(
      directoryId?.trim().isNotEmpty == true
          ? directoryId!.trim()
          : _browseRoot(source),
    );
    if (_isExcludedByKeyword(rootUri, source: source)) {
      return const [];
    }

    final entries = _filterExcludedEntries(
      await _propfind(rootUri, source: source),
      source: source,
    );
    final collections = entries
        .where((entry) => !entry.isSelf && entry.isCollection)
        .map(
          (entry) => MediaCollection(
            id: entry.uri.toString(),
            title: entry.name,
            sourceId: source.id,
            sourceName: source.name,
            sourceKind: source.kind,
            subtitle: 'WebDAV 目录',
          ),
        )
        .toList();

    return collections;
  }

  Future<List<MediaItem>> fetchLibrary(
    MediaSourceConfig source, {
    String? sectionId,
    String sectionName = '',
    int limit = 200,
  }) async {
    final scannedItems = await scanLibrary(
      source,
      sectionId: sectionId,
      sectionName: sectionName,
      limit: limit,
    );
    return scannedItems
        .map((item) => item.toMediaItem(source))
        .toList(growable: false);
  }

  Future<List<WebDavScannedItem>> scanLibrary(
    MediaSourceConfig source, {
    String? sectionId,
    String sectionName = '',
    int limit = 200,
    bool? loadSidecarMetadata,
    bool resolvePlayableStreams = true,
    bool resetCaches = true,
    bool Function()? shouldCancel,
  }) async {
    final scanStopwatch = Stopwatch()..start();
    if (resetCaches) {
      _resetScanCaches();
    }
    final endpoint = source.endpoint.trim();
    if (endpoint.isEmpty) {
      return const [];
    }
    final shouldLoadSidecarMetadata =
        loadSidecarMetadata ?? source.webDavSidecarScrapingEnabled;

    final rootUri = Uri.parse(
      sectionId?.trim().isNotEmpty == true
          ? sectionId!.trim()
          : _browseRoot(source),
    );
    if (_isExcludedByKeyword(rootUri, source: source)) {
      return const [];
    }
    final collectionId = rootUri.toString();
    final collectionName = sectionName.trim().isEmpty
        ? _displayNameFromUri(rootUri, fallback: source.name)
        : sectionName.trim();

    appLogTrace(
      'library.scan',
      'WebDAV directory scan started',
      fields: <String, Object?>{
        'sourceId': source.id,
        'sectionScoped': sectionId?.trim().isNotEmpty == true,
        'itemLimit': limit,
        'structureInference': source.webDavStructureInferenceEnabled,
      },
    );

    final visited = <String>{};

    Future<_PendingWebDavScannedItem?> resolvePendingItem(
      _WebDavEntry entry,
      List<_WebDavEntry> siblings,
    ) async {
      if (_isExcludedByKeyword(entry.uri, source: source)) {
        return null;
      }
      if (!_isPlayableVideo(entry)) {
        return null;
      }
      final metadata = shouldLoadSidecarMetadata
          ? await _resolveSidecarMetadata(
              entry,
              siblings: siblings,
              source: source,
            )
          : _buildBasicMetadataSeed(entry);
      _throwIfCancelled(shouldCancel);
      final resolvedPlayable = await _resolvePlayableSource(
        entry,
        source: source,
        resolveStrmTarget: resolvePlayableStreams,
      );
      _throwIfCancelled(shouldCancel);
      if (resolvedPlayable.streamUrl.trim().isEmpty) {
        return null;
      }
      final pendingItem = _PendingWebDavScannedItem(
        resourceId: entry.uri.toString(),
        fileName: entry.name,
        actualAddress: _relativePathForNasDisplay(entry.uri, source: source),
        sectionId: collectionId,
        sectionName: collectionName,
        streamUrl: resolvedPlayable.streamUrl,
        streamHeaders: resolvedPlayable.headers,
        addedAt: entry.modifiedAt ?? DateTime.now(),
        modifiedAt: entry.modifiedAt,
        fileSizeBytes: entry.sizeBytes,
        metadataSeed: metadata,
        relativeDirectories: _relativeDirectorySegmentsFromRoot(
          fileUri: entry.uri,
          rootUri: rootUri,
        ),
      );

      return pendingItem;
    }

    Future<_DirectoryWalkResult> walk(
      Uri uri,
      int depth,
      int remaining, {
      DateTime? directoryModifiedAt,
      String directoryEtag = '',
    }) async {
      _throwIfCancelled(shouldCancel);
      if (remaining <= 0) {
        return const _DirectoryWalkResult(truncated: true);
      }
      if (depth > 8) {
        return const _DirectoryWalkResult(truncated: true);
      }
      if (!visited.add(uri.toString())) {
        return const _DirectoryWalkResult();
      }
      if (_isExcludedByKeyword(uri, source: source)) {
        return const _DirectoryWalkResult();
      }

      final cachedSubtree = await _loadCachedDirectorySubtree(
        source: source,
        uri: uri,
        includeSidecarMetadata: shouldLoadSidecarMetadata,
        directoryModifiedAt: directoryModifiedAt,
        directoryEtag: directoryEtag,
      );
      if (cachedSubtree != null) {
        final rebasedItems = _rebasePendingItemsForRoot(
          cachedSubtree.items,
          rootUri: rootUri,
          sectionId: collectionId,
          sectionName: collectionName,
        );
        final truncated = rebasedItems.length > remaining;
        final items = truncated
            ? rebasedItems.take(remaining).toList(growable: false)
            : rebasedItems;

        return _DirectoryWalkResult(
          items: items,
          truncated: truncated,
        );
      }

      final entries = _filterExcludedEntries(
        await _propfind(uri, source: source),
        source: source,
      );
      _throwIfCancelled(shouldCancel);
      _directoryCache[_webDavCacheKey(source, uri)] = entries;
      final directoryEntries =
          entries.where((entry) => !entry.isSelf).toList(growable: false);
      final collected = <_PendingWebDavScannedItem>[];
      final fileResultFutures = <int, Future<_PendingWebDavScannedItem?>>{};
      final childDirectoryResults = <int, Future<_DirectoryWalkResult>>{};
      final activeDirectoryTasks = <Future<void>>[];
      final activeFileTasks = <Future<void>>[];
      var truncated = false;

      for (var entryIndex = 0;
          entryIndex < directoryEntries.length;
          entryIndex++) {
        final entry = directoryEntries[entryIndex];
        _throwIfCancelled(shouldCancel);
        if (entry.isCollection) {
          final childResult = walk(
            entry.uri,
            depth + 1,
            remaining,
            directoryModifiedAt: entry.modifiedAt,
            directoryEtag: entry.etag,
          );
          childDirectoryResults[entryIndex] = childResult;
          late final Future<void> completion;
          completion = childResult
              .then<void>(
            (_) {},
            onError: (Object _, StackTrace __) {},
          )
              .whenComplete(() {
            activeDirectoryTasks.remove(completion);
          });
          activeDirectoryTasks.add(completion);
          if (activeDirectoryTasks.length >= _maxConcurrentDirectoryWalks) {
            await Future.any(activeDirectoryTasks);
            _throwIfCancelled(shouldCancel);
          }
          continue;
        }
        final fileResult = resolvePendingItem(entry, directoryEntries);
        fileResultFutures[entryIndex] = fileResult;
        late final Future<void> completion;
        completion = fileResult
            .then<void>(
          (_) {},
          onError: (Object _, StackTrace __) {},
        )
            .whenComplete(() {
          activeFileTasks.remove(completion);
        });
        activeFileTasks.add(completion);
        if (activeFileTasks.length >= _maxConcurrentFilePreparations) {
          await Future.any(activeFileTasks);
          _throwIfCancelled(shouldCancel);
        }
      }

      for (var entryIndex = 0;
          entryIndex < directoryEntries.length;
          entryIndex++) {
        _throwIfCancelled(shouldCancel);
        final remainingForEntry = remaining - collected.length;
        if (remainingForEntry <= 0) {
          truncated = true;
          break;
        }

        final pendingFileFuture = fileResultFutures[entryIndex];
        if (pendingFileFuture != null) {
          final pendingFile = await pendingFileFuture;
          if (pendingFile != null) {
            collected.add(pendingFile);
            continue;
          }
        }

        final childResultFuture = childDirectoryResults[entryIndex];
        if (childResultFuture == null) {
          continue;
        }
        final childResult = await childResultFuture;
        _throwIfCancelled(shouldCancel);
        if (childResult.items.length > remainingForEntry) {
          collected.addAll(
            childResult.items.take(remainingForEntry),
          );
          truncated = true;
        } else {
          collected.addAll(childResult.items);
        }
        truncated = truncated || childResult.truncated;
      }

      if (!truncated &&
          (directoryModifiedAt != null || directoryEtag.trim().isNotEmpty)) {
        _storeCachedDirectorySubtree(
          source: source,
          uri: uri,
          includeSidecarMetadata: shouldLoadSidecarMetadata,
          directoryModifiedAt: directoryModifiedAt,
          directoryEtag: directoryEtag,
          items: _rebasePendingItemsForRoot(
            collected,
            rootUri: uri,
            sectionId: collectionId,
            sectionName: collectionName,
          ),
        );
      }
      return _DirectoryWalkResult(
        items: collected,
        truncated: truncated,
      );
    }

    final walkResult = await walk(rootUri, 0, limit);
    _throwIfCancelled(shouldCancel);
    final pendingItems = walkResult.items;
    appLogTrace(
      'library.scan',
      'WebDAV directory walk completed',
      fields: <String, Object?>{
        'sourceId': source.id,
        'directoryCount': visited.length,
        'pendingItemCount': pendingItems.length,
        'truncated': walkResult.truncated,
        'durationMs': scanStopwatch.elapsedMilliseconds,
      },
    );

    var resolvedPendingItems = pendingItems;
    if (source.webDavStructureInferenceEnabled && pendingItems.isNotEmpty) {
      final structureStopwatch = Stopwatch()..start();
      appLogTrace(
        'library.scan',
        'WebDAV structure inference started',
        fields: <String, Object?>{
          'sourceId': source.id,
          'itemCount': pendingItems.length,
        },
      );
      resolvedPendingItems = await _applyStructureInferenceInBackground(
        pendingItems,
        source: source,
      );
      _throwIfCancelled(shouldCancel);
      appLogTrace(
        'library.scan',
        'WebDAV structure inference completed',
        fields: <String, Object?>{
          'sourceId': source.id,
          'itemCount': resolvedPendingItems.length,
          'durationMs': structureStopwatch.elapsedMilliseconds,
          'backgroundIsolate': !kIsWeb && pendingItems.length >= 32,
        },
      );
    }

    final items = <WebDavScannedItem>[];
    for (var index = 0; index < resolvedPendingItems.length; index++) {
      items.add(resolvedPendingItems[index].toScannedItem());
      if ((index + 1) % 64 == 0) {
        await Future<void>.delayed(Duration.zero);
        _throwIfCancelled(shouldCancel);
      }
    }
    items.sort((left, right) => right.addedAt.compareTo(left.addedAt));

    appLogInfo(
      'library.scan',
      'WebDAV media scan completed',
      fields: <String, Object?>{
        'sourceId': source.id,
        'itemCount': items.length,
        'directoryCount': visited.length,
        'durationMs': scanStopwatch.elapsedMilliseconds,
      },
    );

    return ExternalScanResult(items, complete: !walkResult.truncated);
  }

  Future<WebDavScannedItem?> scanResource(
    MediaSourceConfig source, {
    required String resourceId,
    required String sectionId,
    required String sectionName,
    bool? loadSidecarMetadata,
    bool resolvePlayableStreams = true,
    bool Function()? shouldCancel,
  }) async {
    final endpoint = source.endpoint.trim();
    final normalizedResourceId = resourceId.trim();
    if (endpoint.isEmpty || normalizedResourceId.isEmpty) {
      return null;
    }
    final resourceUri = Uri.tryParse(normalizedResourceId);
    if (resourceUri == null) {
      return null;
    }
    if (_isExcludedByKeyword(resourceUri, source: source)) {
      return null;
    }

    final parentUri = _parentDirectoryUri(resourceUri);
    if (parentUri == null) {
      return null;
    }
    final shouldLoadSidecarMetadata =
        loadSidecarMetadata ?? source.webDavSidecarScrapingEnabled;
    final siblings = _filterExcludedEntries(
      await _loadDirectoryEntries(parentUri, source: source),
      source: source,
    );
    _throwIfCancelled(shouldCancel);
    _WebDavEntry? entry;
    for (final candidate in siblings) {
      if (candidate.isCollection || candidate.isSelf) {
        continue;
      }
      if (candidate.uri.toString() == normalizedResourceId) {
        entry = candidate;
        break;
      }
    }
    if (entry == null || !_isPlayableVideo(entry)) {
      return null;
    }

    final metadata = shouldLoadSidecarMetadata
        ? await _resolveSidecarMetadata(
            entry,
            siblings: siblings,
            source: source,
          )
        : _buildBasicMetadataSeed(entry);
    _throwIfCancelled(shouldCancel);
    final resolvedPlayable = await _resolvePlayableSource(
      entry,
      source: source,
      resolveStrmTarget: resolvePlayableStreams,
    );
    _throwIfCancelled(shouldCancel);
    if (resolvedPlayable.streamUrl.trim().isEmpty) {
      return null;
    }
    final collectionName = sectionName.trim().isEmpty
        ? _displayNameFromUri(Uri.parse(sectionId), fallback: source.name)
        : sectionName.trim();
    return WebDavScannedItem(
      resourceId: entry.uri.toString(),
      fileName: entry.name,
      actualAddress: _relativePathForNasDisplay(entry.uri, source: source),
      sectionId: sectionId,
      sectionName: collectionName,
      streamUrl: resolvedPlayable.streamUrl,
      streamHeaders: resolvedPlayable.headers,
      addedAt: entry.modifiedAt ?? DateTime.now(),
      modifiedAt: entry.modifiedAt,
      fileSizeBytes: entry.sizeBytes,
      metadataSeed: metadata,
    );
  }

  Future<PlaybackTarget> resolvePlaybackTarget({
    required MediaSourceConfig source,
    required PlaybackTarget target,
  }) async {
    if (target.sourceKind != MediaSourceKind.nas) {
      return target;
    }
    final candidateUrl = target.streamUrl.trim();
    final candidateAddress = target.actualAddress.trim();
    final shouldResolveStrm = _looksLikeStrmReference(candidateUrl) ||
        (candidateUrl.isEmpty && _looksLikeStrmReference(candidateAddress));
    if (!shouldResolveStrm) {
      // History can predate origin checks or a source endpoint/password change.
      // Rebuild headers from the configured source, never the cached target.
      return target.copyWith(
        headers: _headersForResolvedStream(source, candidateUrl),
      );
    }

    final strmUri = _resolvePlaybackTargetUri(
      source,
      streamUrl: candidateUrl,
      actualAddress: candidateAddress,
    );
    if (strmUri == null) {
      return target;
    }
    final resolvedPlayableUrl =
        await _resolvePlayableUrlFromUri(strmUri, source: source);
    if (resolvedPlayableUrl.trim().isEmpty) {
      return target;
    }
    final resolvedFileSizeBytes = await _resolvePlayableFileSizeBytes(
      source,
      streamUrl: resolvedPlayableUrl,
    );
    final resolvedContainer = _resolvePlayableContainer(
      target.container,
      resolvedPlayableUrl,
    );

    return target.copyWith(
      streamUrl: resolvedPlayableUrl,
      headers: _headersForResolvedStream(source, resolvedPlayableUrl),
      container: resolvedContainer,
      // Null in copyWith preserves the STRM wrapper's size, not the video size.
      fileSizeBytes: resolvedFileSizeBytes ?? 0,
    );
  }

  String _resolvePlayableContainer(String current, String streamUrl) {
    final normalizedCurrent = current.trim();
    if (normalizedCurrent.isNotEmpty &&
        normalizedCurrent.toLowerCase() != 'strm') {
      return normalizedCurrent;
    }
    final uri = Uri.tryParse(streamUrl.trim());
    final path = (uri?.path ?? streamUrl).trim();
    final fileName = path.split('/').last;
    final extensionIndex = fileName.lastIndexOf('.');
    if (extensionIndex < 0 || extensionIndex == fileName.length - 1) {
      return '';
    }
    return fileName.substring(extensionIndex + 1).trim();
  }

  Future<String> resolveStrmTargetUrl({
    required MediaSourceConfig source,
    required String resourcePath,
    String sectionId = '',
  }) async {
    final endpoint = source.endpoint.trim();
    final normalizedResourcePath = resourcePath.trim();
    if (endpoint.isEmpty || normalizedResourcePath.isEmpty) {
      return '';
    }

    final targetUri = resolveResourceUri(
      source,
      resourcePath: normalizedResourcePath,
      sectionId: sectionId,
    );
    if (!targetUri.path.toLowerCase().endsWith('.strm')) {
      return '';
    }
    return _resolvePlayableUrlFromUri(targetUri, source: source);
  }

  Future<void> deleteResource(
    MediaSourceConfig source, {
    required String resourcePath,
    String sectionId = '',
  }) async {
    final endpoint = source.endpoint.trim();
    final normalizedResourcePath = resourcePath.trim();
    if (endpoint.isEmpty || normalizedResourcePath.isEmpty) {
      return;
    }

    final targetUri = resolveResourceUri(
      source,
      resourcePath: normalizedResourcePath,
      sectionId: sectionId,
    );
    _requireSourceResource(targetUri, source);
    final response = await sendBoundedRequest(
      _client,
      'DELETE',
      targetUri,
      headers: _headers(source),
      timeout: const Duration(seconds: 30),
      maxBytes: 1024 * 1024,
      allowUri: (next) => _isSourceResource(next, source),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WebDavDeleteException(response.statusCode);
    }
    _resetScanCaches();
    final cacheStore = _directoryCacheStore;
    if (cacheStore != null) {
      unawaited(cacheStore.removeSource(source.id));
    }
    final parentUri = _parentDirectoryUri(targetUri);
    if (parentUri != null) {
      // Deletion checks must not use filtered caches or swallow read failures.
      final siblings = await _propfind(parentUri, source: source);
      if (!siblings.any((entry) => entry.isSelf && entry.isCollection)) {
        throw Exception('WebDAV 删除结果未确认：父目录响应不完整');
      }
      final stillExists = siblings.any(
        (entry) =>
            _normalizeParsedWebDavUri(entry.uri) ==
            _normalizeParsedWebDavUri(targetUri),
      );
      if (stillExists) {
        throw Exception('WebDAV 删除未生效：远端文件或目录仍然存在');
      }
    }
  }

  Future<int?> _resolvePlayableFileSizeBytes(
    MediaSourceConfig source, {
    required String streamUrl,
  }) async {
    final resolvedUrl = streamUrl.trim();
    if (resolvedUrl.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(resolvedUrl);
    if (uri == null || !isHttpUri(uri)) {
      return null;
    }

    final headers = _headersForResolvedStream(source, resolvedUrl);
    final directSize = await _tryReadPlayableFileSize(
      uri,
      method: 'HEAD',
      headers: headers,
    );
    if (directSize != null && directSize > 0) {
      return directSize;
    }

    return _tryReadPlayableFileSize(
      uri,
      method: 'GET',
      headers: headers,
    );
  }

  Future<int?> _tryReadPlayableFileSize(
    Uri uri, {
    required String method,
    required Map<String, String> headers,
  }) async {
    final abort = Completer<void>();
    final watch = Stopwatch()..start();
    try {
      var current = uri;
      var currentHeaders = headers;
      for (var redirects = 0; redirects <= 5; redirects++) {
        if (!isHttpUri(current) || _isPlaylistUri(current)) return null;
        final remaining = const Duration(seconds: 5) - watch.elapsed;
        if (remaining <= Duration.zero) return null;
        final request =
            http.AbortableRequest(method, current, abortTrigger: abort.future)
              ..followRedirects = false
              ..headers.addAll(currentHeaders)
              ..headers['Accept-Encoding'] = 'identity';
        if (method == 'GET') request.headers['Range'] = 'bytes=0-0';
        final pending = _client.send(request);
        // Dispose late headers even when a transport ignores request abortion.
        unawaited(pending.then((response) {
          if (abort.isCompleted) {
            unawaited(response.stream.listen(null).cancel());
          }
        }, onError: (Object _, StackTrace __) {}));
        final response = await pending.timeout(remaining);
        try {
          if (const [301, 302, 303, 307, 308].contains(response.statusCode)) {
            final location = response.headers['location'];
            if (location == null || location.trim().isEmpty) return null;
            final next = current.resolve(location);
            if (!isSameHttpOrigin(current, next)) {
              // Never forward NAS credentials to a CDN, or restore them later.
              currentHeaders = const {};
            }
            current = next;
            continue;
          }
          return _playableFileSizeFromHeaders(response);
        } finally {
          // A server may ignore Range and send the entire video. Do not read it.
          await response.stream.listen(null).cancel();
        }
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      abort.complete();
    }
  }

  bool _isPlaylistUri(Uri uri) =>
      const ['.m3u', '.m3u8', '.mpd'].any(uri.path.toLowerCase().endsWith);

  int? _playableFileSizeFromHeaders(http.StreamedResponse response) {
    if (response.statusCode != 200 && response.statusCode != 206) return null;
    final contentType = (response.headers['content-type'] ?? '')
        .split(';')
        .first
        .trim()
        .toLowerCase();
    if (contentType.startsWith('text/') ||
        contentType.contains('json') ||
        contentType.contains('xml') ||
        contentType.contains('mpegurl')) {
      return null;
    }
    final encoding = response.headers['content-encoding']?.trim().toLowerCase();
    if (encoding != null && encoding.isNotEmpty && encoding != 'identity') {
      return null;
    }
    final contentRange = response.headers['content-range'];
    if (response.statusCode == 206 || contentRange != null) {
      final match = RegExp(r'^bytes\s+(\d+)-(\d+)/(\d+)$', caseSensitive: false)
          .firstMatch(contentRange?.trim() ?? '');
      if (match == null) return null;
      final start = int.tryParse(match.group(1)!);
      final end = int.tryParse(match.group(2)!);
      final total = _parsePositiveInt(match.group(3));
      if (start == null ||
          end == null ||
          total == null ||
          start > end ||
          end >= total) {
        return null;
      }
      return total;
    }
    return _parsePositiveInt(response.headers['content-length']);
  }

  int? _parsePositiveInt(String? rawValue) {
    final parsed = int.tryParse(rawValue?.trim() ?? '');
    if (parsed == null || parsed <= 0) {
      return null;
    }
    return parsed;
  }

  /// Use the same target for remote operations and cloud sync-delete matching.
  Uri resolveResourceUri(
    MediaSourceConfig source, {
    required String resourcePath,
    required String sectionId,
  }) {
    final directUri = Uri.tryParse(resourcePath);
    if (directUri != null && directUri.hasScheme) {
      return directUri;
    }

    final baseUri = Uri.parse(
      sectionId.trim().isNotEmpty ? sectionId.trim() : _browseRoot(source),
    );
    final normalizedBasePath =
        baseUri.path.endsWith('/') ? baseUri.path : '${baseUri.path}/';
    final normalizedResourcePath = resourcePath.replaceAll('\\', '/').trim();
    final resolvedPath = normalizedResourcePath.startsWith('/')
        ? normalizedResourcePath
        : '$normalizedBasePath$normalizedResourcePath';
    return baseUri.replace(
      path: resolvedPath.replaceAll(RegExp(r'/+'), '/'),
    );
  }
}
