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
    homeModules: const [],
  );

  static const List<MediaItem> seedLibrary = [];

  static const List<DoubanEntry> seedDoubanRecommendations = [];

  static const List<DoubanEntry> seedDoubanWishList = [];
}
