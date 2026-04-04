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
          tmdbId: '693134',
          addedAt: DateTime.utc(2026, 4, 4),
        ),
      ];

      final matched = matchMediaItemByExternalIds(
        library,
        imdbId: 'tt15239678',
      );

      expect(matched?.id, 'movie-1');
    });

    test('matches tmdb id exactly', () {
      final library = [
        MediaItem(
          id: 'movie-2',
          title: 'Another Title',
          overview: '',
          posterUrl: '',
          year: 2024,
          durationLabel: '',
          genres: const [],
          sourceId: 'emby-main',
          sourceName: 'Home Emby',
          sourceKind: MediaSourceKind.emby,
          streamUrl: '',
          tmdbId: '693134',
          addedAt: DateTime.utc(2026, 4, 4),
        ),
      ];

      final matched = matchMediaItemByExternalIds(
        library,
        tmdbId: '693134',
      );

      expect(matched?.id, 'movie-2');
    });
  });
}
