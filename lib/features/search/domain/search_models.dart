import 'package:starflow/features/details/domain/media_detail_models.dart';

enum SearchCloudType {
  baidu,
  aliyun,
  quark,
  tianyi,
  uc,
  mobile,
  cloud115,
  pikpak,
  xunlei,
  cloud123,
  magnet,
  ed2k,
}

extension SearchCloudTypeX on SearchCloudType {
  String get code {
    switch (this) {
      case SearchCloudType.baidu:
        return 'baidu';
      case SearchCloudType.aliyun:
        return 'aliyun';
      case SearchCloudType.quark:
        return 'quark';
      case SearchCloudType.tianyi:
        return 'tianyi';
      case SearchCloudType.uc:
        return 'uc';
      case SearchCloudType.mobile:
        return 'mobile';
      case SearchCloudType.cloud115:
        return '115';
      case SearchCloudType.pikpak:
        return 'pikpak';
      case SearchCloudType.xunlei:
        return 'xunlei';
      case SearchCloudType.cloud123:
        return '123';
      case SearchCloudType.magnet:
        return 'magnet';
      case SearchCloudType.ed2k:
        return 'ed2k';
    }
  }

  String get label {
    switch (this) {
      case SearchCloudType.baidu:
        return '百度网盘';
      case SearchCloudType.aliyun:
        return '阿里云盘';
      case SearchCloudType.quark:
        return '夸克网盘';
      case SearchCloudType.tianyi:
        return '天翼云盘';
      case SearchCloudType.uc:
        return 'UC 网盘';
      case SearchCloudType.mobile:
        return '移动云盘';
      case SearchCloudType.cloud115:
        return '115 网盘';
      case SearchCloudType.pikpak:
        return 'PikPak';
      case SearchCloudType.xunlei:
        return '迅雷云盘';
      case SearchCloudType.cloud123:
        return '123 云盘';
      case SearchCloudType.magnet:
        return '磁力链接';
      case SearchCloudType.ed2k:
        return '电驴链接';
    }
  }

  static SearchCloudType? fromCode(String raw) {
    final normalized = raw.trim().toLowerCase();
    switch (normalized) {
      case 'baidu':
      case '百度':
      case '百度网盘':
        return SearchCloudType.baidu;
      case 'aliyun':
      case '阿里':
      case '阿里云':
      case '阿里云盘':
      case '阿里网盘':
        return SearchCloudType.aliyun;
      case 'quark':
      case '夸克':
      case '夸克网盘':
        return SearchCloudType.quark;
      case 'tianyi':
      case '天翼':
      case '天翼云盘':
        return SearchCloudType.tianyi;
      case 'uc':
      case 'uc网盘':
      case 'uc 云盘':
        return SearchCloudType.uc;
      case 'mobile':
      case '移动':
      case '移动云':
      case '移动云盘':
        return SearchCloudType.mobile;
      case '115':
      case 'cloud115':
      case '115网盘':
      case '115 网盘':
        return SearchCloudType.cloud115;
      case 'pikpak':
      case 'pik pak':
        return SearchCloudType.pikpak;
      case 'xunlei':
      case '迅雷':
      case '迅雷网盘':
      case '迅雷云盘':
        return SearchCloudType.xunlei;
      case '123':
      case 'cloud123':
      case '123云盘':
      case '123 云盘':
      case '123pan':
        return SearchCloudType.cloud123;
      case 'magnet':
      case '磁力':
      case '磁力链接':
        return SearchCloudType.magnet;
      case 'ed2k':
      case '电驴':
      case '电驴链接':
        return SearchCloudType.ed2k;
      default:
        return null;
    }
  }
}

enum SearchProviderKind {
  panSou,
  cloudSaver,
}

extension SearchProviderKindX on SearchProviderKind {
  String get label {
    switch (this) {
      case SearchProviderKind.panSou:
        return 'PanSou';
      case SearchProviderKind.cloudSaver:
        return 'CloudSaver';
    }
  }

  String get defaultName {
    switch (this) {
      case SearchProviderKind.panSou:
        return 'PanSou';
      case SearchProviderKind.cloudSaver:
        return 'CloudSaver';
    }
  }

  String get defaultEndpoint {
    switch (this) {
      case SearchProviderKind.panSou:
        return 'https://so.252035.xyz';
      case SearchProviderKind.cloudSaver:
        return 'http://127.0.0.1:8009';
    }
  }

  String get defaultParserHint {
    switch (this) {
      case SearchProviderKind.panSou:
        return 'pansou-api';
      case SearchProviderKind.cloudSaver:
        return 'cloudsaver-api';
    }
  }

  static SearchProviderKind fromName(String raw) {
    switch (raw) {
      case 'panSou':
      case 'pansou':
      case 'indexer':
      case 'direct':
      case 'torrent':
        return SearchProviderKind.panSou;
      case 'cloudSaver':
      case 'cloudsaver':
        return SearchProviderKind.cloudSaver;
      default:
        return SearchProviderKind.panSou;
    }
  }
}

class SearchProviderConfig {
  const SearchProviderConfig({
    required this.id,
    required this.name,
    required this.kind,
    required this.endpoint,
    required this.enabled,
    this.apiKey = '',
    this.parserHint = '',
    this.username = '',
    this.password = '',
    this.quarkCookie = '',
    this.quarkSaveFolderId = '0',
    this.quarkSaveFolderPath = '/',
    this.smartStrmWebhookUrl = '',
    this.smartStrmTaskName = '',
    this.allowedCloudTypes = const [],
    this.blockedKeywords = const [],
    this.strongMatchEnabled = false,
    this.maxTitleLength = 50,
  });

  final String id;
  final String name;
  final SearchProviderKind kind;
  final String endpoint;
  final bool enabled;
  final String apiKey;
  final String parserHint;
  final String username;
  final String password;
  final String quarkCookie;
  final String quarkSaveFolderId;
  final String quarkSaveFolderPath;
  final String smartStrmWebhookUrl;
  final String smartStrmTaskName;
  final List<String> allowedCloudTypes;
  final List<String> blockedKeywords;
  final bool strongMatchEnabled;
  final int maxTitleLength;

  SearchProviderConfig copyWith({
    String? id,
    String? name,
    SearchProviderKind? kind,
    String? endpoint,
    bool? enabled,
    String? apiKey,
    String? parserHint,
    String? username,
    String? password,
    String? quarkCookie,
    String? quarkSaveFolderId,
    String? quarkSaveFolderPath,
    String? smartStrmWebhookUrl,
    String? smartStrmTaskName,
    List<String>? allowedCloudTypes,
    List<String>? blockedKeywords,
    bool? strongMatchEnabled,
    int? maxTitleLength,
  }) {
    return SearchProviderConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      endpoint: endpoint ?? this.endpoint,
      enabled: enabled ?? this.enabled,
      apiKey: apiKey ?? this.apiKey,
      parserHint: parserHint ?? this.parserHint,
      username: username ?? this.username,
      password: password ?? this.password,
      quarkCookie: quarkCookie ?? this.quarkCookie,
      quarkSaveFolderId: quarkSaveFolderId ?? this.quarkSaveFolderId,
      quarkSaveFolderPath: quarkSaveFolderPath ?? this.quarkSaveFolderPath,
      smartStrmWebhookUrl: smartStrmWebhookUrl ?? this.smartStrmWebhookUrl,
      smartStrmTaskName: smartStrmTaskName ?? this.smartStrmTaskName,
      allowedCloudTypes: allowedCloudTypes ?? this.allowedCloudTypes,
      blockedKeywords: blockedKeywords ?? this.blockedKeywords,
      strongMatchEnabled: strongMatchEnabled ?? this.strongMatchEnabled,
      maxTitleLength: maxTitleLength ?? this.maxTitleLength,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'kind': kind.name,
      'endpoint': endpoint,
      'enabled': enabled,
      'apiKey': apiKey,
      'parserHint': parserHint,
      'username': username,
      'password': password,
      'quarkCookie': quarkCookie,
      'quarkSaveFolderId': quarkSaveFolderId,
      'quarkSaveFolderPath': quarkSaveFolderPath,
      'smartStrmWebhookUrl': smartStrmWebhookUrl,
      'smartStrmTaskName': smartStrmTaskName,
      'allowedCloudTypes': allowedCloudTypes,
      'blockedKeywords': blockedKeywords,
      'strongMatchEnabled': strongMatchEnabled,
      'maxTitleLength': maxTitleLength,
    };
  }

  factory SearchProviderConfig.fromJson(Map<String, dynamic> json) {
    return SearchProviderConfig(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      kind: SearchProviderKindX.fromName(json['kind'] as String? ?? ''),
      endpoint: json['endpoint'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? false,
      apiKey: json['apiKey'] as String? ?? '',
      parserHint: json['parserHint'] as String? ?? '',
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      quarkCookie: json['quarkCookie'] as String? ?? '',
      quarkSaveFolderId: json['quarkSaveFolderId'] as String? ?? '0',
      quarkSaveFolderPath: json['quarkSaveFolderPath'] as String? ?? '/',
      smartStrmWebhookUrl: json['smartStrmWebhookUrl'] as String? ?? '',
      smartStrmTaskName: json['smartStrmTaskName'] as String? ?? '',
      allowedCloudTypes:
          (json['allowedCloudTypes'] as List<dynamic>? ?? const [])
              .map((value) => '$value')
              .where((value) => SearchCloudTypeX.fromCode(value) != null)
              .map((value) => SearchCloudTypeX.fromCode(value)!.code)
              .toList(growable: false),
      blockedKeywords: (json['blockedKeywords'] as List<dynamic>? ?? const [])
          .map((value) => '$value')
          .where((value) => value.trim().isNotEmpty)
          .toList(growable: false),
      strongMatchEnabled: json['strongMatchEnabled'] as bool? ?? false,
      maxTitleLength:
          ((json['maxTitleLength'] as num?)?.toInt() ?? 50).clamp(1, 500),
    );
  }
}

class SearchResult {
  const SearchResult({
    required this.id,
    required this.title,
    required this.posterUrl,
    this.posterHeaders = const {},
    required this.providerId,
    required this.providerName,
    required this.quality,
    required this.sizeLabel,
    required this.seeders,
    required this.summary,
    required this.resourceUrl,
    this.password = '',
    this.cloudType = '',
    this.source = '',
    this.publishedAt = '',
    this.imageUrls = const [],
    this.detailTarget,
    this.favoriteFolderName = '',
    this.originalSearchTitle = '',
    this.metadataMediaType = '',
    this.doubanId = '',
    this.imdbId = '',
    this.tmdbId = '',
    this.tvdbId = '',
    this.wikidataId = '',
  });

  final String id;
  final String title;
  final String posterUrl;
  final Map<String, String> posterHeaders;
  final String providerId;
  final String providerName;
  final String quality;
  final String sizeLabel;
  final int seeders;
  final String summary;
  final String resourceUrl;
  final String password;
  final String cloudType;
  final String source;
  final String publishedAt;
  final List<String> imageUrls;
  final MediaDetailTarget? detailTarget;
  final String favoriteFolderName;
  final String originalSearchTitle;
  final String metadataMediaType;
  final String doubanId;
  final String imdbId;
  final String tmdbId;
  final String tvdbId;
  final String wikidataId;

  SearchResult copyWith({
    String? title,
    MediaDetailTarget? detailTarget,
    String? favoriteFolderName,
    String? originalSearchTitle,
    String? metadataMediaType,
    String? doubanId,
    String? imdbId,
    String? tmdbId,
    String? tvdbId,
    String? wikidataId,
  }) {
    return SearchResult(
      id: id,
      title: title ?? this.title,
      posterUrl: posterUrl,
      posterHeaders: posterHeaders,
      providerId: providerId,
      providerName: providerName,
      quality: quality,
      sizeLabel: sizeLabel,
      seeders: seeders,
      summary: summary,
      resourceUrl: resourceUrl,
      password: password,
      cloudType: cloudType,
      source: source,
      publishedAt: publishedAt,
      imageUrls: imageUrls,
      detailTarget: detailTarget ?? this.detailTarget,
      favoriteFolderName: favoriteFolderName ?? this.favoriteFolderName,
      originalSearchTitle: originalSearchTitle ?? this.originalSearchTitle,
      metadataMediaType: metadataMediaType ?? this.metadataMediaType,
      doubanId: doubanId ?? this.doubanId,
      imdbId: imdbId ?? this.imdbId,
      tmdbId: tmdbId ?? this.tmdbId,
      tvdbId: tvdbId ?? this.tvdbId,
      wikidataId: wikidataId ?? this.wikidataId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'posterUrl': posterUrl,
      'posterHeaders': posterHeaders,
      'providerId': providerId,
      'providerName': providerName,
      'quality': quality,
      'sizeLabel': sizeLabel,
      'seeders': seeders,
      'summary': summary,
      'resourceUrl': resourceUrl,
      'password': password,
      'cloudType': cloudType,
      'source': source,
      'publishedAt': publishedAt,
      'imageUrls': imageUrls,
      'detailTarget': detailTarget?.toJson(),
      'favoriteFolderName': favoriteFolderName,
      'originalSearchTitle': originalSearchTitle,
      'metadataMediaType': metadataMediaType,
      'doubanId': doubanId,
      'imdbId': imdbId,
      'tmdbId': tmdbId,
      'tvdbId': tvdbId,
      'wikidataId': wikidataId,
    };
  }

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      posterUrl: json['posterUrl'] as String? ?? '',
      posterHeaders: (json['posterHeaders'] as Map<dynamic, dynamic>? ??
              const <dynamic, dynamic>{})
          .map((key, value) => MapEntry('$key', '$value')),
      providerId: json['providerId'] as String? ?? '',
      providerName: json['providerName'] as String? ?? '',
      quality: json['quality'] as String? ?? '',
      sizeLabel: json['sizeLabel'] as String? ?? '',
      seeders: (json['seeders'] as num?)?.toInt() ?? 0,
      summary: json['summary'] as String? ?? '',
      resourceUrl: json['resourceUrl'] as String? ?? '',
      password: json['password'] as String? ?? '',
      cloudType: json['cloudType'] as String? ?? '',
      source: json['source'] as String? ?? '',
      publishedAt: json['publishedAt'] as String? ?? '',
      imageUrls: (json['imageUrls'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => '$item')
          .where((item) => item.trim().isNotEmpty)
          .toList(growable: false),
      detailTarget: (json['detailTarget'] as Map?) == null
          ? null
          : MediaDetailTarget.fromJson(
              Map<String, dynamic>.from(json['detailTarget'] as Map),
            ),
      favoriteFolderName: json['favoriteFolderName'] as String? ?? '',
      originalSearchTitle: json['originalSearchTitle'] as String? ?? '',
      metadataMediaType: json['metadataMediaType'] as String? ?? '',
      doubanId: json['doubanId'] as String? ?? '',
      imdbId: json['imdbId'] as String? ?? '',
      tmdbId: json['tmdbId'] as String? ?? '',
      tvdbId: json['tvdbId'] as String? ?? '',
      wikidataId: json['wikidataId'] as String? ?? '',
    );
  }
}

String searchResultFavoriteKey(SearchResult result) {
  final normalizedResourceUrl = normalizeSearchResourceUrl(result.resourceUrl);
  if (normalizedResourceUrl.isNotEmpty) {
    return 'resource|$normalizedResourceUrl';
  }

  final detailTarget = result.detailTarget;
  if (detailTarget != null) {
    return [
      'detail',
      detailTarget.sourceKind?.name ?? '',
      detailTarget.sourceId.trim(),
      detailTarget.itemId.trim(),
      detailTarget.searchQuery.trim(),
      detailTarget.title.trim(),
    ].join('|');
  }

  return [
    'fallback',
    result.providerId.trim().toLowerCase(),
    result.title.trim().toLowerCase(),
    result.summary.trim().toLowerCase(),
  ].join('|');
}

String resolveSearchFavoriteFolderName({
  required SearchResult result,
  String searchQuery = '',
}) {
  final query = searchQuery.trim();
  if (query.isNotEmpty) {
    return query;
  }
  for (final candidate in [
    result.favoriteFolderName,
    result.title,
    result.originalSearchTitle,
  ]) {
    final trimmed = candidate.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return '';
}

String resolveSearchSaveFolderName({
  required SearchResult result,
  required bool isFavoriteResultsView,
  String searchQuery = '',
}) {
  if (isFavoriteResultsView) {
    return resolveSearchFavoriteFolderName(result: result);
  }

  final query = searchQuery.trim();
  if (query.isNotEmpty) {
    return query;
  }

  return resolveSearchFavoriteFolderName(result: result);
}

class SearchFetchResult {
  SearchFetchResult({
    required this.items,
    required this.filteredCount,
    int? rawCount,
  }) : rawCount = rawCount ?? items.length + filteredCount;

  final List<SearchResult> items;
  final int rawCount;
  final int filteredCount;
}

List<String> parseSearchBlockedKeywords(String raw) {
  return raw
      .split(RegExp(r'[\n,，;；]+'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList(growable: false);
}

String normalizeSearchResourceUrl(String rawUrl) {
  final trimmed = sanitizeSearchResourceUrl(rawUrl);
  if (trimmed.isEmpty) {
    return '';
  }

  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) {
    return trimmed;
  }

  final queryParameters = Map<String, String>.from(uri.queryParameters)
    ..removeWhere((key, value) {
      final normalizedKey = key.trim().toLowerCase();
      return normalizedKey == 'pwd' ||
          normalizedKey == 'password' ||
          normalizedKey == 'passcode' ||
          normalizedKey == 'extractcode' ||
          normalizedKey == 'code';
    });
  final normalized = uri.replace(
    scheme: uri.scheme.toLowerCase(),
    host: uri.host.toLowerCase(),
    path: uri.path == '/' ? uri.path : uri.path.replaceFirst(RegExp(r'/$'), ''),
    query: queryParameters.isEmpty
        ? ''
        : Uri(queryParameters: queryParameters).query,
    fragment: null,
  );
  return normalized.toString();
}

String sanitizeSearchResourceUrl(String rawUrl) {
  var sanitized = rawUrl.trim();
  if (sanitized.isEmpty) {
    return '';
  }

  sanitized = sanitized
      .replaceAll(RegExp("^[<\\[\\(【「『\"']+"), '')
      .replaceAll(RegExp("[>\\]\\)】」』\"']+\$"), '')
      .trim();

  final embeddedMatch =
      RegExp(r'((?:https?|magnet|ed2k):[^\s]+)', caseSensitive: false)
          .firstMatch(sanitized);
  if (embeddedMatch != null) {
    sanitized = embeddedMatch.group(1) ?? sanitized;
  }

  sanitized = sanitized.replaceAll(RegExp(r'[，。；、]+$'), '').trim();
  return sanitized;
}

SearchCloudType? detectSearchCloudTypeFromUrl(String rawUrl) {
  final sanitized = sanitizeSearchResourceUrl(rawUrl);
  final normalizedRaw = sanitized.toLowerCase();
  final uri = Uri.tryParse(sanitized);
  if (uri == null) {
    if (_looksLike115Url(normalizedRaw)) {
      return SearchCloudType.cloud115;
    }
    return null;
  }

  final host = uri.host.toLowerCase();
  final path = uri.path.toLowerCase();
  final normalized = '$host$path';

  if (host.contains('baidu')) {
    return SearchCloudType.baidu;
  }
  if (host.contains('quark')) {
    return SearchCloudType.quark;
  }
  if (host.contains('alipan') || host.contains('aliyundrive')) {
    return SearchCloudType.aliyun;
  }
  if (host.contains('189.cn')) {
    return SearchCloudType.tianyi;
  }
  if (host.contains('uc.cn') || host.contains('pan.uc')) {
    return SearchCloudType.uc;
  }
  if (host.contains('139.com')) {
    return SearchCloudType.mobile;
  }
  if (_looksLike115Url(normalizedRaw) || host.contains('115.com')) {
    return SearchCloudType.cloud115;
  }
  if (host.contains('mypikpak') || host.contains('pikpak')) {
    return SearchCloudType.pikpak;
  }
  if (host.contains('xunlei')) {
    return SearchCloudType.xunlei;
  }
  if (host.contains('123684.com') ||
      host.contains('123865.com') ||
      host.contains('123912.com') ||
      host.contains('123pan.com')) {
    return SearchCloudType.cloud123;
  }
  if (normalized.startsWith('magnet:')) {
    return SearchCloudType.magnet;
  }
  if (normalized.startsWith('ed2k://')) {
    return SearchCloudType.ed2k;
  }
  return null;
}

bool _looksLike115Url(String normalizedRaw) {
  final raw = normalizedRaw.trim();
  if (raw.isEmpty) {
    return false;
  }
  return raw.contains('115.com/') ||
      raw.contains('.115.com/') ||
      raw.contains('anxia.com/') ||
      raw.contains('.anxia.com/') ||
      raw.startsWith('115://');
}

String? resolveSearchCloudTypeCode({
  required String rawUrl,
  Iterable<String> hints = const [],
}) {
  final fromUrl = detectSearchCloudTypeFromUrl(rawUrl);
  if (fromUrl != null) {
    return fromUrl.code;
  }

  for (final hint in hints) {
    final normalizedHint = hint.trim();
    if (normalizedHint.isEmpty) {
      continue;
    }
    final byCode = SearchCloudTypeX.fromCode(normalizedHint);
    if (byCode != null) {
      return byCode.code;
    }

    final lowered = normalizedHint.toLowerCase();
    if (lowered.contains('夸克')) {
      return SearchCloudType.quark.code;
    }
    if (lowered.contains('百度')) {
      return SearchCloudType.baidu.code;
    }
    if (lowered.contains('阿里')) {
      return SearchCloudType.aliyun.code;
    }
    if (lowered.contains('天翼')) {
      return SearchCloudType.tianyi.code;
    }
    if (lowered.contains('uc')) {
      return SearchCloudType.uc.code;
    }
    if (lowered.contains('115')) {
      return SearchCloudType.cloud115.code;
    }
    if (lowered.contains('123')) {
      return SearchCloudType.cloud123.code;
    }
    if (lowered.contains('迅雷')) {
      return SearchCloudType.xunlei.code;
    }
    if (lowered.contains('pikpak')) {
      return SearchCloudType.pikpak.code;
    }
    if (lowered.contains('磁力')) {
      return SearchCloudType.magnet.code;
    }
    if (lowered.contains('电驴')) {
      return SearchCloudType.ed2k.code;
    }
  }

  return null;
}
