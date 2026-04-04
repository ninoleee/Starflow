import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';

void main() {
  group('MediaDetailTarget.needsMetadataMatch', () {
    test('returns true when poster exists but rich metadata is missing', () {
      const target = MediaDetailTarget(
        title: 'Inception',
        posterUrl: 'https://example.com/poster.jpg',
        overview: '',
      );

      expect(target.needsMetadataMatch, isTrue);
    });

    test('returns true when overview is only a raw url', () {
      const target = MediaDetailTarget(
        title: 'Movie File',
        posterUrl: '',
        overview: 'https://nas.local/dav/movies/file.mkv',
      );

      expect(target.needsMetadataMatch, isTrue);
    });

    test('returns false when overview or cast data is already useful', () {
      const target = MediaDetailTarget(
        title: 'Arrival',
        posterUrl: 'https://example.com/poster.jpg',
        overview: 'A linguist works with the military after alien crafts land.',
      );

      expect(target.needsMetadataMatch, isFalse);
    });
  });

  group('MediaDetailTarget.needsImdbRatingMatch', () {
    test('returns true when only non-IMDb ratings exist', () {
      const target = MediaDetailTarget(
        title: 'Inception',
        posterUrl: '',
        overview: '',
        ratingLabels: ['豆瓣 8.8'],
      );

      expect(target.needsImdbRatingMatch, isTrue);
    });

    test('returns false when IMDb rating already exists', () {
      const target = MediaDetailTarget(
        title: 'Inception',
        posterUrl: '',
        overview: '',
        ratingLabels: ['IMDb 8.7', '豆瓣 8.8'],
      );

      expect(target.needsImdbRatingMatch, isFalse);
    });
  });
}
