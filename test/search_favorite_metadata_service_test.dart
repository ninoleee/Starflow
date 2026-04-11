import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';
import 'package:starflow/features/search/application/search_favorite_metadata_service.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

AppSettings _testSettings() {
  return const AppSettings(
    mediaSources: [],
    searchProviders: [],
    doubanAccount: DoubanAccountConfig(enabled: false),
    homeModules: [
      HomeModuleConfig(
        id: HomeModuleConfig.heroModuleId,
        type: HomeModuleType.hero,
        title: 'Hero',
        enabled: true,
      ),
    ],
  );
}

void main() {
  group('SearchFavoriteMetadataService', () {
    test('serializes favorite metadata fields', () {
      const result = SearchResult(
        id: 'favorite-json',
        title: '三体',
        posterUrl: '',
        providerId: 'provider-1',
        providerName: 'PanSou',
        quality: '',
        sizeLabel: '',
        seeders: 0,
        summary: '',
        resourceUrl: 'https://pan.quark.cn/s/favorite-json',
        favoriteFolderName: '三体',
        originalSearchTitle: 'The Three-Body Problem 全集',
        metadataMediaType: 'series',
        doubanId: '35155748',
        imdbId: 'tt13016388',
        tmdbId: '205715',
        tvdbId: '387119',
        wikidataId: 'Q105005998',
      );

      final restored = SearchResult.fromJson(result.toJson());

      expect(restored.title, '三体');
      expect(restored.favoriteFolderName, '三体');
      expect(restored.originalSearchTitle, 'The Three-Body Problem 全集');
      expect(restored.metadataMediaType, 'series');
      expect(restored.doubanId, '35155748');
      expect(restored.imdbId, 'tt13016388');
      expect(restored.tmdbId, '205715');
      expect(restored.tvdbId, '387119');
      expect(restored.wikidataId, 'Q105005998');
    });

    test(
        'uses search name as favorite title and folder name while keeping TMDB ids',
        () async {
      MetadataMatchRequest? capturedRequest;
      final service = SearchFavoriteMetadataService(
        resolveMatch: ({
          required AppSettings settings,
          required MetadataMatchRequest request,
        }) async {
          capturedRequest = request;
          return const MetadataMatchResult(
            provider: MetadataMatchProvider.tmdb,
            mediaType: MetadataMediaType.series,
            title: '9号秘事',
            imdbId: 'tt2674806',
            tmdbId: '65707',
          );
        },
      );

      const result = SearchResult(
        id: 'favorite-1',
        title: '9号秘事 第1季 1080P',
        posterUrl: '',
        providerId: 'provider-1',
        providerName: 'PanSou',
        quality: '',
        sizeLabel: '',
        seeders: 0,
        summary: '',
        resourceUrl: 'https://pan.quark.cn/s/favorite-1',
        detailTarget: MediaDetailTarget(
          title: '9号秘事',
          posterUrl: '',
          overview: '',
          itemType: 'series',
          searchQuery: '9号秘事',
          imdbId: 'TT2674806',
        ),
      );

      final enriched = await service.enrichFavorite(
        result: result,
        query: '内九号',
        settings: _testSettings(),
      );

      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.query, '内九号');
      expect(capturedRequest!.imdbId, 'tt2674806');
      expect(capturedRequest!.preferSeries, isTrue);
      expect(enriched.title, '内九号');
      expect(enriched.favoriteFolderName, '内九号');
      expect(enriched.originalSearchTitle, '9号秘事 第1季 1080P');
      expect(enriched.imdbId, 'tt2674806');
      expect(enriched.tmdbId, '65707');
      expect(enriched.metadataMediaType, 'series');
    });

    test('keeps existing tmdb-based favorites without rematching', () async {
      var called = false;
      final service = SearchFavoriteMetadataService(
        resolveMatch: ({
          required AppSettings settings,
          required MetadataMatchRequest request,
        }) async {
          called = true;
          return null;
        },
      );

      const result = SearchResult(
        id: 'favorite-2',
        title: '三体',
        posterUrl: '',
        providerId: 'provider-1',
        providerName: 'PanSou',
        quality: '',
        sizeLabel: '',
        seeders: 0,
        summary: '',
        resourceUrl: 'https://pan.quark.cn/s/favorite-2',
        favoriteFolderName: '三体',
        tmdbId: '205715',
      );

      final enriched = await service.enrichFavorite(
        result: result,
        query: '三体',
        settings: _testSettings(),
      );

      expect(called, isFalse);
      expect(enriched.title, '三体');
      expect(enriched.favoriteFolderName, '三体');
      expect(enriched.tmdbId, '205715');
    });
  });
}
