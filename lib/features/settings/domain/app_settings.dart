import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';
import 'package:starflow/features/search/domain/search_models.dart';

enum HomeModuleType {
  hero,
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
      case HomeModuleType.hero:
        return 'Hero';
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
      'hero' => HomeModuleType.hero,
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
        return 'normal';
      case HomeHeroStyle.borderless:
        return 'borderless';
    }
  }

  static HomeHeroStyle fromName(String raw) {
    return switch (raw) {
      'borderless' => HomeHeroStyle.borderless,
      'normal' => HomeHeroStyle.normal,
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

  static const heroModuleId = 'home-module-hero';

  String get description {
    switch (type) {
      case HomeModuleType.hero:
        return '首页 Hero';
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
      HomeModuleType.hero => 'Hero',
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

  static HomeModuleConfig hero({bool enabled = true}) {
    return HomeModuleConfig(
      id: heroModuleId,
      type: HomeModuleType.hero,
      title: 'Hero',
      enabled: enabled,
    );
  }
}

class NetworkStorageConfig {
  const NetworkStorageConfig({
    this.quarkCookie = '',
    this.quarkSaveFolderId = '0',
    this.quarkSaveFolderPath = '/',
    this.smartStrmWebhookUrl = '',
    this.smartStrmTaskName = '',
    this.refreshMediaSourceIds = const [],
    this.refreshDelaySeconds = 1,
  });

  final String quarkCookie;
  final String quarkSaveFolderId;
  final String quarkSaveFolderPath;
  final String smartStrmWebhookUrl;
  final String smartStrmTaskName;
  final List<String> refreshMediaSourceIds;
  final int refreshDelaySeconds;

  bool get hasAnyConfigured {
    return quarkCookie.trim().isNotEmpty ||
        smartStrmWebhookUrl.trim().isNotEmpty ||
        smartStrmTaskName.trim().isNotEmpty ||
        quarkSaveFolderId.trim() != '0' ||
        quarkSaveFolderPath.trim() != '/' ||
        refreshMediaSourceIds.isNotEmpty ||
        refreshDelaySeconds != 1;
  }

  NetworkStorageConfig copyWith({
    String? quarkCookie,
    String? quarkSaveFolderId,
    String? quarkSaveFolderPath,
    String? smartStrmWebhookUrl,
    String? smartStrmTaskName,
    List<String>? refreshMediaSourceIds,
    int? refreshDelaySeconds,
  }) {
    return NetworkStorageConfig(
      quarkCookie: quarkCookie ?? this.quarkCookie,
      quarkSaveFolderId: quarkSaveFolderId ?? this.quarkSaveFolderId,
      quarkSaveFolderPath: quarkSaveFolderPath ?? this.quarkSaveFolderPath,
      smartStrmWebhookUrl: smartStrmWebhookUrl ?? this.smartStrmWebhookUrl,
      smartStrmTaskName: smartStrmTaskName ?? this.smartStrmTaskName,
      refreshMediaSourceIds:
          refreshMediaSourceIds ?? this.refreshMediaSourceIds,
      refreshDelaySeconds: refreshDelaySeconds ?? this.refreshDelaySeconds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'quarkCookie': quarkCookie,
      'quarkSaveFolderId': quarkSaveFolderId,
      'quarkSaveFolderPath': quarkSaveFolderPath,
      'smartStrmWebhookUrl': smartStrmWebhookUrl,
      'smartStrmTaskName': smartStrmTaskName,
      'refreshMediaSourceIds': refreshMediaSourceIds,
      'refreshDelaySeconds': refreshDelaySeconds,
    };
  }

  factory NetworkStorageConfig.fromJson(Map<String, dynamic> json) {
    final resolvedRefreshDelaySeconds =
        (json['refreshDelaySeconds'] as num?)?.toInt() ?? 1;
    return NetworkStorageConfig(
      quarkCookie: json['quarkCookie'] as String? ?? '',
      quarkSaveFolderId: json['quarkSaveFolderId'] as String? ?? '0',
      quarkSaveFolderPath: json['quarkSaveFolderPath'] as String? ?? '/',
      smartStrmWebhookUrl: json['smartStrmWebhookUrl'] as String? ?? '',
      smartStrmTaskName: json['smartStrmTaskName'] as String? ?? '',
      refreshMediaSourceIds:
          (json['refreshMediaSourceIds'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false),
      refreshDelaySeconds:
          resolvedRefreshDelaySeconds <= 0 ? 1 : resolvedRefreshDelaySeconds,
    );
  }
}

class AppSettings {
  const AppSettings({
    required this.mediaSources,
    required this.searchProviders,
    required this.doubanAccount,
    required this.homeModules,
    this.networkStorage = const NetworkStorageConfig(),
    this.homeHeroSourceModuleId = '',
    this.homeHeroStyle = HomeHeroStyle.normal,
    this.homeHeroBackgroundEnabled = true,
    this.translucentEffectsEnabled = true,
    this.tmdbMetadataMatchEnabled = false,
    this.wmdbMetadataMatchEnabled = false,
    this.metadataMatchPriority = MetadataMatchProvider.tmdb,
    this.imdbRatingMatchEnabled = false,
    this.tmdbReadAccessToken = '',
    this.playbackOpenTimeoutSeconds = 20,
  });

  final List<MediaSourceConfig> mediaSources;
  final List<SearchProviderConfig> searchProviders;
  final DoubanAccountConfig doubanAccount;
  final List<HomeModuleConfig> homeModules;
  final NetworkStorageConfig networkStorage;
  final String homeHeroSourceModuleId;
  final HomeHeroStyle homeHeroStyle;
  final bool homeHeroBackgroundEnabled;
  final bool translucentEffectsEnabled;
  final bool tmdbMetadataMatchEnabled;
  final bool wmdbMetadataMatchEnabled;
  final MetadataMatchProvider metadataMatchPriority;
  final bool imdbRatingMatchEnabled;
  final String tmdbReadAccessToken;
  final int playbackOpenTimeoutSeconds;

  AppSettings copyWith({
    List<MediaSourceConfig>? mediaSources,
    List<SearchProviderConfig>? searchProviders,
    DoubanAccountConfig? doubanAccount,
    List<HomeModuleConfig>? homeModules,
    NetworkStorageConfig? networkStorage,
    String? homeHeroSourceModuleId,
    HomeHeroStyle? homeHeroStyle,
    bool? homeHeroBackgroundEnabled,
    bool? translucentEffectsEnabled,
    bool? tmdbMetadataMatchEnabled,
    bool? wmdbMetadataMatchEnabled,
    MetadataMatchProvider? metadataMatchPriority,
    bool? imdbRatingMatchEnabled,
    String? tmdbReadAccessToken,
    int? playbackOpenTimeoutSeconds,
  }) {
    return AppSettings(
      mediaSources: mediaSources ?? this.mediaSources,
      searchProviders: searchProviders ?? this.searchProviders,
      doubanAccount: doubanAccount ?? this.doubanAccount,
      homeModules: homeModules ?? this.homeModules,
      networkStorage: networkStorage ?? this.networkStorage,
      homeHeroSourceModuleId:
          homeHeroSourceModuleId ?? this.homeHeroSourceModuleId,
      homeHeroStyle: homeHeroStyle ?? this.homeHeroStyle,
      homeHeroBackgroundEnabled:
          homeHeroBackgroundEnabled ?? this.homeHeroBackgroundEnabled,
      translucentEffectsEnabled:
          translucentEffectsEnabled ?? this.translucentEffectsEnabled,
      tmdbMetadataMatchEnabled:
          tmdbMetadataMatchEnabled ?? this.tmdbMetadataMatchEnabled,
      wmdbMetadataMatchEnabled:
          wmdbMetadataMatchEnabled ?? this.wmdbMetadataMatchEnabled,
      metadataMatchPriority:
          metadataMatchPriority ?? this.metadataMatchPriority,
      imdbRatingMatchEnabled:
          imdbRatingMatchEnabled ?? this.imdbRatingMatchEnabled,
      tmdbReadAccessToken: tmdbReadAccessToken ?? this.tmdbReadAccessToken,
      playbackOpenTimeoutSeconds:
          playbackOpenTimeoutSeconds ?? this.playbackOpenTimeoutSeconds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mediaSources': mediaSources.map((item) => item.toJson()).toList(),
      'searchProviders': searchProviders.map((item) => item.toJson()).toList(),
      'doubanAccount': doubanAccount.toJson(),
      'homeModules': homeModules.map((item) => item.toJson()).toList(),
      'networkStorage': networkStorage.toJson(),
      'homeHeroSourceModuleId': homeHeroSourceModuleId,
      'homeHeroStyle': homeHeroStyle.name,
      'homeHeroBackgroundEnabled': homeHeroBackgroundEnabled,
      'translucentEffectsEnabled': translucentEffectsEnabled,
      'tmdbMetadataMatchEnabled': tmdbMetadataMatchEnabled,
      'wmdbMetadataMatchEnabled': wmdbMetadataMatchEnabled,
      'metadataMatchPriority': metadataMatchPriority.name,
      'imdbRatingMatchEnabled': imdbRatingMatchEnabled,
      'tmdbReadAccessToken': tmdbReadAccessToken,
      'playbackOpenTimeoutSeconds': playbackOpenTimeoutSeconds,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final legacyImdbAutoMatchEnabled =
        json['imdbAutoMatchEnabled'] as bool? ?? false;
    final legacyHeroEnabled = json['homeHeroEnabled'] as bool? ?? true;
    final rawHomeModules = (json['homeModules'] as List<dynamic>? ?? [])
        .map(
          (item) => HomeModuleConfig.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
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
      homeModules: _normalizeHomeModules(
        rawHomeModules,
        legacyHeroEnabled: legacyHeroEnabled,
      ),
      networkStorage: NetworkStorageConfig.fromJson(
        Map<String, dynamic>.from(
          (json['networkStorage'] as Map?) ?? const {},
        ),
      ),
      homeHeroSourceModuleId: json['homeHeroSourceModuleId'] as String? ?? '',
      homeHeroStyle: HomeHeroStyleX.fromName(
        json['homeHeroStyle'] as String? ?? '',
      ),
      homeHeroBackgroundEnabled:
          json['homeHeroBackgroundEnabled'] as bool? ?? true,
      translucentEffectsEnabled:
          json['translucentEffectsEnabled'] as bool? ?? true,
      tmdbMetadataMatchEnabled: json['tmdbMetadataMatchEnabled'] as bool? ??
          legacyImdbAutoMatchEnabled,
      wmdbMetadataMatchEnabled:
          json['wmdbMetadataMatchEnabled'] as bool? ?? false,
      metadataMatchPriority: MetadataMatchProviderX.fromName(
        json['metadataMatchPriority'] as String? ?? '',
      ),
      imdbRatingMatchEnabled: json['imdbRatingMatchEnabled'] as bool? ?? false,
      tmdbReadAccessToken: json['tmdbReadAccessToken'] as String? ?? '',
      playbackOpenTimeoutSeconds:
          ((json['playbackOpenTimeoutSeconds'] as num?)?.toInt() ?? 20)
              .clamp(1, 600),
    );
  }
}

List<HomeModuleConfig> _normalizeHomeModules(
  List<HomeModuleConfig> modules, {
  required bool legacyHeroEnabled,
}) {
  final normalized = <HomeModuleConfig>[];
  HomeModuleConfig? heroModule;

  for (final module in modules) {
    if (module.type == HomeModuleType.hero ||
        module.id == HomeModuleConfig.heroModuleId) {
      heroModule = module.copyWith(
        id: HomeModuleConfig.heroModuleId,
        type: HomeModuleType.hero,
      );
      continue;
    }
    normalized.add(module);
  }

  normalized.insert(
    0,
    heroModule ?? HomeModuleConfig.hero(enabled: legacyHeroEnabled),
  );
  return normalized;
}
