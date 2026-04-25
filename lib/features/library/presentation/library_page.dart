import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/navigation/page_activity_mixin.dart';
import 'package:starflow/core/navigation/retained_async_value.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/application/detail_rating_prefetch_coordinator.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/application/library_cached_items.dart';
import 'package:starflow/features/library/application/library_refresh_revision.dart';
import 'package:starflow/features/library/application/media_refresh_coordinator.dart';
import 'package:starflow/features/library/application/nas_media_index_revision.dart';
import 'package:starflow/features/library/application/webdav_scrape_progress.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/library_collection_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/presentation/widgets/library_paged_grid.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

enum LibraryFilter {
  all,
  emby,
  nas,
  quark,
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
      case LibraryFilter.quark:
        return 'Quark';
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
      case LibraryFilter.quark:
        return MediaSourceKind.quark;
    }
  }
}

enum _LibraryRefreshSourceKind {
  emby,
  indexed,
  webDav,
  quark,
}

extension _LibraryRefreshSourceKindX on _LibraryRefreshSourceKind {
  String get label {
    switch (this) {
      case _LibraryRefreshSourceKind.emby:
        return 'Emby';
      case _LibraryRefreshSourceKind.indexed:
        return '非 Emby';
      case _LibraryRefreshSourceKind.webDav:
        return 'WebDAV';
      case _LibraryRefreshSourceKind.quark:
        return 'Quark';
    }
  }

  String get rebuildTitle {
    switch (this) {
      case _LibraryRefreshSourceKind.emby:
      case _LibraryRefreshSourceKind.indexed:
        return '重建索引';
      case _LibraryRefreshSourceKind.webDav:
      case _LibraryRefreshSourceKind.quark:
        return '重建 $label 索引';
    }
  }

  String rebuildDescription({
    required bool interruptIncrementalRefresh,
  }) {
    if (this == _LibraryRefreshSourceKind.emby) {
      return '';
    }
    if (interruptIncrementalRefresh) {
      if (this == _LibraryRefreshSourceKind.indexed) {
        return '当前正在执行增量更新。继续后会先停止这次增量，再对当前启用的 WebDAV 和 Quark 媒体源执行全量重扫。';
      }
      return '当前正在执行增量更新。继续后会先停止这次增量，再对当前启用的 $label 媒体源执行全量重扫。';
    }
    switch (this) {
      case _LibraryRefreshSourceKind.emby:
        return '';
      case _LibraryRefreshSourceKind.indexed:
        return '这会同时对当前启用的 WebDAV 和 Quark 媒体源执行全量重扫，忽略已有指纹并重新建立本地索引。';
      case _LibraryRefreshSourceKind.webDav:
        return '这会对当前启用的 WebDAV 媒体源执行全量重扫，忽略已有指纹并重新抓取 sidecar、WMDB 和 TMDB 信息。';
      case _LibraryRefreshSourceKind.quark:
        return '这会对当前启用的 Quark 媒体源执行全量重扫，并重新扫描目录结构推断、本地刮削与媒体条目。';
    }
  }

  String incrementalCompletedMessage(int sourceCount) {
    if (this == _LibraryRefreshSourceKind.emby) {
      return sourceCount == 1 ? '已完成 Emby 更新' : '已完成 $sourceCount 个 Emby 媒体源更新';
    }
    if (this == _LibraryRefreshSourceKind.indexed) {
      if (sourceCount == 1) {
        return '已完成非 Emby 媒体源增量更新';
      }
      return '已完成 $sourceCount 个非 Emby 媒体源的增量更新';
    }
    if (sourceCount == 1) {
      return '已完成 $label 增量更新';
    }
    return '已完成 $sourceCount 个 $label 媒体源的增量更新';
  }

  String rebuildCompletedMessage(int sourceCount) {
    if (this == _LibraryRefreshSourceKind.indexed) {
      if (sourceCount == 1) {
        return '已完成非 Emby 媒体源索引重建';
      }
      return '已完成 $sourceCount 个非 Emby 媒体源的全量重扫';
    }
    if (sourceCount == 1) {
      return '已完成 $label 索引重建';
    }
    return '已完成 $sourceCount 个 $label 媒体源的全量重扫';
  }
}

class _LibraryRefreshScope {
  const _LibraryRefreshScope({
    required this.kind,
    required this.sourceIds,
    this.supportsRebuild = true,
  });

  final _LibraryRefreshSourceKind kind;
  final List<String> sourceIds;
  final bool supportsRebuild;

  String get incrementalButtonLabel {
    switch (kind) {
      case _LibraryRefreshSourceKind.emby:
        return '更新';
      case _LibraryRefreshSourceKind.indexed:
        return '增量更新';
      case _LibraryRefreshSourceKind.webDav:
      case _LibraryRefreshSourceKind.quark:
        return '增量更新 ${kind.label}';
    }
  }

  String get rebuildButtonLabel => kind == _LibraryRefreshSourceKind.indexed
      ? '重建索引'
      : '重建 ${kind.label} 索引';
}

final libraryMediaSourcesSettingsSliceProvider =
    Provider<List<MediaSourceConfig>>((ref) {
  return ref.watch(
    appSettingsProvider.select((settings) => settings.mediaSources),
  );
});

final librarySeedItemsProvider =
    FutureProvider.family<List<MediaItem>, LibraryFilter>((ref, filter) async {
  ref.watch(nasMediaIndexRevisionProvider);
  ref.watch(libraryRefreshRevisionProvider);
  ref.watch(libraryMediaSourcesSettingsSliceProvider);
  return ref.read(mediaRepositoryProvider).fetchLibrary(kind: filter.kind);
});

final libraryItemsProvider =
    FutureProvider.family<List<MediaItem>, LibraryFilter>((ref, filter) {
  return ref.watch(librarySeedItemsProvider(filter).future);
});

class LibraryVisiblePageRequest {
  const LibraryVisiblePageRequest({
    required this.filter,
    required this.page,
    required this.pageSize,
  });

  final LibraryFilter filter;
  final int page;
  final int pageSize;

  @override
  bool operator ==(Object other) {
    return other is LibraryVisiblePageRequest &&
        other.filter == filter &&
        other.page == page &&
        other.pageSize == pageSize;
  }

  @override
  int get hashCode => Object.hash(filter, page, pageSize);
}

final libraryVisiblePageItemsProvider = FutureProvider.family<
    LibraryVisiblePageItemsResult,
    LibraryVisiblePageRequest>((ref, request) async {
  final liveOverlayEnabled = ref.watch(
    effectivePerformanceLiveItemHeroOverlayEnabledProvider,
  );
  final items =
      await ref.watch(librarySeedItemsProvider(request.filter).future);
  final cacheRepository = ref.read(localStorageCacheRepositoryProvider);
  if (!liveOverlayEnabled) {
    return resolveVisibleLibraryPageItemsWithCachedDetails(
      items: items,
      page: request.page,
      pageSize: request.pageSize,
      localStorageCacheRepository: cacheRepository,
    );
  }
  await cacheRepository.primeDetailPayload();
  return LibraryVisiblePageItemsResult(
    totalItems: items.length,
    items: visibleLibraryPageItems(
      items: items,
      page: request.page,
      pageSize: request.pageSize,
    ),
  );
});

final libraryCollectionsProvider =
    FutureProvider.family<List<MediaCollection>, LibraryFilter>((ref, filter) {
  ref.watch(nasMediaIndexRevisionProvider);
  ref.watch(libraryRefreshRevisionProvider);
  ref.watch(libraryMediaSourcesSettingsSliceProvider);
  return ref.read(mediaRepositoryProvider).fetchCollections(kind: filter.kind);
});

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage>
    with PageActivityMixin<LibraryPage> {
  static const int _gridPageSize = 24;
  LibraryFilter _filter = LibraryFilter.all;
  int _currentPage = 0;
  bool _isIncrementalRefreshing = false;
  bool _isForceRescanning = false;
  int _refreshIntentSerial = 0;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _topFilterFocusNode =
      FocusNode(debugLabel: 'library-filter-top');
  final TvFocusMemoryController _tvFocusMemoryController =
      TvFocusMemoryController();
  final DetailRatingPrefetchCoordinator _ratingPrefetchCoordinator =
      DetailRatingPrefetchCoordinator();
  final Map<LibraryVisiblePageRequest,
          AsyncValue<LibraryVisiblePageItemsResult>>
      _cachedVisibleItemsByRequest =
      <LibraryVisiblePageRequest, AsyncValue<LibraryVisiblePageItemsResult>>{};
  final Map<LibraryFilter, AsyncValue<List<MediaCollection>>>
      _cachedCollectionsByFilter =
      <LibraryFilter, AsyncValue<List<MediaCollection>>>{};

  @override
  void dispose() {
    _topFilterFocusNode.dispose();
    _scrollController.dispose();
    _tvFocusMemoryController.dispose();
    super.dispose();
  }

  @override
  void onPageBecameInactive() {
    _refreshIntentSerial += 1;
    _ratingPrefetchCoordinator.reset();
    unawaited(
      ref.read(mediaRepositoryProvider).cancelActiveWebDavRefreshes(
            includeForceFull: false,
          ),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isIncrementalRefreshing = false;
      _isForceRescanning = false;
    });
  }

  void _handleBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.goNamed('home');
  }

  @override
  Widget build(BuildContext context) {
    final mediaSources = ref.watch(libraryMediaSourcesSettingsSliceProvider);
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    final visiblePageRequest = LibraryVisiblePageRequest(
      filter: _filter,
      page: _currentPage,
      pageSize: _gridPageSize,
    );
    final displayAsync = resolveRetainedAsyncValue(
      activeValue: isPageVisible
          ? ref.watch(libraryVisiblePageItemsProvider(visiblePageRequest))
          : null,
      cachedValue: _cachedVisibleItemsByRequest[visiblePageRequest],
      cacheValue: (value) {
        _cachedVisibleItemsByRequest[visiblePageRequest] = value;
        _pruneVisiblePageCache(visiblePageRequest);
      },
      fallbackValue: const AsyncLoading<LibraryVisiblePageItemsResult>(),
    );
    final collectionsAsync = resolveRetainedAsyncValue(
      activeValue:
          isPageVisible ? ref.watch(libraryCollectionsProvider(_filter)) : null,
      cachedValue: _cachedCollectionsByFilter[_filter],
      cacheValue: (value) => _cachedCollectionsByFilter[_filter] = value,
      fallbackValue: const AsyncLoading<List<MediaCollection>>(),
    );
    final refreshScope = _currentRefreshScope(mediaSources);

    return TvPageFocusScope(
      controller: _tvFocusMemoryController,
      scopeId: 'library',
      isTelevision: isTelevision,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            AppPageBackground(
              contentPadding: appPageContentPadding(
                context,
                includeBottomNavigationBar: true,
              ),
              child: ListView(
                controller: _scrollController,
                padding: EdgeInsets.zero,
                children: [
                  const SizedBox(height: kToolbarHeight),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (var index = 0;
                          index < LibraryFilter.values.length;
                          index++)
                        _LibraryFilterChip(
                          filter: LibraryFilter.values[index],
                          selected: LibraryFilter.values[index] == _filter,
                          focusNode: index == 0 ? _topFilterFocusNode : null,
                          focusId:
                              'library:filter:${LibraryFilter.values[index].name}',
                          autofocus: index == 0 && isTelevision,
                          onPressed: () =>
                              _selectFilter(LibraryFilter.values[index]),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (refreshScope != null &&
                      refreshScope.sourceIds.isNotEmpty) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          if (isTelevision)
                            TvAdaptiveButton(
                              label: _isIncrementalRefreshing
                                  ? '更新中...'
                                  : refreshScope.incrementalButtonLabel,
                              icon: Icons.refresh_rounded,
                              onPressed:
                                  _isIncrementalRefreshing || _isForceRescanning
                                      ? null
                                      : () => _runIncrementalRefresh(
                                            refreshScope,
                                          ),
                              variant: TvButtonVariant.outlined,
                              focusId: 'library:refresh:incremental',
                            )
                          else
                            OutlinedButton.icon(
                              onPressed:
                                  _isIncrementalRefreshing || _isForceRescanning
                                      ? null
                                      : () => _runIncrementalRefresh(
                                            refreshScope,
                                          ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                minimumSize: const Size(0, 40),
                                visualDensity: VisualDensity.compact,
                              ),
                              icon: _isIncrementalRefreshing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.refresh_rounded),
                              label: Text(
                                _isIncrementalRefreshing
                                    ? '更新中...'
                                    : refreshScope.incrementalButtonLabel,
                              ),
                            ),
                          if (refreshScope.supportsRebuild && isTelevision)
                            TvAdaptiveButton(
                              label: _isForceRescanning
                                  ? '重建中...'
                                  : refreshScope.rebuildButtonLabel,
                              icon: Icons.restart_alt_rounded,
                              onPressed: _isForceRescanning
                                  ? null
                                  : () => _confirmForceRescan(
                                        refreshScope,
                                      ),
                              variant: TvButtonVariant.outlined,
                              focusId: 'library:refresh:rescan',
                            )
                          else if (refreshScope.supportsRebuild)
                            OutlinedButton.icon(
                              onPressed: _isForceRescanning
                                  ? null
                                  : () => _confirmForceRescan(
                                        refreshScope,
                                      ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                minimumSize: const Size(0, 40),
                                visualDensity: VisualDensity.compact,
                              ),
                              icon: _isForceRescanning
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.restart_alt_rounded),
                              label: Text(
                                _isForceRescanning
                                    ? '重建中...'
                                    : refreshScope.rebuildButtonLabel,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _buildScrapeProgressSection(mediaSources),
                  collectionsAsync.when(
                    data: (collections) {
                      if (collections.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: SizedBox(
                          height: 56,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            clipBehavior: Clip.none,
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            itemCount: collections.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(width: 10),
                            itemBuilder: (context, index) {
                              final collection = collections[index];
                              return _LibraryCollectionChip(
                                label: collection.title,
                                focusId: 'library:collection:${collection.id}',
                                autofocus: index == 0 && isTelevision,
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
                  displayAsync.when(
                    data: (pageItems) {
                      _ratingPrefetchCoordinator.schedulePrefetch(
                        ref: ref,
                        targets: pageItems.items
                            .map(MediaDetailTarget.fromMediaItem),
                        isPageActive: () => mounted && isPageVisible,
                      );
                      return LibraryPagedGrid(
                        pageItems: pageItems.items,
                        totalItems: pageItems.totalItems,
                        currentPage: _currentPage,
                        isTelevision: isTelevision,
                        focusScopePrefix: 'library',
                        onPageChanged: _handleLibraryPageChanged,
                        onItemContextAction: (item) =>
                            _handleItemContextAction(item),
                        emptyMessage: '无',
                        header: Text(
                          _filter == LibraryFilter.all
                              ? '全部内容'
                              : '${_filter.label} 内容',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                        ),
                      );
                    },
                    loading: () => const Center(
                      child: CircularProgressIndicator(),
                    ),
                    error: (error, stackTrace) => Text('加载失败：$error'),
                  ),
                  appPageBottomSpacer(),
                ],
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: OverlayToolbar(
                onBack: _handleBack,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _pruneVisiblePageCache(LibraryVisiblePageRequest request) {
    pruneRetainedVisiblePageCacheEntries(
      entries: _cachedVisibleItemsByRequest,
      currentRequest: request,
      pageOf: (entry) => entry.page,
      isSameScope: (entry, currentRequest) =>
          entry.filter == currentRequest.filter &&
          entry.pageSize == currentRequest.pageSize,
    );
  }

  _LibraryRefreshScope? _currentRefreshScope(
    List<MediaSourceConfig> mediaSources,
  ) {
    switch (_filter) {
      case LibraryFilter.all:
        final sourceIds = _refreshableSourceIdsForIndexedSources(mediaSources);
        if (sourceIds.isEmpty) {
          return null;
        }
        return _LibraryRefreshScope(
          kind: _LibraryRefreshSourceKind.indexed,
          sourceIds: sourceIds,
        );
      case LibraryFilter.nas:
        final sourceIds = _refreshableSourceIds(
          mediaSources,
          kind: MediaSourceKind.nas,
        );
        if (sourceIds.isEmpty) {
          return null;
        }
        return _LibraryRefreshScope(
          kind: _LibraryRefreshSourceKind.webDav,
          sourceIds: sourceIds,
        );
      case LibraryFilter.quark:
        final sourceIds = _refreshableSourceIds(
          mediaSources,
          kind: MediaSourceKind.quark,
        );
        if (sourceIds.isEmpty) {
          return null;
        }
        return _LibraryRefreshScope(
          kind: _LibraryRefreshSourceKind.quark,
          sourceIds: sourceIds,
        );
      case LibraryFilter.emby:
        final sourceIds = _refreshableSourceIds(
          mediaSources,
          kind: MediaSourceKind.emby,
        );
        if (sourceIds.isEmpty) {
          return null;
        }
        return _LibraryRefreshScope(
          kind: _LibraryRefreshSourceKind.emby,
          sourceIds: sourceIds,
          supportsRebuild: false,
        );
    }
  }

  List<String> _refreshableSourceIdsForIndexedSources(
    List<MediaSourceConfig> mediaSources,
  ) {
    return {
      ..._refreshableSourceIds(
        mediaSources,
        kind: MediaSourceKind.nas,
      ),
      ..._refreshableSourceIds(
        mediaSources,
        kind: MediaSourceKind.quark,
      ),
    }.toList(growable: false);
  }

  List<String> _refreshableSourceIds(
    List<MediaSourceConfig> mediaSources, {
    required MediaSourceKind kind,
  }) {
    return mediaSources
        .where(
          (source) =>
              source.enabled &&
              source.kind == kind &&
              (kind != MediaSourceKind.emby || source.hasActiveSession) &&
              (kind != MediaSourceKind.quark ||
                  source.hasConfiguredQuarkFolder),
        )
        .map((source) => source.id.trim())
        .where((sourceId) => sourceId.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  List<WebDavScrapeProgress> _visibleScrapeProgress(
    Iterable<WebDavScrapeProgress> progressEntries,
    List<MediaSourceConfig> mediaSources,
  ) {
    final enabledVisibleSourceIds = switch (_filter) {
      LibraryFilter.all =>
        _refreshableSourceIdsForIndexedSources(mediaSources).toSet(),
      LibraryFilter.nas => _refreshableSourceIds(
          mediaSources,
          kind: MediaSourceKind.nas,
        ).toSet(),
      LibraryFilter.quark => _refreshableSourceIds(
          mediaSources,
          kind: MediaSourceKind.quark,
        ).toSet(),
      LibraryFilter.emby => const <String>{},
    };
    if (enabledVisibleSourceIds.isEmpty) {
      return const [];
    }
    final visible = progressEntries
        .where((entry) => enabledVisibleSourceIds.contains(entry.sourceId))
        .toList(growable: false)
      ..sort((left, right) => left.sourceName.compareTo(right.sourceName));
    return visible;
  }

  Widget _buildScrapeProgressSection(
    List<MediaSourceConfig> mediaSources,
  ) {
    if (!isPageVisible) {
      return const SizedBox.shrink();
    }
    return Consumer(
      builder: (context, ref, child) {
        final scrapeProgress = ref.watch(webDavScrapeProgressProvider);
        final visibleProgress = _visibleScrapeProgress(
          scrapeProgress.values,
          mediaSources,
        );
        if (visibleProgress.isEmpty) {
          return const SizedBox.shrink();
        }
        return RepaintBoundary(
          child: Column(
            children: [
              ...visibleProgress.map(
                (progress) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _WebDavScrapeProgressCard(progress: progress),
                ),
              ),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
  }

  void _selectFilter(LibraryFilter filter) {
    if (_filter == filter) {
      return;
    }
    setState(() {
      _filter = filter;
      _currentPage = 0;
      _cachedVisibleItemsByRequest.clear();
    });
  }

  void _handleLibraryPageChanged(int page) {
    if (page == _currentPage) {
      return;
    }
    setState(() {
      _currentPage = page;
    });
    _pruneVisiblePageCache(
      LibraryVisiblePageRequest(
        filter: _filter,
        page: page,
        pageSize: _gridPageSize,
      ),
    );
  }

  Future<void> _confirmForceRescan(_LibraryRefreshScope scope) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(scope.kind.rebuildTitle),
            content: Text(
              scope.kind.rebuildDescription(
                interruptIncrementalRefresh: _isIncrementalRefreshing,
              ),
            ),
            actions: [
              StarflowButton(
                label: '取消',
                onPressed: () => Navigator.of(context).pop(false),
                variant: StarflowButtonVariant.ghost,
                compact: true,
              ),
              StarflowButton(
                label: '开始重扫',
                onPressed: () => Navigator.of(context).pop(true),
                compact: true,
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) {
      return;
    }
    await _runForceRescan(scope);
  }

  Future<void> _runForceRescan(_LibraryRefreshScope scope) async {
    _refreshIntentSerial += 1;
    setState(() {
      _isIncrementalRefreshing = false;
      _isForceRescanning = true;
    });
    try {
      await ref
          .read(mediaRefreshCoordinatorProvider)
          .rebuildSelectedSources(sourceIds: scope.sourceIds);
      for (final filter in LibraryFilter.values) {
        ref.invalidate(librarySeedItemsProvider(filter));
        ref.invalidate(libraryItemsProvider(filter));
        ref.invalidate(libraryCollectionsProvider(filter));
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            scope.kind.rebuildCompletedMessage(scope.sourceIds.length),
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

  Future<void> _runIncrementalRefresh(_LibraryRefreshScope scope) async {
    final refreshIntent = ++_refreshIntentSerial;
    setState(() {
      _isIncrementalRefreshing = true;
    });
    try {
      await ref.read(mediaRefreshCoordinatorProvider).refreshSelectedSources(
            sourceIds: scope.sourceIds,
          );
      if (refreshIntent != _refreshIntentSerial) {
        return;
      }
      for (final filter in LibraryFilter.values) {
        ref.invalidate(librarySeedItemsProvider(filter));
        ref.invalidate(libraryItemsProvider(filter));
        ref.invalidate(libraryCollectionsProvider(filter));
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            scope.kind.incrementalCompletedMessage(scope.sourceIds.length),
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

  Future<void> _handleItemContextAction(MediaItem item) async {
    if (!_supportsManagedIndexedItem(item)) {
      return;
    }
    final action = await showModalBottomSheet<_LibraryItemAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: StarflowSelectionTile(
                title: item.title,
                subtitle: item.actualAddress.trim().isEmpty
                    ? item.sourceName
                    : item.actualAddress,
                onPressed: null,
                trailing: const SizedBox.shrink(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: StarflowSelectionTile(
                leading: const Icon(Icons.restart_alt_rounded),
                title: '重建当前源索引',
                onPressed: () => Navigator.of(context)
                    .pop(_LibraryItemAction.rebuildSourceIndex),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: StarflowSelectionTile(
                leading: const Icon(Icons.manage_search_rounded),
                title: '手动索引',
                onPressed: () =>
                    Navigator.of(context).pop(_LibraryItemAction.manualIndex),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: StarflowSelectionTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: item.isFolder ||
                        item.itemType == 'series' ||
                        item.itemType == 'season'
                    ? '删除目录'
                    : '删除文件',
                onPressed: () => Navigator.of(context)
                    .pop(_LibraryItemAction.deleteResource),
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case _LibraryItemAction.rebuildSourceIndex:
        await _runForceRescan(
          _LibraryRefreshScope(
            kind: _refreshSourceKindForItem(item),
            sourceIds: [item.sourceId],
          ),
        );
      case _LibraryItemAction.manualIndex:
        await context.pushNamed(
          'metadata-index',
          extra: MediaDetailTarget.fromMediaItem(item),
        );
      case _LibraryItemAction.deleteResource:
        await _confirmDeleteResource(item);
    }
  }

  Future<void> _confirmDeleteResource(MediaItem item) async {
    final directResourceUri = Uri.tryParse(item.id.trim());
    final resourcePath =
        directResourceUri != null && directResourceUri.hasScheme
            ? item.id.trim()
            : item.actualAddress.trim();
    if (resourcePath.isEmpty) {
      return;
    }
    final isDirectory =
        item.isFolder || item.itemType == 'series' || item.itemType == 'season';
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(isDirectory ? '删除目录' : '删除文件'),
            content: Text(
              isDirectory
                  ? '将从 ${_managedSourceLabel(item)} 删除“${item.title}”对应目录，并从本地索引中移除相关条目。'
                  : '将从 ${_managedSourceLabel(item)} 删除“${item.title}”对应文件，并从本地索引中移除该条目。',
            ),
            actions: [
              StarflowButton(
                label: '取消',
                onPressed: () => Navigator.of(context).pop(false),
                variant: StarflowButtonVariant.ghost,
                compact: true,
              ),
              StarflowButton(
                label: '确认删除',
                onPressed: () => Navigator.of(context).pop(true),
                variant: StarflowButtonVariant.danger,
                compact: true,
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) {
      return;
    }
    try {
      await ref.read(mediaRepositoryProvider).deleteResource(
            sourceId: item.sourceId,
            resourcePath: resourcePath,
            sectionId: item.sectionId,
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isDirectory ? '已删除目录' : '已删除文件')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$error')),
      );
    }
  }

  bool _supportsManagedIndexedItem(MediaItem item) {
    return item.sourceKind == MediaSourceKind.nas ||
        item.sourceKind == MediaSourceKind.quark;
  }

  _LibraryRefreshSourceKind _refreshSourceKindForItem(MediaItem item) {
    return item.sourceKind == MediaSourceKind.quark
        ? _LibraryRefreshSourceKind.quark
        : _LibraryRefreshSourceKind.webDav;
  }

  String _managedSourceLabel(MediaItem item) {
    return item.sourceKind == MediaSourceKind.quark ? 'Quark' : 'WebDAV';
  }
}

class _LibraryFilterChip extends StatelessWidget {
  const _LibraryFilterChip({
    required this.filter,
    required this.selected,
    required this.onPressed,
    this.focusNode,
    this.focusId,
    this.autofocus = false,
  });

  final LibraryFilter filter;
  final bool selected;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final String? focusId;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return StarflowChipButton(
      label: filter.label,
      selected: selected,
      onPressed: onPressed,
      focusNode: focusNode,
      focusId: focusId,
      autofocus: autofocus,
    );
  }
}

class _LibraryCollectionChip extends StatelessWidget {
  const _LibraryCollectionChip({
    required this.label,
    required this.onPressed,
    this.focusId,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback onPressed;
  final String? focusId;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return StarflowChipButton(
      label: label,
      selected: false,
      onPressed: onPressed,
      focusId: focusId,
      autofocus: autofocus,
    );
  }
}

enum _LibraryItemAction {
  rebuildSourceIndex,
  manualIndex,
  deleteResource,
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

@visibleForTesting
List<MediaItem> visibleLibraryGridPageItems({
  required List<MediaItem> items,
  required int page,
  required int pageSize,
}) {
  return visibleLibraryPageItems(
    items: items,
    page: page,
    pageSize: pageSize,
  );
}

@visibleForTesting
bool libraryPageVisibleSegmentChanged({
  required List<MediaItem> previousItems,
  required List<MediaItem> nextItems,
  required int page,
  required int pageSize,
}) {
  return visibleLibraryPageSegmentChanged(
    previousItems: previousItems,
    nextItems: nextItems,
    page: page,
    pageSize: pageSize,
  );
}
