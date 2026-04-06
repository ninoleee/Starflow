import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/domain/media_title_matcher.dart';

void main() {
  group('matchMediaItemByExternalIds', () {
    test('matches imdb id exactly before fuzzy title matching', () {
      final library = [
        MediaItem(
          id: 'movie-1',
          title: 'Completely Different Title',
          overview: '',
          posterUrl: '',
          year: 2024,
          durationLabel: '',
          genres: const [],
          sourceId: 'emby-main',
          sourceName: 'Home Emby',
          sourceKind: MediaSourceKind.emby,
          streamUrl: '',
          imdbId: 'tt15239678',
          addedAt: DateTime.utc(2026, 4, 4),
        ),
      ];

      final matched = matchMediaItemByExternalIds(
        library,
        imdbId: 'tt15239678',
      );

      expect(matched?.id, 'movie-1');
    });

    test('falls back to tmdb when imdb id is unavailable', () {
      final library = [
        MediaItem(
          id: 'movie-1',
          title: 'Avatar',
          overview: '',
          posterUrl: '',
          year: 2009,
          durationLabel: '',
          genres: const [],
          sourceId: 'emby-main',
          sourceName: 'Home Emby',
          sourceKind: MediaSourceKind.emby,
          streamUrl: '',
          tmdbId: '19995',
          addedAt: DateTime.utc(2026, 4, 4),
        ),
      ];

      expect(
        matchMediaItemByExternalIds(library, tmdbId: '19995')?.id,
        'movie-1',
      );
    });

    test('always prefers imdb over lower-priority ids', () {
      final library = [
        MediaItem(
          id: 'tmdb-match-first',
          title: 'Avatar',
          overview: '',
          posterUrl: '',
          year: 2009,
          durationLabel: '',
          genres: const [],
          sourceId: 'emby-main',
          sourceName: 'Home Emby',
          sourceKind: MediaSourceKind.emby,
          streamUrl: '',
          tmdbId: '19995',
          addedAt: DateTime.utc(2026, 4, 4),
        ),
        MediaItem(
          id: 'imdb-match-second',
          title: 'Avatar',
          overview: '',
          posterUrl: '',
          year: 2009,
          durationLabel: '',
          genres: const [],
          sourceId: 'emby-main',
          sourceName: 'Home Emby',
          sourceKind: MediaSourceKind.emby,
          streamUrl: '',
          imdbId: 'tt0499549',
          addedAt: DateTime.utc(2026, 4, 4),
        ),
      ];

      final matched = matchMediaItemByExternalIds(
        library,
        imdbId: 'tt0499549',
        tmdbId: '19995',
      );

      expect(matched?.id, 'imdb-match-second');
    });
  });

  group('listScoredMediaItemsMatchingTitles', () {
    test('returns all items above threshold sorted by score', () {
      final library = [
        MediaItem(
          id: 'a',
          title: 'Inception',
          overview: '',
          posterUrl: '',
          year: 2010,
          durationLabel: '',
          genres: const [],
          sourceId: 's1',
          sourceName: 'NAS',
          sourceKind: MediaSourceKind.nas,
          streamUrl: '',
          addedAt: DateTime.utc(2026, 4, 4),
        ),
        MediaItem(
          id: 'b',
          title: 'Inception Remux',
          overview: '',
          posterUrl: '',
          year: 2010,
          durationLabel: '',
          genres: const [],
          sourceId: 's1',
          sourceName: 'NAS',
          sourceKind: MediaSourceKind.nas,
          streamUrl: '',
          addedAt: DateTime.utc(2026, 4, 4),
        ),
        MediaItem(
          id: 'c',
          title: 'Other Movie',
          overview: '',
          posterUrl: '',
          year: 2020,
          durationLabel: '',
          genres: const [],
          sourceId: 's1',
          sourceName: 'NAS',
          sourceKind: MediaSourceKind.nas,
          streamUrl: '',
          addedAt: DateTime.utc(2026, 4, 4),
        ),
      ];

      final list = listScoredMediaItemsMatchingTitles(
        library,
        titles: const ['Inception'],
        year: 2010,
      );

      expect(list.length, 2);
      expect(list.map((e) => e.item.id).toList(), ['a', 'b']);
      expect(list.first.score >= list.last.score, isTrue);
    });
  });
}
