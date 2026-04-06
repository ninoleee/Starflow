import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/search/domain/search_models.dart';

class SeedData {
  static final AppSettings defaultSettings = AppSettings(
    mediaSources: const [],
    searchProviders: const [
      SearchProviderConfig(
        id: 'pansou-api',
        name: 'PanSou',
        kind: SearchProviderKind.panSou,
        endpoint: 'https://so.252035.xyz',
        enabled: false,
        parserHint: 'pansou-api',
      ),
    ],
    doubanAccount: const DoubanAccountConfig(
      enabled: true,
      userId: '',
      sessionCookie: '',
    ),
    homeModules: const [
      HomeModuleConfig(
        id: HomeModuleConfig.heroModuleId,
        type: HomeModuleType.hero,
        title: 'Hero',
        enabled: true,
      ),
      HomeModuleConfig(
        id: 'default-douban-tv-hot',
        type: HomeModuleType.doubanList,
        title: '热播新剧',
        enabled: true,
        doubanListUrl: 'https://m.douban.com/subject_collection/tv_hot',
      ),
      HomeModuleConfig(
        id: 'default-douban-movie-hot',
        type: HomeModuleType.doubanList,
        title: '豆瓣热门电影',
        enabled: true,
        doubanListUrl: 'https://m.douban.com/subject_collection/movie_hot_gaia',
      ),
      HomeModuleConfig(
        id: 'default-douban-show-hot',
        type: HomeModuleType.doubanList,
        title: '热播综艺',
        enabled: true,
        doubanListUrl: 'https://m.douban.com/subject_collection/show_hot',
      ),
    ],
    networkStorage: const NetworkStorageConfig(),
    homeHeroSourceModuleId: '',
    homeHeroStyle: HomeHeroStyle.normal,
    homeHeroLogoTitleEnabled: false,
    homeHeroBackgroundEnabled: true,
    translucentEffectsEnabled: true,
    highPerformanceModeEnabled: false,
    tmdbMetadataMatchEnabled: false,
    wmdbMetadataMatchEnabled: false,
    metadataMatchPriority: MetadataMatchProvider.tmdb,
    imdbRatingMatchEnabled: false,
    detailAutoLibraryMatchEnabled: false,
    tmdbReadAccessToken: '',
    playbackBackgroundPlaybackEnabled: true,
  );

  static const List<MediaItem> seedLibrary = [];

  static const List<DoubanEntry> seedDoubanRecommendations = [];

  static const List<DoubanEntry> seedDoubanWishList = [];
}
