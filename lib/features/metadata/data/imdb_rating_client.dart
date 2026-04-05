import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

final imdbRatingClientProvider = Provider<ImdbRatingClient>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return ImdbRatingClient(client);
});

class ImdbRatingClient {
  ImdbRatingClient(this._client);

  final http.Client _client;
  Future<List<int>>? _ratingsDatasetFuture;
  final Map<String, ImdbRatingMatch?> _lookupCache = {};

  void clearCache({bool includeDataset = false}) {
    _lookupCache.clear();
    if (includeDataset) {
      _ratingsDatasetFuture = null;
    }
  }

  Future<ImdbRatingPreview?> previewMatch({
    required String query,
    int year = 0,
    bool preferSeries = false,
  }) async {
    final cleanedQuery = _cleanQuery(query);
    if (cleanedQuery.isEmpty) {
      return null;
    }

    final best = await _matchSuggestion(
      query: cleanedQuery,
      year: year,
      preferSeries: preferSeries,
    );
    if (best == null) {
      return null;
    }

    final rating = await _lookupRating(best.id);
    return ImdbRatingPreview(
      imdbId: best.id,
      title: best.title,
      year: best.year,
      typeLabel: best.type,
      posterUrl: best.posterUrl,
      ratingLabel: rating == null
          ? ''
          : 'IMDb ${rating.averageRating.toStringAsFixed(1)}',
      voteCount: rating?.voteCount ?? 0,
    );
  }

  Future<ImdbRatingMatch?> matchRating({
    required String query,
    int year = 0,
    bool preferSeries = false,
    String imdbId = '',
  }) async {
    final resolvedId = imdbId.trim().isNotEmpty
        ? imdbId.trim()
        : await _matchImdbId(
            query: query,
            year: year,
            preferSeries: preferSeries,
          );
    if (resolvedId.isEmpty) {
      return null;
    }
    if (_lookupCache.containsKey(resolvedId)) {
      return _lookupCache[resolvedId];
    }

    final rating = await _lookupRating(resolvedId);
    final result = rating == null
        ? ImdbRatingMatch(imdbId: resolvedId, ratingLabel: '')
        : ImdbRatingMatch(
            imdbId: resolvedId,
            ratingLabel: 'IMDb ${rating.averageRating.toStringAsFixed(1)}',
            voteCount: rating.voteCount,
          );
    _lookupCache[resolvedId] = result;
    return result;
  }

  Future<String> _matchImdbId({
    required String query,
    required int year,
    required bool preferSeries,
  }) async {
    final best = await _matchSuggestion(
      query: query,
      year: year,
      preferSeries: preferSeries,
    );
    return best?.id ?? '';
  }

  Future<_ImdbSuggestionItem?> _matchSuggestion({
    required String query,
    required int year,
    required bool preferSeries,
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
      throw ImdbRatingException('IMDb 匹配失败：HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(
      utf8.decode(response.bodyBytes, allowMalformed: true),
    );
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

    return _pickBestMatch(
      matches,
      query: cleanedQuery,
      year: year,
      preferSeries: preferSeries,
    );
  }

  Future<_ImdbRatingEntry?> _lookupRating(String imdbId) async {
    final responseBytes = await _loadRatingsDataset();
    final decodedBytes = GZipDecoder().decodeBytes(responseBytes);
    final lines = const LineSplitter().convert(
      utf8.decode(decodedBytes, allowMalformed: true),
    );
    for (final line in lines.skip(1)) {
      if (line.trim().isEmpty) {
        continue;
      }
      final fields = line.split('\t');
      if (fields.length < 3) {
        continue;
      }
      if (fields[0].trim() != imdbId) {
        continue;
      }
      final averageRating = double.tryParse(fields[1].trim());
      final voteCount = int.tryParse(fields[2].trim());
      if (averageRating == null || voteCount == null) {
        return null;
      }
      return _ImdbRatingEntry(
        averageRating: averageRating,
        voteCount: voteCount,
      );
    }
    return null;
  }

  Future<List<int>> _loadRatingsDataset() {
    return _ratingsDatasetFuture ??= () async {
      final response = await _client.get(
        Uri.parse('https://datasets.imdbws.com/title.ratings.tsv.gz'),
        headers: const {
          'Accept': 'application/gzip',
          'User-Agent': 'Starflow/1.0',
        },
      );
      if (response.statusCode != 200) {
        throw ImdbRatingException(
          'IMDb 评分数据加载失败：HTTP ${response.statusCode}',
        );
      }
      return response.bodyBytes;
    }();
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

class ImdbRatingMatch {
  const ImdbRatingMatch({
    required this.imdbId,
    required this.ratingLabel,
    this.voteCount = 0,
  });

  final String imdbId;
  final String ratingLabel;
  final int voteCount;

  bool get hasRating => ratingLabel.trim().isNotEmpty;
}

class ImdbRatingPreview {
  const ImdbRatingPreview({
    required this.imdbId,
    required this.title,
    this.year = 0,
    this.typeLabel = '',
    this.posterUrl = '',
    this.ratingLabel = '',
    this.voteCount = 0,
  });

  final String imdbId;
  final String title;
  final int year;
  final String typeLabel;
  final String posterUrl;
  final String ratingLabel;
  final int voteCount;
}

class ImdbRatingException implements Exception {
  const ImdbRatingException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _ImdbRatingEntry {
  const _ImdbRatingEntry({
    required this.averageRating,
    required this.voteCount,
  });

  final double averageRating;
  final int voteCount;
}

class _ImdbSuggestionItem {
  const _ImdbSuggestionItem({
    required this.id,
    required this.title,
    required this.year,
    required this.rank,
    required this.type,
    required this.typeId,
    this.posterUrl = '',
  });

  final String id;
  final String title;
  final int year;
  final int rank;
  final String type;
  final String typeId;
  final String posterUrl;

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
    final json = Map<String, dynamic>.from(raw);
    final id = '${json['id'] ?? ''}'.trim();
    final title = '${json['l'] ?? ''}'.trim();
    if (id.isEmpty || title.isEmpty) {
      return null;
    }

    return _ImdbSuggestionItem(
      id: id,
      title: title,
      year: json['y'] as int? ?? 0,
      rank: json['rank'] as int? ?? 999999,
      type: '${json['q'] ?? ''}',
      typeId: '${json['qid'] ?? ''}',
      posterUrl: _resolvePosterUrl(json['i']),
    );
  }

  static String _resolvePosterUrl(Object? raw) {
    if (raw is! Map) {
      return '';
    }
    return '${raw['imageUrl'] ?? raw['url'] ?? ''}'.trim();
  }
}
