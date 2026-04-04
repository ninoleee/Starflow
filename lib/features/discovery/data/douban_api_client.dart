import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/core/utils/douban_cover_debug.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';

final doubanApiClientProvider = Provider<DoubanApiClient>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return DoubanApiClient(client);
});

class DoubanApiClient {
  DoubanApiClient(this._client);

  final http.Client _client;

  static const _userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

  Future<List<DoubanEntry>> fetchInterestItems({
    required String userId,
    required DoubanInterestStatus status,
    int page = 1,
  }) async {
    final trimmedUserId = userId.trim();
    if (trimmedUserId.isEmpty) {
      return const [];
    }

    if (status == DoubanInterestStatus.randomMark) {
      final items = <DoubanEntry>[];
      var start = 0;
      const pageSize = 50;

      while (true) {
        final batch = await _fetchInterestPage(
          userId: trimmedUserId,
          status: DoubanInterestStatus.mark,
          start: start,
          count: pageSize,
        );
        items.addAll(batch);
        if (batch.length < pageSize) {
          break;
        }
        start += pageSize;
      }

      final deduped = {
        for (final item in items) item.id: item,
      }.values.toList()
        ..shuffle(Random());
      return deduped.take(min(9, deduped.length)).toList();
    }

    const pageSize = 20;
    return _fetchInterestPage(
      userId: trimmedUserId,
      status: status,
      start: (page - 1) * pageSize,
      count: pageSize,
    );
  }

  Future<List<DoubanEntry>> fetchSuggestionItems({
    required String cookie,
    required DoubanSuggestionMediaType mediaType,
    int page = 1,
  }) async {
    const pageSize = 20;
    final ckValue = _extractCookieValue(cookie, 'ck');
    final uri = Uri.parse(
      'https://m.douban.com/rexxar/api/v2/${mediaType.value}/suggestion'
      '?start=${(page - 1) * pageSize}&count=$pageSize&new_struct=1&with_review=1&ck=$ckValue',
    );

    final payload = await _getJson(
      uri,
      headers: {
        'Referer': 'https://m.douban.com/movie',
        if (cookie.trim().isNotEmpty) 'Cookie': cookie.trim(),
      },
    );
    final items = payload['items'] as List<dynamic>? ?? const [];
    return items
        .map((item) => _mapDoubanEntry(Map<String, dynamic>.from(item as Map)))
        .whereType<DoubanEntry>()
        .toList();
  }

  Future<List<DoubanEntry>> fetchListItems({
    required String url,
    int page = 1,
  }) async {
    final normalized = url.trim();
    if (normalized.isEmpty) {
      return const [];
    }

    if (normalized.contains('douban.com/doulist/')) {
      return _fetchDouListItems(normalized, page: page);
    }
    if (normalized.contains('douban.com/subject_collection/')) {
      return _fetchSubjectCollectionItems(normalized, page: page);
    }
    throw const DoubanApiException('暂不支持这个豆瓣片单地址');
  }

  Future<List<DoubanCarouselEntry>> fetchCarouselItems() async {
    final response = await _client.get(
      Uri.parse(
        'https://gist.githubusercontent.com/huangxd-/5ae61c105b417218b9e5bad7073d2f36/raw/douban_carousel.json',
      ),
      headers: const {
        'User-Agent': _userAgent,
        'Accept': 'application/json',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DoubanApiException('读取豆瓣轮播失败：HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    final items = decoded is List ? decoded : const [];
    return items
        .map((item) => Map<String, dynamic>.from(item as Map))
        .map(_mapCarouselEntry)
        .whereType<DoubanCarouselEntry>()
        .toList();
  }

  Future<List<DoubanEntry>> _fetchInterestPage({
    required String userId,
    required DoubanInterestStatus status,
    required int start,
    required int count,
  }) async {
    final uri = Uri.parse(
      'https://m.douban.com/rexxar/api/v2/user/$userId/interests'
      '?status=${status == DoubanInterestStatus.randomMark ? DoubanInterestStatus.mark.value : status.value}&start=$start&count=$count',
    );
    final payload = await _getJson(
      uri,
      headers: const {
        'Referer': 'https://m.douban.com/mine/movie',
      },
    );
    final interests = payload['interests'] as List<dynamic>? ?? const [];
    return interests
        .map(
            (item) => _mapInterestEntry(Map<String, dynamic>.from(item as Map)))
        .whereType<DoubanEntry>()
        .toList();
  }

  Future<List<DoubanEntry>> _fetchDouListItems(
    String url, {
    required int page,
  }) async {
    final listId = RegExp(r'doulist/(\d+)').firstMatch(url)?.group(1);
    if (listId == null || listId.isEmpty) {
      throw const DoubanApiException('无法解析豆瓣片单 ID');
    }

    const pageSize = 25;
    final uri = Uri.parse(
      'https://m.douban.com/rexxar/api/v2/doulist/$listId/items'
      '?start=${(page - 1) * pageSize}&count=$pageSize&updated_at&items_only=1&type_tag&for_mobile=1',
    );
    final payload = await _getJson(
      uri,
      headers: const {
        'Referer': 'https://movie.douban.com/explore',
      },
    );
    final items = payload['items'] as List<dynamic>? ?? const [];
    return items
        .map((item) => _mapDoubanEntry(Map<String, dynamic>.from(item as Map)))
        .whereType<DoubanEntry>()
        .toList();
  }

  Future<List<DoubanEntry>> _fetchSubjectCollectionItems(
    String url, {
    required int page,
  }) async {
    final collectionId =
        RegExp(r'subject_collection/(\w+)').firstMatch(url)?.group(1);
    if (collectionId == null || collectionId.isEmpty) {
      throw const DoubanApiException('无法解析豆瓣合集 ID');
    }

    const pageSize = 20;
    final uri = Uri.parse(
      'https://m.douban.com/rexxar/api/v2/subject_collection/$collectionId/items'
      '?start=${(page - 1) * pageSize}&count=$pageSize&updated_at&items_only=1&type_tag&for_mobile=1',
    );
    final payload = await _getJson(
      uri,
      headers: {
        'Referer': 'https://m.douban.com/subject_collection/$collectionId/',
      },
    );
    final items =
        payload['subject_collection_items'] as List<dynamic>? ?? const [];
    return items
        .map((item) => _mapDoubanEntry(Map<String, dynamic>.from(item as Map)))
        .whereType<DoubanEntry>()
        .toList();
  }

  Future<Map<String, dynamic>> _getJson(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    final response = await _client.get(
      uri,
      headers: {
        'User-Agent': _userAgent,
        'Accept': 'application/json',
        ...headers,
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DoubanApiException('豆瓣请求失败：HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return const {};
  }

  DoubanEntry? _mapInterestEntry(Map<String, dynamic> item) {
    final payload = Map<String, dynamic>.from(item);
    final subject =
        Map<String, dynamic>.from(item['subject'] as Map? ?? const {});
    if (subject.isNotEmpty) {
      payload['subject'] = subject;
    }
    return _mapDoubanEntry(
      payload,
      noteFallback: [
        (item['comment'] as String? ?? '').trim(),
      ],
      secondaryNoteFallback: [
        (item['create_time'] as String? ?? '').trim(),
      ],
    );
  }

  DoubanEntry? _mapDoubanEntry(
    Map<String, dynamic> item, {
    List<String> noteFallback = const [],
    List<String> secondaryNoteFallback = const [],
  }) {
    final target = _resolveSubjectMap(item);
    final id = _resolveId(target, item);
    final title = _resolveString(target, const [
      'title',
      'name',
      'display_title',
    ]);
    if (id.isEmpty || title.isEmpty) {
      return null;
    }

    final year = _resolveYear(target, item);
    final posterUrl = _resolvePosterUrl(target, item);
    final normalizedPosterUrl = _normalizePosterUrl(posterUrl);
    final ratingLabel = _resolveRating(target, item);
    final description = _resolveString(
      target,
      const ['description', 'desc', 'intro', 'card_subtitle', 'subtitle'],
    );
    final backupDescription = _resolveString(
      item,
      const ['description', 'brief', 'comment'],
    );
    final durationLabel = _resolveDurationLabel(target, item);
    final genres =
        _resolveNames(target, item, const ['genres', 'genre', 'type']);
    final directors = _resolveNames(
      target,
      item,
      const ['directors', 'director', 'director_names'],
    );
    final actors = _resolveNames(
      target,
      item,
      const ['actors', 'actor', 'casts', 'cast'],
    );
    final note = [
      ...noteFallback,
      description,
      backupDescription,
      if (directors.isNotEmpty) '导演：${directors.take(3).join(' / ')}',
      if (actors.isNotEmpty) '演员：${actors.take(4).join(' / ')}',
      if (genres.isNotEmpty) genres.join(' / '),
      ratingLabel,
      ...secondaryNoteFallback,
    ].firstWhere((value) => value.trim().isNotEmpty, orElse: () => '');
    final subjectType = _resolveString(target, const ['type', 'type_name']);

    debugLogDoubanCover(
      'api-map',
      title: title,
      doubanId: id,
      url: normalizedPosterUrl,
      detail: _debugPosterCandidates(target, item),
    );

    return DoubanEntry(
      id: id,
      title: title,
      year: year,
      posterUrl: normalizedPosterUrl,
      note: note,
      durationLabel: durationLabel,
      genres: genres,
      directors: directors,
      actors: actors,
      sourceUrl: 'https://movie.douban.com/subject/$id/',
      ratingLabel: ratingLabel,
      subjectType: subjectType,
    );
  }

  DoubanCarouselEntry? _mapCarouselEntry(Map<String, dynamic> item) {
    final id = '${item['id'] ?? ''}'.trim();
    final title = '${item['title'] ?? ''}'.trim();
    if (id.isEmpty || title.isEmpty) {
      return null;
    }

    final backdropPath = '${item['backdropPath'] ?? ''}'.trim();
    final posterPath = '${item['posterPath'] ?? ''}'.trim();
    final releaseDate = '${item['releaseDate'] ?? ''}'.trim();
    final year = _parseYearString(releaseDate);
    final rating = '${item['rating'] ?? ''}'.trim();
    final mediaType = '${item['mediaType'] ?? ''}'.trim();

    return DoubanCarouselEntry(
      id: id,
      title: title,
      imageUrl: backdropPath.isEmpty
          ? ''
          : 'https://image.tmdb.org/t/p/w780$backdropPath',
      posterUrl: posterPath.isEmpty
          ? ''
          : 'https://image.tmdb.org/t/p/w500$posterPath',
      overview: '${item['description'] ?? ''}'.trim(),
      year: year,
      ratingLabel: rating.isEmpty
          ? ''
          : '豆瓣 ${double.tryParse(rating)?.toStringAsFixed(1) ?? rating}',
      mediaType: mediaType,
    );
  }

  Map<String, dynamic> _resolveSubjectMap(Map<String, dynamic> item) {
    final nestedTarget = item['target'];
    if (nestedTarget is Map) {
      return Map<String, dynamic>.from(nestedTarget);
    }
    final subject = item['subject'];
    if (subject is Map) {
      return Map<String, dynamic>.from(subject);
    }
    return item;
  }

  String _resolveId(
      Map<String, dynamic> target, Map<String, dynamic> fallback) {
    // 片单等列表外层常用 target_id 表示条目；id 有时是列表行 id，需优先 target_id。
    for (final value in [
      fallback['target_id'],
      target['target_id'],
      target['id'],
      fallback['id'],
    ]) {
      final text = '$value'.trim();
      if (text.isNotEmpty && text != 'null') {
        return text;
      }
    }
    return '';
  }

  static String _normalizePosterUrl(String url) {
    final t = url.trim();
    if (t.isEmpty || t == 'null') {
      return '';
    }
    if (t.startsWith('//')) {
      return 'https:$t';
    }
    return t;
  }

  String _resolvePosterUrl(
    Map<String, dynamic> target,
    Map<String, dynamic> fallback,
  ) {
    final picText = _resolveImageValue(target['pic']);
    if (picText.isNotEmpty && picText != 'null') {
      return picText;
    }
    final coverText = _resolveImageValue(target['cover']);
    if (coverText.isNotEmpty && coverText != 'null') {
      return coverText;
    }

    for (final map in [target, fallback]) {
      for (final key in [
        'cover_url',
        'poster',
        'poster_url',
        'image',
        'pic',
        'thumbnail',
      ]) {
        final text = _resolveImageValue(map[key]);
        if (text.isNotEmpty && text != 'null') {
          return text;
        }
      }
    }
    return '';
  }

  String _resolveImageValue(Object? raw) {
    if (raw is Map) {
      for (final key in ['large', 'normal', 'url', 'medium', 'small']) {
        final text = '${raw[key] ?? ''}'.trim();
        if (text.isNotEmpty && text != 'null') {
          return text;
        }
      }
    }
    return '$raw'.trim();
  }

  String _debugPosterCandidates(
    Map<String, dynamic> target,
    Map<String, dynamic> fallback,
  ) {
    final segments = <String>[];
    void addSegment(String label, Object? raw) {
      final value = _resolveImageValue(raw).trim();
      if (value.isEmpty || value == 'null') {
        return;
      }
      final shortened =
          value.length > 96 ? '${value.substring(0, 96)}...' : value;
      segments.add('$label=$shortened');
    }

    addSegment('target.pic', target['pic']);
    addSegment('target.cover', target['cover']);
    addSegment('target.cover_url', target['cover_url']);
    addSegment('target.poster', target['poster']);
    addSegment('fallback.pic', fallback['pic']);
    addSegment('fallback.cover', fallback['cover']);
    addSegment('fallback.cover_url', fallback['cover_url']);
    addSegment('fallback.poster', fallback['poster']);

    if (segments.isEmpty) {
      return 'posterCandidates=empty';
    }
    return segments.join(' ; ');
  }

  int _resolveYear(Map<String, dynamic> target, Map<String, dynamic> fallback) {
    for (final value in [
      target['year'],
      target['release_date'],
      target['releaseDate'],
      fallback['create_time'],
      fallback['release_date'],
    ]) {
      final year = _parseYear(value);
      if (year > 0) {
        return year;
      }
    }
    return 0;
  }

  String _resolveRating(
    Map<String, dynamic> target,
    Map<String, dynamic> fallback,
  ) {
    for (final map in [target, fallback]) {
      final rating = map['rating'];
      if (rating is Map) {
        final value = rating['value'] ?? rating['star_count'] ?? '';
        final text = '$value'.trim();
        if (text.isNotEmpty && text != 'null' && text != '0') {
          final parsed = double.tryParse(text);
          return parsed == null ? text : '豆瓣 ${parsed.toStringAsFixed(1)}';
        }
      }
      final text = '${map['rating'] ?? ''}'.trim();
      if (text.isNotEmpty && text != 'null' && text != '0') {
        final parsed = double.tryParse(text);
        return parsed == null ? text : '豆瓣 ${parsed.toStringAsFixed(1)}';
      }
    }
    return '';
  }

  String _resolveString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final raw = map[key];
      if (raw is List) {
        final names = raw
            .map((item) => _extractName(item))
            .where((item) => item.isNotEmpty)
            .toList();
        if (names.isNotEmpty) {
          return names.join(' / ');
        }
      }
      final text = '$raw'.trim();
      if (text.isNotEmpty && text != 'null') {
        return text;
      }
    }
    return '';
  }

  List<String> _resolveNames(
    Map<String, dynamic> target,
    Map<String, dynamic> fallback,
    List<String> keys,
  ) {
    for (final map in [target, fallback]) {
      for (final key in keys) {
        final raw = map[key];
        final names = _extractNames(raw);
        if (names.isNotEmpty) {
          return names;
        }
      }
    }
    return const [];
  }

  List<String> _extractNames(Object? raw) {
    if (raw is List) {
      return raw
          .map(_extractName)
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList();
    }
    final single = _extractName(raw);
    return single.isEmpty ? const [] : [single];
  }

  String _extractName(Object? raw) {
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      for (final key in ['name', 'title']) {
        final text = '${map[key] ?? ''}'.trim();
        if (text.isNotEmpty && text != 'null') {
          return text;
        }
      }
    }
    final text = '$raw'.trim();
    if (text.isEmpty || text == 'null') {
      return '';
    }
    return text;
  }

  String _resolveDurationLabel(
    Map<String, dynamic> target,
    Map<String, dynamic> fallback,
  ) {
    for (final map in [target, fallback]) {
      final duration = map['durations'];
      if (duration is List && duration.isNotEmpty) {
        final text = _extractName(duration.first);
        if (text.isNotEmpty) {
          return text;
        }
      }
      for (final key in ['duration', 'card_subtitle']) {
        final text = '${map[key] ?? ''}'.trim();
        if (text.isNotEmpty &&
            text != 'null' &&
            RegExp(r'(\d+\s*分钟|\d+h|\d+m|\d+\s*min)', caseSensitive: false)
                .hasMatch(text)) {
          return text;
        }
      }
    }
    return '';
  }

  int _parseYear(dynamic value) {
    if (value is int) {
      return value;
    }
    return _parseYearString('$value');
  }

  int _parseYearString(String value) {
    final match = RegExp(r'(\d{4})').firstMatch(value);
    if (match == null) {
      return 0;
    }
    return int.tryParse(match.group(1) ?? '') ?? 0;
  }

  String _extractCookieValue(String cookie, String key) {
    final match = RegExp('$key=([^;]+)').firstMatch(cookie);
    return match?.group(1)?.trim() ?? '';
  }
}

class DoubanApiException implements Exception {
  const DoubanApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
