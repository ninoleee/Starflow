import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:starflow/core/utils/subtitle_search_trace.dart';
import 'package:starflow/features/playback/domain/online_subtitle_structured_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';

const String _defaultOpenSubtitlesApiKey = String.fromEnvironment(
  'STARFLOW_OPENSUBTITLES_API_KEY',
);

abstract class OnlineSubtitleStructuredProvider {
  OnlineSubtitleSource get source;

  String get providerLabel;

  bool get isConfigured;

  Future<List<ProviderSubtitleHit>> search(
    OnlineSubtitleSearchRequest request,
  );
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
      if (request.preferHearingImpaired) 'hearing_impaired': 'include',
      if (query.kind == StructuredSubtitleQueryKind.hash) 'moviehash': query.query,
      if (query.kind == StructuredSubtitleQueryKind.hash &&
          request.fileSizeBytes != null)
        'moviebytesize': '${request.fileSizeBytes!}',
      if (query.kind == StructuredSubtitleQueryKind.imdbId) 'imdb_id': query.query,
      if (query.kind == StructuredSubtitleQueryKind.tmdbId) 'tmdb_id': query.query,
      if (query.kind != StructuredSubtitleQueryKind.hash &&
          query.kind != StructuredSubtitleQueryKind.imdbId &&
          query.kind != StructuredSubtitleQueryKind.tmdbId)
        'query': query.query,
      if (request.seasonNumber != null) 'season_number': '${request.seasonNumber!}',
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
      .map((item) => _parseOpenSubtitlesHit(Map<String, dynamic>.from(item as Map)))
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
    id:
        '${OnlineSubtitleSource.subdl.name}:${json['sd_id'] ?? json['id'] ?? fileName}',
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
