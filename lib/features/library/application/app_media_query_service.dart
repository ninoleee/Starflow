import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/library/application/empty_library_auto_rebuild_scheduler.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/data/nas_media_indexer.dart';
import 'package:starflow/features/library/data/quark_external_storage_client.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/domain/media_title_matcher.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

class AppMediaQueryService {
  AppMediaQueryService({
    required this.ref,
    required EmbyApiClient embyApiClient,
    required WebDavNasClient webDavNasClient,
    required NasMediaIndexer nasMediaIndexer,
    required QuarkExternalStorageClient quarkExternalStorageClient,
  })  : _embyApiClient = embyApiClient,
        _webDavNasClient = webDavNasClient,
        _nasMediaIndexer = nasMediaIndexer,
        _quarkExternalStorageClient = quarkExternalStorageClient,
        _emptyLibraryAutoRebuildScheduler = EmptyLibraryAutoRebuildScheduler();

  final Ref ref;
  final EmbyApiClient _embyApiClient;
  final WebDavNasClient _webDavNasClient;
  final NasMediaIndexer _nasMediaIndexer;
  final QuarkExternalStorageClient _quarkExternalStorageClient;
  final EmptyLibraryAutoRebuildScheduler _emptyLibraryAutoRebuildScheduler;

  Future<List<MediaSourceConfig>> fetchSources() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return _enabledSources;
  }

  Future<List<MediaCollection>> fetchCollections({
    MediaSourceKind? kind,
    String? sourceId,
  }) async {
    final sources = _enabledSources
        .where(
          (item) =>
              (kind == null || item.kind == kind) &&
              (sourceId == null || sourceId == item.id),
        )
        .toList();
    final collections = await Future.wait(
      sources.map((source) async {
        try {
          return await _fetchCollectionsForSource(source);
        } catch (_) {
          return const <MediaCollection>[];
        }
      }),
    );

    return collections.expand((item) => item).toList();
  }

  Future<List<MediaItem>> fetchLibrary({
    MediaSourceKind? kind,
    String? sourceId,
    String? sectionId,
    int limit = 200,
  }) async {
    final sources = _enabledSources
        .where(
          (item) =>
              (kind == null || item.kind == kind) &&
              (sourceId == null || sourceId == item.id),
        )
        .toList();
    final seededLibrary = _enabledLibrary;
    final sourceResults = await Future.wait(
      sources.map(
        (source) => _fetchLibraryForSource(
          source,
          sectionId: sectionId,
          limit: limit,
          seededLibrary: seededLibrary,
        ),
      ),
    );
    final items = sourceResults.expand((group) => group.items).toList();

    if (items.isEmpty) {
      for (final result in sourceResults) {
        if (result.error != null) {
          Error.throwWithStackTrace(
            result.error!,
            result.stackTrace ?? StackTrace.current,
          );
        }
      }
    }

    items.sort((left, right) => right.addedAt.compareTo(left.addedAt));
    return items;
  }

  Future<List<MediaItem>> fetchRecentlyAdded({
    MediaSourceKind? kind,
    int limit = 10,
  }) async {
    final items = await fetchLibrary(kind: kind, limit: limit);
    return items.take(limit).toList();
  }

  Future<List<MediaItem>> fetchChildren({
    required String sourceId,
    required String parentId,
    String sectionId = '',
    String sectionName = '',
    int limit = 200,
  }) async {
    final normalizedSourceId = sourceId.trim();
    final normalizedParentId = parentId.trim();
    if (normalizedSourceId.isEmpty || normalizedParentId.isEmpty) {
      return const [];
    }

    MediaSourceConfig? source;
    for (final candidate in _enabledSources) {
      if (candidate.id == normalizedSourceId) {
        source = candidate;
        break;
      }
    }
    if (source == null) {
      return const [];
    }

    if (source.kind == MediaSourceKind.emby) {
      if (!source.hasActiveSession) {
        return const [];
      }
      return _embyApiClient.fetchChildren(
        source,
        parentId: normalizedParentId,
        sectionId: sectionId,
        sectionName: sectionName,
        limit: limit,
      );
    }
    final scopedCollections = _hasScopedSections(source)
        ? await _selectedCollectionsForSource(source)
        : null;
    return _nasMediaIndexer.loadChildren(
      source,
      parentId: normalizedParentId,
      sectionId: sectionId,
      scopedCollections: scopedCollections,
      limit: limit,
    );
  }

  Future<MediaItem?> findById(String id) async {
    final matches = (await fetchLibrary()).where((item) => item.id == id);
    return matches.isEmpty ? null : matches.first;
  }

  Future<MediaItem?> matchTitle(String title) async {
    final library = await fetchLibrary(limit: 2000);
    return matchMediaItemByTitles(library, titles: [title]);
  }

  List<MediaSourceConfig> get _enabledSources {
    return ref
        .read(appSettingsProvider)
        .mediaSources
        .where((item) => item.enabled)
        .toList();
  }

  List<MediaItem> get _enabledLibrary {
    final enabledSourceIds = _enabledSources.map((item) => item.id).toSet();
    return SeedData.seedLibrary
        .where((item) => enabledSourceIds.contains(item.sourceId))
        .toList();
  }

  Future<List<MediaCollection>> _fetchCollectionsForSource(
    MediaSourceConfig source, {
    bool applySelection = true,
  }) async {
    late final List<MediaCollection> collections;
    if (source.kind == MediaSourceKind.emby) {
      if (!source.hasActiveSession) {
        return const [];
      }
      collections = await _embyApiClient.fetchCollections(source);
    } else if (source.kind == MediaSourceKind.quark) {
      collections = await _quarkExternalStorageClient.fetchCollections(source);
    } else {
      if (source.endpoint.trim().isEmpty) {
        return const [];
      }
      collections = await _webDavNasClient.fetchCollections(source);
    }

    if (!applySelection) {
      return collections;
    }
    if (source.hasExplicitNoSectionsSelected) {
      return const [];
    }
    final selectedIds = source.selectedSectionIds;
    if (selectedIds.isEmpty) {
      return collections;
    }
    return collections
        .where((collection) => selectedIds.contains(collection.id))
        .toList();
  }

  Future<_SourceFetchResult> _fetchLibraryForSource(
    MediaSourceConfig source, {
    required String? sectionId,
    required int limit,
    required List<MediaItem> seededLibrary,
  }) async {
    try {
      final hasScopedSections = _hasScopedSections(source);
      if (source.kind == MediaSourceKind.emby) {
        if (!source.hasActiveSession) {
          return const _SourceFetchResult(items: <MediaItem>[]);
        }
        if (sectionId?.trim().isNotEmpty == true) {
          return _SourceFetchResult(
            items: await _embyApiClient.fetchLibrary(
              source,
              limit: limit,
              sectionId: sectionId,
              sectionName: await _resolveSectionName(source, sectionId),
            ),
          );
        }

        final selectedCollections = await _selectedCollectionsForSource(source);
        if (hasScopedSections) {
          if (selectedCollections.isEmpty) {
            return const _SourceFetchResult(items: <MediaItem>[]);
          }
          return _SourceFetchResult(
            items: await _fetchLibraryFromCollections(
              source,
              selectedCollections,
              limit: limit,
            ),
          );
        }

        return _SourceFetchResult(
          items: await _embyApiClient.fetchLibrary(
            source,
            limit: limit,
          ),
        );
      }

      if (source.kind == MediaSourceKind.quark) {
        if (!source.hasConfiguredQuarkFolder) {
          return const _SourceFetchResult(items: <MediaItem>[]);
        }
        if (sectionId?.trim().isNotEmpty == true) {
          final resolvedSectionId = sectionId!.trim();
          final resolvedSectionName =
              await _resolveSectionName(source, sectionId);
          return _SourceFetchResult(
            items: await _loadNasLibraryWithAutoRebuild(
              source,
              sectionId: resolvedSectionId,
              scopedCollections: [
                MediaCollection(
                  id: resolvedSectionId,
                  title: resolvedSectionName,
                  sourceId: source.id,
                  sourceName: source.name,
                  sourceKind: source.kind,
                  subtitle: await _resolveSectionPath(source, sectionId),
                ),
              ],
              limit: limit,
              autoRebuildInBackground: false,
            ),
          );
        }

        final selectedCollections = await _selectedCollectionsForSource(source);
        if (hasScopedSections) {
          if (selectedCollections.isEmpty) {
            return const _SourceFetchResult(items: <MediaItem>[]);
          }
          return _SourceFetchResult(
            items: await _loadNasLibraryWithAutoRebuild(
              source,
              scopedCollections: selectedCollections,
              limit: limit,
              autoRebuildInBackground: false,
            ),
          );
        }

        return _SourceFetchResult(
          items: await _loadNasLibraryWithAutoRebuild(
            source,
            limit: limit,
            autoRebuildInBackground: false,
          ),
        );
      }

      if (source.endpoint.trim().isNotEmpty) {
        if (source.hasExplicitNoSectionsSelected) {
          await _nasMediaIndexer.clearSource(source.id);
          return const _SourceFetchResult(items: <MediaItem>[]);
        }
        if (sectionId?.trim().isNotEmpty == true) {
          final resolvedSectionId = sectionId!.trim();
          final resolvedSectionName =
              await _resolveSectionName(source, sectionId);
          final scopedCollections = [
            MediaCollection(
              id: resolvedSectionId,
              title: resolvedSectionName,
              sourceId: source.id,
              sourceName: source.name,
              sourceKind: source.kind,
            ),
          ];
          return _SourceFetchResult(
            items: await _loadNasLibraryWithAutoRebuild(
              source,
              sectionId: resolvedSectionId,
              scopedCollections: scopedCollections,
              limit: limit,
            ),
          );
        }

        final selectedCollections = await _selectedCollectionsForSource(source);
        if (hasScopedSections) {
          if (selectedCollections.isEmpty) {
            return const _SourceFetchResult(items: <MediaItem>[]);
          }
          return _SourceFetchResult(
            items: await _loadNasLibraryWithAutoRebuild(
              source,
              scopedCollections: selectedCollections,
              limit: limit,
            ),
          );
        }

        final libraryItems = await _loadNasLibraryWithAutoRebuild(
          source,
          limit: limit,
        );
        return _SourceFetchResult(items: libraryItems);
      }

      return const _SourceFetchResult(items: <MediaItem>[]);
    } catch (error, stackTrace) {
      return _SourceFetchResult(
        items: const <MediaItem>[],
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<List<MediaItem>> _fetchLibraryFromCollections(
    MediaSourceConfig source,
    List<MediaCollection> collections, {
    required int limit,
  }) async {
    final groups = await Future.wait(
      collections.map((collection) async {
        if (source.kind == MediaSourceKind.emby) {
          return _embyApiClient.fetchLibrary(
            source,
            limit: limit,
            sectionId: collection.id,
            sectionName: collection.title,
          );
        }
        if (source.kind == MediaSourceKind.quark) {
          return _loadNasLibraryWithAutoRebuild(
            source,
            sectionId: collection.id,
            scopedCollections: [collection],
            limit: limit,
            autoRebuildInBackground: false,
          );
        }
        return _nasMediaIndexer.loadLibrary(
          source,
          sectionId: collection.id,
          scopedCollections: [collection],
          limit: limit,
        );
      }),
    );
    return groups.expand((group) => group).toList();
  }

  Future<List<MediaItem>> _loadNasLibraryWithAutoRebuild(
    MediaSourceConfig source, {
    String? sectionId,
    List<MediaCollection>? scopedCollections,
    required int limit,
    bool autoRebuildInBackground = true,
  }) async {
    final scopeKey = _buildEmptyLibraryAutoRebuildScopeKey(
      source: source,
      sectionId: sectionId,
      scopedCollections: scopedCollections,
    );
    var items = await _nasMediaIndexer.loadLibrary(
      source,
      sectionId: sectionId,
      scopedCollections: scopedCollections,
      limit: limit,
    );
    if (items.isNotEmpty) {
      _emptyLibraryAutoRebuildScheduler.markScopeHealthy(scopeKey);
      return items;
    }

    if (!autoRebuildInBackground) {
      final rebuilt = await _nasMediaIndexer.tryAutoRebuildOnEmpty(
        source,
        scopedCollections: scopedCollections,
      );
      if (!rebuilt) {
        return items;
      }
      items = await _nasMediaIndexer.loadLibrary(
        source,
        sectionId: sectionId,
        scopedCollections: scopedCollections,
        limit: limit,
      );
      if (items.isNotEmpty) {
        _emptyLibraryAutoRebuildScheduler.markScopeHealthy(scopeKey);
      }
      return items;
    }

    _scheduleEmptyLibraryAutoRebuild(
      source: source,
      scopedCollections: scopedCollections,
      scopeKey: scopeKey,
    );
    return items;
  }

  void _scheduleEmptyLibraryAutoRebuild({
    required MediaSourceConfig source,
    List<MediaCollection>? scopedCollections,
    required String scopeKey,
  }) {
    _emptyLibraryAutoRebuildScheduler.schedule(
      scopeKey: scopeKey,
      task: () async {
        await _nasMediaIndexer.tryAutoRebuildOnEmpty(
          source,
          scopedCollections: scopedCollections,
        );
      },
    );
  }

  String _buildEmptyLibraryAutoRebuildScopeKey({
    required MediaSourceConfig source,
    String? sectionId,
    List<MediaCollection>? scopedCollections,
  }) {
    final normalizedSourceId = source.id.trim();
    final normalizedScopeIds = <String>{
      for (final collection in scopedCollections ?? const <MediaCollection>[])
        if (collection.id.trim().isNotEmpty) collection.id.trim(),
      if (sectionId?.trim().isNotEmpty == true) sectionId!.trim(),
    }.toList(growable: false)
      ..sort();
    return '$normalizedSourceId::${normalizedScopeIds.join("|")}';
  }

  Future<String> _resolveSectionName(
    MediaSourceConfig source,
    String? sectionId,
  ) async {
    final normalized = sectionId?.trim() ?? '';
    if (normalized.isEmpty) {
      return '';
    }

    final collections = await _fetchCollectionsForSource(
      source,
      applySelection: false,
    );
    for (final collection in collections) {
      if (collection.id == normalized) {
        return collection.title;
      }
    }
    return '';
  }

  Future<String> _resolveSectionPath(
    MediaSourceConfig source,
    String? sectionId,
  ) async {
    final normalized = sectionId?.trim() ?? '';
    if (normalized.isEmpty) {
      return '';
    }

    final collections = await _fetchCollectionsForSource(
      source,
      applySelection: false,
    );
    for (final collection in collections) {
      if (collection.id == normalized) {
        return collection.subtitle.trim();
      }
    }
    return '';
  }

  Future<List<MediaCollection>> _selectedCollectionsForSource(
    MediaSourceConfig source,
  ) async {
    if (!_hasScopedSections(source)) {
      return const [];
    }
    return _fetchCollectionsForSource(source);
  }

  bool _hasScopedSections(MediaSourceConfig source) {
    return source.featuredSectionIds.any((item) => item.trim().isNotEmpty);
  }
}

class _SourceFetchResult {
  const _SourceFetchResult({
    required this.items,
    this.error,
    this.stackTrace,
  });

  final List<MediaItem> items;
  final Object? error;
  final StackTrace? stackTrace;
}
