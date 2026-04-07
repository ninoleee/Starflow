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

    test('tolerates malformed percent encoding in ASSRT download filenames', () {
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

  group('AssrtSubtitleRepository.parseSubhdSearchHtml', () {
    test('parses SubHD search results as search-only entries', () {
      const html = '''
<div class="bg-white shadow-sm rounded-3 mb-4">
  <div class="row">
    <div class="col-lg-10">
      <div class="pt-3 pe-3 pb-2 ps-3 ps-lg-0 position-relative">
        <div class="clearfix">
          <div class="float-start f16 fw-bold">
            <a class="link-dark align-middle" href='/a/GkvqpU'>地球脉动 第二季</a>
          </div>
          <div class="view-text text-secondary">
            <a href='/a/GkvqpU' class='link-dark'>
              Planet.Earth.II.E01.2016.USA.2160p.BluRay.REMUX.HEVC.HDR.DTS-HD.MA.5.1
            </a>
          </div>
          <div class="text-truncate py-2 f11">
            <span class="rounded p-1 me-1 text-white">官方字幕</span>
            <span class="p-1 fw-bold">简体</span>
            <span class="p-1 text-secondary">ASS</span>
          </div>
          <div class="pt-2 text-secondary f12">
            <span class='align-text-top me-3'>12k</span>
            <span class="align-text-top me-3">252</span>
            <span class="align-text-top me-3">2025-9-6 20:17</span>
          </div>
          <div class="pt-1 f12 text-secondary">
            发布人 <a class="fw-bold text-dark" href='/u/Adans' target='_blank'>Adans</a>
          </div>
        </div>
      </div>
    </div>
  </div>
</div>
''';

      final results = AssrtSubtitleRepository.parseSubhdSearchHtml(html);

      expect(results, hasLength(1));
      expect(results.first.id, 'subhd:GkvqpU');
      expect(results.first.source, OnlineSubtitleSource.subhd);
      expect(results.first.providerLabel, 'SubHD');
      expect(results.first.title, '地球脉动 第二季');
      expect(results.first.version,
          'Planet.Earth.II.E01.2016.USA.2160p.BluRay.REMUX.HEVC.HDR.DTS-HD.MA.5.1');
      expect(results.first.languageLabel, '简体');
      expect(results.first.packageKind, SubtitlePackageKind.subtitleFile);
      expect(results.first.canDownload, isFalse);
      expect(results.first.detailUrl, 'https://subhd.tv/a/GkvqpU');
    });
  });

  group('AssrtSubtitleRepository.parseYifyMoviePageHtml', () {
    test('parses YIFY movie subtitle rows into downloadable ZIP entries', () {
      const html = '''
<h2 class="movie-main-title">Dune: Part Two</h2>
<div class="movie-year">2024</div>
<table>
  <tbody>
    <tr data-id="618051">
      <td class="rating-cell"><span class="label label-success">5</span></td>
      <td class="flag-cell"><span class="sub-lang">Chinese</span></td>
      <td>
        <a href="/subtitles/dune-part-two-2024-chinese-yify-618051"><span class="text-muted">subtitle</span> Dune.Part.Two.2024.720p/1080p.WEBRip.x264.AAC-[YTS]<br />Dune.Part.Two.2024.1080p.AMZN.WEB-DL</a>
      </td>
      <td class="other-cell"></td>
      <td class="uploader-cell"><a href="/user/tester">tester</a></td>
    </tr>
  </tbody>
</table>
''';

      final results = AssrtSubtitleRepository.parseYifyMoviePageHtml(
        html,
        imdbId: 'tt15239678',
      );

      expect(results, hasLength(1));
      expect(results.first.id, 'yify:618051');
      expect(results.first.source, OnlineSubtitleSource.yify);
      expect(results.first.providerLabel, 'YIFY');
      expect(results.first.title, 'Dune: Part Two (2024)');
      expect(results.first.version,
          'Dune.Part.Two.2024.720p/1080p.WEBRip.x264.AAC-[YTS]');
      expect(results.first.languageLabel, 'Chinese');
      expect(results.first.canDownload, isTrue);
      expect(results.first.canAutoLoad, isTrue);
      expect(results.first.packageKind, SubtitlePackageKind.zipArchive);
      expect(
        results.first.downloadUrl,
        'https://www.yifysubtitles.ch/subtitle/dune-part-two-2024-chinese-yify-618051.zip',
      );
      expect(
        results.first.detailUrl,
        'https://www.yifysubtitles.ch/subtitles/dune-part-two-2024-chinese-yify-618051',
      );
    });
  });
}
