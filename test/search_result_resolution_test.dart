import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/search/domain/search_result_resolution.dart';

void main() {
  final aliases = <SearchResultResolution, List<String>>{
    SearchResultResolution.ultra8k: ['8K', '4320p'],
    SearchResultResolution.ultra4k: ['4K', '2160P', 'UHD', 'Ultra HD'],
    SearchResultResolution.qhd: ['2k', '1440p', 'QHD'],
    SearchResultResolution.fullHd: ['1080p', '1080i', 'FHD', 'Full-HD'],
    SearchResultResolution.hd: ['720P'],
    SearchResultResolution.sd: ['480p', '576i', 'SD'],
  };
  for (final entry in aliases.entries) {
    for (final alias in entry.value) {
      test('recognizes $alias in Chinese and release titles', () {
        for (final title in ['电影$alias修复版', 'Movie.$alias.WEB-DL']) {
          expect(searchResultResolutions(_result(title)), {entry.key});
        }
      });
    }
  }

  test('collections match every explicitly advertised resolution', () {
    expect(searchResultResolutions(_result('电影合集 4K / 1080P / 720P')), {
      SearchResultResolution.ultra4k,
      SearchResultResolution.fullHd,
      SearchResultResolution.hd,
    });
  });

  test('uses quality and description but prioritizes explicit title labels',
      () {
    expect(searchResultResolutions(_result('电影', quality: '2160p')),
        {SearchResultResolution.ultra4k});
    expect(searchResultResolutions(_result('电影', summary: '完整版 1080P')),
        {SearchResultResolution.fullHd});
    expect(searchResultResolutions(_result('电影 720P', summary: '另有 4K 版本')),
        {SearchResultResolution.hd});
  });

  test('does not infer resolution from vague quality, numbers or identifiers',
      () {
    for (final title in [
      '电影 高清 蓝光 原画 HDR Dolby Vision REMUX HD',
      '电影 2024 2160 1080 720 x265 4KB 1080password A4K',
      'https://example.com/4K/1080p',
      '',
    ]) {
      expect(searchResultResolutions(_result(title)),
          {SearchResultResolution.unknown});
    }
  });

  test('ignores channel, date, provider and URL metadata', () {
    expect(
      searchResultResolutions(_result(
        '电影',
        source: '4K频道',
        summary: '4K频道 · https://example.com/1080p · 完整版',
      )),
      {SearchResultResolution.unknown},
    );
  });
}

SearchResult _result(String title,
        {String quality = '夸克网盘', String summary = '', String source = ''}) =>
    SearchResult(
      id: 'resource',
      title: title,
      posterUrl: '',
      providerId: 'provider',
      providerName: '8K资源',
      quality: quality,
      sizeLabel: '',
      seeders: 0,
      summary: summary,
      source: source,
      resourceUrl: 'https://example.com/4K',
    );
