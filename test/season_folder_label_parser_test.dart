import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/data/season_folder_label_parser.dart';

void main() {
  group('season folder label parser', () {
    test('parses English and Chinese season keywords', () {
      expect(parseSeasonNumberFromFolderLabel('Season 01'), 1);
      expect(parseSeasonNumberFromFolderLabel('Series 2'), 2);
      expect(parseSeasonNumberFromFolderLabel('SE08'), 8);
      expect(parseSeasonNumberFromFolderLabel('我的天才女友S3 蓝光版'), 3);
      expect(parseSeasonNumberFromFolderLabel('第一季'), 1);
      expect(parseSeasonNumberFromFolderLabel('第十二季'), 12);
      expect(parseSeasonNumberFromFolderLabel('第０季'), 0);
    });

    test('treats special folders as season zero', () {
      expect(parseSeasonNumberFromFolderLabel('Specials'), 0);
      expect(parseSeasonNumberFromFolderLabel('SP'), 0);
      expect(parseSeasonNumberFromFolderLabel('番外'), 0);
      expect(parseSeasonNumberFromFolderLabel('特别篇'), 0);
      expect(looksLikeSeasonFolderLabel('花絮'), isTrue);
    });

    test(
        'keeps part-style labels conservative and numeric topic folders intact',
        () {
      expect(parseSeasonNumberFromFolderLabel('第2部'), 2);
      expect(parseSeasonNumberFromFolderLabel('头文字D第2部'), isNull);
      expect(parseLeadingNumericSeasonNumber('9.韩国'), 9);
      expect(looksLikeNumericTopicSeason('5.美国'), isTrue);
      expect(looksLikeSeasonFolderLabel('呼啸山庄'), isFalse);
      expect(looksLikeStrictSeasonFolderLabel('SE10'), isTrue);
      expect(looksLikeStrictSeasonFolderLabel('我的天才女友S3 蓝光版'), isFalse);
    });

    test('recognizes nested year and quality episode-count grouping labels',
        () {
      expect(looksLikeYearGroupingFolderLabel('2025'), isTrue);
      expect(looksLikeYearGroupingFolderLabel('2026（4K）'), isTrue);
      expect(looksLikeYearGroupingFolderLabel('2026 电视剧'), isFalse);
      expect(looksLikeQualityEpisodeCountFolderLabel('4K 12集'), isTrue);
      expect(looksLikeQualityEpisodeCountFolderLabel('12集'), isFalse);
      expect(parseSeasonNumberFromFolderLabel('4K 12集'), isNull);
    });
  });
}
