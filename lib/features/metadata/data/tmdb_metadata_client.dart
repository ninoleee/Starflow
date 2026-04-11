import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/core/network/starflow_http_client.dart';
import 'package:starflow/features/library/domain/media_naming.dart';

final tmdbMetadataClientProvider = Provider<TmdbMetadataClient>((ref) {
  final client = ref.watch(starflowHttpClientProvider);
  return TmdbMetadataClient(client);
});

class TmdbMetadataClient {
  TmdbMetadataClient(this._client);

  final http.Client _client;
  final Map<String, TmdbMetadataMatch?> _resolvedMatches = {};
  final Map<String, Future<TmdbMetadataMatch?>> _inflightMatches = {};

  void clearCache() {
    _resolvedMatches.clear();
    _inflightMatches.clear();
  }

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

    final cacheKey = _buildCacheKey(
      query: cleanedQuery,
      token: cleanedToken,
      year: year,
      preferSeries: preferSeries,
    );
    if (_resolvedMatches.containsKey(cacheKey)) {
      return _resolvedMatches[cacheKey];
    }

    final inflight = _inflightMatches[cacheKey];
    if (inflight != null) {
      return inflight;
    }

    final future = _matchTitleUncached(
      query: cleanedQuery,
      readAccessToken: cleanedToken,
      year: year,
      preferSeries: preferSeries,
    );
    _inflightMatches[cacheKey] = future;

    try {
      final result = await future;
      _resolvedMatches[cacheKey] = result;
      return result;
    } finally {
      _inflightMatches.remove(cacheKey);
    }
  }

  Future<TmdbMetadataMatch?> matchByImdbId({
    required String imdbId,
    required String readAccessToken,
    bool preferSeries = false,
  }) async {
    final normalizedImdbId = imdbId.trim().toLowerCase();
    final cleanedToken = readAccessToken.trim();
    if (normalizedImdbId.isEmpty || cleanedToken.isEmpty) {
      return null;
    }

    final cacheKey = [
      cleanedToken.hashCode,
      'imdb',
      normalizedImdbId,
      preferSeries ? 'tv' : 'movie',
    ].join('|');
    if (_resolvedMatches.containsKey(cacheKey)) {
      return _resolvedMatches[cacheKey];
    }

    final inflight = _inflightMatches[cacheKey];
    if (inflight != null) {
      return inflight;
    }

    final future = _matchByImdbIdUncached(
      imdbId: normalizedImdbId,
      readAccessToken: cleanedToken,
      preferSeries: preferSeries,
    );
    _inflightMatches[cacheKey] = future;

    try {
      final result = await future;
      _resolvedMatches[cacheKey] = result;
      return result;
    } finally {
      _inflightMatches.remove(cacheKey);
    }
  }

  Future<TmdbMetadataMatch?> _matchTitleUncached({
    required String query,
    required String readAccessToken,
    required int year,
    required bool preferSeries,
  }) async {
    final searchResponse = await _client.get(
      _buildSearchUri(query),
      headers: _buildHeaders(readAccessToken),
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
      query: query,
      year: year,
      preferSeries: preferSeries,
    );
    if (best == null) {
      return null;
    }

    return _fetchCompleteMatch(
      result: best,
      readAccessToken: readAccessToken,
    );
  }

  Future<TmdbMetadataMatch?> _matchByImdbIdUncached({
    required String imdbId,
    required String readAccessToken,
    required bool preferSeries,
  }) async {
    final findResponse = await _client.get(
      _buildFindUri(imdbId),
      headers: _buildHeaders(readAccessToken),
    );
    if (findResponse.statusCode != 200) {
      throw TmdbMetadataException(
        'TMDB IMDb ID 查询失败：HTTP ${findResponse.statusCode}',
      );
    }

    final decodedFind = jsonDecode(
      utf8.decode(findResponse.bodyBytes, allowMalformed: true),
    );
    if (decodedFind is! Map<String, dynamic>) {
      return null;
    }

    final candidates = <_TmdbSearchResult>[
      ...((decodedFind['movie_results'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => _TmdbSearchResult.fromJson(
              <String, dynamic>{
                ...Map<String, dynamic>.from(item),
                'media_type': 'movie',
              },
            ),
          )
          .whereType<_TmdbSearchResult>()),
      ...((decodedFind['tv_results'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => _TmdbSearchResult.fromJson(
              <String, dynamic>{
                ...Map<String, dynamic>.from(item),
                'media_type': 'tv',
              },
            ),
          )
          .whereType<_TmdbSearchResult>()),
    ];
    if (candidates.isEmpty) {
      return null;
    }

    final target = _pickBestImdbIdMatch(
      candidates,
      preferSeries: preferSeries,
    );
    if (target == null) {
      return null;
    }

    return _fetchCompleteMatch(
      result: target,
      readAccessToken: readAccessToken,
    );
  }

  String _buildCacheKey({
    required String query,
    required String token,
    required int year,
    required bool preferSeries,
  }) {
    return [
      token.hashCode,
      preferSeries ? 'tv' : 'movie',
      year,
      _normalizeTitle(query),
    ].join('|');
  }

  Uri _buildSearchUri(String query) {
    return Uri.https('api.themoviedb.org', '/3/search/multi', {
      'query': query,
      'include_adult': 'false',
      'language': 'zh-CN',
    });
  }

  Uri _buildFindUri(String imdbId) {
    return Uri.https('api.themoviedb.org', '/3/find/$imdbId', {
      'external_source': 'imdb_id',
      'language': 'zh-CN',
    });
  }

  Uri _buildDetailsUri(_TmdbSearchResult result) {
    final path =
        result.isSeries ? '/3/tv/${result.id}' : '/3/movie/${result.id}';
    return Uri.https('api.themoviedb.org', path, {
      'language': 'zh-CN',
      'include_image_language': 'null,zh,en',
      'append_to_response': result.isSeries
          ? 'aggregate_credits,external_ids,images'
          : 'credits,external_ids,images',
    });
  }

  Uri _buildPersonSearchUri(String name) {
    return Uri.https('api.themoviedb.org', '/3/search/person', {
      'query': name,
      'language': 'zh-CN',
      'include_adult': 'false',
      'page': '1',
    });
  }

  Uri _buildPersonCombinedCreditsUri(int personId) {
    return Uri.https(
      'api.themoviedb.org',
      '/3/person/$personId/combined_credits',
      {'language': 'zh-CN'},
    );
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

  _TmdbSearchResult? _pickBestImdbIdMatch(
    List<_TmdbSearchResult> results, {
    required bool preferSeries,
  }) {
    if (results.isEmpty) {
      return null;
    }
    if (preferSeries) {
      for (final item in results) {
        if (item.isSeries) {
          return item;
        }
      }
    }
    for (final item in results) {
      if (item.isMovie) {
        return item;
      }
    }
    return results.first;
  }

  Map<String, dynamic>? _pickBestPersonMatch(
    List<Map<String, dynamic>> results, {
    required String name,
    required String avatarUrl,
    required TmdbPersonCreditsRole role,
  }) {
    if (results.isEmpty) {
      return null;
    }

    final normalizedName = name.trim().toLowerCase();
    final avatarSegment = _extractImagePathSegment(avatarUrl);
    Map<String, dynamic>? best;
    var bestScore = double.negativeInfinity;

    for (final item in results) {
      final personName = '${item['name'] ?? ''}'.trim();
      if (personName.isEmpty) {
        continue;
      }

      var score = 0.0;
      final normalizedPersonName = personName.toLowerCase();
      if (normalizedPersonName == normalizedName) {
        score += 120;
      } else if (normalizedPersonName.contains(normalizedName) ||
          normalizedName.contains(normalizedPersonName)) {
        score += 48;
      }

      final knownForDepartment =
          '${item['known_for_department'] ?? ''}'.trim().toLowerCase();
      if (role == TmdbPersonCreditsRole.actor) {
        if (knownForDepartment == 'acting') {
          score += 12;
        }
      } else if (knownForDepartment == 'directing') {
        score += 12;
      }

      final profileSegment = _extractImagePathSegment(
        '${item['profile_path'] ?? ''}',
      );
      if (avatarSegment.isNotEmpty &&
          profileSegment.isNotEmpty &&
          avatarSegment == profileSegment) {
        score += 90;
      }

      score += ((item['popularity'] as num?)?.toDouble() ?? 0) / 100;
      if (score > bestScore) {
        bestScore = score;
        best = item;
      }
    }

    return best;
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

  Future<TmdbMetadataMatch?> _fetchCompleteMatch({
    required _TmdbSearchResult result,
    required String readAccessToken,
  }) async {
    final detailsResponse = await _client.get(
      _buildDetailsUri(result),
      headers: _buildHeaders(readAccessToken),
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

    return _mapDetails(result, decodedDetails);
  }

  TmdbMetadataMatch _mapDetails(
    _TmdbSearchResult searchResult,
    Map<String, dynamic> json,
  ) {
    final images = json['images'] as Map<String, dynamic>? ?? const {};
    final genres = (json['genres'] as List<dynamic>? ?? const [])
        .map((item) => '${(item as Map?)?['name'] ?? ''}'.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    final castSource = searchResult.isSeries
        ? json['aggregate_credits'] as Map<String, dynamic>? ?? const {}
        : json['credits'] as Map<String, dynamic>? ?? const {};
    final actorProfiles = _resolveActorProfiles(castSource['cast']);
    final cast = actorProfiles.map((item) => item.name).toList();

    final crew = (castSource['crew'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final createdBy = (json['created_by'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    final directorProfiles = _resolveDirectorProfiles(
      createdBy: createdBy,
      crew: crew,
    );
    final directors = directorProfiles.map((item) => item.name).toList();
    final companyProfiles = _resolveCompanyProfiles(
      (json['production_companies'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false),
    );
    final companies = companyProfiles.map((item) => item.name).toList();

    final runtime = searchResult.isSeries
        ? _resolveEpisodeRuntime(json['episode_run_time'])
        : (json['runtime'] as num?)?.toInt() ?? 0;
    final releaseDate =
        '${json[searchResult.isSeries ? 'first_air_date' : 'release_date'] ?? ''}';
    final externalIds =
        json['external_ids'] as Map<String, dynamic>? ?? const {};
    final imdbId = '${json['imdb_id'] ?? externalIds['imdb_id'] ?? ''}'.trim();
    final ratingLabels = _resolveRatingLabels(
      voteAverage: json['vote_average'],
      voteCount: json['vote_count'],
    );
    final posterUrl = _resolveImageUrl(
      '${json['poster_path'] ?? searchResult.posterPath}',
      size: 'w500',
    );
    final backdropUrl = _resolveBackdropUrl(
      '${json['backdrop_path'] ?? ''}',
      images['backdrops'],
    );
    final logoUrl = _resolveLogoUrl(images['logos']);
    final extraBackdropUrls = _resolveAdditionalBackdropUrls(
      raw: images['backdrops'],
      primaryBackdropUrl: backdropUrl,
    );

    return TmdbMetadataMatch(
      tmdbId: searchResult.id,
      isSeries: searchResult.isSeries,
      title:
          '${json[searchResult.isSeries ? 'name' : 'title'] ?? searchResult.title}'
              .trim(),
      originalTitle:
          '${json[searchResult.isSeries ? 'original_name' : 'original_title'] ?? searchResult.originalTitle}'
              .trim(),
      posterUrl: posterUrl,
      backdropUrl: backdropUrl,
      logoUrl: logoUrl,
      extraBackdropUrls: extraBackdropUrls,
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
      directorProfiles: directorProfiles,
      actors: cast,
      actorProfiles: actorProfiles,
      platforms: companies,
      platformProfiles: companyProfiles,
      ratingLabels: ratingLabels,
      imdbId: imdbId,
    );
  }

  Future<String> fetchEpisodeStillUrl({
    required int seriesId,
    required int seasonNumber,
    required int episodeNumber,
    required String readAccessToken,
  }) async {
    if (seriesId <= 0 ||
        seasonNumber < 0 ||
        episodeNumber <= 0 ||
        readAccessToken.trim().isEmpty) {
      return '';
    }

    final response = await _client.get(
      Uri.https(
        'api.themoviedb.org',
        '/3/tv/$seriesId/season/$seasonNumber/episode/$episodeNumber',
        {'language': 'zh-CN'},
      ),
      headers: _buildHeaders(readAccessToken.trim()),
    );
    if (response.statusCode != 200) {
      throw TmdbMetadataException(
        'TMDB 分集详情失败：HTTP ${response.statusCode}',
      );
    }

    final decoded = jsonDecode(
      utf8.decode(response.bodyBytes, allowMalformed: true),
    );
    if (decoded is! Map<String, dynamic>) {
      return '';
    }

    return _resolveImageUrl('${decoded['still_path'] ?? ''}', size: 'w780');
  }

  Future<List<TmdbPersonCredit>> fetchPersonCredits({
    required String name,
    required String avatarUrl,
    required TmdbPersonCreditsRole role,
    required String readAccessToken,
    int limit = 60,
  }) async {
    final trimmedName = name.trim();
    final cleanedToken = readAccessToken.trim();
    if (trimmedName.isEmpty || cleanedToken.isEmpty || limit <= 0) {
      return const [];
    }

    final searchResponse = await _client.get(
      _buildPersonSearchUri(trimmedName),
      headers: _buildHeaders(cleanedToken),
    );
    if (searchResponse.statusCode != 200) {
      throw TmdbMetadataException(
        'TMDB 人物搜索失败：HTTP ${searchResponse.statusCode}',
      );
    }

    final decodedSearch = jsonDecode(
      utf8.decode(searchResponse.bodyBytes, allowMalformed: true),
    );
    if (decodedSearch is! Map<String, dynamic>) {
      return const [];
    }

    final personResults =
        (decodedSearch['results'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
    final person = _pickBestPersonMatch(
      personResults,
      name: trimmedName,
      avatarUrl: avatarUrl,
      role: role,
    );
    if (person == null) {
      return const [];
    }

    final personId = (person['id'] as num?)?.toInt() ?? 0;
    if (personId <= 0) {
      return const [];
    }

    final creditsResponse = await _client.get(
      _buildPersonCombinedCreditsUri(personId),
      headers: _buildHeaders(cleanedToken),
    );
    if (creditsResponse.statusCode != 200) {
      throw TmdbMetadataException(
        'TMDB 人物作品失败：HTTP ${creditsResponse.statusCode}',
      );
    }

    final decodedCredits = jsonDecode(
      utf8.decode(creditsResponse.bodyBytes, allowMalformed: true),
    );
    if (decodedCredits is! Map<String, dynamic>) {
      return const [];
    }

    return _mapPersonCredits(
      decodedCredits,
      role: role,
      limit: limit,
    );
  }

  static List<TmdbPersonProfile> _resolveActorProfiles(Object? raw) {
    return _resolvePersonProfiles(raw, limit: 8);
  }

  List<TmdbPersonCredit> _mapPersonCredits(
    Map<String, dynamic> json, {
    required TmdbPersonCreditsRole role,
    required int limit,
  }) {
    final rawItems = switch (role) {
      TmdbPersonCreditsRole.actor => json['cast'] as List<dynamic>? ?? const [],
      TmdbPersonCreditsRole.director =>
        json['crew'] as List<dynamic>? ?? const [],
    };
    final seen = <String>{};
    final credits = <TmdbPersonCredit>[];

    for (final entry in rawItems) {
      if (entry is! Map) {
        continue;
      }
      final item = Map<String, dynamic>.from(entry);
      final mediaType = '${item['media_type'] ?? ''}'.trim().toLowerCase();
      if (mediaType != 'movie' && mediaType != 'tv') {
        continue;
      }
      if (role == TmdbPersonCreditsRole.director && !_isDirectingCredit(item)) {
        continue;
      }

      final id = (item['id'] as num?)?.toInt() ?? 0;
      if (id <= 0) {
        continue;
      }
      final title =
          '${item[mediaType == 'tv' ? 'name' : 'title'] ?? ''}'.trim();
      if (title.isEmpty) {
        continue;
      }

      final dedupeKey = '$mediaType|$id';
      if (!seen.add(dedupeKey)) {
        continue;
      }

      final backdropUrl = _resolveImageUrl(
        '${item['backdrop_path'] ?? ''}',
        size: 'w1280',
      );
      final genres = _resolvePersonCreditGenres(
        item,
        mediaType: mediaType,
      );
      credits.add(
        TmdbPersonCredit(
          tmdbId: id,
          isSeries: mediaType == 'tv',
          title: title,
          originalTitle:
              '${item[mediaType == 'tv' ? 'original_name' : 'original_title'] ?? ''}'
                  .trim(),
          posterUrl: _resolveImageUrl(
            '${item['poster_path'] ?? ''}',
            size: 'w500',
          ),
          backdropUrl: backdropUrl,
          bannerUrl: backdropUrl,
          overview: '${item['overview'] ?? ''}'.trim(),
          year: _extractYear(
            '${item[mediaType == 'tv' ? 'first_air_date' : 'release_date'] ?? ''}',
          ),
          genres: genres,
          ratingLabels: _resolveRatingLabels(
            voteAverage: item['vote_average'],
            voteCount: item['vote_count'],
          ),
          subtitle: _resolvePersonCreditSubtitle(item, role: role),
          popularity: (item['popularity'] as num?)?.toDouble() ?? 0,
        ),
      );
    }

    credits.sort((left, right) {
      final popularityCompare = right.popularity.compareTo(left.popularity);
      if (popularityCompare != 0) {
        return popularityCompare;
      }
      final yearCompare = right.year.compareTo(left.year);
      if (yearCompare != 0) {
        return yearCompare;
      }
      return left.title.compareTo(right.title);
    });

    if (credits.length <= limit) {
      return credits;
    }
    return credits.take(limit).toList(growable: false);
  }

  static bool _isDirectingCredit(Map<String, dynamic> item) {
    final department = '${item['department'] ?? ''}'.trim().toLowerCase();
    final job = '${item['job'] ?? ''}'.trim().toLowerCase();
    return job == 'director' || department == 'directing';
  }

  static String _resolvePersonCreditSubtitle(
    Map<String, dynamic> item, {
    required TmdbPersonCreditsRole role,
  }) {
    if (role == TmdbPersonCreditsRole.actor) {
      final character = '${item['character'] ?? ''}'.trim();
      if (character.isNotEmpty) {
        return '饰 $character';
      }
      return '演员';
    }

    final job = '${item['job'] ?? ''}'.trim();
    if (job.isEmpty || job.toLowerCase() == 'director') {
      return '导演';
    }
    return job;
  }

  static List<String> _resolvePersonCreditGenres(
    Map<String, dynamic> item, {
    required String mediaType,
  }) {
    final genreMap =
        mediaType == 'tv' ? _tmdbTvGenreLabels : _tmdbMovieGenreLabels;
    final genreIds = (item['genre_ids'] as List<dynamic>? ?? const [])
        .map((entry) => (entry as num?)?.toInt())
        .whereType<int>();
    final resolved = <String>[];
    final seen = <String>{};

    for (final genreId in genreIds) {
      final label = genreMap[genreId]?.trim() ?? '';
      if (label.isEmpty || !seen.add(label)) {
        continue;
      }
      resolved.add(label);
    }

    return resolved;
  }

  static const Map<int, String> _tmdbMovieGenreLabels = {
    12: '冒险',
    14: '奇幻',
    16: '动画',
    18: '剧情',
    27: '恐怖',
    28: '动作',
    35: '喜剧',
    36: '历史',
    37: '西部',
    53: '惊悚',
    80: '犯罪',
    99: '纪录',
    878: '科幻',
    9648: '悬疑',
    10402: '音乐',
    10749: '爱情',
    10751: '家庭',
    10752: '战争',
    10770: '电视电影',
  };

  static const Map<int, String> _tmdbTvGenreLabels = {
    16: '动画',
    18: '剧情',
    35: '喜剧',
    37: '西部',
    80: '犯罪',
    99: '纪录',
    9648: '悬疑',
    10751: '家庭',
    10759: '动作冒险',
    10762: '儿童',
    10763: '新闻',
    10764: '真人秀',
    10765: '科幻奇幻',
    10766: '肥皂剧',
    10767: '脱口秀',
    10768: '战争政治',
  };

  static List<TmdbPersonProfile> _resolveDirectorProfiles({
    required List<Map<String, dynamic>> createdBy,
    required List<Map<String, dynamic>> crew,
  }) {
    final directingCrew = crew
        .where(
          (item) =>
              '${item['job'] ?? ''}'.trim().toLowerCase() == 'director' ||
              '${item['department'] ?? ''}'.trim().toLowerCase() == 'directing',
        )
        .toList(growable: false);
    return _resolvePersonProfiles(
      [
        ...createdBy,
        ...directingCrew,
      ],
      limit: 6,
    );
  }

  static List<TmdbPersonProfile> _resolveCompanyProfiles(
    List<Map<String, dynamic>> companies,
  ) {
    return _resolvePersonProfiles(
      companies,
      limit: 12,
      size: 'w300',
      imageKey: 'logo_path',
    );
  }

  static List<TmdbPersonProfile> _resolvePersonProfiles(
    Object? raw, {
    required int limit,
    String size = 'w185',
    String imageKey = 'profile_path',
  }) {
    final seen = <String>{};
    final profiles = <TmdbPersonProfile>[];
    final items = raw as List<dynamic>? ?? const [];

    for (final entry in items) {
      if (entry is! Map) {
        continue;
      }
      final json = Map<String, dynamic>.from(entry);
      final name = '${json['name'] ?? ''}'.trim();
      if (name.isEmpty) {
        continue;
      }
      final key = name.toLowerCase();
      if (!seen.add(key)) {
        continue;
      }
      profiles.add(
        TmdbPersonProfile(
          name: name,
          avatarUrl: _resolveImageUrl(
            '${json[imageKey] ?? ''}',
            size: size,
          ),
        ),
      );
      if (profiles.length >= limit) {
        break;
      }
    }

    return profiles;
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

  static String _resolveBackdropUrl(String path, Object? rawBackdrops) {
    final direct = _resolveImageUrl(path, size: 'w1280');
    if (direct.isNotEmpty) {
      return direct;
    }
    final candidates = _resolveImageList(rawBackdrops, size: 'w1280');
    return candidates.isEmpty ? '' : candidates.first;
  }

  static String _resolveLogoUrl(Object? rawLogos) {
    final candidates = _resolveImageList(rawLogos, size: 'original');
    return candidates.isEmpty ? '' : candidates.first;
  }

  static List<String> _resolveRatingLabels({
    required Object? voteAverage,
    required Object? voteCount,
  }) {
    final label = _formatTmdbRatingLabel(
      voteAverage: voteAverage,
      voteCount: voteCount,
    );
    return label.isEmpty ? const [] : [label];
  }

  static String _formatTmdbRatingLabel({
    required Object? voteAverage,
    required Object? voteCount,
  }) {
    final average = switch (voteAverage) {
      final num value => value.toDouble(),
      final String value => double.tryParse(value.trim()) ?? 0,
      _ => 0,
    };
    final count = switch (voteCount) {
      final num value => value.toInt(),
      final String value => int.tryParse(value.trim()) ?? 0,
      _ => 0,
    };
    if (average <= 0 || count <= 0) {
      return '';
    }
    return 'TMDB ${average.toStringAsFixed(1)}';
  }

  static List<String> _resolveAdditionalBackdropUrls({
    required Object? raw,
    required String primaryBackdropUrl,
  }) {
    final primary = primaryBackdropUrl.trim();
    return _resolveImageList(raw, size: 'w1280')
        .where((item) => item != primary)
        .take(8)
        .toList(growable: false);
  }

  static List<String> _resolveImageList(Object? raw, {required String size}) {
    final seen = <String>{};
    final urls = <String>[];
    final items = raw as List<dynamic>? ?? const [];
    for (final entry in items) {
      if (entry is! Map) {
        continue;
      }
      final json = Map<String, dynamic>.from(entry);
      final url = _resolveImageUrl('${json['file_path'] ?? ''}', size: size);
      if (url.isEmpty || !seen.add(url)) {
        continue;
      }
      urls.add(url);
    }
    return urls;
  }

  static String _cleanQuery(String value) {
    return MediaNaming.cleanLookupQuery(value);
  }

  static String _normalizeTitle(String value) {
    return MediaNaming.normalizeLookupTitle(value);
  }

  static String _extractImagePathSegment(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (trimmed.startsWith('/')) {
      final parts = trimmed.split('/').where((item) => item.isNotEmpty);
      return parts.isEmpty ? '' : parts.last;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.pathSegments.isEmpty) {
      return '';
    }
    return uri.pathSegments.last.trim();
  }
}

class TmdbMetadataMatch {
  const TmdbMetadataMatch({
    required this.tmdbId,
    required this.isSeries,
    required this.title,
    required this.originalTitle,
    required this.posterUrl,
    required this.backdropUrl,
    required this.logoUrl,
    required this.extraBackdropUrls,
    required this.overview,
    required this.year,
    required this.durationLabel,
    required this.genres,
    required this.directors,
    required this.directorProfiles,
    required this.actors,
    required this.actorProfiles,
    required this.platforms,
    required this.platformProfiles,
    required this.ratingLabels,
    required this.imdbId,
  });

  final int tmdbId;
  final bool isSeries;
  final String title;
  final String originalTitle;
  final String posterUrl;
  final String backdropUrl;
  final String logoUrl;
  final List<String> extraBackdropUrls;
  final String overview;
  final int year;
  final String durationLabel;
  final List<String> genres;
  final List<String> directors;
  final List<TmdbPersonProfile> directorProfiles;
  final List<String> actors;
  final List<TmdbPersonProfile> actorProfiles;
  final List<String> platforms;
  final List<TmdbPersonProfile> platformProfiles;
  final List<String> ratingLabels;
  final String imdbId;
}

class TmdbPersonProfile {
  const TmdbPersonProfile({
    required this.name,
    this.avatarUrl = '',
  });

  final String name;
  final String avatarUrl;
}

enum TmdbPersonCreditsRole {
  actor,
  director,
}

class TmdbPersonCredit {
  const TmdbPersonCredit({
    required this.tmdbId,
    required this.isSeries,
    required this.title,
    required this.originalTitle,
    required this.posterUrl,
    required this.backdropUrl,
    required this.bannerUrl,
    required this.overview,
    required this.year,
    required this.genres,
    required this.ratingLabels,
    required this.subtitle,
    required this.popularity,
  });

  final int tmdbId;
  final bool isSeries;
  final String title;
  final String originalTitle;
  final String posterUrl;
  final String backdropUrl;
  final String bannerUrl;
  final String overview;
  final int year;
  final List<String> genres;
  final List<String> ratingLabels;
  final String subtitle;
  final double popularity;
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
