import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/search/domain/search_models.dart';

class SeedData {
  static final AppSettings defaultSettings = AppSettings(
    mediaSources: const [],
    searchProviders: const [
      SearchProviderConfig(
        id: 'pansou-api',
        name: 'PanSou API',
        kind: SearchProviderKind.indexer,
        endpoint: 'https://so.252035.xyz',
        enabled: false,
        parserHint: 'pansou-api',
      ),
    ],
    doubanAccount: const DoubanAccountConfig(
      enabled: false,
      userId: '',
      sessionCookie: '',
    ),
    homeModules: const [
      HomeModuleConfig(
        id: 'module-douban-recommendations',
        type: HomeModuleType.doubanRecommendations,
        title: '豆瓣推荐',
        enabled: true,
      ),
      HomeModuleConfig(
        id: 'module-douban-wish',
        type: HomeModuleType.doubanWishList,
        title: '豆瓣想看',
        enabled: true,
      ),
      HomeModuleConfig(
        id: 'module-recently-added',
        type: HomeModuleType.recentlyAdded,
        title: '最近新增',
        enabled: true,
      ),
      HomeModuleConfig(
        id: 'module-emby-library',
        type: HomeModuleType.embyLibrary,
        title: 'Emby 片库',
        enabled: true,
      ),
      HomeModuleConfig(
        id: 'module-nas-library',
        type: HomeModuleType.nasLibrary,
        title: 'NAS 片库',
        enabled: true,
      ),
    ],
  );

  static const List<MediaItem> seedLibrary = [];

  static const List<DoubanEntry> seedDoubanRecommendations = [];

  static const List<DoubanEntry> seedDoubanWishList = [];
}
