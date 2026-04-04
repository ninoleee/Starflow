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
}
