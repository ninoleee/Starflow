import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:starflow/core/utils/subtitle_search_trace.dart';
import 'package:starflow/features/playback/domain/online_subtitle_structured_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';

const String _defaultOpenSubtitlesApiKey = String.fromEnvironment(
  'STARFLOW_OPENSUBTITLES_API_KEY',
);
const String _assrtRateLimitErrorMessage = 'ASSRT API 请求过于频繁，请稍后再试';

abstract class OnlineSubtitleStructuredProvider {
  OnlineSubtitleSource get source;

  String get providerLabel;

  bool get isConfigured;

  Future<List<ProviderSubtitleHit>> search(
    OnlineSubtitleSearchRequest request,
  );
}

class AssrtProviderConfig {
  const AssrtProviderConfig({
    this.enabled = false,
    this.token = '',
    this.baseUrl = 'https://api.assrt.net',
    this.userAgent = 'Starflow/1.0',
    this.searchCount = 5,
    this.maxDetailRequestsPerQuery = 4,
  });

  final bool enabled;
  final String token;
  final String baseUrl;
  final String userAgent;
  final int searchCount;
  final int maxDetailRequestsPerQuery;

  bool get isConfigured => enabled && token.trim().isNotEmpty;
}

class OpenSubtitlesProviderConfig {
  const OpenSubtitlesProviderConfig({
    this.enabled = false,
    this.apiKey = _defaultOpenSubtitlesApiKey,
    this.username = '',
    this.password = '',
    this.userAgent = 'Starflow/1.0',
    this.baseUrl = 'https://api.opensubtitles.com/api/v1',
  });

  final bool enabled;
  final String apiKey;
  final String username;
  final String password;
  final String userAgent;
  final String baseUrl;

  bool get isConfigured =>
      enabled &&
      apiKey.trim().isNotEmpty &&
      username.trim().isNotEmpty &&
      password.trim().isNotEmpty;
}

class SubdlProviderConfig {
  const SubdlProviderConfig({
    this.enabled = false,
    this.apiKey = '',
    this.baseUrl = 'https://api.subdl.com/api/v1/subtitles',
  });

  final bool enabled;
  final String apiKey;
  final String baseUrl;

  bool get isConfigured => enabled && apiKey.trim().isNotEmpty;
}

class AssrtStructuredProvider implements OnlineSubtitleStructuredProvider {
  AssrtStructuredProvider(
    this._client, {
    this.config = const AssrtProviderConfig(),
  });

  final http.Client _client;
  final AssrtProviderConfig config;

  @override
  OnlineSubtitleSource get source => OnlineSubtitleSource.assrt;

  @override
  String get providerLabel => 'ASSRT';

  @override
  bool get isConfigured => config.isConfigured;

  @override
  Future<List<ProviderSubtitleHit>> search(
    OnlineSubtitleSearchRequest request,
  ) async {
    if (!isConfigured) {
      subtitleSearchTrace(
        'repository.structured.provider.skip-unconfigured',
        fields: {'source': source.name},
      );
      return const [];
    }

    final queryPlan = _buildAssrtQueryPlan(request);
    if (queryPlan.isEmpty) {
      return const [];
    }

    for (final query in queryPlan) {
      final response = await _client.get(
        _buildAssrtSearchUri(query),
        headers: _assrtHeaders(),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 509) {
          subtitleSearchTrace(
            'repository.structured.provider.rate-limited',
            fields: {
              'source': source.name,
              'status': response.statusCode,
              'queryKind': query.kind,
              'query': query.query,
            },
          );
          throw StateError(_assrtRateLimitErrorMessage);
        }
        subtitleSearchTrace(
          'repository.structured.provider.request-failed',
          fields: {
            'source': source.name,
            'status': response.statusCode,
            'queryKind': query.kind,
            'query': query.query,
          },
        );
        continue;
      }

      final candidates = _parseAssrtSearchResponse(response.body)
          .take(config.maxDetailRequestsPerQuery)
          .toList(growable: false);
      if (candidates.isEmpty) {
        continue;
      }

      final hits = <ProviderSubtitleHit>[];
      for (final candidate in candidates) {
        final hit = await _loadAssrtDetail(candidate, request: request);
        if (hit != null) {
          hits.add(hit);
        }
      }
      if (hits.isNotEmpty) {
        return _dedupeHits(hits);
      }
    }
    return const [];
  }

  Map<String, String> _assrtHeaders() {
    return {
      'Accept': 'application/json',
      'Authorization': 'Bearer ${config.token.trim()}',
      'User-Agent': config.userAgent.trim(),
    };
  }

  Uri _buildAssrtSearchUri(_AssrtStructuredQuery query) {
    return Uri.parse('${config.baseUrl}/v1/sub/search').replace(
      queryParameters: {
        'q': query.query,
        'cnt': '${config.searchCount.clamp(1, 20)}',
        'pos': '0',
        'filelist': '1',
        if (query.isFileQuery) 'is_file': '1',
        if (query.noMuxer) 'no_muxer': '1',
      },
    );
  }

  List<_AssrtStructuredQuery> _buildAssrtQueryPlan(
    OnlineSubtitleSearchRequest request,
  ) {
    final queries = <_AssrtStructuredQuery>[];
    final seen = <String>{};
    final broadQueries = <_AssrtStructuredQuery>[];
    final episodeQueries = <_AssrtStructuredQuery>[];

    void addQuery(
      String rawQuery, {
      required String kind,
      bool isFileQuery = false,
      bool noMuxer = false,
    }) {
      final normalized = rawQuery.trim();
      if (normalized.length < 3) {
        return;
      }
      final key = '${normalized.toLowerCase()}|$isFileQuery|$noMuxer';
      if (!seen.add(key)) {
        return;
      }
      final next = _AssrtStructuredQuery(
        query: normalized,
        kind: kind,
        isFileQuery: isFileQuery,
        noMuxer: noMuxer,
      );
      if (kind == 'episode') {
        episodeQueries.add(next);
      } else {
        broadQueries.add(next);
      }
    }

    final fileBaseName = _normalizedFileBaseName(request.normalizedFilePath);
    if (fileBaseName.isNotEmpty) {
      addQuery(
        fileBaseName,
        kind: 'fileName',
        isFileQuery: true,
        noMuxer: true,
      );
    }

    for (final candidate in request.buildQueryPlan()) {
      switch (candidate.kind) {
        case StructuredSubtitleQueryKind.hash:
        case StructuredSubtitleQueryKind.imdbId:
        case StructuredSubtitleQueryKind.tmdbId:
          continue;
        case StructuredSubtitleQueryKind.episode:
          addQuery(candidate.query, kind: 'episode');
          break;
        case StructuredSubtitleQueryKind.titleYear:
          addQuery(candidate.query, kind: 'titleYear');
          break;
        case StructuredSubtitleQueryKind.titleOnly:
          addQuery(candidate.query, kind: 'titleOnly');
          break;
      }
    }

    queries
      ..addAll(broadQueries)
      ..addAll(episodeQueries);
    return queries;
  }

  Future<ProviderSubtitleHit?> _loadAssrtDetail(
    _AssrtSearchCandidate item, {
    required OnlineSubtitleSearchRequest request,
  }) async {
    final response = await _client.get(
      Uri.parse('${config.baseUrl}/v1/sub/detail').replace(
        queryParameters: {'id': '${item.id}'},
      ),
      headers: _assrtHeaders(),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 509) {
        subtitleSearchTrace(
          'repository.structured.provider.rate-limited',
          fields: {
            'source': source.name,
            'status': response.statusCode,
            'detailId': item.id,
          },
        );
        throw StateError(_assrtRateLimitErrorMessage);
      }
      subtitleSearchTrace(
        'repository.structured.provider.request-failed',
        fields: {
          'source': source.name,
          'status': response.statusCode,
          'detailId': item.id,
        },
      );
      return null;
    }

    final root = _tryDecodeJsonObject(response.body);
    if (root == null || !_assrtSuccess(root)) {
      return null;
    }

    final detail = _resolveAssrtDetailPayload(root);
    if (detail == null) {
      return null;
    }

    final version = _firstNonEmpty(
      _readString(detail['videoname']),
      item.videoName,
      _readString(detail['filename']),
    );
    final title = _firstNonEmpty(
      _readString(detail['title']),
      _readString(detail['native_name']),
      item.nativeName,
      item.videoName,
      version,
    );
    final fileChoice = _selectAssrtDownloadChoice(
      detail,
      version: version,
      request: request,
    );
    if (fileChoice == null) {
      return null;
    }

    final lang = _readMap(detail['lang']);
    final producer = _readMap(detail['producer']);
    final voteScore = _readNum(detail['vote_score'])?.toDouble() ?? 0;
    final ratingLabel = voteScore > 0
        ? '评分 ${voteScore.toStringAsFixed(voteScore.truncateToDouble() == voteScore ? 0 : 1)}'
        : '';

    return ProviderSubtitleHit(
      id: '${OnlineSubtitleSource.assrt.name}:${item.id}',
      source: OnlineSubtitleSource.assrt,
      providerLabel: providerLabel,
      title: title,
      downloadUrl: fileChoice.url,
      packageName: fileChoice.packageName,
      packageKind: fileChoice.packageKind,
      detailUrl: Uri.parse('${config.baseUrl}/v1/sub/detail')
          .replace(queryParameters: {'id': '${item.id}'}).toString(),
      version: version,
      formatLabel: _firstNonEmpty(
        _readString(detail['subtype']),
        _extensionLabel(fileChoice.packageName),
      ),
      languageLabel: _readString(lang['desc']),
      sourceLabel: _firstNonEmpty(
        _readString(detail['release_site']),
        _readString(producer['source']),
        _readString(producer['name']),
      ),
      publishDateLabel: _readString(detail['upload_time']),
      ratingLabel: ratingLabel,
      downloadCount:
          _readNum(detail['down_count'])?.toInt() ?? item.downloadCount,
      seasonNumber: request.seasonNumber,
      episodeNumber: request.episodeNumber,
      raw: {
        'assrt_id': item.id,
        'detail': detail,
      },
    );
  }

  List<_AssrtSearchCandidate> _parseAssrtSearchResponse(String body) {
    final root = _tryDecodeJsonObject(body);
    if (root == null || !_assrtSuccess(root)) {
      return const [];
    }
    final payload = _readMap(root['sub']);
    final items = _readList(payload['subs']);
    return items
        .map(_readMap)
        .where((item) => item.isNotEmpty)
        .map(_parseAssrtSearchCandidate)
        .whereType<_AssrtSearchCandidate>()
        .toList(growable: false);
  }

  _AssrtSearchCandidate? _parseAssrtSearchCandidate(Map<String, Object?> json) {
    final id = _readNum(json['id'])?.toInt() ?? 0;
    if (id <= 0) {
      return null;
    }
    return _AssrtSearchCandidate(
      id: id,
      nativeName: _readString(json['native_name']),
      videoName: _readString(json['videoname']),
      downloadCount: _readNum(json['down_count'])?.toInt() ?? 0,
    );
  }
}

class OpenSubtitlesStructuredProvider
    implements OnlineSubtitleStructuredProvider {
  OpenSubtitlesStructuredProvider(
    this._client, {
    this.config = const OpenSubtitlesProviderConfig(),
  });

  final http.Client _client;
  final OpenSubtitlesProviderConfig config;

  @override
  OnlineSubtitleSource get source => OnlineSubtitleSource.opensubtitles;

  @override
  String get providerLabel => 'OpenSubtitles';

  @override
  bool get isConfigured => config.isConfigured;

  @override
  Future<List<ProviderSubtitleHit>> search(
    OnlineSubtitleSearchRequest request,
  ) async {
    if (!isConfigured) {
      subtitleSearchTrace(
        'repository.structured.provider.skip-unconfigured',
        fields: {'source': source.name},
      );
      return const [];
    }

    final searchPlan = request.buildQueryPlan();
    if (searchPlan.isEmpty) {
      return const [];
    }

    final session = await _login();
    if (!session.isReady) {
      return const [];
    }

    final results = <ProviderSubtitleHit>[];
    for (final query in searchPlan) {
      final response = await _client.get(
        _buildSearchUri(request, query, session: session),
        headers: {
          'Api-Key': config.apiKey.trim(),
          'Authorization': 'Bearer ${session.token}',
          'User-Agent': config.userAgent.trim(),
          'Accept': 'application/json',
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        subtitleSearchTrace(
          'repository.structured.provider.request-failed',
          fields: {
            'source': source.name,
            'status': response.statusCode,
            'queryKind': query.kind.name,
            'query': query.query,
          },
        );
        continue;
      }
      final hydratedHits = <ProviderSubtitleHit>[];
      for (final hit in _parseOpenSubtitlesSearchResponse(response.body)) {
        hydratedHits.add(await _hydrateOpenSubtitlesHit(hit, session));
      }
      results.addAll(hydratedHits);
      if (results.isNotEmpty) {
        break;
      }
    }
    return _dedupeHits(results);
  }

  Future<_OpenSubtitlesSession> _login() async {
    final response = await _client.post(
      Uri.parse('${config.baseUrl}/login'),
      headers: {
        'Api-Key': config.apiKey.trim(),
        'User-Agent': config.userAgent.trim(),
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'username': config.username.trim(),
        'password': config.password.trim(),
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      subtitleSearchTrace(
        'repository.structured.provider.auth-failed',
        fields: {
          'source': source.name,
          'status': response.statusCode,
        },
      );
      return const _OpenSubtitlesSession.empty();
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return _OpenSubtitlesSession(
      token: json['token'] as String? ?? '',
      baseUrl: (json['base_url'] as String?)?.trim().isNotEmpty == true
          ? (json['base_url'] as String).trim()
          : config.baseUrl,
    );
  }

  Uri _buildSearchUri(
    OnlineSubtitleSearchRequest request,
    StructuredSubtitleQuery query, {
    required _OpenSubtitlesSession session,
  }) {
    final parameters = <String, String>{
      'order_by': 'download_count',
      'order_direction': 'desc',
      if (request.normalizedLanguages.isNotEmpty)
        'languages': request.normalizedLanguages.join(','),
      if (query.kind == StructuredSubtitleQueryKind.hash)
        'moviehash': query.query,
      if (query.kind == StructuredSubtitleQueryKind.hash &&
          request.fileSizeBytes != null)
        'moviebytesize': '${request.fileSizeBytes!}',
      if (query.kind == StructuredSubtitleQueryKind.imdbId)
        'imdb_id': query.query,
      if (query.kind == StructuredSubtitleQueryKind.tmdbId)
        'tmdb_id': query.query,
      if (query.kind != StructuredSubtitleQueryKind.hash &&
          query.kind != StructuredSubtitleQueryKind.imdbId &&
          query.kind != StructuredSubtitleQueryKind.tmdbId)
        'query': query.query,
      if (request.seasonNumber != null)
        'season_number': '${request.seasonNumber!}',
      if (request.episodeNumber != null)
        'episode_number': '${request.episodeNumber!}',
      if ((request.year ?? 0) > 0) 'year': '${request.year!}',
    };
    return Uri.parse('${session.baseUrl}/subtitles')
        .replace(queryParameters: parameters);
  }

  Future<ProviderSubtitleHit> _hydrateOpenSubtitlesHit(
    ProviderSubtitleHit hit,
    _OpenSubtitlesSession session,
  ) async {
    if (!session.isReady || hit.downloadUrl.trim().isNotEmpty) {
      return hit;
    }
    final fileId = _extractOpenSubtitlesFileId(hit);
    if (fileId <= 0) {
      return hit;
    }
    try {
      final response = await _client.post(
        Uri.parse('${session.baseUrl}/download'),
        headers: {
          'Api-Key': config.apiKey.trim(),
          'Authorization': 'Bearer ${session.token}',
          'User-Agent': config.userAgent.trim(),
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(<String, Object>{'file_id': fileId}),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return hit;
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final link = (json['link'] as String?)?.trim() ??
          (json['url'] as String?)?.trim() ??
          '';
      if (link.isEmpty) {
        return hit;
      }
      return hit.copyWith(downloadUrl: link);
    } catch (_) {
      return hit;
    }
  }
}

class SubdlStructuredProvider implements OnlineSubtitleStructuredProvider {
  SubdlStructuredProvider(
    this._client, {
    this.config = const SubdlProviderConfig(),
  });

  final http.Client _client;
  final SubdlProviderConfig config;

  @override
  OnlineSubtitleSource get source => OnlineSubtitleSource.subdl;

  @override
  String get providerLabel => 'SubDL';

  @override
  bool get isConfigured => config.isConfigured;

  @override
  Future<List<ProviderSubtitleHit>> search(
    OnlineSubtitleSearchRequest request,
  ) async {
    if (!isConfigured) {
      subtitleSearchTrace(
        'repository.structured.provider.skip-unconfigured',
        fields: {'source': source.name},
      );
      return const [];
    }

    final results = <ProviderSubtitleHit>[];
    for (final query in request.buildQueryPlan()) {
      final response = await _client.get(
        Uri.parse(config.baseUrl).replace(
          queryParameters: {
            'api_key': config.apiKey.trim(),
            if (query.query.isNotEmpty) 'film_name': query.query,
            if (request.normalizedImdbId.isNotEmpty)
              'imdb_id': request.normalizedImdbId,
            if (request.normalizedTmdbId.isNotEmpty)
              'tmdb_id': request.normalizedTmdbId,
            if (request.seasonNumber != null)
              'season_number': '${request.seasonNumber!}',
            if (request.episodeNumber != null)
              'episode_number': '${request.episodeNumber!}',
            if ((request.year ?? 0) > 0) 'year': '${request.year!}',
            if (request.normalizedLanguages.isNotEmpty)
              'languages': request.normalizedLanguages.join(','),
          },
        ),
        headers: const {'Accept': 'application/json'},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        subtitleSearchTrace(
          'repository.structured.provider.request-failed',
          fields: {
            'source': source.name,
            'status': response.statusCode,
            'queryKind': query.kind.name,
            'query': query.query,
          },
        );
        continue;
      }
      results.addAll(_parseSubdlSearchResponse(response.body));
      if (results.isNotEmpty) {
        break;
      }
    }
    return _dedupeHits(results);
  }
}

List<ProviderSubtitleHit> _parseOpenSubtitlesSearchResponse(String body) {
  final root = jsonDecode(body) as Map<String, dynamic>;
  final items = (root['data'] as List<dynamic>? ?? const []);
  return items
      .map((item) =>
          _parseOpenSubtitlesHit(Map<String, dynamic>.from(item as Map)))
      .whereType<ProviderSubtitleHit>()
      .toList(growable: false);
}

ProviderSubtitleHit? _parseOpenSubtitlesHit(Map<String, dynamic> json) {
  final attributes =
      Map<String, dynamic>.from(json['attributes'] as Map? ?? const {});
  final featureDetails = Map<String, dynamic>.from(
    attributes['feature_details'] as Map? ?? const {},
  );
  final files = (attributes['files'] as List<dynamic>? ?? const [])
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList(growable: false);
  final firstFile = files.isEmpty ? const <String, dynamic>{} : files.first;
  final fileName = firstFile['file_name'] as String? ?? '';
  final packageName = fileName.trim().isEmpty ? 'subtitle.zip' : fileName;
  final detailUrl = attributes['url'] as String? ?? '';
  final fileId = (firstFile['file_id'] as num?)?.toInt() ?? 0;
  return ProviderSubtitleHit(
    id: '${OnlineSubtitleSource.opensubtitles.name}:${json['id'] ?? ''}',
    source: OnlineSubtitleSource.opensubtitles,
    providerLabel: 'OpenSubtitles',
    title: featureDetails['movie_name'] as String? ??
        attributes['release'] as String? ??
        packageName,
    downloadUrl: '',
    packageName: packageName,
    packageKind: _resolvePackageKind(packageName),
    detailUrl: detailUrl,
    version: attributes['release'] as String? ?? '',
    formatLabel: attributes['format'] as String? ?? '',
    languageLabel: attributes['language'] as String? ?? '',
    publishDateLabel: attributes['upload_date'] as String? ?? '',
    downloadCount: (attributes['download_count'] as num?)?.toInt() ?? 0,
    imdbId: '${featureDetails['imdb_id'] ?? ''}',
    tmdbId: '${featureDetails['tmdb_id'] ?? ''}',
    seasonNumber: (featureDetails['season_number'] as num?)?.toInt(),
    episodeNumber: (featureDetails['episode_number'] as num?)?.toInt(),
    releaseNames: [
      if ((featureDetails['movie_name'] as String? ?? '').trim().isNotEmpty)
        featureDetails['movie_name'] as String,
    ],
    hearingImpaired: attributes['hearing_impaired'] as bool? ?? false,
    raw: {
      ...json,
      'file_id': fileId,
      'file_name': fileName,
    },
  );
}

List<ProviderSubtitleHit> _parseSubdlSearchResponse(String body) {
  final root = jsonDecode(body) as Map<String, dynamic>;
  final items = (root['subtitles'] as List<dynamic>? ?? const []);
  return items
      .map((item) => _parseSubdlHit(Map<String, dynamic>.from(item as Map)))
      .whereType<ProviderSubtitleHit>()
      .toList(growable: false);
}

ProviderSubtitleHit? _parseSubdlHit(Map<String, dynamic> json) {
  final url = json['url'] as String? ?? json['download_url'] as String? ?? '';
  final fileName = json['name'] as String? ??
      json['release_name'] as String? ??
      'subtitle.zip';
  return ProviderSubtitleHit(
    id: '${OnlineSubtitleSource.subdl.name}:${json['sd_id'] ?? json['id'] ?? fileName}',
    source: OnlineSubtitleSource.subdl,
    providerLabel: 'SubDL',
    title: json['name'] as String? ?? fileName,
    downloadUrl: url,
    packageName: fileName,
    packageKind: _resolvePackageKind(fileName),
    detailUrl: json['url'] as String? ?? '',
    version: json['release_name'] as String? ?? '',
    formatLabel: json['format'] as String? ?? '',
    languageLabel: json['language'] as String? ?? '',
    publishDateLabel: json['upload_date'] as String? ?? '',
    downloadCount: (json['downloads'] as num?)?.toInt() ?? 0,
    imdbId: json['imdb_id'] as String? ?? '',
    tmdbId: '${json['tmdb_id'] ?? ''}',
    seasonNumber: (json['season_number'] as num?)?.toInt(),
    episodeNumber: (json['episode_number'] as num?)?.toInt(),
    releaseNames: (json['releases'] as List<dynamic>? ?? const [])
        .map((item) => '$item')
        .where((item) => item.trim().isNotEmpty)
        .toList(growable: false),
    hearingImpaired: json['hi'] as bool? ?? false,
    raw: json,
  );
}

List<ProviderSubtitleHit> _dedupeHits(List<ProviderSubtitleHit> hits) {
  final deduped = <String, ProviderSubtitleHit>{};
  for (final hit in hits) {
    final key =
        '${hit.source.name}|${hit.downloadUrl}|${hit.packageName}|${hit.languageLabel}';
    deduped.putIfAbsent(key, () => hit);
  }
  return deduped.values.toList(growable: false);
}

int _extractOpenSubtitlesFileId(ProviderSubtitleHit hit) {
  final rawValue = hit.raw['file_id'];
  if (rawValue is num) {
    return rawValue.toInt();
  }
  if (rawValue is String) {
    return int.tryParse(rawValue.trim()) ?? 0;
  }
  return 0;
}

_AssrtDownloadChoice? _selectAssrtDownloadChoice(
  Map<String, Object?> detail, {
  required String version,
  required OnlineSubtitleSearchRequest request,
}) {
  final fileEntries = _readList(detail['filelist'])
      .map(_readMap)
      .where((item) => item.isNotEmpty)
      .map(
        (item) => _AssrtDownloadChoice(
          url: _readString(item['url']),
          packageName: _readString(item['f']),
          packageKind: _resolvePackageKind(_readString(item['f'])),
        ),
      )
      .where((item) => item.url.isNotEmpty && item.packageName.isNotEmpty)
      .toList(growable: false);
  if (fileEntries.isNotEmpty) {
    final sorted = fileEntries.toList()
      ..sort(
        (left, right) => _assrtFileScore(
          right.packageName,
          version: version,
          request: request,
        ).compareTo(
          _assrtFileScore(
            left.packageName,
            version: version,
            request: request,
          ),
        ),
      );
    return sorted.first;
  }

  final packageUrl = _readString(detail['url']);
  final packageName = _firstNonEmpty(
    _readString(detail['filename']),
    'assrt-${_readNum(detail['id'])?.toInt() ?? 0}.bin',
  );
  if (packageUrl.isEmpty) {
    return null;
  }
  return _AssrtDownloadChoice(
    url: packageUrl,
    packageName: packageName,
    packageKind: _resolvePackageKind(packageName),
  );
}

int _assrtFileScore(
  String fileName, {
  required String version,
  required OnlineSubtitleSearchRequest request,
}) {
  final normalized = _normalizeToken(fileName);
  final normalizedVersion = _normalizeToken(version);
  var score = 0;
  score += switch (_resolvePackageKind(fileName)) {
    SubtitlePackageKind.subtitleFile => 600,
    SubtitlePackageKind.zipArchive => 420,
    SubtitlePackageKind.rarArchive => 320,
    SubtitlePackageKind.unsupported => 0,
  };
  if (normalizedVersion.isNotEmpty && normalized.contains(normalizedVersion)) {
    score += 140;
  }
  score += scoreSubtitleEpisodeMatch(
    fileName,
    seasonNumber: request.seasonNumber,
    episodeNumber: request.episodeNumber,
  );
  for (final token in const ['中英', '双语', '简中', '繁中', 'chs', 'cht']) {
    if (normalized.contains(_normalizeToken(token))) {
      score += 32;
    }
  }
  return score - fileName.length ~/ 18;
}

String _normalizedFileBaseName(String filePath) {
  return cleanSubtitleSearchFileName(filePath);
}

String _extensionLabel(String fileName) {
  final extension = p.extension(fileName).trim().toLowerCase();
  if (extension.isEmpty) {
    return '';
  }
  return extension.substring(1).toUpperCase();
}

SubtitlePackageKind _resolvePackageKind(String packageName) {
  final normalized = packageName.trim().toLowerCase();
  if (normalized.endsWith('.srt') ||
      normalized.endsWith('.ass') ||
      normalized.endsWith('.ssa') ||
      normalized.endsWith('.vtt')) {
    return SubtitlePackageKind.subtitleFile;
  }
  if (normalized.endsWith('.zip')) {
    return SubtitlePackageKind.zipArchive;
  }
  if (normalized.endsWith('.rar')) {
    return SubtitlePackageKind.rarArchive;
  }
  return SubtitlePackageKind.unsupported;
}

bool _assrtSuccess(Map<String, Object?> root) {
  final status = _readNum(root['status'])?.toInt();
  return status == null || status == 0;
}

Map<String, Object?>? _resolveAssrtDetailPayload(Map<String, Object?> root) {
  final sub = _readMap(root['sub']);
  final nestedSubs = _readList(sub['subs']);
  if (nestedSubs.isNotEmpty) {
    final detail = _readMap(nestedSubs.first);
    if (detail.isNotEmpty) {
      return detail;
    }
  }
  if (sub.isNotEmpty) {
    return sub;
  }
  final subs = _readList(root['subs']);
  if (subs.isEmpty) {
    return null;
  }
  final detail = _readMap(subs.first);
  return detail.isEmpty ? null : detail;
}

Map<String, Object?>? _tryDecodeJsonObject(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      return decoded.map(
        (key, value) => MapEntry('$key', value),
      );
    }
  } catch (_) {
    return null;
  }
  return null;
}

Map<String, Object?> _readMap(Object? value) {
  if (value is Map) {
    return value.map((key, item) => MapEntry('$key', item));
  }
  return const <String, Object?>{};
}

List<Object?> _readList(Object? value) {
  if (value is List) {
    return value.cast<Object?>();
  }
  return const <Object?>[];
}

String _readString(Object? value) {
  return switch (value) {
    null => '',
    String _ => value.trim(),
    _ => '$value'.trim(),
  };
}

num? _readNum(Object? value) {
  if (value is num) {
    return value;
  }
  if (value is String) {
    return num.tryParse(value.trim());
  }
  return null;
}

String _firstNonEmpty(String first,
    [String second = '',
    String third = '',
    String fourth = '',
    String fifth = '']) {
  for (final candidate in [first, second, third, fourth, fifth]) {
    if (candidate.trim().isNotEmpty) {
      return candidate.trim();
    }
  }
  return '';
}

String _normalizeToken(String value) {
  return value.trim().toLowerCase().replaceAll(
        RegExp(r'[\s\-_.,:;!?/\\|()\[\]{}<>《》【】"“”·]+'),
        '',
      );
}

class _AssrtStructuredQuery {
  const _AssrtStructuredQuery({
    required this.query,
    required this.kind,
    required this.isFileQuery,
    required this.noMuxer,
  });

  final String query;
  final String kind;
  final bool isFileQuery;
  final bool noMuxer;
}

class _AssrtSearchCandidate {
  const _AssrtSearchCandidate({
    required this.id,
    required this.nativeName,
    required this.videoName,
    required this.downloadCount,
  });

  final int id;
  final String nativeName;
  final String videoName;
  final int downloadCount;
}

class _AssrtDownloadChoice {
  const _AssrtDownloadChoice({
    required this.url,
    required this.packageName,
    required this.packageKind,
  });

  final String url;
  final String packageName;
  final SubtitlePackageKind packageKind;
}

class _OpenSubtitlesSession {
  const _OpenSubtitlesSession({
    required this.token,
    required this.baseUrl,
  });

  const _OpenSubtitlesSession.empty()
      : token = '',
        baseUrl = '';

  final String token;
  final String baseUrl;

  bool get isReady => token.trim().isNotEmpty && baseUrl.trim().isNotEmpty;
}
