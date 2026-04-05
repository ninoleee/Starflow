import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/core/network/starflow_http_client.dart';
import 'package:starflow/features/search/domain/search_models.dart';

final panSouApiClientProvider = Provider<PanSouApiClient>((ref) {
  final client = ref.watch(starflowHttpClientProvider);
  return PanSouApiClient(client);
});

class PanSouApiClient {
  PanSouApiClient(this._client);

  final http.Client _client;

  Future<List<SearchResult>> search(
    String query, {
    required SearchProviderConfig provider,
  }) async {
    final keyword = query.trim();
    if (keyword.isEmpty) {
      return const [];
    }

    final token = await _resolveToken(provider);
    final response = await _client.post(
      _resolveSearchUri(provider.endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'kw': keyword,
        'res': 'merge',
      }),
    );

    final payload = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PanSouApiException(
          _resolveErrorMessage(payload, response.statusCode));
    }
    if ((payload['code'] as int?) case final code? when code != 0) {
      throw PanSouApiException(
        _resolveErrorMessage(payload, response.statusCode),
      );
    }

    return _parseMergedResults(_unwrapPayload(payload), provider);
  }

  Future<PanSouHealthStatus> testConnection({
    required SearchProviderConfig provider,
  }) async {
    final response = await _client.get(
      _resolveHealthUri(provider.endpoint),
      headers: const {
        'Accept': 'application/json',
      },
    );

    final payload = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PanSouApiException(
          _resolveErrorMessage(payload, response.statusCode));
    }

    final status = (payload['status'] as String? ?? '').trim().toLowerCase();
    if (status != 'ok') {
      throw PanSouApiException(
        _resolveErrorMessage(payload, response.statusCode),
      );
    }

    final plugins = (payload['plugins'] as List<dynamic>? ?? const [])
        .map((value) => '$value')
        .where((value) => value.trim().isNotEmpty)
        .toList(growable: false);
    final channels = (payload['channels'] as List<dynamic>? ?? const [])
        .map((value) => '$value')
        .where((value) => value.trim().isNotEmpty)
        .toList(growable: false);

    return PanSouHealthStatus(
      authEnabled: payload['auth_enabled'] as bool? ?? false,
      pluginsEnabled: payload['plugins_enabled'] as bool? ?? false,
      pluginCount: payload['plugin_count'] as int? ?? plugins.length,
      plugins: plugins,
      channelsCount: payload['channels_count'] as int? ?? channels.length,
      channels: channels,
    );
  }

  Future<String> _resolveToken(SearchProviderConfig provider) async {
    final configuredToken = provider.apiKey.trim();
    if (configuredToken.isNotEmpty) {
      return configuredToken;
    }

    final username = provider.username.trim();
    final password = provider.password.trim();
    if (username.isEmpty || password.isEmpty) {
      return '';
    }

    final response = await _client.post(
      _resolveLoginUri(provider.endpoint),
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    final payload = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PanSouApiException(
          _resolveErrorMessage(payload, response.statusCode));
    }

    final token = payload['token'] as String? ?? '';
    if (token.trim().isEmpty) {
      throw const PanSouApiException('PanSou 登录成功，但没有返回 JWT Token');
    }
    return token.trim();
  }

  List<SearchResult> _parseMergedResults(
    Map<String, dynamic> payload,
    SearchProviderConfig provider,
  ) {
    final mergedByType =
        payload['merged_by_type'] as Map<String, dynamic>? ?? const {};
    final results = <SearchResult>[];
    final seen = <String>{};

    mergedByType.forEach((cloudType, entries) {
      final normalizedCloudType =
          SearchCloudTypeX.fromCode(cloudType)?.code ?? cloudType.trim();
      final links = entries as List<dynamic>? ?? const [];
      for (final entry in links) {
        final item = Map<String, dynamic>.from(entry as Map);
        final url = (item['url'] as String? ?? '').trim();
        if (url.isEmpty || !seen.add(url)) {
          continue;
        }

        final note = (item['note'] as String? ?? '').trim();
        final password = (item['password'] as String? ?? '').trim();
        final source = (item['source'] as String? ?? '').trim();
        final publishedAt = (item['datetime'] as String? ?? '').trim();
        final images = (item['images'] as List<dynamic>? ?? const [])
            .map((value) => '$value')
            .where((value) => value.trim().isNotEmpty)
            .toList();
        final posterUrl = images.isEmpty ? '' : images.first;

        results.add(
          SearchResult(
            id: url,
            title: note.isEmpty ? _cloudTypeLabel(cloudType) : note,
            posterUrl: posterUrl,
            providerId: provider.id,
            providerName: provider.name,
            quality: _cloudTypeLabel(cloudType),
            sizeLabel: password.isEmpty ? '免提取码' : '提取码 $password',
            seeders: 0,
            summary: [
              if (source.isNotEmpty) source,
              if (publishedAt.isNotEmpty) publishedAt,
              if (source.isEmpty && publishedAt.isEmpty) 'PanSou 聚合结果',
            ].join(' · '),
            resourceUrl: url,
            password: password,
            cloudType: normalizedCloudType,
            source: source,
            publishedAt: publishedAt,
            imageUrls: images,
          ),
        );
      }
    });

    if (results.isNotEmpty) {
      return results;
    }

    final rawResults = payload['results'] as List<dynamic>? ?? const [];
    for (final rawEntry in rawResults) {
      final entry = Map<String, dynamic>.from(rawEntry as Map);
      final title = (entry['title'] as String? ?? '').trim();
      final content = (entry['content'] as String? ?? '').trim();
      final channel = (entry['channel'] as String? ?? '').trim();
      final publishedAt = (entry['datetime'] as String? ?? '').trim();
      final images = (entry['images'] as List<dynamic>? ?? const [])
          .map((value) => '$value')
          .where((value) => value.trim().isNotEmpty)
          .toList(growable: false);
      final links = entry['links'] as List<dynamic>? ?? const [];
      for (final rawLink in links) {
        final link = Map<String, dynamic>.from(rawLink as Map);
        final url = (link['url'] as String? ?? '').trim();
        if (url.isEmpty || !seen.add(url)) {
          continue;
        }
        final password = (link['password'] as String? ?? '').trim();
        final cloudType = (link['type'] as String? ?? '').trim();
        final normalizedCloudType =
            SearchCloudTypeX.fromCode(cloudType)?.code ?? cloudType;
        final workTitle = (link['work_title'] as String? ?? '').trim();
        final resolvedTitle =
            workTitle.isNotEmpty ? workTitle : (title.isNotEmpty ? title : url);

        results.add(
          SearchResult(
            id: url,
            title: resolvedTitle,
            posterUrl: images.isEmpty ? '' : images.first,
            providerId: provider.id,
            providerName: provider.name,
            quality: _cloudTypeLabel(cloudType),
            sizeLabel: password.isEmpty ? '免提取码' : '提取码 $password',
            seeders: 0,
            summary: [
              if (channel.isNotEmpty) 'tg:$channel',
              if (publishedAt.isNotEmpty) publishedAt,
              if (content.isNotEmpty && content != resolvedTitle) content,
              if (channel.isEmpty && publishedAt.isEmpty && content.isEmpty)
                'PanSou 搜索结果',
            ].join(' · '),
            resourceUrl: url,
            password: password,
            cloudType: normalizedCloudType,
            source: channel.isEmpty ? '' : 'tg:$channel',
            publishedAt: publishedAt,
            imageUrls: images,
          ),
        );
      }
    }

    return results;
  }

  Uri _resolveSearchUri(String endpoint) {
    return _resolveEndpoint(endpoint, resourcePath: 'search');
  }

  Uri _resolveLoginUri(String endpoint) {
    return _resolveEndpoint(endpoint, resourcePath: 'auth/login');
  }

  Uri _resolveHealthUri(String endpoint) {
    return _resolveEndpoint(endpoint, resourcePath: 'health');
  }

  Uri _resolveEndpoint(String endpoint, {required String resourcePath}) {
    final parsed = Uri.parse(endpoint.trim());
    final normalizedPath = _trimTrailingSlash(parsed.path);
    final apiIndex = normalizedPath.indexOf('/api');
    final apiBasePath = apiIndex >= 0
        ? normalizedPath.substring(0, apiIndex + 4)
        : _joinPath(normalizedPath, 'api');

    return parsed.replace(
      path: _joinPath(apiBasePath, resourcePath),
      query: null,
      fragment: null,
    );
  }

  String _resolveErrorMessage(Map<String, dynamic> payload, int statusCode) {
    final error = payload['error'] as String? ?? '';
    if (error.trim().isNotEmpty) {
      return error.trim();
    }
    final message = payload['message'] as String? ?? '';
    if (message.trim().isNotEmpty) {
      return message.trim();
    }
    return 'PanSou 请求失败：HTTP $statusCode';
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.body.trim().isEmpty) {
      return const {};
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

  Map<String, dynamic> _unwrapPayload(Map<String, dynamic> payload) {
    final data = payload['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return payload;
  }

  String _cloudTypeLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'baidu':
        return '百度网盘';
      case 'quark':
        return '夸克网盘';
      case 'aliyun':
        return '阿里云盘';
      case 'uc':
        return 'UC 网盘';
      case 'tianyi':
        return '天翼云盘';
      case '115':
        return '115 网盘';
      case 'pikpak':
        return 'PikPak';
      case 'xunlei':
        return '迅雷云盘';
      case '123':
        return '123 云盘';
      case 'magnet':
        return '磁力链接';
      case 'ed2k':
        return '电驴链接';
      default:
        return raw.trim().isEmpty ? '网盘资源' : raw.trim();
    }
  }

  static bool supports(SearchProviderConfig provider) {
    final hint = provider.parserHint.trim().toLowerCase();
    final endpoint = provider.endpoint.trim().toLowerCase();
    return provider.kind == SearchProviderKind.panSou ||
        hint == 'pansou-api' ||
        endpoint.contains('so.252035.xyz') ||
        (endpoint.contains('/api/search') &&
            provider.kind != SearchProviderKind.cloudSaver &&
            hint != 'cloudsaver-api');
  }

  static String _trimTrailingSlash(String path) {
    if (path == '/' || path.isEmpty) {
      return '';
    }
    return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  }

  static String _joinPath(String basePath, String segment) {
    final normalizedBase = _trimTrailingSlash(basePath);
    final normalizedSegment =
        segment.startsWith('/') ? segment.substring(1) : segment;
    if (normalizedBase.isEmpty) {
      return '/$normalizedSegment';
    }
    return '$normalizedBase/$normalizedSegment';
  }
}

class PanSouApiException implements Exception {
  const PanSouApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PanSouHealthStatus {
  const PanSouHealthStatus({
    required this.authEnabled,
    required this.pluginsEnabled,
    required this.pluginCount,
    required this.plugins,
    required this.channelsCount,
    required this.channels,
  });

  final bool authEnabled;
  final bool pluginsEnabled;
  final int pluginCount;
  final List<String> plugins;
  final int channelsCount;
  final List<String> channels;

  String get summary {
    final parts = <String>[
      authEnabled ? '已启用认证' : '未启用认证',
      pluginsEnabled ? '插件 $pluginCount' : '插件关闭',
      '频道 $channelsCount',
    ];
    return parts.join(' · ');
  }
}
