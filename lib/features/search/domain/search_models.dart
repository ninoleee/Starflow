import 'package:starflow/features/details/domain/media_detail_models.dart';

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
  final String source;
  final String publishedAt;
  final List<String> imageUrls;
  final MediaDetailTarget? detailTarget;
}
