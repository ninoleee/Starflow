import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

final imdbMetadataClientProvider = Provider<ImdbMetadataClient>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return ImdbMetadataClient(client);
});

class ImdbMetadataClient {
  ImdbMetadataClient(this._client);

  final http.Client _client;

  Future<ImdbMetadataMatch?> matchTitle({
    required String query,
    int year = 0,
    bool preferSeries = false,
  }) async {
    final cleanedQuery = _cleanQuery(query);
    if (cleanedQuery.isEmpty) {
      return null;
    }

    final response = await _client.get(
      _buildSuggestionUri(cleanedQuery),
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'Starflow/1.0',
      },
    );
    if (response.statusCode != 200) {
      throw ImdbMetadataException('IMDb 匹配失败：HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    final matches = (decoded['d'] as List<dynamic>? ?? const [])
        .map((item) => _ImdbSuggestionItem.fromJson(item))
        .whereType<_ImdbSuggestionItem>()
        .toList();
    if (matches.isEmpty) {
      return null;
    }

    final best = _pickBestMatch(
      matches,
      query: cleanedQuery,
      year: year,
      preferSeries: preferSeries,
    );
    if (best == null) {
      return null;
    }

    return ImdbMetadataMatch(
      imdbId: best.id,
      title: best.title,
      posterUrl: best.posterUrl,
      year: best.year,
      actors: best.stars,
      overview: _buildOverview(best),
    );
  }

  Uri _buildSuggestionUri(String query) {
    final normalized = query.trim().toLowerCase();
    final prefix = normalized.isEmpty
        ? 'x'
        : RegExp(r'[a-z0-9]').hasMatch(normalized[0])
            ? normalized[0]
            : 'x';
    return Uri.parse(
      'https://v3.sg.media-imdb.com/suggestion/$prefix/${Uri.encodeComponent(query)}.json?includeVideos=1',
    );
  }

  _ImdbSuggestionItem? _pickBestMatch(
    List<_ImdbSuggestionItem> items, {
    required String query,
    required int year,
    required bool preferSeries,
  }) {
    final normalizedQuery = _normalizeTitle(query);
    _ImdbSuggestionItem? best;
    var bestScore = double.negativeInfinity;

    for (final item in items) {
      final score = _scoreMatch(
        item,
        normalizedQuery: normalizedQuery,
        year: year,
        preferSeries: preferSeries,
      );
      if (score > bestScore) {
        bestScore = score;
        best = item;
      }
    }

    return bestScore < 0 ? null : best;
  }

  double _scoreMatch(
    _ImdbSuggestionItem item, {
    required String normalizedQuery,
    required int year,
    required bool preferSeries,
  }) {
    final normalizedTitle = _normalizeTitle(item.title);
    var score = 0.0;

    if (normalizedTitle == normalizedQuery) {
      score += 100;
    } else if (normalizedTitle.contains(normalizedQuery) ||
        normalizedQuery.contains(normalizedTitle)) {
      score += 55;
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
        score -= 16;
      }
    }

    if (preferSeries) {
      score += item.isSeries ? 16 : -8;
    } else {
      score += item.isMovie ? 12 : 0;
    }

    score -= item.rank / 100000;
    return score;
  }

  String _buildOverview(_ImdbSuggestionItem item) {
    final entries = <String>[
      'IMDb 自动匹配到《${item.title}》',
      if (item.year > 0) '${item.year}',
      if (item.stars.isNotEmpty) '主演：${item.stars.join('、')}',
    ];
    return entries.join(' · ');
  }

  static String _cleanQuery(String value) {
    var cleaned = value
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
    return cleaned;
  }

  static String _normalizeTitle(String value) {
    return _cleanQuery(value)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), '');
  }
}

class ImdbMetadataMatch {
  const ImdbMetadataMatch({
    required this.imdbId,
    required this.title,
    required this.posterUrl,
    required this.year,
    required this.actors,
    required this.overview,
  });

  final String imdbId;
  final String title;
  final String posterUrl;
  final int year;
  final List<String> actors;
  final String overview;
}

class ImdbMetadataException implements Exception {
  const ImdbMetadataException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _ImdbSuggestionItem {
  const _ImdbSuggestionItem({
    required this.id,
    required this.title,
    required this.posterUrl,
    required this.year,
    required this.rank,
    required this.type,
    required this.typeId,
    required this.stars,
  });

  final String id;
  final String title;
  final String posterUrl;
  final int year;
  final int rank;
  final String type;
  final String typeId;
  final List<String> stars;

  bool get isSeries =>
      typeId.toLowerCase().contains('tv') ||
      type.toLowerCase().contains('series');

  bool get isMovie =>
      typeId.toLowerCase().contains('movie') ||
      type.toLowerCase().contains('feature');

  static _ImdbSuggestionItem? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final json = Map<String, dynamic>.from(raw as Map);
    final id = '${json['id'] ?? ''}'.trim();
    final title = '${json['l'] ?? ''}'.trim();
    if (id.isEmpty || title.isEmpty) {
      return null;
    }

    final image = json['i'] as Map<String, dynamic>? ?? const {};
    final stars = '${json['s'] ?? ''}'
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();

    return _ImdbSuggestionItem(
      id: id,
      title: title,
      posterUrl: '${image['imageUrl'] ?? ''}'.trim(),
      year: json['y'] as int? ?? 0,
      rank: json['rank'] as int? ?? 999999,
      type: '${json['q'] ?? ''}'.trim(),
      typeId: '${json['qid'] ?? ''}'.trim(),
      stars: stars,
    );
  }
}
