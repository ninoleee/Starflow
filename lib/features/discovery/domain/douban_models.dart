class DoubanAccountConfig {
  const DoubanAccountConfig({
    required this.enabled,
    this.userId = '',
    this.sessionCookie = '',
  });

  final bool enabled;
  final String userId;
  final String sessionCookie;

  DoubanAccountConfig copyWith({
    bool? enabled,
    String? userId,
    String? sessionCookie,
  }) {
    return DoubanAccountConfig(
      enabled: enabled ?? this.enabled,
      userId: userId ?? this.userId,
      sessionCookie: sessionCookie ?? this.sessionCookie,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'userId': userId,
      'sessionCookie': sessionCookie,
    };
  }

  factory DoubanAccountConfig.fromJson(Map<String, dynamic> json) {
    return DoubanAccountConfig(
      enabled: json['enabled'] as bool? ?? false,
      userId: json['userId'] as String? ?? '',
      sessionCookie: json['sessionCookie'] as String? ?? '',
    );
  }
}

class DoubanEntry {
  const DoubanEntry({
    required this.id,
    required this.title,
    required this.year,
    required this.posterUrl,
    required this.note,
    this.sourceUrl = '',
  });

  final String id;
  final String title;
  final int year;
  final String posterUrl;
  final String note;
  final String sourceUrl;
}
