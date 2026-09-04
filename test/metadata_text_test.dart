import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/utils/metadata_text.dart';

void main() {
  group('sanitizeMetadataOverviewText', () {
    test('removes the label, anchor, and keeps only the following synopsis',
        () {
      expect(
        sanitizeMetadataOverviewText(
          '原始视频：<a href="https://www.bilibili.com/video/BV1yhBjBSEzn/">'
          'BV1yhBjBSEzn</a><br/><br/>—段传奇，一个全世界瞩目的创业项目',
        ),
        '—段传奇，一个全世界瞩目的创业项目',
      );
    });

    test('removes anchor content for any label and keeps no line break', () {
      expect(
        sanitizeMetadataOverviewText(
          '在线观看：<a href="https://example.com">入口</a><br/>更多内容',
        ),
        '更多内容',
      );
    });

    test('keeps punctuation and content before the label', () {
      expect(
        sanitizeMetadataOverviewText(
          '前面内容。原始视频：<a href="https://example.com">链接</a><br/>正文',
        ),
        '前面内容。正文',
      );
    });

    test('keeps whitespace and content before the label', () {
      expect(
        sanitizeMetadataOverviewText(
          '前面内容 在线观看：<a href="https://example.com">入口</a><br/>更多内容',
        ),
        '前面内容 更多内容',
      );
    });

    test('removes unlabeled anchor content as well', () {
      expect(
        sanitizeMetadataOverviewText(
            '这是<a href="https://example.com">链接</a>内容'),
        '这是内容',
      );
    });

    test('handles malformed tags without a closing bracket', () {
      expect(
        sanitizeMetadataOverviewText('原始视频：<a br 这种连接'),
        '原始视频：',
      );
    });

    test('decodes common HTML entities', () {
      expect(
        sanitizeMetadataOverviewText(
            'A &amp; B&nbsp;&#39;C&#39; &lt; 8 &gt; 3'),
        'A & B \'C\' < 8 > 3',
      );
    });

    test('keeps ordinary comparison text intact', () {
      expect(sanitizeMetadataOverviewText('豆瓣评分 < 8，值得一看。'), '豆瓣评分 < 8，值得一看。');
    });
  });
}
