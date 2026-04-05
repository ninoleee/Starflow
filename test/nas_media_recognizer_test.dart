import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/domain/nas_media_recognition.dart';

void main() {
  group('NasMediaRecognizer', () {
    test('extracts clean movie title and year from release file name', () {
      final result = NasMediaRecognizer.recognize(
        'Movies/The.Matrix.1999.1080p.BluRay.x265.mkv',
      );

      expect(result.title, 'The Matrix');
      expect(result.searchQuery, 'The Matrix');
      expect(result.year, 1999);
      expect(result.itemType, isEmpty);
      expect(result.preferSeries, isFalse);
      expect(result.seasonNumber, isNull);
      expect(result.episodeNumber, isNull);
    });

    test('uses parent folders to resolve series episode names', () {
      final result = NasMediaRecognizer.recognize(
        'Shows/繁城之下/第1季/第05集.strm',
      );

      expect(result.title, '繁城之下');
      expect(result.parentTitle, '繁城之下');
      expect(result.itemType, 'episode');
      expect(result.preferSeries, isTrue);
      expect(result.seasonNumber, 1);
      expect(result.episodeNumber, 5);
    });

    test('extracts imdb and tmdb ids from file and folder names', () {
      final result = NasMediaRecognizer.recognize(
        'Movies/Dune {tmdb-438631}/Dune.Part.One.tt1160419.2021.mkv',
      );

      expect(result.imdbId, 'tt1160419');
    });

    test('prioritizes explicit SxxEyy naming for series title inference', () {
      final result = NasMediaRecognizer.recognize(
        'Shows/怪奇物语/Stranger.Things.S01.2160p.BluRay.REMUX/Stranger.Things.S01E02.Chapter.Two.strm',
      );

      expect(result.title, '怪奇物语');
      expect(result.parentTitle, '怪奇物语');
      expect(result.itemType, 'episode');
      expect(result.preferSeries, isTrue);
      expect(result.seasonNumber, 1);
      expect(result.episodeNumber, 2);
    });
  });
}
