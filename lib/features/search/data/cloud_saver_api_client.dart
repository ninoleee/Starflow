import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/features/search/domain/search_models.dart';

final cloudSaverApiClientProvider = Provider<CloudSaverApiClient>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return CloudSaverApiClient(client);
});

class CloudSaverApiClient {
  CloudSaverApiClient(this._client);

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
    final response = await _client.get(
      _resolveSearchUri(provider.endpoint, keyword: keyword),
      headers: {
        'Accept': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    );

    final payload = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudSaverApiException(
        _resolveErrorMessage(payload, response.statusCode),
      );
    }
    if (payload['success'] == false || (payload['code'] as int? ?? 0) != 0) {
      throw CloudSaverApiException(
        _resolveErrorMessage(payload, response.statusCode),
      );
    }

    return _parseResults(payload, provider);
  }

  Future<CloudSaverConnectionStatus> testConnection({
    required SearchProviderConfig provider,
  }) async {
    final token = await _resolveToken(provider);
    final response = await _client.get(
      _resolveSearchUri(provider.endpoint, keyword: '测试'),
      headers: {
        'Accept': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    );

    final payload = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudSaverApiException(
        _resolveErrorMessage(payload, response.statusCode),
      );
    }
    if (payload['success'] == false || (payload['code'] as int? ?? 0) != 0) {
      throw CloudSaverApiException(
        _resolveErrorMessage(payload, response.statusCode),
      );
    }

    final groups = (payload['data'] as List<dynamic>? ?? const []);
    final itemCount = groups.fold<int>(
      0,
      (sum, group) =>
          sum + ((group as Map)['list'] as List<dynamic>? ?? const []).length,
    );
    return CloudSaverConnectionStatus(
      channelCount: groups.length,
      itemCount: itemCount,
      authenticated: token.isNotEmpty,
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
      throw CloudSaverApiException(
        _resolveErrorMessage(payload, response.statusCode),
      );
    }
    if (payload['success'] == false || (payload['code'] as int? ?? 0) != 0) {
      throw CloudSaverApiException(
        _resolveErrorMessage(payload, response.statusCode),
      );
    }

    final data = payload['data'] as Map<String, dynamic>? ?? const {};
    final token = (data['token'] as String? ?? '').trim();
    if (token.isEmpty) {
      throw const CloudSaverApiException('CloudSaver 登录成功，但没有返回 token');
    }
    return token;
  }

  List<SearchResult> _parseResults(
    Map<String, dynamic> payload,
    SearchProviderConfig provider,
  ) {
    final results = <SearchResult>[];
    final seen = <String>{};
    final groups = payload['data'] as List<dynamic>? ?? const [];

    for (final rawGroup in groups) {
      final group = Map<String, dynamic>.from(rawGroup as Map);
      final list = group['list'] as List<dynamic>? ?? const [];
      for (final rawItem in list) {
        final item = Map<String, dynamic>.from(rawItem as Map);
        final title = (item['title'] as String? ?? '').trim();
        final content = (item['content'] as String? ?? '').trim();
        final image = (item['image'] as String? ?? '').trim();
        final source = (item['channel'] as String? ?? '').trim();
        final publishedAt = (item['pubDate'] as String? ?? '').trim();
        final cloudType = (item['cloudType'] as String? ?? '').trim();
        final normalizedCloudType =
            SearchCloudTypeX.fromCode(cloudType)?.code ?? cloudType;
        final cloudLinks = (item['cloudLinks'] as List<dynamic>? ?? const [])
            .map((value) => '$value')
            .where((value) => value.trim().isNotEmpty)
            .toList(growable: false);

        for (final url in cloudLinks) {
          if (!seen.add(url)) {
            continue;
          }
          final password = _extractPassword(url, content);
          results.add(
            SearchResult(
              id: url,
              title: title.isEmpty ? url : title,
              posterUrl: image,
              providerId: provider.id,
              providerName: provider.name,
              quality: _cloudTypeLabel(cloudType),
              sizeLabel: password.isEmpty ? '免提取码' : '提取码 $password',
              seeders: 0,
              summary: [
                if (source.isNotEmpty) source,
                if (publishedAt.isNotEmpty) publishedAt,
                if (content.isNotEmpty) content,
                if (source.isEmpty && publishedAt.isEmpty && content.isEmpty)
                  'CloudSaver 搜索结果',
              ].join(' · '),
              resourceUrl: url,
              password: password,
              cloudType: normalizedCloudType,
              source: source,
              publishedAt: publishedAt,
              imageUrls: image.isEmpty ? const [] : [image],
            ),
          );
        }
      }
    }

    return results;
  }

  Uri _resolveSearchUri(String endpoint, {required String keyword}) {
    final base = _resolveEndpoint(endpoint, resourcePath: 'search');
    return base.replace(queryParameters: {
      'keyword': keyword,
    });
  }

  Uri _resolveLoginUri(String endpoint) {
    return _resolveEndpoint(endpoint, resourcePath: 'user/login');
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

  String _resolveErrorMessage(Map<String, dynamic> payload, int statusCode) {
    final message = (payload['message'] as String? ?? '').trim();
    if (message.isNotEmpty) {
      return message;
    }
    return 'CloudSaver 请求失败：HTTP $statusCode';
  }

  String _extractPassword(String url, String content) {
    final uri = Uri.tryParse(url);
    for (final key in const ['pwd', 'password', 'passcode']) {
      final value = uri?.queryParameters[key]?.trim() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }
    final match =
        RegExp(r'(提取码|访问码|密码)[:：\s]+([a-zA-Z0-9]{4,8})').firstMatch(content);
    return match?.group(2)?.trim() ?? '';
  }

  String _cloudTypeLabel(String raw) {
    switch (raw.toLowerCase()) {
      case 'quark':
        return '夸克网盘';
      case 'cloud115':
      case '115':
        return '115 网盘';
      case 'baidu':
        return '百度网盘';
      case 'aliyun':
        return '阿里云盘';
      case 'tianyi':
        return '天翼云盘';
      case 'uc':
        return 'UC 网盘';
      case 'xunlei':
        return '迅雷云盘';
      default:
        return raw.isEmpty ? '网盘资源' : raw;
    }
  }

  static bool supports(SearchProviderConfig provider) {
    final hint = provider.parserHint.trim().toLowerCase();
    final endpoint = provider.endpoint.trim().toLowerCase();
    return provider.kind == SearchProviderKind.cloudSaver ||
        hint == 'cloudsaver-api' ||
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

class CloudSaverConnectionStatus {
  const CloudSaverConnectionStatus({
    required this.channelCount,
    required this.itemCount,
    required this.authenticated,
  });

  final int channelCount;
  final int itemCount;
  final bool authenticated;

  String get summary {
    final authStatus = authenticated ? '已完成认证' : '无需认证或未提供认证';
    return '$authStatus · 频道 $channelCount · 结果 $itemCount';
  }
}

class CloudSaverApiException implements Exception {
  const CloudSaverApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
