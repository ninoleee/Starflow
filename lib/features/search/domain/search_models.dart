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
        return SearchCloudType.baidu;
      case 'aliyun':
        return SearchCloudType.aliyun;
      case 'quark':
        return SearchCloudType.quark;
      case 'tianyi':
        return SearchCloudType.tianyi;
      case 'uc':
        return SearchCloudType.uc;
      case 'mobile':
        return SearchCloudType.mobile;
      case '115':
      case 'cloud115':
        return SearchCloudType.cloud115;
      case 'pikpak':
        return SearchCloudType.pikpak;
      case 'xunlei':
        return SearchCloudType.xunlei;
      case '123':
      case 'cloud123':
        return SearchCloudType.cloud123;
      case 'magnet':
        return SearchCloudType.magnet;
      case 'ed2k':
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
    this.allowedCloudTypes = const [],
    this.blockedKeywords = const [],
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
  final List<String> allowedCloudTypes;
  final List<String> blockedKeywords;

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
    List<String>? allowedCloudTypes,
    List<String>? blockedKeywords,
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
      allowedCloudTypes: allowedCloudTypes ?? this.allowedCloudTypes,
      blockedKeywords: blockedKeywords ?? this.blockedKeywords,
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
      'allowedCloudTypes': allowedCloudTypes,
      'blockedKeywords': blockedKeywords,
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
    );
  }
}

class SearchResult {
  const SearchResult({
    required this.id,
    required this.title,
    required this.posterUrl,
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
  });

  final String id;
  final String title;
  final String posterUrl;
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
  final trimmed = rawUrl.trim();
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

SearchCloudType? detectSearchCloudTypeFromUrl(String rawUrl) {
  final uri = Uri.tryParse(rawUrl.trim());
  if (uri == null) {
    return null;
  }

  final host = uri.host.toLowerCase();
  final path = uri.path.toLowerCase();
  final normalized = '$host$path';

  if (host.contains('pan.baidu.com')) {
    return SearchCloudType.baidu;
  }
  if (host.contains('pan.quark.cn')) {
    return SearchCloudType.quark;
  }
  if (host.contains('alipan.com') || host.contains('aliyundrive.com')) {
    return SearchCloudType.aliyun;
  }
  if (host.contains('cloud.189.cn')) {
    return SearchCloudType.tianyi;
  }
  if (host.contains('drive.uc.cn') || host.contains('pan.uc.cn')) {
    return SearchCloudType.uc;
  }
  if (host.contains('yun.139.com')) {
    return SearchCloudType.mobile;
  }
  if (host.contains('115.com')) {
    return SearchCloudType.cloud115;
  }
  if (host.contains('mypikpak.com') || host.contains('pikpak.me')) {
    return SearchCloudType.pikpak;
  }
  if (host.contains('pan.xunlei.com')) {
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
