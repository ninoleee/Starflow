import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/features/library/application/library_cached_items.dart';
import 'package:starflow/features/library/application/nas_media_index_revision.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/library_collection_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
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

  @override
  Widget build(BuildContext context) {
    final target = widget.target;
    final itemsAsync = ref.watch(libraryCollectionItemsProvider(target));

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          AppPageBackground(
            child: ListView(
              padding: overlayToolbarPagePadding(context),
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
                const SizedBox(height: 20),
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
    );
  }
}
