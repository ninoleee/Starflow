import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/domain/media_title_matcher.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

abstract class MediaRepository {
  Future<List<MediaSourceConfig>> fetchSources();

  Future<List<MediaCollection>> fetchCollections({
    MediaSourceKind? kind,
    String? sourceId,
  });

  Future<List<MediaItem>> fetchLibrary({
    MediaSourceKind? kind,
    String? sourceId,
    String? sectionId,
    int limit = 200,
  });

  Future<List<MediaItem>> fetchRecentlyAdded({
    MediaSourceKind? kind,
    int limit = 10,
  });

  Future<List<MediaItem>> fetchChildren({
    required String sourceId,
    required String parentId,
    String sectionId = '',
    String sectionName = '',
    int limit = 200,
  });

  Future<MediaItem?> findById(String id);

  Future<MediaItem?> matchTitle(String title);
}

final mediaRepositoryProvider = Provider<MediaRepository>(
  (ref) => AppMediaRepository(
    ref,
    ref.read(embyApiClientProvider),
    ref.read(webDavNasClientProvider),
  ),
);

class AppMediaRepository implements MediaRepository {
  AppMediaRepository(this.ref, this._embyApiClient, this._webDavNasClient);

  final Ref ref;
  final EmbyApiClient _embyApiClient;
  final WebDavNasClient _webDavNasClient;

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

  @override
  Future<List<MediaSourceConfig>> fetchSources() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return _enabledSources;
  }

  @override
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
        if (source.kind == MediaSourceKind.emby) {
          if (!source.hasActiveSession) {
            return const <MediaCollection>[];
          }
          return _embyApiClient.fetchCollections(source);
        }
        if (source.endpoint.trim().isEmpty) {
          return const <MediaCollection>[];
        }
        try {
          return await _webDavNasClient.fetchCollections(source);
        } catch (_) {
          return const <MediaCollection>[];
        }
      }),
    );

    return collections.expand((item) => item).toList();
  }

  @override
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
      sources.map((source) async {
        if (source.kind == MediaSourceKind.emby) {
          if (!source.hasActiveSession) {
            return const _SourceFetchResult(items: <MediaItem>[]);
          }
          try {
            return _SourceFetchResult(
              items: await _embyApiClient.fetchLibrary(
                source,
                limit: limit,
                sectionId: sectionId,
                sectionName: await _resolveSectionName(source, sectionId),
              ),
            );
          } catch (error, stackTrace) {
            return _SourceFetchResult(
              items: const <MediaItem>[],
              error: error,
              stackTrace: stackTrace,
            );
          }
        }

        if (source.endpoint.trim().isNotEmpty) {
          try {
            return _SourceFetchResult(
              items: await _webDavNasClient.fetchLibrary(
                source,
                sectionId: sectionId,
                sectionName: await _resolveSectionName(source, sectionId),
                limit: limit,
              ),
            );
          } catch (error, stackTrace) {
            return _SourceFetchResult(
              items: const <MediaItem>[],
              error: error,
              stackTrace: stackTrace,
            );
          }
        }

        return _SourceFetchResult(
          items: seededLibrary
              .where((item) => item.sourceId == source.id)
              .where(
                (item) =>
                    sectionId == null ||
                    sectionId.trim().isEmpty ||
                    item.sectionId == sectionId,
              )
              .toList(),
        );
      }),
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

  @override
  Future<List<MediaItem>> fetchRecentlyAdded({
    MediaSourceKind? kind,
    int limit = 10,
  }) async {
    final items = await fetchLibrary(kind: kind, limit: limit);
    return items.take(limit).toList();
  }

  @override
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
    if (source == null || !source.enabled) {
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

    return const [];
  }

  @override
  Future<MediaItem?> findById(String id) async {
    final matches = (await fetchLibrary()).where((item) => item.id == id);
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Future<MediaItem?> matchTitle(String title) async {
    final library = await fetchLibrary(limit: 2000);
    return matchMediaItemByTitles(library, titles: [title]);
  }

  Future<String> _resolveSectionName(
    MediaSourceConfig source,
    String? sectionId,
  ) async {
    final normalized = sectionId?.trim() ?? '';
    if (normalized.isEmpty) {
      return '';
    }

    final collections = await fetchCollections(sourceId: source.id);
    for (final collection in collections) {
      if (collection.id == normalized) {
        return collection.title;
      }
    }
    return '';
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
