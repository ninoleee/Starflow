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

    test('strips embedded external id tags from dotted series folders', () {
      final result = NasMediaRecognizer.recognize(
        'Shows/圆桌派.Round Table (2016) {tmdbid-95903}/Season 1/圆桌派.Round Table (2016) S01E01.师徒.{tmdbid-95903}.strm',
      );

      expect(result.title, '圆桌派 Round Table');
      expect(result.parentTitle, '圆桌派 Round Table');
      expect(result.searchQuery, '圆桌派 Round Table');
      expect(result.itemType, 'episode');
      expect(result.preferSeries, isTrue);
      expect(result.seasonNumber, 1);
      expect(result.episodeNumber, 1);
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

    test('recognizes SE season folders and dotted episode numbers', () {
      final result = NasMediaRecognizer.recognize(
        'Shows/老友记/SE08/老友记.H265.1080P.SE08.06.(mkv).strm',
      );

      expect(result.title, '老友记');
      expect(result.parentTitle, '老友记');
      expect(result.itemType, 'episode');
      expect(result.preferSeries, isTrue);
      expect(result.seasonNumber, 8);
      expect(result.episodeNumber, 6);
    });

    test('recognizes a season suffix attached to a Chinese series title', () {
      final result = NasMediaRecognizer.recognize(
        'Shows/我的天才女友/我的天才女友S3 蓝光版/我的天才女友.Lamica.geniale.S03E08.1080p.strm',
      );

      expect(result.title, '我的天才女友');
      expect(result.parentTitle, '我的天才女友');
      expect(result.itemType, 'episode');
      expect(result.seasonNumber, 3);
      expect(result.episodeNumber, 8);
    });

    test('uses hash-numbered parent folders as season one episodes', () {
      final result = NasMediaRecognizer.recognize(
        'Shows/陈鲁豫/陈鲁豫 · 慢谈 #19 对话张泉灵/video.strm',
        seriesTitleFilterKeywords: const ['shows'],
      );

      expect(result.title, '陈鲁豫');
      expect(result.parentTitle, '陈鲁豫');
      expect(result.itemType, 'episode');
      expect(result.preferSeries, isTrue);
      expect(result.seasonNumber, 1);
      expect(result.episodeNumber, 19);
    });

    test('does not treat unrelated hashtag folders as episodes', () {
      final result = NasMediaRecognizer.recognize(
        'Shows/纪录片/Research #19/video.mkv',
        seriesTitleFilterKeywords: const ['shows'],
      );

      expect(result.itemType, isEmpty);
      expect(result.seasonNumber, isNull);
      expect(result.episodeNumber, isNull);
    });

    test('does not treat hashtag numbers in file names as episode cues', () {
      final result = NasMediaRecognizer.recognize(
        'Movies/纪录片/Research #19.mkv',
      );

      expect(result.itemType, isEmpty);
      expect(result.seasonNumber, isNull);
      expect(result.episodeNumber, isNull);
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
