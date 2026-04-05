import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/core/network/starflow_http_client.dart';
import 'package:starflow/core/utils/webdav_trace.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/domain/nas_media_recognition.dart';
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
      },
    );
    final visited = <String>{};

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
      var truncated = false;
      webDavTrace(
        'scan.walk.entries',
        fields: {
          'uri': uri,
          'depth': depth,
          'entryCount': directoryEntries.length,
          'directories': directoryEntries
              .where((entry) => entry.isCollection)
              .map((entry) => entry.name)
              .toList(),
        },
      );
      for (final entry in directoryEntries) {
        _throwIfCancelled(shouldCancel);
        final remainingForEntry = remaining - collected.length;
        if (remainingForEntry <= 0) {
          truncated = true;
          break;
        }
        if (entry.isCollection) {
          webDavTrace(
            'scan.walk.descend',
            fields: {
              'parent': uri,
              'child': entry.uri,
              'name': entry.name,
            },
          );
          final childResult = await walk(
            entry.uri,
            depth + 1,
            remainingForEntry,
            directoryModifiedAt: entry.modifiedAt,
          );
          _throwIfCancelled(shouldCancel);
          collected.addAll(childResult.items);
          truncated = truncated || childResult.truncated;
          continue;
        }
        if (_isExcludedByKeyword(entry.uri, source: source)) {
          webDavTrace(
            'scan.walk.skipExcludedFile',
            fields: {
              'uri': entry.uri,
              'name': entry.name,
            },
          );
          continue;
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
          continue;
        }
        final metadata = shouldLoadSidecarMetadata
            ? await _resolveSidecarMetadata(
                entry,
                siblings: directoryEntries,
                source: source,
              )
            : _buildBasicMetadataSeed(entry);
        _throwIfCancelled(shouldCancel);
        final streamUrl = await _resolvePlayableUrl(entry, source: source);
        _throwIfCancelled(shouldCancel);
        if (streamUrl.trim().isEmpty) {
          webDavTrace(
            'scan.walk.skipEmptyStream',
            fields: {
              'uri': entry.uri,
              'name': entry.name,
            },
          );
          continue;
        }
        final pendingItem = _PendingWebDavScannedItem(
          resourceId: entry.uri.toString(),
          fileName: entry.name,
          actualAddress: _relativePathForNasDisplay(entry.uri, source: source),
          sectionId: collectionId,
          sectionName: collectionName,
          streamUrl: streamUrl,
          streamHeaders: _headersForResolvedStream(source, streamUrl),
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
        collected.add(pendingItem);
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
            ? _applyDirectoryStructureInference(pendingItems)
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
    final streamUrl = await _resolvePlayableUrl(entry, source: source);
    _throwIfCancelled(shouldCancel);
    if (streamUrl.trim().isEmpty) {
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
      streamUrl: streamUrl,
      streamHeaders: _headersForResolvedStream(source, streamUrl),
      addedAt: entry.modifiedAt ?? DateTime.now(),
      modifiedAt: entry.modifiedAt,
      fileSizeBytes: entry.sizeBytes,
      metadataSeed: metadata,
    );
  }
}
