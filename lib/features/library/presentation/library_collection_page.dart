import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/library/application/library_cached_items.dart';
import 'package:starflow/features/library/application/media_refresh_coordinator.dart';
import 'package:starflow/features/library/application/nas_media_index_revision.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/library_collection_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/presentation/widgets/library_paged_grid.dart';
import 'package:starflow/features/storage/application/local_storage_cache_revision.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

final libraryCollectionItemsProvider =
    FutureProvider.family<List<MediaItem>, LibraryCollectionTarget>((
  ref,
  target,
) async {
  ref.watch(nasMediaIndexRevisionProvider);
  ref.watch(localStorageDetailCacheRevisionProvider);
  final items = await ref.read(mediaRepositoryProvider).fetchLibrary(
        sourceId: target.sourceId,
        sectionId: target.sectionId,
      );
  return resolveLibraryItemsWithCachedDetails(
    items: items,
    localStorageCacheRepository: ref.read(localStorageCacheRepositoryProvider),
  );
});

class LibraryCollectionPage extends ConsumerStatefulWidget {
  const LibraryCollectionPage({super.key, required this.target});

  final LibraryCollectionTarget target;

  @override
  ConsumerState<LibraryCollectionPage> createState() =>
      _LibraryCollectionPageState();
}

class _LibraryCollectionPageState extends ConsumerState<LibraryCollectionPage> {
  int _currentPage = 0;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _headerFocusNode =
      FocusNode(debugLabel: 'library-collection-header');

  @override
  void dispose() {
    _headerFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _returnToTop() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_headerFocusNode.canRequestFocus) {
        return;
      }
      _headerFocusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.target;
    final itemsAsync = ref.watch(libraryCollectionItemsProvider(target));
    final isTelevision = ref.watch(isTelevisionProvider).valueOrNull ?? false;

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

    return TvReturnToTopScope(
      onReturnToTop: _returnToTop,
      child: Scaffold(
        body: TvDirectionalFocusBoundary(
          child: Stack(
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
                    itemsAsync.when(
                      data: (items) {
                        return LibraryPagedGrid(
                          items: items,
                          currentPage: _currentPage,
                          isTelevision: isTelevision,
                          onPageChanged: (page) {
                            setState(() {
                              _currentPage = page;
                            });
                          },
                          onItemContextAction: (item) =>
                              _handleItemContextAction(item),
                          emptyMessage: '无',
                        );
                      },
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
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
                  onBack: () => context.pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleItemContextAction(MediaItem item) async {
    if (item.sourceKind != MediaSourceKind.nas) {
      return;
    }
    final action = await showModalBottomSheet<_LibraryCollectionItemAction>(
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
        await context.pushNamed(
          'metadata-index',
          extra: MediaDetailTarget.fromMediaItem(item),
        );
      case _LibraryCollectionItemAction.deleteResource:
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

enum _LibraryCollectionItemAction {
  rebuildSourceIndex,
  manualIndex,
  deleteResource,
}
