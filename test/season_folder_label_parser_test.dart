import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/data/season_folder_label_parser.dart';

void main() {
  group('season folder label parser', () {
    test('parses English and Chinese season keywords', () {
      expect(parseSeasonNumberFromFolderLabel('Season 01'), 1);
      expect(parseSeasonNumberFromFolderLabel('Series 2'), 2);
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
    });
  });
}
