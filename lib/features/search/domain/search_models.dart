enum SearchProviderKind {
  torrent,
  direct,
  indexer,
}

extension SearchProviderKindX on SearchProviderKind {
  String get label {
    switch (this) {
      case SearchProviderKind.torrent:
        return 'BT/Torrent';
      case SearchProviderKind.direct:
        return '直链';
      case SearchProviderKind.indexer:
        return '聚合索引';
    }
  }

  static SearchProviderKind fromName(String raw) {
    return SearchProviderKind.values.firstWhere(
      (item) => item.name == raw,
      orElse: () => SearchProviderKind.indexer,
    );
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
  });

  final String id;
  final String name;
  final SearchProviderKind kind;
  final String endpoint;
  final bool enabled;
  final String apiKey;
  final String parserHint;

  SearchProviderConfig copyWith({
    String? id,
    String? name,
    SearchProviderKind? kind,
    String? endpoint,
    bool? enabled,
    String? apiKey,
    String? parserHint,
  }) {
    return SearchProviderConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      endpoint: endpoint ?? this.endpoint,
      enabled: enabled ?? this.enabled,
      apiKey: apiKey ?? this.apiKey,
      parserHint: parserHint ?? this.parserHint,
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
}
