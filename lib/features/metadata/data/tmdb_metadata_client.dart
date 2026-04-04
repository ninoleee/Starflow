import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

final tmdbMetadataClientProvider = Provider<TmdbMetadataClient>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return TmdbMetadataClient(client);
});

class TmdbMetadataClient {
  TmdbMetadataClient(this._client);

  final http.Client _client;

  Future<TmdbMetadataMatch?> matchTitle({
    required String query,
    required String readAccessToken,
    int year = 0,
    bool preferSeries = false,
  }) async {
    final cleanedQuery = _cleanQuery(query);
    final cleanedToken = readAccessToken.trim();
    if (cleanedQuery.isEmpty || cleanedToken.isEmpty) {
      return null;
    }

    final searchResponse = await _client.get(
      _buildSearchUri(cleanedQuery),
      headers: _buildHeaders(cleanedToken),
    );
    if (searchResponse.statusCode != 200) {
      throw TmdbMetadataException(
        'TMDB 搜索失败：HTTP ${searchResponse.statusCode}',
      );
    }

    final decodedSearch = jsonDecode(
      utf8.decode(searchResponse.bodyBytes, allowMalformed: true),
    );
    if (decodedSearch is! Map<String, dynamic>) {
      return null;
    }

    final candidates = (decodedSearch['results'] as List<dynamic>? ?? const [])
        .map((item) => _TmdbSearchResult.fromJson(item))
        .whereType<_TmdbSearchResult>()
        .toList();
    if (candidates.isEmpty) {
      return null;
    }

    final best = _pickBestMatch(
      candidates,
      query: cleanedQuery,
      year: year,
      preferSeries: preferSeries,
    );
    if (best == null) {
      return null;
    }

    final detailsResponse = await _client.get(
      _buildDetailsUri(best),
      headers: _buildHeaders(cleanedToken),
    );
    if (detailsResponse.statusCode != 200) {
      throw TmdbMetadataException(
        'TMDB 详情失败：HTTP ${detailsResponse.statusCode}',
      );
    }

    final decodedDetails = jsonDecode(
      utf8.decode(detailsResponse.bodyBytes, allowMalformed: true),
    );
    if (decodedDetails is! Map<String, dynamic>) {
      return null;
    }

    return _mapDetails(best, decodedDetails);
  }

  Uri _buildSearchUri(String query) {
    return Uri.https('api.themoviedb.org', '/3/search/multi', {
      'query': query,
      'include_adult': 'false',
      'language': 'zh-CN',
    });
  }

  Uri _buildDetailsUri(_TmdbSearchResult result) {
    final path =
        result.isSeries ? '/3/tv/${result.id}' : '/3/movie/${result.id}';
    return Uri.https('api.themoviedb.org', path, {
      'language': 'zh-CN',
      'append_to_response': result.isSeries
          ? 'aggregate_credits,external_ids'
          : 'credits,external_ids',
    });
  }

  Map<String, String> _buildHeaders(String token) {
    return {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  _TmdbSearchResult? _pickBestMatch(
    List<_TmdbSearchResult> results, {
    required String query,
    required int year,
    required bool preferSeries,
  }) {
    final normalizedQuery = _normalizeTitle(query);
    _TmdbSearchResult? best;
    var bestScore = double.negativeInfinity;

    for (final item in results) {
      final score = _scoreCandidate(
        item,
        normalizedQuery: normalizedQuery,
        year: year,
        preferSeries: preferSeries,
      );
      if (score > bestScore) {
        best = item;
        bestScore = score;
      }
    }

    return bestScore < 0 ? null : best;
  }

  double _scoreCandidate(
    _TmdbSearchResult item, {
    required String normalizedQuery,
    required int year,
    required bool preferSeries,
  }) {
    final normalizedTitle = _normalizeTitle(item.title);
    final normalizedOriginalTitle = _normalizeTitle(item.originalTitle);
    var score = 0.0;

    if (normalizedTitle == normalizedQuery ||
        normalizedOriginalTitle == normalizedQuery) {
      score += 100;
    } else if (normalizedTitle.contains(normalizedQuery) ||
        normalizedQuery.contains(normalizedTitle) ||
        normalizedOriginalTitle.contains(normalizedQuery) ||
        normalizedQuery.contains(normalizedOriginalTitle)) {
      score += 56;
    }

    if (year > 0 && item.year > 0) {
      final delta = (item.year - year).abs();
      if (delta == 0) {
        score += 24;
      } else if (delta == 1) {
        score += 12;
      } else if (delta <= 3) {
        score += 4;
      } else {
        score -= 14;
      }
    }

    if (preferSeries) {
      score += item.isSeries ? 18 : -10;
    } else {
      score += item.isMovie ? 12 : 0;
    }

    score += item.popularity / 500;
    return score;
  }

  TmdbMetadataMatch _mapDetails(
    _TmdbSearchResult searchResult,
    Map<String, dynamic> json,
  ) {
    final genres = (json['genres'] as List<dynamic>? ?? const [])
        .map((item) => '${(item as Map?)?['name'] ?? ''}'.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    final castSource = searchResult.isSeries
        ? json['aggregate_credits'] as Map<String, dynamic>? ?? const {}
        : json['credits'] as Map<String, dynamic>? ?? const {};
    final cast = (castSource['cast'] as List<dynamic>? ?? const [])
        .map((item) => '${(item as Map?)?['name'] ?? ''}'.trim())
        .where((item) => item.isNotEmpty)
        .take(8)
        .toList();

    final crew = (castSource['crew'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final createdBy = (json['created_by'] as List<dynamic>? ?? const [])
        .map((item) => '${(item as Map?)?['name'] ?? ''}'.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    final directors = _dedupe([
      ...createdBy,
      ...crew
          .where(
            (item) =>
                '${item['job'] ?? ''}'.trim().toLowerCase() == 'director' ||
                '${item['department'] ?? ''}'.trim().toLowerCase() ==
                    'directing',
          )
          .map((item) => '${item['name'] ?? ''}'.trim())
          .where((item) => item.isNotEmpty),
    ]);

    final runtime = searchResult.isSeries
        ? _resolveEpisodeRuntime(json['episode_run_time'])
        : (json['runtime'] as num?)?.toInt() ?? 0;
    final releaseDate =
        '${json[searchResult.isSeries ? 'first_air_date' : 'release_date'] ?? ''}';
    final externalIds =
        json['external_ids'] as Map<String, dynamic>? ?? const {};
    final imdbId = '${json['imdb_id'] ?? externalIds['imdb_id'] ?? ''}'.trim();

    return TmdbMetadataMatch(
      title:
          '${json[searchResult.isSeries ? 'name' : 'title'] ?? searchResult.title}'
              .trim(),
      posterUrl: _resolveImageUrl(
        '${json['poster_path'] ?? searchResult.posterPath}',
        size: 'w500',
      ),
      overview: '${json['overview'] ?? searchResult.overview}'.trim(),
      year: _extractYear(releaseDate) > 0
          ? _extractYear(releaseDate)
          : searchResult.year,
      durationLabel: _formatRuntime(
        runtime,
        perEpisode: searchResult.isSeries,
      ),
      genres: genres,
      directors: directors,
      actors: cast,
      imdbId: imdbId,
    );
  }

  static int _resolveEpisodeRuntime(Object? raw) {
    final runtimes = (raw as List<dynamic>? ?? const [])
        .map((item) => (item as num?)?.toInt() ?? 0)
        .where((item) => item > 0)
        .toList();
    if (runtimes.isEmpty) {
      return 0;
    }
    return runtimes.first;
  }

  static String _formatRuntime(int minutes, {required bool perEpisode}) {
    if (minutes <= 0) {
      return '';
    }
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    final buffer = StringBuffer();
    if (hours > 0) {
      buffer.write('${hours}h');
    }
    if (remainingMinutes > 0) {
      if (buffer.isNotEmpty) {
        buffer.write(' ');
      }
      buffer.write('${remainingMinutes}m');
    }
    if (buffer.isEmpty) {
      buffer.write('${minutes}m');
    }
    if (perEpisode) {
      buffer.write(' / 集');
    }
    return buffer.toString();
  }

  static int _extractYear(String rawDate) {
    if (rawDate.length < 4) {
      return 0;
    }
    return int.tryParse(rawDate.substring(0, 4)) ?? 0;
  }

  static String _resolveImageUrl(String path, {required String size}) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'https://image.tmdb.org/t/p/$size$trimmed';
  }

  static List<String> _dedupe(Iterable<String> items) {
    final seen = <String>{};
    final result = <String>[];
    for (final item in items) {
      final trimmed = item.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final key = trimmed.toLowerCase();
      if (seen.add(key)) {
        result.add(trimmed);
      }
    }
    return result;
  }

  static String _cleanQuery(String value) {
    return value
        .replaceAll(RegExp(r'[._]+'), ' ')
        .replaceAll(RegExp(r'\[[^\]]*\]|\([^\)]*\)'), ' ')
        .replaceAll(
          RegExp(
            r'\b(2160p|1080p|720p|480p|bluray|blu-ray|bdrip|brrip|webrip|web-dl|webdl|hdrip|dvdrip|remux|x264|x265|h264|h265|hevc|aac|dts|atmos|hdr|uhd|proper|repack|extended|limited|internal|multi|dubbed|subs?)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\bS\d{1,2}E\d{1,2}\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _normalizeTitle(String value) {
    return _cleanQuery(value)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), '');
  }
}

class TmdbMetadataMatch {
  const TmdbMetadataMatch({
    required this.title,
    required this.posterUrl,
    required this.overview,
    required this.year,
    required this.durationLabel,
    required this.genres,
    required this.directors,
    required this.actors,
    required this.imdbId,
  });

  final String title;
  final String posterUrl;
  final String overview;
  final int year;
  final String durationLabel;
  final List<String> genres;
  final List<String> directors;
  final List<String> actors;
  final String imdbId;
}

class TmdbMetadataException implements Exception {
  const TmdbMetadataException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _TmdbSearchResult {
  const _TmdbSearchResult({
    required this.id,
    required this.mediaType,
    required this.title,
    required this.originalTitle,
    required this.overview,
    required this.posterPath,
    required this.year,
    required this.popularity,
  });

  final int id;
  final String mediaType;
  final String title;
  final String originalTitle;
  final String overview;
  final String posterPath;
  final int year;
  final double popularity;

  bool get isSeries => mediaType == 'tv';

  bool get isMovie => mediaType == 'movie';

  static _TmdbSearchResult? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final json = Map<String, dynamic>.from(raw);
    final mediaType = '${json['media_type'] ?? ''}'.trim().toLowerCase();
    if (mediaType != 'movie' && mediaType != 'tv') {
      return null;
    }
    final id = (json['id'] as num?)?.toInt() ?? 0;
    final title = '${json[mediaType == 'tv' ? 'name' : 'title'] ?? ''}'.trim();
    if (id <= 0 || title.isEmpty) {
      return null;
    }

    return _TmdbSearchResult(
      id: id,
      mediaType: mediaType,
      title: title,
      originalTitle:
          '${json[mediaType == 'tv' ? 'original_name' : 'original_title'] ?? title}'
              .trim(),
      overview: '${json['overview'] ?? ''}'.trim(),
      posterPath: '${json['poster_path'] ?? ''}'.trim(),
      year: TmdbMetadataClient._extractYear(
        '${json[mediaType == 'tv' ? 'first_air_date' : 'release_date'] ?? ''}',
      ),
      popularity: (json['popularity'] as num?)?.toDouble() ?? 0,
    );
  }
}
