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
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/storage/application/local_storage_cache_revision.dart';
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
  webDav,
  quark,
}

extension _LibraryRefreshSourceKindX on _LibraryRefreshSourceKind {
  String get label {
    switch (this) {
      case _LibraryRefreshSourceKind.webDav:
        return 'WebDAV';
      case _LibraryRefreshSourceKind.quark:
        return 'Quark';
    }
  }

  String get rebuildTitle => '重建 $label 索引';

  String rebuildDescription({
    required bool interruptIncrementalRefresh,
  }) {
    if (interruptIncrementalRefresh) {
      return '当前正在执行增量更新。继续后会先停止这次增量，再对当前启用的 $label 媒体源执行全量重扫。';
    }
    switch (this) {
      case _LibraryRefreshSourceKind.webDav:
        return '这会对当前启用的 WebDAV 媒体源执行全量重扫，忽略已有指纹并重新抓取 sidecar、WMDB、TMDB 和 IMDb 信息。';
      case _LibraryRefreshSourceKind.quark:
        return '这会对当前启用的 Quark 媒体源执行全量重扫，并重新扫描目录结构推断、本地刮削与媒体条目。';
    }
  }

  String incrementalCompletedMessage(int sourceCount) {
    if (sourceCount == 1) {
      return '已完成 $label 增量更新';
    }
    return '已完成 $sourceCount 个 $label 媒体源的增量更新';
  }

  String rebuildCompletedMessage(int sourceCount) {
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
  });

  final _LibraryRefreshSourceKind kind;
  final List<String> sourceIds;

  String get incrementalButtonLabel => '增量更新 ${kind.label}';

  String get rebuildButtonLabel => '重建 ${kind.label} 索引';
}

final libraryMediaSourcesSettingsSliceProvider =
    Provider<List<MediaSourceConfig>>((ref) {
  return ref.watch(
    appSettingsProvider.select((settings) => settings.mediaSources),
  );
});

final libraryItemsProvider =
    FutureProvider.family<List<MediaItem>, LibraryFilter>((ref, filter) async {
  ref.watch(nasMediaIndexRevisionProvider);
  ref.watch(libraryRefreshRevisionProvider);
  ref.watch(libraryMediaSourcesSettingsSliceProvider);
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
  final Map<LibraryFilter, AsyncValue<List<MediaItem>>> _cachedItemsByFilter =
      <LibraryFilter, AsyncValue<List<MediaItem>>>{};
  final Map<LibraryFilter, AsyncValue<List<MediaCollection>>>
      _cachedCollectionsByFilter =
      <LibraryFilter, AsyncValue<List<MediaCollection>>>{};
  Map<String, WebDavScrapeProgress> _cachedScrapeProgress =
      <String, WebDavScrapeProgress>{};

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
    final settings = ref.watch(appSettingsProvider);
    final isTelevision = ref.watch(isTelevisionProvider).valueOrNull ?? false;
    final itemsAsync = resolveRetainedAsyncValue(
      activeValue:
          isPageVisible ? ref.watch(libraryItemsProvider(_filter)) : null,
      cachedValue: _cachedItemsByFilter[_filter],
      cacheValue: (value) => _cachedItemsByFilter[_filter] = value,
      fallbackValue: const AsyncLoading<List<MediaItem>>(),
    );
    final collectionsAsync = resolveRetainedAsyncValue(
      activeValue:
          isPageVisible ? ref.watch(libraryCollectionsProvider(_filter)) : null,
      cachedValue: _cachedCollectionsByFilter[_filter],
      cacheValue: (value) => _cachedCollectionsByFilter[_filter] = value,
      fallbackValue: const AsyncLoading<List<MediaCollection>>(),
    );
    final refreshScope = _currentRefreshScope(settings);
    final scrapeProgress = isPageVisible
        ? ref.watch(webDavScrapeProgressProvider)
        : _cachedScrapeProgress;
    if (isPageVisible) {
      _cachedScrapeProgress = scrapeProgress;
    }
    final visibleProgress = _visibleScrapeProgress(
      scrapeProgress.values,
      settings,
    );

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
                          onPressed: () {
                            setState(() {
                              _filter = LibraryFilter.values[index];
                              _currentPage = 0;
                            });
                          },
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
                          if (isTelevision)
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
                          else
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
                  itemsAsync.when(
                    data: (items) {
                      return LibraryPagedGrid(
                        items: items,
                        currentPage: _currentPage,
                        isTelevision: isTelevision,
                        focusScopePrefix: 'library',
                        onPageChanged: (page) {
                          setState(() {
                            _currentPage = page;
                          });
                        },
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

  _LibraryRefreshScope? _currentRefreshScope(AppSettings settings) {
    switch (_filter) {
      case LibraryFilter.nas:
        final sourceIds = _refreshableSourceIds(
          settings,
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
          settings,
          kind: MediaSourceKind.quark,
        );
        if (sourceIds.isEmpty) {
          return null;
        }
        return _LibraryRefreshScope(
          kind: _LibraryRefreshSourceKind.quark,
          sourceIds: sourceIds,
        );
      case LibraryFilter.all:
      case LibraryFilter.emby:
        return null;
    }
  }

  List<String> _refreshableSourceIds(
    AppSettings settings, {
    required MediaSourceKind kind,
  }) {
    return settings.mediaSources
        .where(
          (source) =>
              source.enabled &&
              source.kind == kind &&
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
    AppSettings settings,
  ) {
    late final MediaSourceKind scopedKind;
    switch (_filter) {
      case LibraryFilter.nas:
        scopedKind = MediaSourceKind.nas;
      case LibraryFilter.quark:
        scopedKind = MediaSourceKind.quark;
      case LibraryFilter.all:
      case LibraryFilter.emby:
        return const [];
    }
    final enabledVisibleSourceIds = settings.mediaSources
        .where(
          (source) =>
              source.enabled &&
              source.kind == scopedKind &&
              (scopedKind != MediaSourceKind.quark ||
                  source.hasConfiguredQuarkFolder),
        )
        .map((source) => source.id.trim())
        .where((sourceId) => sourceId.isNotEmpty)
        .toSet();
    final visible = progressEntries
        .where((entry) => enabledVisibleSourceIds.contains(entry.sourceId))
        .toList(growable: false)
      ..sort((left, right) => left.sourceName.compareTo(right.sourceName));
    return visible;
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
    if (item.sourceKind != MediaSourceKind.nas) {
      return;
    }
    final action = await showModalBottomSheet<_LibraryItemAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
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
            kind: _LibraryRefreshSourceKind.webDav,
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
                  ? '将从 WebDAV 删除“${item.title}”对应目录，并从本地索引中移除相关条目。'
                  : '将从 WebDAV 删除“${item.title}”对应文件，并从本地索引中移除该条目。',
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
