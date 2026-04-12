import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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
import 'package:starflow/features/library/application/library_cached_items.dart';
import 'package:starflow/features/library/application/library_refresh_revision.dart';
import 'package:starflow/features/library/application/media_refresh_coordinator.dart';
import 'package:starflow/features/library/application/nas_media_index_revision.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/library_collection_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/presentation/widgets/library_paged_grid.dart';
import 'package:starflow/features/storage/application/local_storage_cache_revision.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

final libraryCollectionSeedItemsProvider =
    FutureProvider.family<List<MediaItem>, LibraryCollectionTarget>((
  ref,
  target,
) async {
  ref.watch(nasMediaIndexRevisionProvider);
  ref.watch(libraryRefreshRevisionProvider);
  return ref.read(mediaRepositoryProvider).fetchLibrary(
        sourceId: target.sourceId,
        sectionId: target.sectionId,
      );
});

final libraryCollectionItemsProvider =
    FutureProvider.family<List<MediaItem>, LibraryCollectionTarget>((
  ref,
  target,
) async {
  final items =
      await ref.watch(libraryCollectionSeedItemsProvider(target).future);
  final seedTargets =
      items.map(MediaDetailTarget.fromMediaItem).toList(growable: false);
  final cacheScope =
      LocalStorageCacheRepository.buildScopeForTargets(seedTargets);
  if (!cacheScope.isEmpty) {
    ref.watch(
      localStorageDetailCacheChangeProvider.select(
        (state) => state.revisionForScope(cacheScope),
      ),
    );
  }
  return resolveLibraryItemsWithCachedDetails(
    items: items,
    localStorageCacheRepository: ref.read(localStorageCacheRepositoryProvider),
    seedTargets: seedTargets,
  );
});

class LibraryCollectionVisiblePageRequest {
  const LibraryCollectionVisiblePageRequest({
    required this.target,
    required this.page,
    required this.pageSize,
  });

  final LibraryCollectionTarget target;
  final int page;
  final int pageSize;

  @override
  bool operator ==(Object other) {
    return other is LibraryCollectionVisiblePageRequest &&
        other.target == target &&
        other.page == page &&
        other.pageSize == pageSize;
  }

  @override
  int get hashCode => Object.hash(target, page, pageSize);
}

final libraryCollectionVisiblePageItemsProvider = FutureProvider.family<
    LibraryVisiblePageItemsResult,
    LibraryCollectionVisiblePageRequest>((ref, request) async {
  final items = await ref
      .watch(libraryCollectionSeedItemsProvider(request.target).future);
  await ref.read(localStorageCacheRepositoryProvider).primeDetailPayload();
  return LibraryVisiblePageItemsResult(
    totalItems: items.length,
    items: visibleLibraryPageItems(
      items: items,
      page: request.page,
      pageSize: request.pageSize,
    ),
  );
});

class LibraryCollectionPage extends ConsumerStatefulWidget {
  const LibraryCollectionPage({super.key, required this.target});

  final LibraryCollectionTarget target;

  @override
  ConsumerState<LibraryCollectionPage> createState() =>
      _LibraryCollectionPageState();
}

class _LibraryCollectionPageState extends ConsumerState<LibraryCollectionPage>
    with PageActivityMixin<LibraryCollectionPage> {
  static const int _gridPageSize = 24;
  int _currentPage = 0;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _headerFocusNode =
      FocusNode(debugLabel: 'library-collection-header');
  final TvFocusMemoryController _tvFocusMemoryController =
      TvFocusMemoryController();
  final DetailRatingPrefetchCoordinator _ratingPrefetchCoordinator =
      DetailRatingPrefetchCoordinator();
  AsyncValue<List<MediaItem>>? _cachedItemsAsync;
  final Map<LibraryCollectionVisiblePageRequest,
          AsyncValue<LibraryVisiblePageItemsResult>>
      _cachedVisibleItemsByRequest = <LibraryCollectionVisiblePageRequest,
          AsyncValue<LibraryVisiblePageItemsResult>>{};

  @override
  void dispose() {
    _headerFocusNode.dispose();
    _scrollController.dispose();
    _tvFocusMemoryController.dispose();
    super.dispose();
  }

  @override
  void onPageBecameInactive() {
    _ratingPrefetchCoordinator.reset();
    unawaited(
      ref.read(mediaRepositoryProvider).cancelActiveWebDavRefreshes(
            includeForceFull: false,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.target;
    final seedItemsAsync = resolveRetainedAsyncValue(
      activeValue: isPageVisible
          ? ref.watch(libraryCollectionSeedItemsProvider(target))
          : null,
      cachedValue: _cachedItemsAsync,
      cacheValue: (value) => _cachedItemsAsync = value,
      fallbackValue: const AsyncLoading<List<MediaItem>>(),
    );
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    final visiblePageRequest = LibraryCollectionVisiblePageRequest(
      target: target,
      page: _currentPage,
      pageSize: _gridPageSize,
    );
    final displayAsync = _resolveVisiblePageItemsAsync(
      request: visiblePageRequest,
      activeValue: isPageVisible
          ? ref.watch(
              libraryCollectionVisiblePageItemsProvider(visiblePageRequest),
            )
          : null,
      seedItemsAsync: seedItemsAsync,
    );

    final headerContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          target.title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          target.subtitle.trim().isEmpty
              ? '${target.sourceKind.label} · ${target.sourceName}'
              : '${target.sourceName} · ${target.subtitle}',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF90A0BD),
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );

    return TvPageFocusScope(
      controller: _tvFocusMemoryController,
      scopeId: _libraryCollectionFocusScopeId(target),
      isTelevision: isTelevision,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            AppPageBackground(
              child: ListView(
                controller: _scrollController,
                padding: overlayToolbarPagePadding(context),
                children: [
                  if (isTelevision)
                    TvFocusableAction(
                      onPressed: () => FocusScope.of(context).nextFocus(),
                      focusNode: _headerFocusNode,
                      focusId: 'library-collection:header',
                      borderRadius: BorderRadius.circular(20),
                      child: headerContent,
                    )
                  else
                    headerContent,
                  const SizedBox(height: 20),
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
                        focusScopePrefix:
                            _libraryCollectionGridFocusScopePrefix(target),
                        onPageChanged: _handleCollectionPageChanged,
                        onItemContextAction: (item) =>
                            _handleItemContextAction(item),
                        emptyMessage: '无',
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
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
                onBack: () => context.pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleCollectionPageChanged(int page) {
    if (page == _currentPage) {
      return;
    }
    setState(() {
      _currentPage = page;
    });
  }

  Future<void> _handleItemContextAction(MediaItem item) async {
    if (!_supportsManagedIndexedItem(item)) {
      return;
    }
    final action = await showModalBottomSheet<_LibraryCollectionItemAction>(
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
                    .pop(_LibraryCollectionItemAction.rebuildSourceIndex),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: StarflowSelectionTile(
                leading: const Icon(Icons.manage_search_rounded),
                title: '手动索引',
                onPressed: () => Navigator.of(context)
                    .pop(_LibraryCollectionItemAction.manualIndex),
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
                    .pop(_LibraryCollectionItemAction.deleteResource),
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
      case _LibraryCollectionItemAction.rebuildSourceIndex:
        await ref
            .read(mediaRefreshCoordinatorProvider)
            .rebuildSelectedSources(sourceIds: [item.sourceId]);
      case _LibraryCollectionItemAction.manualIndex:
        context.pushNamed(
          'metadata-index',
          extra: MediaDetailTarget.fromMediaItem(item),
        );
      case _LibraryCollectionItemAction.deleteResource:
        await _confirmDeleteResource(item);
    }
  }

  List<MediaItem> _visibleItemsForCurrentPage(List<MediaItem> items) {
    return visibleLibraryCollectionGridPageItems(
      items: items,
      page: _currentPage,
      pageSize: _gridPageSize,
    );
  }

  AsyncValue<LibraryVisiblePageItemsResult> _resolveVisiblePageItemsAsync({
    required LibraryCollectionVisiblePageRequest request,
    required AsyncValue<LibraryVisiblePageItemsResult>? activeValue,
    required AsyncValue<List<MediaItem>> seedItemsAsync,
  }) {
    final cachedValue = _cachedVisibleItemsByRequest[request];
    if (activeValue == null) {
      return cachedValue ?? _seedVisiblePageItemsFallback(seedItemsAsync);
    }
    if (activeValue.hasValue || activeValue.hasError) {
      _cachedVisibleItemsByRequest[request] = activeValue;
      return activeValue;
    }
    return cachedValue ?? _seedVisiblePageItemsFallback(seedItemsAsync);
  }

  AsyncValue<LibraryVisiblePageItemsResult> _seedVisiblePageItemsFallback(
    AsyncValue<List<MediaItem>> seedItemsAsync,
  ) {
    final items = seedItemsAsync.asData?.value;
    if (items == null) {
      return const AsyncLoading<LibraryVisiblePageItemsResult>();
    }
    return AsyncData(
      LibraryVisiblePageItemsResult(
        totalItems: items.length,
        items: _visibleItemsForCurrentPage(items),
      ),
    );
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
                  ? '将从${_managedSourceLabel(item)}删除“${item.title}”对应目录，并从本地索引中移除相关条目。'
                  : '将从${_managedSourceLabel(item)}删除“${item.title}”对应文件，并从本地索引中移除该条目。',
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

  String _managedSourceLabel(MediaItem item) {
    return item.sourceKind == MediaSourceKind.quark ? ' Quark ' : ' WebDAV ';
  }
}

enum _LibraryCollectionItemAction {
  rebuildSourceIndex,
  manualIndex,
  deleteResource,
}

String _libraryCollectionFocusScopeId(LibraryCollectionTarget target) {
  return buildTvFocusScopeId(
    prefix: 'library-collection',
    segments: [
      target.sourceKind.name,
      target.sourceId,
      target.sectionId,
      target.title,
      target.subtitle,
    ],
  );
}

String _libraryCollectionGridFocusScopePrefix(LibraryCollectionTarget target) {
  return buildTvFocusId(
    prefix: 'library-collection:grid',
    segments: [
      target.sourceKind.name,
      target.sourceId,
      target.sectionId,
      target.title,
    ],
  );
}

@visibleForTesting
List<MediaItem> visibleLibraryCollectionGridPageItems({
  required List<MediaItem> items,
  required int page,
  required int pageSize,
}) {
  if (items.isEmpty) {
    return const [];
  }
  final safePageSize = math.max(1, pageSize);
  final totalPages = (items.length / safePageSize).ceil();
  final safePage =
      totalPages <= 0 ? 0 : math.min(math.max(page, 0), totalPages - 1);
  return items
      .skip(safePage * safePageSize)
      .take(safePageSize)
      .toList(growable: false);
}

@visibleForTesting
bool libraryCollectionVisibleSegmentChanged({
  required List<MediaItem> previousItems,
  required List<MediaItem> nextItems,
  required int page,
  required int pageSize,
}) {
  final previousVisible = visibleLibraryCollectionGridPageItems(
    items: previousItems,
    page: page,
    pageSize: pageSize,
  );
  final nextVisible = visibleLibraryCollectionGridPageItems(
    items: nextItems,
    page: page,
    pageSize: pageSize,
  );
  if (previousVisible.length != nextVisible.length) {
    return true;
  }
  for (var index = 0; index < previousVisible.length; index++) {
    if (!_libraryCollectionGridMediaItemsVisuallyEquivalent(
      previousVisible[index],
      nextVisible[index],
    )) {
      return true;
    }
  }
  return false;
}

bool _libraryCollectionGridMediaItemsVisuallyEquivalent(
  MediaItem a,
  MediaItem b,
) {
  if (a.id != b.id) {
    return false;
  }
  if (a.title != b.title || a.year != b.year) {
    return false;
  }
  if (a.durationLabel != b.durationLabel) {
    return false;
  }
  if (a.posterUrl != b.posterUrl) {
    return false;
  }
  if (!mapEquals(a.posterHeaders, b.posterHeaders)) {
    return false;
  }
  if (!listEquals(a.ratingLabels, b.ratingLabels)) {
    return false;
  }
  return true;
}
