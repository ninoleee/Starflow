import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/utils/media_rating_labels.dart';

void main() {
  group('resolvePreferredPosterRatingLabel', () {
    test('prefers douban over imdb and tmdb', () {
      expect(
        resolvePreferredPosterRatingLabel(const [
          'TMDB 7.1',
          'IMDb 8.0',
          '豆瓣 8.7',
        ]),
        '豆瓣 8.7',
      );
    });

    test('falls back to imdb before tmdb', () {
      expect(
        resolvePreferredPosterRatingLabel(const [
          'TMDB 7.1',
          'IMDb 8.0',
        ]),
        'IMDb 8.0',
      );
    });

    test('ignores zero-valued source ratings', () {
      expect(
        resolvePreferredPosterRatingLabel(const [
          '豆瓣 0',
          'IMDb 7.9',
          'TMDB 7.4',
        ]),
        'IMDb 7.9',
      );
    });

    test('supports douban-only selection', () {
      expect(
        resolvePreferredPosterRatingLabel(
          const ['IMDb 7.9', 'TMDB 7.4', '豆瓣 8.3'],
          preferDoubanOnly: true,
        ),
        '豆瓣 8.3',
      );
      expect(
        resolvePreferredPosterRatingLabel(
          const ['IMDb 7.9', 'TMDB 7.4'],
          preferDoubanOnly: true,
        ),
        isEmpty,
      );
    });
  });

  group('mergeDistinctRatingLabels', () {
    test('keeps one label per source and prefers usable values', () {
      expect(
        mergeDistinctRatingLabels(
          const ['豆瓣 0', 'TMDB 7.1'],
          const ['豆瓣 8.6', 'IMDb 7.9', 'TMDB 7.4'],
        ),
        const ['豆瓣 8.6', 'TMDB 7.1', 'IMDb 7.9'],
      );
    });
  });
}
