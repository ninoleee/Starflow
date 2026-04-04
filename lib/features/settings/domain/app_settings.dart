import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/search/domain/search_models.dart';

enum HomeModuleType {
  doubanRecommendations,
  doubanWishList,
  recentlyAdded,
  embyLibrary,
  nasLibrary,
}

extension HomeModuleTypeX on HomeModuleType {
  String get label {
    switch (this) {
      case HomeModuleType.doubanRecommendations:
        return '豆瓣推荐';
      case HomeModuleType.doubanWishList:
        return '豆瓣想看';
      case HomeModuleType.recentlyAdded:
        return '最近新增';
      case HomeModuleType.embyLibrary:
        return 'Emby 媒体库';
      case HomeModuleType.nasLibrary:
        return 'NAS 媒体库';
    }
  }

  String get description {
    switch (this) {
      case HomeModuleType.doubanRecommendations:
        return '把豆瓣推荐条目和本地可播放资源关联起来';
      case HomeModuleType.doubanWishList:
        return '把想看片单和资源就绪状态放在一起';
      case HomeModuleType.recentlyAdded:
        return '展示最近同步进来的内容';
      case HomeModuleType.embyLibrary:
        return '展示 Emby 中最近可看的资源';
      case HomeModuleType.nasLibrary:
        return '展示 NAS 侧的片库亮点';
    }
  }

  static HomeModuleType fromName(String raw) {
    return HomeModuleType.values.firstWhere(
      (item) => item.name == raw,
      orElse: () => HomeModuleType.recentlyAdded,
    );
  }
}

class HomeModuleConfig {
  const HomeModuleConfig({
    required this.id,
    required this.type,
    required this.title,
    required this.enabled,
  });

  final String id;
  final HomeModuleType type;
  final String title;
  final bool enabled;

  HomeModuleConfig copyWith({
    String? id,
    HomeModuleType? type,
    String? title,
    bool? enabled,
  }) {
    return HomeModuleConfig(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'title': title,
      'enabled': enabled,
    };
  }

  factory HomeModuleConfig.fromJson(Map<String, dynamic> json) {
    return HomeModuleConfig(
      id: json['id'] as String? ?? '',
      type: HomeModuleTypeX.fromName(json['type'] as String? ?? ''),
      title: json['title'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? false,
    );
  }
}

class AppSettings {
  const AppSettings({
    required this.mediaSources,
    required this.searchProviders,
    required this.doubanAccount,
    required this.homeModules,
  });

  final List<MediaSourceConfig> mediaSources;
  final List<SearchProviderConfig> searchProviders;
  final DoubanAccountConfig doubanAccount;
  final List<HomeModuleConfig> homeModules;

  AppSettings copyWith({
    List<MediaSourceConfig>? mediaSources,
    List<SearchProviderConfig>? searchProviders,
    DoubanAccountConfig? doubanAccount,
    List<HomeModuleConfig>? homeModules,
  }) {
    return AppSettings(
      mediaSources: mediaSources ?? this.mediaSources,
      searchProviders: searchProviders ?? this.searchProviders,
      doubanAccount: doubanAccount ?? this.doubanAccount,
      homeModules: homeModules ?? this.homeModules,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mediaSources': mediaSources.map((item) => item.toJson()).toList(),
      'searchProviders': searchProviders.map((item) => item.toJson()).toList(),
      'doubanAccount': doubanAccount.toJson(),
      'homeModules': homeModules.map((item) => item.toJson()).toList(),
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      mediaSources: (json['mediaSources'] as List<dynamic>? ?? [])
          .map(
            (item) => MediaSourceConfig.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      searchProviders: (json['searchProviders'] as List<dynamic>? ?? [])
          .map(
            (item) => SearchProviderConfig.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      doubanAccount: DoubanAccountConfig.fromJson(
        Map<String, dynamic>.from(
          (json['doubanAccount'] as Map?) ?? const {},
        ),
      ),
      homeModules: (json['homeModules'] as List<dynamic>? ?? [])
          .map(
            (item) => HomeModuleConfig.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
    );
  }
}
