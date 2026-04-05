enum MetadataMatchProvider {
  tmdb,
  wmdb,
}

extension MetadataMatchProviderX on MetadataMatchProvider {
  String get label {
    switch (this) {
      case MetadataMatchProvider.tmdb:
        return 'TMDB';
      case MetadataMatchProvider.wmdb:
        return 'WMDB';
    }
  }

  static MetadataMatchProvider fromName(String raw) {
    return switch (raw) {
      'wmdb' => MetadataMatchProvider.wmdb,
      _ => MetadataMatchProvider.tmdb,
    };
  }
}

class MetadataMatchRequest {
  const MetadataMatchRequest({
    required this.query,
    this.doubanId = '',
    this.year = 0,
    this.preferSeries = false,
    this.actors = const [],
  });

  final String query;
  final String doubanId;
  final int year;
  final bool preferSeries;
  final List<String> actors;
}

class MetadataPersonProfile {
  const MetadataPersonProfile({
    required this.name,
    this.avatarUrl = '',
  });

  final String name;
  final String avatarUrl;
}

class MetadataMatchResult {
  const MetadataMatchResult({
    required this.provider,
    required this.title,
    this.originalTitle = '',
    this.alternateTitles = const [],
    this.posterUrl = '',
    this.overview = '',
    this.year = 0,
    this.durationLabel = '',
    this.genres = const [],
    this.directors = const [],
    this.actors = const [],
    this.actorProfiles = const [],
    this.ratingLabels = const [],
    this.imdbId = '',
    this.doubanId = '',
  });

  final MetadataMatchProvider provider;
  final String title;
  final String originalTitle;
  final List<String> alternateTitles;
  final String posterUrl;
  final String overview;
  final int year;
  final String durationLabel;
  final List<String> genres;
  final List<String> directors;
  final List<String> actors;
  final List<MetadataPersonProfile> actorProfiles;
  final List<String> ratingLabels;
  final String imdbId;
  final String doubanId;

  List<String> get titlesForMatching {
    final seen = <String>{};
    final values = <String>[];
    for (final raw in [
      title,
      originalTitle,
      ...alternateTitles,
    ]) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final key = trimmed.toLowerCase();
      if (seen.add(key)) {
        values.add(trimmed);
      }
    }
    return values;
  }
}
