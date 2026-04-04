import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/search/domain/search_models.dart';

enum HomeModuleType {
  recentlyAdded,
  librarySection,
  doubanInterest,
  doubanSuggestion,
  doubanList,
  doubanCarousel,
}

extension HomeModuleTypeX on HomeModuleType {
  String get label {
    switch (this) {
      case HomeModuleType.recentlyAdded:
        return '最近新增';
      case HomeModuleType.librarySection:
        return '来源分区';
      case HomeModuleType.doubanInterest:
        return '豆瓣我看';
      case HomeModuleType.doubanSuggestion:
        return '豆瓣个性化推荐';
      case HomeModuleType.doubanList:
        return '豆瓣片单';
      case HomeModuleType.doubanCarousel:
        return '豆瓣首页轮播';
    }
  }

  static HomeModuleType fromName(String raw) {
    return switch (raw) {
      'recentlyAdded' => HomeModuleType.recentlyAdded,
      'librarySection' => HomeModuleType.librarySection,
      'doubanInterest' => HomeModuleType.doubanInterest,
      'doubanSuggestion' => HomeModuleType.doubanSuggestion,
      'doubanList' => HomeModuleType.doubanList,
      'doubanCarousel' => HomeModuleType.doubanCarousel,
      // Legacy mappings
      'doubanRecommendations' => HomeModuleType.doubanSuggestion,
      'doubanWishList' => HomeModuleType.doubanInterest,
      'embyLibrary' => HomeModuleType.librarySection,
      'nasLibrary' => HomeModuleType.librarySection,
      _ => HomeModuleType.recentlyAdded,
    };
  }
}

enum HomeHeroStyle {
  normal,
  borderless,
}

extension HomeHeroStyleX on HomeHeroStyle {
  String get label {
    switch (this) {
      case HomeHeroStyle.normal:
        return '正常';
      case HomeHeroStyle.borderless:
        return '无边';
    }
  }

  static HomeHeroStyle fromName(String raw) {
    return switch (raw) {
      'borderless' => HomeHeroStyle.borderless,
      _ => HomeHeroStyle.normal,
    };
  }
}

class HomeModuleConfig {
  const HomeModuleConfig({
    required this.id,
    required this.type,
    required this.title,
    required this.enabled,
    this.sourceId = '',
    this.sourceName = '',
    this.sectionId = '',
    this.sectionName = '',
    this.doubanInterestStatus = DoubanInterestStatus.mark,
    this.doubanSuggestionType = DoubanSuggestionMediaType.movie,
    this.doubanListUrl = '',
  });

  final String id;
  final HomeModuleType type;
  final String title;
  final bool enabled;
  final String sourceId;
  final String sourceName;
  final String sectionId;
  final String sectionName;
  final DoubanInterestStatus doubanInterestStatus;
  final DoubanSuggestionMediaType doubanSuggestionType;
  final String doubanListUrl;

  String get description {
    switch (type) {
      case HomeModuleType.recentlyAdded:
        return '展示最近同步进来的内容';
      case HomeModuleType.librarySection:
        final sourcePart = sourceName.trim().isEmpty ? '资源来源' : sourceName;
        final sectionPart = sectionName.trim().isEmpty ? '分区' : sectionName;
        return '$sourcePart · $sectionPart';
      case HomeModuleType.doubanInterest:
        return doubanInterestStatus.label;
      case HomeModuleType.doubanSuggestion:
        return '个性化推荐 · ${doubanSuggestionType.label}';
      case HomeModuleType.doubanList:
        return doubanListUrl.trim().isEmpty ? '未填写片单地址' : doubanListUrl;
      case HomeModuleType.doubanCarousel:
        return '首页轮播';
    }
  }

  bool get isLibrarySection =>
      type == HomeModuleType.librarySection &&
      sourceId.trim().isNotEmpty &&
      sectionId.trim().isNotEmpty;

  HomeModuleConfig copyWith({
    String? id,
    HomeModuleType? type,
    String? title,
    bool? enabled,
    String? sourceId,
    String? sourceName,
    String? sectionId,
    String? sectionName,
    DoubanInterestStatus? doubanInterestStatus,
    DoubanSuggestionMediaType? doubanSuggestionType,
    String? doubanListUrl,
  }) {
    return HomeModuleConfig(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      enabled: enabled ?? this.enabled,
      sourceId: sourceId ?? this.sourceId,
      sourceName: sourceName ?? this.sourceName,
      sectionId: sectionId ?? this.sectionId,
      sectionName: sectionName ?? this.sectionName,
      doubanInterestStatus: doubanInterestStatus ?? this.doubanInterestStatus,
      doubanSuggestionType: doubanSuggestionType ?? this.doubanSuggestionType,
      doubanListUrl: doubanListUrl ?? this.doubanListUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'title': title,
      'enabled': enabled,
      'sourceId': sourceId,
      'sourceName': sourceName,
      'sectionId': sectionId,
      'sectionName': sectionName,
      'doubanInterestStatus': doubanInterestStatus.value,
      'doubanSuggestionType': doubanSuggestionType.value,
      'doubanListUrl': doubanListUrl,
    };
  }

  factory HomeModuleConfig.fromJson(Map<String, dynamic> json) {
    final type = HomeModuleTypeX.fromName(json['type'] as String? ?? '');
    final id = json['id'] as String? ?? '';

    return HomeModuleConfig(
      id: id,
      type: type,
      title: (json['title'] as String? ?? '').trim().isEmpty
          ? _fallbackTitle(type, json)
          : (json['title'] as String? ?? '').trim(),
      enabled: json['enabled'] as bool? ?? false,
      sourceId: json['sourceId'] as String? ?? '',
      sourceName: json['sourceName'] as String? ?? '',
      sectionId: json['sectionId'] as String? ?? '',
      sectionName: json['sectionName'] as String? ?? '',
      doubanInterestStatus: DoubanInterestStatusX.fromValue(
        json['doubanInterestStatus'] as String? ??
            _legacyInterestStatus(json['type'] as String? ?? '', id),
      ),
      doubanSuggestionType: DoubanSuggestionMediaTypeX.fromValue(
        json['doubanSuggestionType'] as String? ??
            _legacySuggestionType(json['type'] as String? ?? ''),
      ),
      doubanListUrl: json['doubanListUrl'] as String? ?? '',
    );
  }

  static String _fallbackTitle(HomeModuleType type, Map<String, dynamic> json) {
    return switch (type) {
      HomeModuleType.recentlyAdded => '最近新增',
      HomeModuleType.librarySection =>
        (json['sectionName'] as String? ?? '').trim().isEmpty
            ? '来源分区'
            : (json['sectionName'] as String? ?? '').trim(),
      HomeModuleType.doubanInterest => DoubanInterestStatusX.fromValue(
          json['doubanInterestStatus'] as String? ??
              _legacyInterestStatus(json['type'] as String? ?? '', ''),
        ).label,
      HomeModuleType.doubanSuggestion => '豆瓣个性化推荐',
      HomeModuleType.doubanList => '豆瓣片单',
      HomeModuleType.doubanCarousel => '豆瓣轮播',
    };
  }

  static String _legacyInterestStatus(String rawType, String id) {
    if (rawType == 'doubanWishList' || id.contains('wish')) {
      return DoubanInterestStatus.mark.value;
    }
    return DoubanInterestStatus.mark.value;
  }

  static String _legacySuggestionType(String rawType) {
    if (rawType == 'doubanRecommendations') {
      return DoubanSuggestionMediaType.movie.value;
    }
    return DoubanSuggestionMediaType.movie.value;
  }

  static HomeModuleConfig recentlyAdded() {
    return HomeModuleConfig(
      id: 'home-module-${DateTime.now().millisecondsSinceEpoch}',
      type: HomeModuleType.recentlyAdded,
      title: '最近新增',
      enabled: true,
    );
  }

  static HomeModuleConfig libraryCollection(MediaCollection collection) {
    return HomeModuleConfig(
      id: 'home-module-${DateTime.now().millisecondsSinceEpoch}',
      type: HomeModuleType.librarySection,
      title: collection.title,
      enabled: true,
      sourceId: collection.sourceId,
      sourceName: collection.sourceName,
      sectionId: collection.id,
      sectionName: collection.title,
    );
  }

  static HomeModuleConfig doubanInterest(DoubanInterestStatus status) {
    return HomeModuleConfig(
      id: 'home-module-${DateTime.now().millisecondsSinceEpoch}',
      type: HomeModuleType.doubanInterest,
      title: status.label,
      enabled: true,
      doubanInterestStatus: status,
    );
  }

  static HomeModuleConfig doubanSuggestion(
    DoubanSuggestionMediaType mediaType,
  ) {
    return HomeModuleConfig(
      id: 'home-module-${DateTime.now().millisecondsSinceEpoch}',
      type: HomeModuleType.doubanSuggestion,
      title: '豆瓣个性化推荐 · ${mediaType.label}',
      enabled: true,
      doubanSuggestionType: mediaType,
    );
  }

  static HomeModuleConfig doubanList({
    required String title,
    required String url,
  }) {
    return HomeModuleConfig(
      id: 'home-module-${DateTime.now().millisecondsSinceEpoch}',
      type: HomeModuleType.doubanList,
      title: title,
      enabled: true,
      doubanListUrl: url,
    );
  }

  static HomeModuleConfig doubanCarousel() {
    return HomeModuleConfig(
      id: 'home-module-${DateTime.now().millisecondsSinceEpoch}',
      type: HomeModuleType.doubanCarousel,
      title: '豆瓣轮播',
      enabled: true,
    );
  }
}

class AppSettings {
  const AppSettings({
    required this.mediaSources,
    required this.searchProviders,
    required this.doubanAccount,
    required this.homeModules,
    this.homeHeroStyle = HomeHeroStyle.normal,
    this.tmdbMetadataMatchEnabled = false,
    this.imdbRatingMatchEnabled = false,
    this.tmdbReadAccessToken = '',
  });

  final List<MediaSourceConfig> mediaSources;
  final List<SearchProviderConfig> searchProviders;
  final DoubanAccountConfig doubanAccount;
  final List<HomeModuleConfig> homeModules;
  final HomeHeroStyle homeHeroStyle;
  final bool tmdbMetadataMatchEnabled;
  final bool imdbRatingMatchEnabled;
  final String tmdbReadAccessToken;

  AppSettings copyWith({
    List<MediaSourceConfig>? mediaSources,
    List<SearchProviderConfig>? searchProviders,
    DoubanAccountConfig? doubanAccount,
    List<HomeModuleConfig>? homeModules,
    HomeHeroStyle? homeHeroStyle,
    bool? tmdbMetadataMatchEnabled,
    bool? imdbRatingMatchEnabled,
    String? tmdbReadAccessToken,
  }) {
    return AppSettings(
      mediaSources: mediaSources ?? this.mediaSources,
      searchProviders: searchProviders ?? this.searchProviders,
      doubanAccount: doubanAccount ?? this.doubanAccount,
      homeModules: homeModules ?? this.homeModules,
      homeHeroStyle: homeHeroStyle ?? this.homeHeroStyle,
      tmdbMetadataMatchEnabled:
          tmdbMetadataMatchEnabled ?? this.tmdbMetadataMatchEnabled,
      imdbRatingMatchEnabled:
          imdbRatingMatchEnabled ?? this.imdbRatingMatchEnabled,
      tmdbReadAccessToken: tmdbReadAccessToken ?? this.tmdbReadAccessToken,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mediaSources': mediaSources.map((item) => item.toJson()).toList(),
      'searchProviders': searchProviders.map((item) => item.toJson()).toList(),
      'doubanAccount': doubanAccount.toJson(),
      'homeModules': homeModules.map((item) => item.toJson()).toList(),
      'homeHeroStyle': homeHeroStyle.name,
      'tmdbMetadataMatchEnabled': tmdbMetadataMatchEnabled,
      'imdbRatingMatchEnabled': imdbRatingMatchEnabled,
      'tmdbReadAccessToken': tmdbReadAccessToken,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final legacyImdbAutoMatchEnabled =
        json['imdbAutoMatchEnabled'] as bool? ?? false;
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
      homeHeroStyle: HomeHeroStyleX.fromName(
        json['homeHeroStyle'] as String? ?? '',
      ),
      tmdbMetadataMatchEnabled: json['tmdbMetadataMatchEnabled'] as bool? ??
          legacyImdbAutoMatchEnabled,
      imdbRatingMatchEnabled: json['imdbRatingMatchEnabled'] as bool? ?? false,
      tmdbReadAccessToken: json['tmdbReadAccessToken'] as String? ?? '',
    );
  }
}
