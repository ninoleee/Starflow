import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/core/network/starflow_http_client.dart';
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
      return null;
    }

    final cacheKey = 'id|$normalizedDoubanId';
    if (_resolvedMatches.containsKey(cacheKey)) {
      return _resolvedMatches[cacheKey];
    }
    final inflight = _inflightMatches[cacheKey];
    if (inflight != null) {
      return inflight;
    }

    final future = _matchByDoubanIdUncached(normalizedDoubanId);
    _inflightMatches[cacheKey] = future;

    try {
      final result = await future;
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
      return _resolvedMatches[cacheKey];
    }
    final inflight = _inflightMatches[cacheKey];
    if (inflight != null) {
      return inflight;
    }

    final future = _matchTitleUncached(
      query: query.trim(),
      actorHint: actorHint,
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
      return null;
    }

    final best = _pickBestMatch(
      entries,
      query: query,
      year: year,
      preferSeries: preferSeries,
    );
    if (best == null) {
      return null;
    }
    return _mapMatch(best, provider: MetadataMatchProvider.wmdb);
  }

  Map<String, dynamic>? _pickBestMatch(
    List<Map<String, dynamic>> candidates, {
    required String query,
    required int year,
    required bool preferSeries,
  }) {
    final normalizedQuery = _normalizeTitle(query);
    Map<String, dynamic>? best;
    var bestScore = double.negativeInfinity;

    for (final candidate in candidates) {
      final score = _scoreCandidate(
        candidate,
        normalizedQuery: normalizedQuery,
        year: year,
        preferSeries: preferSeries,
      );
      if (score > bestScore) {
        best = candidate;
        bestScore = score;
      }
    }

    return bestScore < 0 ? null : best;
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
  }) {}

  void _logSuccess({
    required String action,
    required Uri uri,
    required http.Response response,
    required String details,
  }) {}

  void _logFailure({
    required String action,
    required Uri uri,
    required http.Response response,
    required String details,
  }) {}
}

class WmdbMetadataException implements Exception {
  const WmdbMetadataException(this.message);

  final String message;

  @override
  String toString() => message;
}
