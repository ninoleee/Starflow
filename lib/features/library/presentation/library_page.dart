import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/library_collection_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/presentation/widgets/library_paged_grid.dart';

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
        return 'NAS';
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
    FutureProvider.family<List<MediaItem>, LibraryFilter>((ref, filter) {
  return ref.read(mediaRepositoryProvider).fetchLibrary(kind: filter.kind);
});

final libraryCollectionsProvider =
    FutureProvider.family<List<MediaCollection>, LibraryFilter>((ref, filter) {
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

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(libraryItemsProvider(_filter));
    final collectionsAsync = ref.watch(libraryCollectionsProvider(_filter));

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
}
