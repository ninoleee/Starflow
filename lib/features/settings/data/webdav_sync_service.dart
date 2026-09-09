import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/core/network/starflow_http_client.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

class WebDavSyncConfig {
  const WebDavSyncConfig({
    this.url = '',
    this.directory = 'Starflow',
    this.username = '',
    this.password = '',
    this.settings = true,
    this.favorites = true,
  });

  final String url;
  final String directory;
  final String username;
  final String password;
  final bool settings;
  final bool favorites;

  Uri get baseUri {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        username.contains(':')) {
      throw const FormatException('请填写有效的 HTTP / HTTPS 地址，认证信息请填写在账号字段中');
    }
    return uri.replace(
        path: uri.path.endsWith('/') ? uri.path : '${uri.path}/');
  }

  List<String> get directories {
    final parts =
        directory.trim().split('/').where((s) => s.isNotEmpty).toList();
    if (parts.any((s) => s == '.' || s == '..' || s.contains('\\'))) {
      throw const FormatException('同步目录不能包含 .、.. 或反斜杠');
    }
    return parts;
  }

  Uri get directoryUri => baseUri.replace(
        pathSegments: [
          ...baseUri.pathSegments.where((s) => s.isNotEmpty),
          ...directories,
          '',
        ],
      );

  Uri get fileUri => directoryUri.resolve('starflow-sync.json');

  Map<String, dynamic> toJson() => {
        'url': url,
        'directory': directory,
        'username': username,
        'password': password,
        'settings': settings,
        'favorites': favorites,
      };

  factory WebDavSyncConfig.fromJson(Map<String, dynamic> json) =>
      WebDavSyncConfig(
        url: json['url'] as String? ?? '',
        directory: json['directory'] as String? ?? 'Starflow',
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        settings: json['settings'] as bool? ?? true,
        favorites: json['favorites'] as bool? ?? true,
      );
}

final webDavSyncPreferencesProvider =
    Provider((ref) => WebDavSyncPreferences());

class WebDavSyncPreferences {
  final _store = AppPreferencesStore();
  static const _key = 'starflow.webdavSync.v1';

  Future<WebDavSyncConfig> load() async {
    final raw = await _store.getString(_key);
    return raw == null
        ? const WebDavSyncConfig()
        : WebDavSyncConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(WebDavSyncConfig config) =>
      _store.setString(_key, jsonEncode(config.toJson()));
}

final webDavSyncServiceProvider = Provider(
  (ref) => WebDavSyncService(ref.watch(starflowHttpClientProvider)),
);

class WebDavSyncSnapshot {
  const WebDavSyncSnapshot({this.settings, this.favorites});

  final AppSettings? settings;
  final List<SearchResult>? favorites;

  Map<String, dynamic> toJson() => {
        'format': 'starflow-sync',
        'version': 1,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        if (settings != null) 'settings': settings!.toJson(),
        if (favorites != null)
          'favorites': favorites!.map((item) => item.toJson()).toList(),
      };

  factory WebDavSyncSnapshot.decode(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    if (json['format'] != 'starflow-sync' || json['version'] != 1) {
      throw const FormatException('不是受支持的 Starflow 同步文件');
    }
    final settings = json['settings'];
    if (settings != null &&
        (settings is! Map<String, dynamic> ||
            !settings.containsKey('mediaSources') ||
            !settings.containsKey('searchProviders') ||
            !settings.containsKey('homeModules'))) {
      throw const FormatException('远端配置不完整');
    }
    final favorites = json['favorites'] == null
        ? null
        : (json['favorites'] as List)
            .map((item) => SearchResult.fromJson(item as Map<String, dynamic>))
            .toList();
    if (favorites != null &&
        (favorites.length > 200 ||
            favorites.any((item) => item.title.trim().isEmpty))) {
      throw const FormatException('远端收藏无效或超过 200 条');
    }
    return WebDavSyncSnapshot(
      settings: settings == null ? null : AppSettings.fromCurrentJson(settings),
      favorites: favorites,
    );
  }
}

class WebDavSyncService {
  WebDavSyncService(this._client);
  final http.Client _client;
  static const _maxBytes = 16 * 1024 * 1024;

  Future<http.Response> _request(
    WebDavSyncConfig config,
    String method,
    Uri uri, {
    String? body,
    Map<String, String> headers = const {},
  }) async {
    final request = http.Request(method, uri)
      ..followRedirects = false
      ..headers.addAll({
        if (config.username.isNotEmpty || config.password.isNotEmpty)
          'Authorization':
              'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}',
        ...headers,
      });
    if (body != null) {
      if (utf8.encode(body).length > _maxBytes) {
        throw const FormatException('同步文件超过 16 MB');
      }
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.body = body;
    }
    return (() async {
      final response = await _client.send(request);
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > _maxBytes) {
          throw const FormatException('同步文件超过 16 MB');
        }
        bytes.addAll(chunk);
      }
      return http.Response.bytes(bytes, response.statusCode,
          headers: response.headers);
    })()
        .timeout(const Duration(seconds: 30));
  }

  void _check(http.Response response, Set<int> allowed) {
    if (!allowed.contains(response.statusCode)) {
      throw StateError(switch (response.statusCode) {
        401 || 403 => '认证失败或没有访问权限',
        404 => '远端同步文件或目录不存在',
        412 => '远端文件已被其他设备修改，请重新操作',
        >= 300 && < 400 => '服务器返回重定向，请填写最终 WebDAV 地址',
        _ => 'WebDAV 请求失败（HTTP ${response.statusCode}）',
      });
    }
  }

  Future<void> testConnection(WebDavSyncConfig config) async {
    // Probe the configured directory without creating or changing remote data.
    final response = await _request(config, 'PROPFIND', config.directoryUri,
        headers: {'Depth': '0'});
    _check(response, {200, 207});
  }

  Future<WebDavSyncSnapshot> download(WebDavSyncConfig config) async {
    final response = await _request(config, 'GET', config.fileUri);
    _check(response, {200});
    final snapshot = WebDavSyncSnapshot.decode(utf8.decode(response.bodyBytes));
    if ((config.settings && snapshot.settings == null) ||
        (config.favorites && snapshot.favorites == null)) {
      throw const FormatException('远端文件不包含所选同步内容');
    }
    return snapshot;
  }

  Future<void> upload(WebDavSyncConfig config, WebDavSyncSnapshot local) async {
    var directory = config.baseUri;
    for (final segment in config.directories) {
      directory = directory.replace(pathSegments: [
        ...directory.pathSegments.where((s) => s.isNotEmpty),
        segment,
        '',
      ]);
      final result = await _request(config, 'MKCOL', directory);
      _check(result, {200, 201, 204, 405});
    }
    final previous = await _request(config, 'GET', config.fileUri);
    _check(previous, {200, 404});
    final remote = previous.statusCode == 404
        ? const WebDavSyncSnapshot()
        : WebDavSyncSnapshot.decode(utf8.decode(previous.bodyBytes));
    final next = WebDavSyncSnapshot(
      settings: config.settings ? local.settings : remote.settings,
      favorites: config.favorites ? local.favorites : remote.favorites,
    );
    final response = await _request(config, 'PUT', config.fileUri,
        body: jsonEncode(next.toJson()),
        headers: {
          if (previous.statusCode == 404) 'If-None-Match': '*',
          if (previous.headers['etag'] != null)
            'If-Match': previous.headers['etag']!,
        });
    _check(response, {200, 201, 204});
  }
}
