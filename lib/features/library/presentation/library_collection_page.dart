import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/core/widgets/media_poster_tile.dart';
import 'package:starflow/core/widgets/section_panel.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/library_collection_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';

final libraryCollectionItemsProvider =
    FutureProvider.family<List<MediaItem>, LibraryCollectionTarget>((
  ref,
  target,
) {
  return ref.read(mediaRepositoryProvider).fetchLibrary(
        sourceId: target.sourceId,
        sectionId: target.sectionId,
      );
});

class LibraryCollectionPage extends ConsumerWidget {
  const LibraryCollectionPage({super.key, required this.target});

  final LibraryCollectionTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(libraryCollectionItemsProvider(target));

    return Scaffold(
      appBar: AppBar(title: Text(target.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          SectionPanel(
            title: target.title,
            subtitle: target.subtitle.trim().isEmpty
                ? '${target.sourceKind.label} · ${target.sourceName}'
                : '${target.sourceName} · ${target.subtitle}',
            child: itemsAsync.when(
              data: (items) {
                if (items.isEmpty) {
                  return const Text('无');
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: items
                      .map(
                        (item) => MediaPosterTile(
                          title: item.title,
                          subtitle: item.durationLabel,
                          posterUrl: item.posterUrl,
                          badges: [
                            item.sourceKind.label,
                            if (item.sectionName.trim().isNotEmpty)
                              item.sectionName,
                          ],
                          caption: item.overview,
                          actionLabel: '查看详情',
                          onTap: () {
                            context.pushNamed(
                              'detail',
                              extra: MediaDetailTarget.fromMediaItem(item),
                            );
                          },
                        ),
                      )
                      .toList(),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => Text('加载失败：$error'),
            ),
          ),
        ],
      ),
    );
  }
}
