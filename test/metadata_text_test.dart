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
        '',
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

    test('extracts deduplicated sources without changing original metadata',
        () {
      const raw = '原始视频：<a href="https://example.com/watch?a=1&amp;b=2">'
          '<b>BV123</b></a><br/><br/>正文'
          '<a href="https://example.com/watch?a=1&amp;b=2">重复</a>';
      final content = parseMetadataOverview(raw);
      expect(content.text, '正文');
      expect(content.sources.map((uri) => uri.toString()),
          ['https://example.com/watch?a=1&b=2']);
      expect(raw, contains('BV123'));
    });

    test('keeps paragraphs and only removes source-related breaks', () {
      expect(
        sanitizeMetadataOverviewText('<p>第一段。</p><p>来源：'
            '<a href="https://example.com">链接</a><br/><br/></p>'
            '<p>第二段。<br/>下一行。</p>'),
        '第一段。\n\n第二段。\n下一行。',
      );
      expect(sanitizeMetadataOverviewText('第一段。\n\n第二段。'), '第一段。\n\n第二段。');
    });

    test('preserves prose when there is no reliable source-label boundary', () {
      for (final prefix in ['前面内容原始视频：', '剧情是这样的：', '第一段包含很多重要正文：']) {
        expect(
            sanitizeMetadataOverviewText(
                '$prefix<a href="https://example.com">入口</a><br/>后文'),
            '$prefix后文');
      }
      expect(
          sanitizeMetadataOverviewText('正文，官网地址：'
              '<a href="https://example.com">入口</a>后文'),
          '正文，后文');
    });

    test('handles nested label formatting and escaped HTML', () {
      expect(
          sanitizeMetadataOverviewText('<b>原始视频</b>：'
              '<a href="https://example.com"><em>编号</em></a><br/>正文'),
          '正文');
      final content = parseMetadataOverview('原始视频：&lt;a '
          'href="https://example.com"&gt;编号&lt;/a&gt;&lt;br/&gt;正文');
      expect(content.text, '正文');
      expect(content.sources.single.host, 'example.com');
    });

    test('extracts plain URLs and keeps their surrounding punctuation', () {
      final content =
          parseMetadataOverview('正文。来源：https://example.com/watch。后文');
      expect(content.text, '正文。。后文');
      expect(content.sources.single.toString(), 'https://example.com/watch');
    });

    test('rejects unsafe or malformed launch targets and hidden content', () {
      for (final raw in [
        'javascript:alert(1)',
        'file:///tmp/a',
        '//example.com',
        'https://',
        'https://user:pass@example.com',
        'https://exa mple.com'
      ]) {
        expect(resolveMetadataSourceUri(raw), isNull);
        expect(parseMetadataOverview('<a href="$raw">链接</a>').sources, isEmpty);
      }
      expect(
          sanitizeMetadataOverviewText('<script>alert(1)</script>'
              '<style>body{}</style>正文<!-- comment -->'),
          '正文');
    });
  });
}
