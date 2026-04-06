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

    test('treats bare E01 naming as an episode cue', () {
      final result = NasMediaRecognizer.recognize(
        'Shows/陈鲁豫/陈鲁豫E01.strm',
      );

      expect(result.title, '陈鲁豫');
      expect(result.parentTitle, '陈鲁豫');
      expect(result.itemType, 'episode');
      expect(result.preferSeries, isTrue);
      expect(result.seasonNumber, isNull);
      expect(result.episodeNumber, 1);
    });

    test(
        'treats leading numeric release names as episode cues in series folder',
        () {
      final result = NasMediaRecognizer.recognize(
        'Shows/正义女神/01-4K.国&粤.(mkv).strm',
      );

      expect(result.title, '正义女神');
      expect(result.parentTitle, '正义女神');
      expect(result.itemType, 'episode');
      expect(result.preferSeries, isTrue);
      expect(result.seasonNumber, isNull);
      expect(result.episodeNumber, 1);
    });

    test('does not treat movie titles starting with numbers as episode cues',
        () {
      final result = NasMediaRecognizer.recognize(
        'Movies/十二怒汉/12 Angry Men (1957).mkv',
      );

      expect(result.title, '12 Angry Men');
      expect(result.itemType, isEmpty);
      expect(result.preferSeries, isTrue);
      expect(result.seasonNumber, isNull);
      expect(result.episodeNumber, isNull);
    });
  });
}
