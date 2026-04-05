import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/features/library/application/library_cached_items.dart';
import 'package:starflow/features/library/application/media_refresh_coordinator.dart';
import 'package:starflow/features/library/application/nas_media_index_revision.dart';
import 'package:starflow/features/library/application/webdav_scrape_progress.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/library_collection_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/presentation/widgets/library_paged_grid.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/storage/application/local_storage_cache_revision.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

enum LibraryFilter {
  all,
  emby,
  nas,
}

extension LibraryFilterX on LibraryFilter {
  String get label {
    switch (this) {
      case LibraryFilter.all:
        return '全部';
      case LibraryFilter.emby:
        return 'Emby';
      case LibraryFilter.nas:
        return 'WebDAV';
    }
  }

  MediaSourceKind? get kind {
    switch (this) {
      case LibraryFilter.all:
        return null;
      case LibraryFilter.emby:
        return MediaSourceKind.emby;
      case LibraryFilter.nas:
        return MediaSourceKind.nas;
    }
  }
}

final libraryItemsProvider =
    FutureProvider.family<List<MediaItem>, LibraryFilter>((ref, filter) async {
  ref.watch(nasMediaIndexRevisionProvider);
  ref.watch(appSettingsProvider);
  ref.watch(localStorageDetailCacheRevisionProvider);
  final items =
      await ref.read(mediaRepositoryProvider).fetchLibrary(kind: filter.kind);
  return resolveLibraryItemsWithCachedDetails(
    items: items,
    localStorageCacheRepository: ref.read(localStorageCacheRepositoryProvider),
  );
});

final libraryCollectionsProvider =
    FutureProvider.family<List<MediaCollection>, LibraryFilter>((ref, filter) {
  ref.watch(nasMediaIndexRevisionProvider);
  ref.watch(appSettingsProvider);
  return ref.read(mediaRepositoryProvider).fetchCollections(kind: filter.kind);
});

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  LibraryFilter _filter = LibraryFilter.all;
  int _currentPage = 0;
  bool _isIncrementalRefreshing = false;
  bool _isForceRescanning = false;
  int _refreshIntentSerial = 0;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final itemsAsync = ref.watch(libraryItemsProvider(_filter));
    final collectionsAsync = ref.watch(libraryCollectionsProvider(_filter));
    final rebuildableSourceIds = _rebuildableWebDavSourceIds(settings);
    final scrapeProgress = ref.watch(webDavScrapeProgressProvider);
    final visibleProgress = _visibleWebDavProgress(
      scrapeProgress.values,
      settings,
    );

    return Scaffold(
      body: AppPageBackground(
        contentPadding: appPageContentPadding(
          context,
          includeBottomNavigationBar: true,
        ),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            SegmentedButton<LibraryFilter>(
              segments: LibraryFilter.values
                  .map(
                    (filter) => ButtonSegment(
                      value: filter,
                      label: Text(filter.label),
                    ),
                  )
                  .toList(),
              selected: {_filter},
              onSelectionChanged: (value) {
                setState(() {
                  _filter = value.first;
                  _currentPage = 0;
                });
              },
            ),
            const SizedBox(height: 18),
            if (rebuildableSourceIds.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _isIncrementalRefreshing || _isForceRescanning
                          ? null
                          : () => _runIncrementalRefresh(rebuildableSourceIds),
                      icon: _isIncrementalRefreshing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                      label: Text(
                        _isIncrementalRefreshing ? '更新中...' : '增量更新 WebDAV',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _isForceRescanning
                          ? null
                          : () => _confirmForceRescan(rebuildableSourceIds),
                      icon: _isForceRescanning
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.restart_alt_rounded),
                      label: Text(
                        _isForceRescanning ? '重建中...' : '重建 WebDAV 索引',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (visibleProgress.isNotEmpty) ...[
              ...visibleProgress.map(
                (progress) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _WebDavScrapeProgressCard(progress: progress),
                ),
              ),
              const SizedBox(height: 6),
            ],
            collectionsAsync.when(
              data: (collections) {
                if (collections.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: SizedBox(
                    height: 42,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: collections.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final collection = collections[index];
                        return ActionChip(
                          backgroundColor: Colors.white.withValues(alpha: 0.06),
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                          label: Text(collection.title),
                          onPressed: () {
                            context.pushNamed(
                              'collection',
                              extra: LibraryCollectionTarget(
                                title: collection.title,
                                sourceId: collection.sourceId,
                                sourceName: collection.sourceName,
                                sourceKind: collection.sourceKind,
                                sectionId: collection.id,
                                subtitle: collection.subtitle,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (error, stackTrace) => const SizedBox.shrink(),
            ),
            itemsAsync.when(
              data: (items) {
                return LibraryPagedGrid(
                  items: items,
                  currentPage: _currentPage,
                  onPageChanged: (page) {
                    setState(() {
                      _currentPage = page;
                    });
                  },
                  emptyMessage: '无',
                  header: Text(
                    _filter == LibraryFilter.all
                        ? '全部内容'
                        : '${_filter.label} 内容',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => Text('加载失败：$error'),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _rebuildableWebDavSourceIds(AppSettings settings) {
    if (_filter == LibraryFilter.emby) {
      return const [];
    }
    return settings.mediaSources
        .where(
          (source) => source.enabled && source.kind == MediaSourceKind.nas,
        )
        .map((source) => source.id.trim())
        .where((sourceId) => sourceId.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  List<WebDavScrapeProgress> _visibleWebDavProgress(
    Iterable<WebDavScrapeProgress> progressEntries,
    AppSettings settings,
  ) {
    if (_filter == LibraryFilter.emby) {
      return const [];
    }
    final enabledWebDavSourceIds = settings.mediaSources
        .where((source) => source.enabled && source.kind == MediaSourceKind.nas)
        .map((source) => source.id.trim())
        .where((sourceId) => sourceId.isNotEmpty)
        .toSet();
    final visible = progressEntries
        .where((entry) => enabledWebDavSourceIds.contains(entry.sourceId))
        .toList(growable: false)
      ..sort((left, right) => left.sourceName.compareTo(right.sourceName));
    return visible;
  }

  Future<void> _confirmForceRescan(List<String> sourceIds) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('重建 WebDAV 索引'),
            content: Text(
              _isIncrementalRefreshing
                  ? '当前正在执行增量更新。继续后会先停止这次增量，再对当前启用的 WebDAV 媒体源执行全量重扫。'
                  : '这会对当前启用的 WebDAV 媒体源执行全量重扫，忽略已有指纹并重新抓取 sidecar、WMDB、TMDB 和 IMDb 信息。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('开始重扫'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) {
      return;
    }
    await _runForceRescan(sourceIds);
  }

  Future<void> _runForceRescan(List<String> sourceIds) async {
    _refreshIntentSerial += 1;
    setState(() {
      _isIncrementalRefreshing = false;
      _isForceRescanning = true;
    });
    try {
      await ref.read(mediaRefreshCoordinatorProvider).refreshSelectedSources(
            sourceIds: sourceIds,
            forceFullRescan: true,
          );
      for (final filter in LibraryFilter.values) {
        ref.invalidate(libraryItemsProvider(filter));
        ref.invalidate(libraryCollectionsProvider(filter));
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sourceIds.length == 1
                ? '已完成 WebDAV 索引重建'
                : '已完成 ${sourceIds.length} 个 WebDAV 媒体源的全量重扫',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isForceRescanning = false;
        });
      }
    }
  }

  Future<void> _runIncrementalRefresh(List<String> sourceIds) async {
    final refreshIntent = ++_refreshIntentSerial;
    setState(() {
      _isIncrementalRefreshing = true;
    });
    try {
      await ref.read(mediaRefreshCoordinatorProvider).refreshSelectedSources(
            sourceIds: sourceIds,
            forceFullRescan: false,
          );
      if (refreshIntent != _refreshIntentSerial) {
        return;
      }
      for (final filter in LibraryFilter.values) {
        ref.invalidate(libraryItemsProvider(filter));
        ref.invalidate(libraryCollectionsProvider(filter));
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sourceIds.length == 1
                ? '已完成 WebDAV 增量更新'
                : '已完成 ${sourceIds.length} 个 WebDAV 媒体源的增量更新',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isIncrementalRefreshing = false;
        });
      }
    }
  }
}

class _WebDavScrapeProgressCard extends StatelessWidget {
  const _WebDavScrapeProgressCard({required this.progress});

  final WebDavScrapeProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  progress.sourceName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                progress.summaryLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (progress.detail.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              progress.detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.68),
              ),
            ),
          ],
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: progress.fraction,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
