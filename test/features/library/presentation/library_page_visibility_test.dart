import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/presentation/library_collection_page.dart';
import 'package:starflow/features/library/presentation/library_page.dart';

MediaItem _buildMediaItem(int index) {
  return MediaItem(
    id: 'movie-$index',
    title: 'Movie #$index',
    overview: '',
    posterUrl: 'https://example.com/poster-$index.png',
    year: 2000 + index,
    durationLabel: '${90 + index}',
    genres: const [],
    sourceId: 'source',
    sourceName: 'Source',
    sourceKind: MediaSourceKind.emby,
    streamUrl: 'stream://movie/$index',
    addedAt: DateTime(2024, 1, 1),
  );
}

List<MediaItem> _buildMediaItems(int count) =>
    List.generate(count, _buildMediaItem);

void main() {
  group('LibraryPage visibility helpers', () {
    final items = _buildMediaItems(30);

    test('visibleLibraryGridPageItems slices the requested page', () {
      final pageItems = visibleLibraryGridPageItems(
        items: items,
        page: 0,
        pageSize: 5,
      );
      expect(pageItems.length, 5);
      expect(pageItems.first.id, 'movie-0');
      expect(pageItems.last.id, 'movie-4');
    });

    test('libraryPageVisibleSegmentChanged ignores updates outside the page', () {
      final previous = List<MediaItem>.from(items);
      final next = List<MediaItem>.from(items);
      next[10] = next[10].copyWith(title: 'Changed Title');
      final changed = libraryPageVisibleSegmentChanged(
        previousItems: previous,
        nextItems: next,
        page: 0,
        pageSize: 5,
      );
      expect(changed, isFalse);
    });

    test('libraryPageVisibleSegmentChanged detects updates on visible items', () {
      final previous = List<MediaItem>.from(items);
      final next = List<MediaItem>.from(items);
      next[2] = next[2].copyWith(title: 'Changed Title');
      final changed = libraryPageVisibleSegmentChanged(
        previousItems: previous,
        nextItems: next,
        page: 0,
        pageSize: 5,
      );
      expect(changed, isTrue);
    });
  });

  group('LibraryCollectionPage visibility helpers', () {
    final items = _buildMediaItems(40);

    test('visibleLibraryCollectionGridPageItems slices correctly', () {
      final pageItems = visibleLibraryCollectionGridPageItems(
        items: items,
        page: 1,
        pageSize: 6,
      );
      expect(pageItems.length, 6);
      expect(pageItems.first.id, 'movie-6');
      expect(pageItems.last.id, 'movie-11');
    });

    test(
        'libraryCollectionVisibleSegmentChanged ignores non-visible updates',
        () {
      final previous = List<MediaItem>.from(items);
      final next = List<MediaItem>.from(items);
      next[30] = next[30].copyWith(posterUrl: 'https://example.com/other.png');
      final changed = libraryCollectionVisibleSegmentChanged(
        previousItems: previous,
        nextItems: next,
        page: 1,
        pageSize: 6,
      );
      expect(changed, isFalse);
    });

    test('libraryCollectionVisibleSegmentChanged detects visible item updates',
        () {
      final previous = List<MediaItem>.from(items);
      final next = List<MediaItem>.from(items);
      next[8] = next[8].copyWith(posterUrl: 'https://example.com/other.png');
      final changed = libraryCollectionVisibleSegmentChanged(
        previousItems: previous,
        nextItems: next,
        page: 1,
        pageSize: 6,
      );
      expect(changed, isTrue);
    });
  });
}
