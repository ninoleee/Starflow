import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/search/domain/search_models.dart';

void main() {
  group('search folder naming', () {
    const result = SearchResult(
      id: 'result-1',
      title: 'TMDB 标题',
      posterUrl: '',
      providerId: 'provider-1',
      providerName: 'PanSou',
      quality: '',
      sizeLabel: '',
      seeders: 0,
      summary: '',
      resourceUrl: 'https://pan.quark.cn/s/result-1',
      favoriteFolderName: '已收藏名称',
      originalSearchTitle: '原始搜索标题',
    );

    test('uses current search query when storing a favorite', () {
      expect(
        resolveSearchFavoriteFolderName(
          result: result,
          searchQuery: '当前搜索名',
        ),
        '当前搜索名',
      );
    });

    test('uses current search query when saving from search results', () {
      expect(
        resolveSearchSaveFolderName(
          result: result,
          isFavoriteResultsView: false,
          searchQuery: '搜索页名称',
        ),
        '搜索页名称',
      );
    });

    test('uses stored favorite folder name when saving from favorites', () {
      expect(
        resolveSearchSaveFolderName(
          result: result,
          isFavoriteResultsView: true,
          searchQuery: '不该生效的搜索名',
        ),
        '已收藏名称',
      );
    });
  });
}
