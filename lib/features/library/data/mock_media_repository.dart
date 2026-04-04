import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

abstract class MediaRepository {
  Future<List<MediaSourceConfig>> fetchSources();

  Future<List<MediaItem>> fetchLibrary({MediaSourceKind? kind});

  Future<List<MediaItem>> fetchRecentlyAdded({
    MediaSourceKind? kind,
    int limit = 10,
  });

  Future<MediaItem?> findById(String id);

  Future<MediaItem?> matchTitle(String title);
}

final mediaRepositoryProvider = Provider<MediaRepository>(
  (ref) => AppMediaRepository(
    ref,
    ref.read(embyApiClientProvider),
  ),
);

class AppMediaRepository implements MediaRepository {
  AppMediaRepository(this.ref, this._embyApiClient);

  final Ref ref;
  final EmbyApiClient _embyApiClient;

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
  Future<List<MediaItem>> fetchLibrary({MediaSourceKind? kind}) async {
    final sources = _enabledSources
        .where((item) => kind == null || item.kind == kind)
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
              items: await _embyApiClient.fetchLibrary(source),
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
    final items = await fetchLibrary(kind: kind);
    return items.take(limit).toList();
  }

  @override
  Future<MediaItem?> findById(String id) async {
    final matches = (await fetchLibrary()).where((item) => item.id == id);
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Future<MediaItem?> matchTitle(String title) async {
    final library = await fetchLibrary();
    final target = _normalize(title);
    for (final item in library) {
      final sourceTitle = _normalize(item.title);
      if (sourceTitle == target ||
          sourceTitle.contains(target) ||
          target.contains(sourceTitle)) {
        return item;
      }
    }
    return null;
  }

  String _normalize(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
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
