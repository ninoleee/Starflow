import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/utils/seed_data.dart';
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
  (ref) => MockMediaRepository(ref),
);

class MockMediaRepository implements MediaRepository {
  MockMediaRepository(this.ref);

  final Ref ref;

  List<MediaSourceConfig> get _enabledSources {
    return ref.read(appSettingsProvider).mediaSources
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
    await Future<void>.delayed(const Duration(milliseconds: 160));
    final items = _enabledLibrary;
    final filtered = kind == null
        ? items
        : items.where((item) => item.sourceKind == kind).toList();
    filtered.sort((left, right) => right.addedAt.compareTo(left.addedAt));
    return filtered;
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
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final matches = _enabledLibrary.where((item) => item.id == id);
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Future<MediaItem?> matchTitle(String title) async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final target = _normalize(title);
    for (final item in _enabledLibrary) {
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
