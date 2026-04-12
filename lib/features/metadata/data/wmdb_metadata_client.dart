import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/core/network/starflow_http_client.dart';
import 'package:starflow/core/utils/metadata_search_trace.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';

final wmdbMetadataClientProvider = Provider<WmdbMetadataClient>((ref) {
  final client = ref.watch(starflowHttpClientProvider);
  return WmdbMetadataClient(client);
});

class WmdbMetadataClient {
  WmdbMetadataClient(this._client);

  final http.Client _client;
  final Map<String, MetadataMatchResult?> _resolvedMatches = {};
  final Map<String, Future<MetadataMatchResult?>> _inflightMatches = {};

  void clearCache() {
    _resolvedMatches.clear();
    _inflightMatches.clear();
  }

  Future<MetadataMatchResult?> matchByDoubanId({
    required String doubanId,
  }) async {
    final normalizedDoubanId = doubanId.trim();
    if (normalizedDoubanId.isEmpty) {
      metadataSearchTrace(
        'wmdb.matchByDoubanId.skip-invalid',
        fields: <String, Object?>{
          'doubanId': doubanId,
        },
      );
      return null;
    }

    final cacheKey = 'id|$normalizedDoubanId';
    if (_resolvedMatches.containsKey(cacheKey)) {
      final cached = _resolvedMatches[cacheKey];
      metadataSearchTrace(
        'wmdb.matchByDoubanId.cache-hit',
        fields: <String, Object?>{
          'doubanId': normalizedDoubanId,
          'matched': cached != null,
          'title': cached?.title ?? '',
          'tmdbId': cached?.tmdbId ?? '',
        },
      );
      return cached;
    }
    final inflight = _inflightMatches[cacheKey];
    if (inflight != null) {
      metadataSearchTrace(
        'wmdb.matchByDoubanId.inflight-hit',
        fields: <String, Object?>{
          'doubanId': normalizedDoubanId,
        },
      );
      return inflight;
    }

    metadataSearchTrace(
      'wmdb.matchByDoubanId.start',
      fields: <String, Object?>{
        'doubanId': normalizedDoubanId,
      },
    );
    final future = _matchByDoubanIdUncached(normalizedDoubanId);
    _inflightMatches[cacheKey] = future;

    try {
      final result = await future;
      metadataSearchTrace(
        'wmdb.matchByDoubanId.finish',
        fields: <String, Object?>{
          'doubanId': normalizedDoubanId,
          'matched': result != null,
          'title': result?.title ?? '',
          'tmdbId': result?.tmdbId ?? '',
          'imdbId': result?.imdbId ?? '',
        },
      );
      _resolvedMatches[cacheKey] = result;
      return result;
    } finally {
      _inflightMatches.remove(cacheKey);
    }
  }

  Future<MetadataMatchResult?> matchTitle({
    required String query,
    int year = 0,
    bool preferSeries = false,
    List<String> actors = const [],
  }) async {
    final normalizedQuery = _normalizeTitle(query);
    final actorHint = actors
        .map((item) => item.trim())
        .firstWhere((item) => item.isNotEmpty, orElse: () => '');
    if (normalizedQuery.isEmpty && actorHint.isEmpty) {
      metadataSearchTrace(
        'wmdb.matchTitle.skip-invalid',
        fields: <String, Object?>{
          'query': query,
          'normalizedQuery': normalizedQuery,
          'year': year,
          'preferSeries': preferSeries,
          'actorHint': actorHint,
        },
      );
      return null;
    }

    final cacheKey = [
      'search',
      normalizedQuery,
      year,
      preferSeries ? 'tv' : 'movie',
      _normalizeTitle(actorHint),
    ].join('|');
    if (_resolvedMatches.containsKey(cacheKey)) {
      final cached = _resolvedMatches[cacheKey];
      metadataSearchTrace(
        'wmdb.matchTitle.cache-hit',
        fields: <String, Object?>{
          'query': query,
          'normalizedQuery': normalizedQuery,
          'year': year,
          'preferSeries': preferSeries,
          'actorHint': actorHint,
          'matched': cached != null,
          'title': cached?.title ?? '',
          'tmdbId': cached?.tmdbId ?? '',
        },
      );
      return cached;
    }
    final inflight = _inflightMatches[cacheKey];
    if (inflight != null) {
      metadataSearchTrace(
        'wmdb.matchTitle.inflight-hit',
        fields: <String, Object?>{
          'query': query,
          'normalizedQuery': normalizedQuery,
          'year': year,
          'preferSeries': preferSeries,
          'actorHint': actorHint,
        },
      );
      return inflight;
    }

    metadataSearchTrace(
      'wmdb.matchTitle.start',
      fields: <String, Object?>{
        'query': query,
        'normalizedQuery': normalizedQuery,
        'year': year,
        'preferSeries': preferSeries,
        'actorHint': actorHint,
      },
    );
    final future = _matchTitleUncached(
      query: query.trim(),
      actorHint: actorHint,
      year: year,
      preferSeries: preferSeries,
    );
    _inflightMatches[cacheKey] = future;

    try {
      final result = await future;
      metadataSearchTrace(
        'wmdb.matchTitle.finish',
        fields: <String, Object?>{
          'query': query,
          'year': year,
          'preferSeries': preferSeries,
          'actorHint': actorHint,
          'matched': result != null,
          'title': result?.title ?? '',
          'tmdbId': result?.tmdbId ?? '',
          'imdbId': result?.imdbId ?? '',
        },
      );
      _resolvedMatches[cacheKey] = result;
      return result;
    } finally {
      _inflightMatches.remove(cacheKey);
    }
  }

  Future<List<MetadataMatchResult>> searchTitleMatches({
    required String query,
    int year = 0,
    bool preferSeries = false,
    List<String> actors = const [],
    int maxResults = 3,
  }) async {
    final normalizedQuery = _normalizeTitle(query);
    final actorHint = actors
        .map((item) => item.trim())
        .firstWhere((item) => item.isNotEmpty, orElse: () => '');
    if ((normalizedQuery.isEmpty && actorHint.isEmpty) || maxResults <= 0) {
      return const <MetadataMatchResult>[];
    }

    final parameters = <String, String>{
      'limit': '10',
      'skip': '0',
      'lang': 'Cn',
      if (query.trim().isNotEmpty) 'q': query.trim(),
      if (actorHint.isNotEmpty) 'actor': actorHint,
      if (year > 0) 'year': '$year',
    };
    final uri = Uri.https('api.wmdb.tv', '/api/v1/movie/search', parameters);
    final response = await _client.get(
      uri,
      headers: const {'Accept': 'application/json'},
    );
    if (response.statusCode != 200) {
      throw WmdbMetadataException('WMDB 搜索失败：HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(
      utf8.decode(response.bodyBytes, allowMalformed: true),
    );
    if (decoded is! Map<String, dynamic>) {
      return const <MetadataMatchResult>[];
    }

    final entries = (decoded['data'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    if (entries.isEmpty) {
      return const <MetadataMatchResult>[];
    }

    final scored = entries
        .map(
          (item) => (
            item: item,
            score: _scoreCandidate(
              item,
              normalizedQuery: normalizedQuery,
              year: year,
              preferSeries: preferSeries,
            ),
          ),
        )
        .where((entry) => entry.score >= 0)
        .toList(growable: false)
      ..sort((left, right) => right.score.compareTo(left.score));

    final seen = <String>{};
    final results = <MetadataMatchResult>[];
    for (final entry in scored) {
      final result =
          _mapMatch(entry.item, provider: MetadataMatchProvider.wmdb);
      if (result == null) {
        continue;
      }
      final key = [
        result.doubanId.trim(),
        result.imdbId.trim(),
        result.tmdbId.trim(),
        result.title.trim().toLowerCase(),
      ].where((item) => item.isNotEmpty).join('|');
      if (key.isEmpty || !seen.add(key)) {
        continue;
      }
      results.add(result);
      if (results.length >= maxResults) {
        break;
      }
    }
    return results;
  }

  Future<MetadataMatchResult?> _matchByDoubanIdUncached(String doubanId) async {
    final uri = Uri.https('api.wmdb.tv', '/movie/api', {'id': doubanId});
    _logRequest(
      action: 'lookup',
      uri: uri,
      details: 'doubanId=$doubanId',
    );
    final response = await _client.get(
      uri,
      headers: const {'Accept': 'application/json'},
    );
    if (response.statusCode != 200) {
      _logFailure(
        action: 'lookup',
        uri: uri,
        response: response,
        details: 'doubanId=$doubanId',
      );
      throw WmdbMetadataException('WMDB 查询失败：HTTP ${response.statusCode}');
    }
    _logSuccess(
      action: 'lookup',
      uri: uri,
      response: response,
      details: 'doubanId=$doubanId',
    );

    final decoded = jsonDecode(
      utf8.decode(response.bodyBytes, allowMalformed: true),
    );
    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    return _mapMatch(decoded, provider: MetadataMatchProvider.wmdb);
  }

  Future<MetadataMatchResult?> _matchTitleUncached({
    required String query,
    required String actorHint,
    required int year,
    required bool preferSeries,
  }) async {
    final parameters = <String, String>{
      'limit': '10',
      'skip': '0',
      'lang': 'Cn',
      if (query.trim().isNotEmpty) 'q': query.trim(),
      if (actorHint.isNotEmpty) 'actor': actorHint,
      if (year > 0) 'year': '$year',
    };
    final uri = Uri.https('api.wmdb.tv', '/api/v1/movie/search', parameters);
    _logRequest(
      action: 'search',
      uri: uri,
      details:
          'query=${query.trim()} year=$year preferSeries=$preferSeries actor=$actorHint',
    );
    final response = await _client.get(
      uri,
      headers: const {'Accept': 'application/json'},
    );
    if (response.statusCode != 200) {
      _logFailure(
        action: 'search',
        uri: uri,
        response: response,
        details:
            'query=${query.trim()} year=$year preferSeries=$preferSeries actor=$actorHint',
      );
      throw WmdbMetadataException('WMDB 搜索失败：HTTP ${response.statusCode}');
    }
    _logSuccess(
      action: 'search',
      uri: uri,
      response: response,
      details:
          'query=${query.trim()} year=$year preferSeries=$preferSeries actor=$actorHint',
    );

    final decoded = jsonDecode(
      utf8.decode(response.bodyBytes, allowMalformed: true),
    );
    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    final entries = (decoded['data'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    if (entries.isEmpty) {
      metadataSearchTrace(
        'wmdb.matchTitle.candidates',
        fields: <String, Object?>{
          'query': query,
          'count': 0,
          'sample': '',
        },
      );
      return null;
    }

    final ranked = _rankScoredCandidates(
      entries,
      query: query,
      year: year,
      preferSeries: preferSeries,
    );
    metadataSearchTrace(
      'wmdb.matchTitle.candidates',
      fields: <String, Object?>{
        'query': query,
        'count': entries.length,
        'rankedCount': ranked.length,
        'sample': _describeRankedWmdbCandidates(ranked),
      },
    );
    if (ranked.isEmpty) {
      return null;
    }
    final best = ranked.first.item;
    metadataSearchTrace(
      'wmdb.matchTitle.best',
      fields: <String, Object?>{
        'query': query,
        'candidate': _describeWmdbCandidate(best, score: ranked.first.score),
      },
    );
    return _mapMatch(best, provider: MetadataMatchProvider.wmdb);
  }

  List<({Map<String, dynamic> item, double score})> _rankScoredCandidates(
    List<Map<String, dynamic>> entries, {
    required String query,
    required int year,
    required bool preferSeries,
  }) {
    final normalizedQuery = _normalizeTitle(query);
    return entries
        .map(
          (item) => (
            item: item,
            score: _scoreCandidate(
              item,
              normalizedQuery: normalizedQuery,
              year: year,
              preferSeries: preferSeries,
            ),
          ),
        )
        .where((entry) => entry.score >= 0)
        .toList(growable: false)
      ..sort((left, right) => right.score.compareTo(left.score));
  }

  double _scoreCandidate(
    Map<String, dynamic> item, {
    required String normalizedQuery,
    required int year,
    required bool preferSeries,
  }) {
    final names = <String>[
      '${item['originalName'] ?? ''}',
      ..._splitAliases('${item['alias'] ?? ''}'),
      _resolveLocalizedEntry(item)['name'] ?? '',
    ].map(_normalizeTitle).where((item) => item.isNotEmpty);
    var score = 0.0;

    for (final name in names) {
      if (name == normalizedQuery) {
        score += 100;
      } else if (name.contains(normalizedQuery) ||
          normalizedQuery.contains(name)) {
        score += 52;
      }
    }

    final candidateYear = int.tryParse('${item['year'] ?? ''}') ?? 0;
    if (year > 0 && candidateYear > 0) {
      final delta = (candidateYear - year).abs();
      if (delta == 0) {
        score += 20;
      } else if (delta == 1) {
        score += 10;
      } else if (delta <= 3) {
        score += 3;
      } else {
        score -= 12;
      }
    }

    final type = '${item['type'] ?? ''}'.trim().toLowerCase();
    if (preferSeries) {
      score += type.contains('series') || type.contains('tv') ? 16 : -8;
    } else {
      score += type.contains('movie') ? 12 : 0;
    }

    final doubanVotes = (item['doubanVotes'] as num?)?.toDouble() ?? 0;
    score += doubanVotes / 100000;
    return score;
  }

  MetadataMatchResult? _mapMatch(
    Map<String, dynamic> json, {
    required MetadataMatchProvider provider,
  }) {
    final data = _resolveLocalizedEntry(json);
    final mediaType = MetadataMediaTypeX.fromRaw('${json['type'] ?? ''}');
    final title = '${data['name'] ?? json['originalName'] ?? ''}'.trim();
    if (title.isEmpty) {
      return null;
    }

    final genres = _splitGenres(data['genre'] ?? '');
    final directors = _resolveNames(json['director']);
    final actors = _resolveNames(json['actor']);
    final posterUrl = (data['poster'] ?? '').trim();
    final overview = (data['description'] ?? '').trim();
    final year = int.tryParse('${json['year'] ?? ''}') ?? 0;
    final imdbId = '${json['imdbId'] ?? ''}'.trim();
    final tmdbId = '${json['tmdbId'] ?? ''}'.trim();
    final doubanId = '${json['doubanId'] ?? ''}'.trim();
    final doubanRating = '${json['doubanRating'] ?? ''}'.trim();
    final imdbRating = '${json['imdbRating'] ?? ''}'.trim();
    final durationLabel = _formatDuration(
      (json['duration'] as num?)?.toInt() ?? 0,
    );

    return MetadataMatchResult(
      provider: provider,
      mediaType: mediaType,
      title: title,
      originalTitle: '${json['originalName'] ?? title}'.trim(),
      alternateTitles: _splitAliases('${json['alias'] ?? ''}'),
      posterUrl: posterUrl,
      overview: overview,
      year: year,
      durationLabel: durationLabel,
      genres: genres,
      directors: directors,
      actors: actors,
      imdbId: imdbId,
      tmdbId: tmdbId,
      doubanId: doubanId,
      ratingLabels: [
        _formatDoubanRatingLabel(doubanRating),
        if (imdbRating.isNotEmpty) 'IMDb $imdbRating',
      ],
    );
  }

  String _formatDoubanRatingLabel(String raw) {
    final text = raw.trim();
    if (text.isEmpty || text == 'null') {
      return '豆瓣 0';
    }
    final parsed = double.tryParse(text);
    if (parsed == null) {
      return '豆瓣 $text';
    }
    if (parsed <= 0) {
      return '豆瓣 0';
    }
    return '豆瓣 ${parsed.toStringAsFixed(1)}';
  }

  Map<String, String> _resolveLocalizedEntry(Map<String, dynamic> json) {
    final localizedEntries = (json['data'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    if (localizedEntries.isEmpty) {
      return const {};
    }

    for (final entry in localizedEntries) {
      if ('${entry['lang'] ?? ''}'.trim().toLowerCase() == 'cn') {
        return {
          'name': '${entry['name'] ?? ''}'.trim(),
          'poster': '${entry['poster'] ?? ''}'.trim(),
          'genre': '${entry['genre'] ?? ''}'.trim(),
          'description': '${entry['description'] ?? ''}'.trim(),
        };
      }
    }

    final first = localizedEntries.first;
    return {
      'name': '${first['name'] ?? ''}'.trim(),
      'poster': '${first['poster'] ?? ''}'.trim(),
      'genre': '${first['genre'] ?? ''}'.trim(),
      'description': '${first['description'] ?? ''}'.trim(),
    };
  }

  List<String> _resolveNames(Object? raw) {
    final seen = <String>{};
    final names = <String>[];
    final groups = raw as List<dynamic>? ?? const [];

    for (final group in groups) {
      if (group is! Map) {
        continue;
      }
      final items = (group['data'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (items.isEmpty) {
        continue;
      }

      Map<String, dynamic> selected = items.first;
      for (final item in items) {
        if ('${item['lang'] ?? ''}'.trim().toLowerCase() == 'cn') {
          selected = item;
          break;
        }
      }

      final name = '${selected['name'] ?? ''}'.trim();
      if (name.isEmpty) {
        continue;
      }
      final key = name.toLowerCase();
      if (seen.add(key)) {
        names.add(name);
      }
    }

    return names;
  }

  List<String> _splitGenres(String raw) {
    return raw
        .split(RegExp(r'[/,|]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  List<String> _splitAliases(String raw) {
    return raw
        .split(RegExp(r'/|,|;|｜|\|'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) {
      return '';
    }
    final totalMinutes = (seconds / 60).round();
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours <= 0) {
      return '${totalMinutes}m';
    }
    if (minutes == 0) {
      return '${hours}h';
    }
    return '${hours}h ${minutes}m';
  }

  String _normalizeTitle(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[._]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), '')
        .trim();
  }

  void _logRequest({
    required String action,
    required Uri uri,
    required String details,
  }) {
    metadataSearchTrace(
      'wmdb.$action.request',
      fields: <String, Object?>{
        'uri': uri,
        'details': details,
      },
    );
  }

  void _logSuccess({
    required String action,
    required Uri uri,
    required http.Response response,
    required String details,
  }) {
    metadataSearchTrace(
      'wmdb.$action.response',
      fields: <String, Object?>{
        'uri': uri,
        'status': response.statusCode,
        'bytes': response.bodyBytes.length,
        'details': details,
      },
    );
  }

  void _logFailure({
    required String action,
    required Uri uri,
    required http.Response response,
    required String details,
  }) {
    metadataSearchTrace(
      'wmdb.$action.response-failed',
      fields: <String, Object?>{
        'uri': uri,
        'status': response.statusCode,
        'bytes': response.bodyBytes.length,
        'details': details,
      },
    );
  }

  String _describeRankedWmdbCandidates(
    List<({Map<String, dynamic> item, double score})> ranked,
  ) {
    return ranked
        .take(5)
        .map((entry) => _describeWmdbCandidate(entry.item, score: entry.score))
        .join(' || ');
  }

  String _describeWmdbCandidate(Map<String, dynamic> item, {double? score}) {
    final data = _resolveLocalizedEntry(item);
    final title = '${data['name'] ?? item['originalName'] ?? ''}'.trim();
    final originalTitle = '${item['originalName'] ?? ''}'.trim();
    final year = '${item['year'] ?? ''}'.trim();
    final doubanId = '${item['doubanId'] ?? ''}'.trim();
    final tmdbId = '${item['tmdbId'] ?? ''}'.trim();
    final type = '${item['type'] ?? ''}'.trim();
    final doubanVotes = '${item['doubanVotes'] ?? ''}'.trim();
    final parts = <String>[
      if (type.isNotEmpty) type,
      if (title.isNotEmpty) title,
      if (originalTitle.isNotEmpty &&
          originalTitle.toLowerCase() != title.toLowerCase())
        'orig=$originalTitle',
      if (year.isNotEmpty) 'year=$year',
      if (doubanId.isNotEmpty) 'doubanId=$doubanId',
      if (tmdbId.isNotEmpty) 'tmdbId=$tmdbId',
      if (doubanVotes.isNotEmpty) 'votes=$doubanVotes',
      if (score != null) 'score=${score.toStringAsFixed(2)}',
    ];
    return parts.join(' ');
  }
}

class WmdbMetadataException implements Exception {
  const WmdbMetadataException(this.message);

  final String message;

  @override
  String toString() => message;
}
