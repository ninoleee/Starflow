enum DoubanInterestStatus {
  mark,
  doing,
  done,
  randomMark,
}

extension DoubanInterestStatusX on DoubanInterestStatus {
  String get value {
    switch (this) {
      case DoubanInterestStatus.mark:
        return 'mark';
      case DoubanInterestStatus.doing:
        return 'doing';
      case DoubanInterestStatus.done:
        return 'done';
      case DoubanInterestStatus.randomMark:
        return 'random_mark';
    }
  }

  String get label {
    switch (this) {
      case DoubanInterestStatus.mark:
        return '我想看';
      case DoubanInterestStatus.doing:
        return '我在看';
      case DoubanInterestStatus.done:
        return '我看过';
      case DoubanInterestStatus.randomMark:
        return '随机想看';
    }
  }

  static DoubanInterestStatus fromValue(String raw) {
    return DoubanInterestStatus.values.firstWhere(
      (item) => item.value == raw,
      orElse: () => DoubanInterestStatus.mark,
    );
  }
}

enum DoubanSuggestionMediaType {
  movie,
  tv,
}

extension DoubanSuggestionMediaTypeX on DoubanSuggestionMediaType {
  String get value {
    switch (this) {
      case DoubanSuggestionMediaType.movie:
        return 'movie';
      case DoubanSuggestionMediaType.tv:
        return 'tv';
    }
  }

  String get label {
    switch (this) {
      case DoubanSuggestionMediaType.movie:
        return '电影';
      case DoubanSuggestionMediaType.tv:
        return '电视';
    }
  }

  static DoubanSuggestionMediaType fromValue(String raw) {
    return DoubanSuggestionMediaType.values.firstWhere(
      (item) => item.value == raw,
      orElse: () => DoubanSuggestionMediaType.movie,
    );
  }
}

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
    this.durationLabel = '',
    this.genres = const [],
    this.directors = const [],
    this.actors = const [],
    this.sourceUrl = '',
    this.ratingLabel = '',
    this.subjectType = '',
  });

  final String id;
  final String title;
  final int year;
  final String posterUrl;
  final String note;
  final String durationLabel;
  final List<String> genres;
  final List<String> directors;
  final List<String> actors;
  final String sourceUrl;
  final String ratingLabel;
  final String subjectType;
}

class DoubanCarouselEntry {
  const DoubanCarouselEntry({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.posterUrl,
    required this.overview,
    this.year = 0,
    this.ratingLabel = '',
    this.mediaType = '',
  });

  final String id;
  final String title;
  final String imageUrl;
  final String posterUrl;
  final String overview;
  final int year;
  final String ratingLabel;
  final String mediaType;
}

String resolveDoubanItemType(String raw) {
  final normalized = raw.trim().toLowerCase();
  if (normalized.isEmpty) {
    return '';
  }

  if (normalized == 'movie' || normalized == 'film') {
    return 'movie';
  }
  if (normalized == 'tv' ||
      normalized == 'series' ||
      normalized == 'tvshow' ||
      normalized == 'tv_show' ||
      normalized == 'show') {
    return 'series';
  }
  if (normalized.contains('movie') || normalized.contains('film')) {
    return 'movie';
  }
  if (normalized.contains('tv') ||
      normalized.contains('series') ||
      normalized.contains('show')) {
    return 'series';
  }
  return '';
}
