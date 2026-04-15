import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/data/online_subtitle_repository_io.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';

void main() {
  group('buildSubtitleSearchQueryVariants', () {
    test('falls back from episode query to title only', () {
      expect(
        buildSubtitleSearchQueryVariants('请求救援 S01E01'),
        ['请求救援 S01E01', '请求救援'],
      );
    });

    test('falls back from movie query with year to title only', () {
      expect(
        buildSubtitleSearchQueryVariants('Dune Part Two 2024'),
        ['Dune Part Two 2024', 'Dune Part Two'],
      );
    });

    test('falls back from episode query with year to pure title', () {
      expect(
        buildSubtitleSearchQueryVariants('Dune Part Two 2024 S01E01'),
        ['Dune Part Two 2024 S01E01', 'Dune Part Two 2024', 'Dune Part Two'],
      );
    });
  });

  group('isAssrtErrorResponse', () {
    test('detects ASSRT error pages from body markers', () {
      expect(
        isAssrtErrorResponse(
          200,
          '<html><title>啊呀</title>java.money.noMoneyException 请您通过Email报告指向此页面的网址</html>',
        ),
        isTrue,
      );
    });

    test('treats 4xx responses as errors', () {
      expect(isAssrtErrorResponse(402, ''), isTrue);
    });
  });

  group('AssrtSubtitleRepository.parseAssrtSearchHtml', () {
    test('parses ASSRT search results and prioritizes auto-loadable entries',
        () {
      const html = '''
<div onmouseover="addclass(this,'subitem_hover')" onmouseout="redclass(this,'subitem_hover')" class="subitem">
  <a class="introtitle" title="Planet Earth II" href="/xml/sub/123/456.xml">Planet Earth II</a>
  <span>版本： WEB-DL 1080p</span>
  <span>格式： ASS</span>
  <span>语言： 简体中文</span>
  <span>来源： ASSRT</span>
  <span>日期： 2024-05-01</span>
  下载次数： 88
  用户评分9分(12人评分)
  <button onclick="javascript:location.href='/download/648270/Planet.Earth.II.ass';return false;">下载</button>
</div>
<div onmouseover="addclass(this,'subitem_hover')" onmouseout="redclass(this,'subitem_hover')" class="subitem">
  <a class="introtitle" title="Planet Earth II ZIP" href="/xml/sub/999/888.xml">Planet Earth II ZIP</a>
  <span>版本： BluRay</span>
  <span>格式： SRT</span>
  <span>语言： 中英双语</span>
  <span>来源： ASSRT</span>
  <span>日期： 2024-04-30</span>
  下载次数： 188
  用户评分7分(5人评分)
  <button onclick="javascript:location.href='/download/648271/Planet.Earth.II.zip';return false;">下载</button>
</div>
''';

      final results = AssrtSubtitleRepository.parseAssrtSearchHtml(html);

      expect(results, hasLength(2));
      expect(results.first.id, '648270');
      expect(results.first.source, OnlineSubtitleSource.assrt);
      expect(results.first.title, 'Planet Earth II');
      expect(results.first.packageKind, SubtitlePackageKind.subtitleFile);
      expect(results.first.canAutoLoad, isTrue);
      expect(results.first.downloadUrl,
          'https://assrt.net/download/648270/Planet.Earth.II.ass');
      expect(results.first.summaryLine, contains('字幕文件'));

      expect(results.last.id, '648271');
      expect(results.last.packageKind, SubtitlePackageKind.zipArchive);
      expect(results.last.canAutoLoad, isTrue);
      expect(results.last.detailUrl, 'https://assrt.net/xml/sub/999/888.xml');
    });

    test('tolerates malformed percent encoding in ASSRT download filenames',
        () {
      const html = '''
<div onmouseover="addclass(this,'subitem_hover')" onmouseout="redclass(this,'subitem_hover')" class="subitem">
  <a class="introtitle" title="The Protector" href="/xml/sub/123/456.xml">The Protector</a>
  <span>版本： WEB-DL 1080p</span>
  <span>格式： ASS</span>
  <span>语言： 简体中文</span>
  <span>来源： ASSRT</span>
  <span>日期： 2024-05-01</span>
  下载次数： 88
  <button onclick="javascript:location.href='/download/648270/The.Protector.100%.ass';return false;">下载</button>
</div>
''';

      final results = AssrtSubtitleRepository.parseAssrtSearchHtml(html);

      expect(results, hasLength(1));
      expect(results.first.id, '648270');
      expect(results.first.packageName, 'The.Protector.100%.ass');
      expect(results.first.packageKind, SubtitlePackageKind.subtitleFile);
      expect(results.first.canDownload, isTrue);
    });
  });
}
