import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/core/network/starflow_http_client.dart';
import 'package:starflow/core/utils/webdav_trace.dart';
import 'package:starflow/features/library/data/season_folder_label_parser.dart';
import 'package:starflow/features/library/domain/media_naming.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/domain/nas_media_recognition.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:xml/xml.dart';

part 'webdav_nas_client_sidecar.dart';
part 'webdav_nas_client_structure.dart';
part 'webdav_nas_client_models.dart';

final webDavNasClientProvider = Provider<WebDavNasClient>((ref) {
  final client = ref.watch(starflowHttpClientProvider);
  return WebDavNasClient(client);
});

class WebDavNasClient {
  WebDavNasClient(this._client);

  static const int _maxConcurrentDirectoryWalks = 4;
  static const int _maxConcurrentFilePreparations = 8;

  final http.Client _client;
  final Map<String, _ParsedNfoMetadata?> _nfoCache =
      <String, _ParsedNfoMetadata?>{};
  final Map<String, Future<_ParsedNfoMetadata?>> _nfoInflight =
      <String, Future<_ParsedNfoMetadata?>>{};
  final Map<String, List<_WebDavEntry>> _directoryCache =
      <String, List<_WebDavEntry>>{};
  final Map<String, Future<List<_WebDavEntry>>> _directoryInflight =
      <String, Future<List<_WebDavEntry>>>{};
  final Map<String, _DirectorySubtreeCacheEntry> _directorySubtreeCache =
      <String, _DirectorySubtreeCacheEntry>{};

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
      webDavTrace(
        'fetchCollections.skipExcludedRoot',
        fields: {
          'sourceId': source.id,
          'rootUri': rootUri,
          'keywords': source.normalizedWebDavExcludedPathKeywords,
        },
      );
      return const [];
    }
    webDavTrace(
      'fetchCollections.start',
      fields: {
        'sourceId': source.id,
        'sourceName': source.name,
        'rootUri': rootUri,
      },
    );
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
    webDavTrace(
      'fetchCollections.done',
      fields: {
        'sourceId': source.id,
        'count': collections.length,
        'titles': collections.map((item) => item.title).toList(),
      },
    );
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
      webDavTrace(
        'scanLibrary.skipExcludedRoot',
        fields: {
          'sourceId': source.id,
          'rootUri': rootUri,
          'keywords': source.normalizedWebDavExcludedPathKeywords,
        },
      );
      return const [];
    }
    final collectionId = rootUri.toString();
    final collectionName = sectionName.trim().isEmpty
        ? _displayNameFromUri(rootUri, fallback: source.name)
        : sectionName.trim();
    webDavTrace(
      'scanLibrary.start',
      fields: {
        'sourceId': source.id,
        'sourceName': source.name,
        'rootUri': rootUri,
        'sectionName': collectionName,
        'limit': limit,
        'structureInference': source.webDavStructureInferenceEnabled,
        'sidecar': shouldLoadSidecarMetadata,
        'maxConcurrentDirectoryWalks': _maxConcurrentDirectoryWalks,
        'maxConcurrentFilePreparations': _maxConcurrentFilePreparations,
        'resolvePlayableStreams': resolvePlayableStreams,
      },
    );
    final visited = <String>{};

    Future<_PendingWebDavScannedItem?> resolvePendingItem(
      _WebDavEntry entry,
      List<_WebDavEntry> siblings,
    ) async {
      if (_isExcludedByKeyword(entry.uri, source: source)) {
        webDavTrace(
          'scan.walk.skipExcludedFile',
          fields: {
            'uri': entry.uri,
            'name': entry.name,
          },
        );
        return null;
      }
      if (!_isPlayableVideo(entry)) {
        webDavTrace(
          'scan.walk.skipNonPlayable',
          fields: {
            'uri': entry.uri,
            'name': entry.name,
            'contentType': entry.contentType,
          },
        );
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
        webDavTrace(
          'scan.walk.skipEmptyStream',
          fields: {
            'uri': entry.uri,
            'name': entry.name,
          },
        );
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
      webDavTrace(
        'scan.walk.accept',
        fields: {
          'path': pendingItem.actualAddress,
          'title': pendingItem.metadataSeed.title,
          'itemType': pendingItem.metadataSeed.itemType,
          'season': pendingItem.metadataSeed.seasonNumber,
          'episode': pendingItem.metadataSeed.episodeNumber,
          'directories': pendingItem.relativeDirectories,
        },
      );
      return pendingItem;
    }

    Future<_DirectoryWalkResult> walk(
      Uri uri,
      int depth,
      int remaining, {
      DateTime? directoryModifiedAt,
    }) async {
      _throwIfCancelled(shouldCancel);
      if (remaining <= 0) {
        return const _DirectoryWalkResult(truncated: true);
      }
      if (depth > 8 || !visited.add(uri.toString())) {
        return const _DirectoryWalkResult();
      }
      if (_isExcludedByKeyword(uri, source: source)) {
        webDavTrace(
          'scan.walk.skipExcludedDirectory',
          fields: {
            'uri': uri,
            'depth': depth,
          },
        );
        return const _DirectoryWalkResult();
      }

      final cachedSubtree = _loadCachedDirectorySubtree(
        source: source,
        uri: uri,
        includeSidecarMetadata: shouldLoadSidecarMetadata,
        directoryModifiedAt: directoryModifiedAt,
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
        webDavTrace(
          'scan.walk.cacheHit',
          fields: {
            'uri': uri,
            'depth': depth,
            'cachedCount': cachedSubtree.items.length,
            'returnedCount': items.length,
            'truncated': truncated,
          },
        );
        return _DirectoryWalkResult(
          items: items,
          truncated: truncated,
        );
      }

      webDavTrace(
        'scan.walk.enter',
        fields: {
          'uri': uri,
          'depth': depth,
          'remaining': remaining,
        },
      );
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
      final childDirectoryCount =
          directoryEntries.where((entry) => entry.isCollection).length;
      final fileEntryCount =
          directoryEntries.where((entry) => !entry.isCollection).length;
      var truncated = false;
      webDavTrace(
        'scan.walk.entries',
        fields: {
          'uri': uri,
          'depth': depth,
          'entryCount': directoryEntries.length,
          'childDirectoryCount': childDirectoryCount,
          'fileEntryCount': fileEntryCount,
          'maxConcurrentDirectoryWalks': _maxConcurrentDirectoryWalks,
          'maxConcurrentFilePreparations': _maxConcurrentFilePreparations,
          'directories': directoryEntries
              .where((entry) => entry.isCollection)
              .map((entry) => entry.name)
              .toList(),
        },
      );
      for (var entryIndex = 0;
          entryIndex < directoryEntries.length;
          entryIndex++) {
        final entry = directoryEntries[entryIndex];
        _throwIfCancelled(shouldCancel);
        if (entry.isCollection) {
          webDavTrace(
            'scan.walk.descend',
            fields: {
              'parent': uri,
              'child': entry.uri,
              'name': entry.name,
            },
          );
          final childResult = walk(
            entry.uri,
            depth + 1,
            remaining,
            directoryModifiedAt: entry.modifiedAt,
          );
          childDirectoryResults[entryIndex] = childResult;
          late final Future<void> completion;
          completion = childResult.whenComplete(() {
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
        completion = fileResult.whenComplete(() {
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

      if (!truncated && directoryModifiedAt != null) {
        _storeCachedDirectorySubtree(
          source: source,
          uri: uri,
          includeSidecarMetadata: shouldLoadSidecarMetadata,
          directoryModifiedAt: directoryModifiedAt,
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
    final items = (source.webDavStructureInferenceEnabled
            ? applyExternalDirectoryStructureInference(
                pendingItems,
                source: source,
              )
            : pendingItems)
        .map((item) => item.toScannedItem())
        .toList(growable: false);
    items.sort((left, right) => right.addedAt.compareTo(left.addedAt));
    webDavTrace(
      'scanLibrary.done',
      fields: {
        'sourceId': source.id,
        'rootUri': rootUri,
        'pendingCount': pendingItems.length,
        'resultCount': items.length,
        'truncated': walkResult.truncated,
        'maxConcurrentDirectoryWalks': _maxConcurrentDirectoryWalks,
      },
    );
    return items;
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
      return target;
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

    return PlaybackTarget(
      title: target.title,
      sourceId: target.sourceId,
      streamUrl: resolvedPlayableUrl,
      sourceName: target.sourceName,
      sourceKind: target.sourceKind,
      actualAddress: target.actualAddress,
      itemId: target.itemId,
      itemType: target.itemType,
      year: target.year,
      seriesId: target.seriesId,
      seriesTitle: target.seriesTitle,
      preferredMediaSourceId: target.preferredMediaSourceId,
      subtitle: target.subtitle,
      headers: _headersForResolvedStream(source, resolvedPlayableUrl),
      container: target.container,
      videoCodec: target.videoCodec,
      audioCodec: target.audioCodec,
      seasonNumber: target.seasonNumber,
      episodeNumber: target.episodeNumber,
      width: target.width,
      height: target.height,
      bitrate: target.bitrate,
      fileSizeBytes: resolvedFileSizeBytes,
    );
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

    final targetUri = _resolveResourceUri(
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

    final targetUri = _resolveResourceUri(
      source,
      resourcePath: normalizedResourcePath,
      sectionId: sectionId,
    );
    final response = await _client.delete(
      targetUri,
      headers: _headers(source),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('WebDAV 删除失败：HTTP ${response.statusCode}');
    }
    _resetScanCaches();
    if (_looksLikePlayableResourceUri(targetUri)) {
      final parentUri = _parentDirectoryUri(targetUri);
      if (parentUri != null) {
        final siblings = await _loadDirectoryEntries(parentUri, source: source);
        final stillExists = siblings.any(
          (entry) => !entry.isCollection && entry.uri == targetUri,
        );
        if (stillExists) {
          throw Exception('WebDAV 删除未生效：远端文件仍然存在');
        }
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
    if (uri == null || !uri.hasScheme) {
      return null;
    }

    final headers = _headersForResolvedStream(source, resolvedUrl);
    final directSize = await _tryReadContentLength(
      () => _client.head(uri, headers: headers),
    );
    if (directSize != null && directSize > 0) {
      return directSize;
    }

    return _tryReadRangeContentLength(
      uri,
      headers: headers,
    );
  }

  Future<int?> _tryReadContentLength(
    Future<http.Response> Function() request,
  ) async {
    try {
      final response = await request().timeout(const Duration(seconds: 5));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      return _parsePositiveInt(response.headers['content-length']);
    } catch (_) {
      return null;
    }
  }

  Future<int?> _tryReadRangeContentLength(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    try {
      final request = http.Request('GET', uri)
        ..headers.addAll(headers)
        ..headers['Range'] = 'bytes=0-0';
      final response =
          await _client.send(request).timeout(const Duration(seconds: 5));
      try {
        if (response.statusCode < 200 || response.statusCode >= 300) {
          return null;
        }

        final contentRange = response.headers['content-range']?.trim() ?? '';
        final rangeMatch =
            RegExp(r'bytes\s+\d+-\d+/(\d+)$').firstMatch(contentRange);
        if (rangeMatch != null) {
          final parsed = _parsePositiveInt(rangeMatch.group(1));
          if (parsed != null && parsed > 0) {
            return parsed;
          }
        }

        return _parsePositiveInt(response.headers['content-length']);
      } finally {
        await response.stream.listen(null).cancel();
      }
    } catch (_) {
      return null;
    }
  }

  int? _parsePositiveInt(String? rawValue) {
    final parsed = int.tryParse(rawValue?.trim() ?? '');
    if (parsed == null || parsed <= 0) {
      return null;
    }
    return parsed;
  }

  Uri _resolveResourceUri(
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

  bool _looksLikePlayableResourceUri(Uri uri) {
    final normalizedPath = uri.path.toLowerCase();
    return const [
      '.mp4',
      '.m4v',
      '.mov',
      '.mkv',
      '.iso',
      '.avi',
      '.ts',
      '.webm',
      '.flv',
      '.wmv',
      '.mpg',
      '.mpeg',
      '.strm',
    ].any(normalizedPath.endsWith);
  }
}
