import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/core/widgets/media_poster_tile.dart';
import 'package:starflow/core/widgets/section_panel.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/media_models.dart';

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

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  LibraryFilter _filter = LibraryFilter.all;

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(libraryItemsProvider(_filter));

    return Scaffold(
      appBar: AppBar(title: const Text('媒体库')),
      body: AppPageBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            SectionPanel(
              title: '你的媒体源',
              subtitle: '首页模块来自同一套媒体库抽象，所以这里和首页能保持一致',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                      });
                    },
                  ),
                  const SizedBox(height: 18),
                  itemsAsync.when(
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
                                subtitle: item.year > 0 ? '${item.year}' : '',
                                posterUrl: item.posterUrl,
                                onTap: () {
                                  context.pushNamed(
                                    'detail',
                                    extra:
                                        MediaDetailTarget.fromMediaItem(item),
                                  );
                                },
                              ),
                            )
                            .toList(),
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, stackTrace) => Text('加载失败：$error'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
