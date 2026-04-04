import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/features/search/domain/search_models.dart';

final panSouApiClientProvider = Provider<PanSouApiClient>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
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

    return _parseMergedResults(payload, provider);
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
        final posterUrl = images.isEmpty
            ? _fallbackPosterUrl(provider.id, note.isEmpty ? url : note)
            : images.first;

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
            source: source,
            publishedAt: publishedAt,
            imageUrls: images,
          ),
        );
      }
    });

    return results;
  }

  Uri _resolveSearchUri(String endpoint) {
    return _resolveEndpoint(endpoint, resourcePath: 'search');
  }

  Uri _resolveLoginUri(String endpoint) {
    return _resolveEndpoint(endpoint, resourcePath: 'auth/login');
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

  String _fallbackPosterUrl(String providerId, String seed) {
    final encodedSeed = Uri.encodeComponent('$providerId-$seed');
    return 'https://picsum.photos/seed/$encodedSeed/400/600';
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
    return hint == 'pansou-api' ||
        endpoint.contains('so.252035.xyz') ||
        endpoint.contains('/api/search');
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
