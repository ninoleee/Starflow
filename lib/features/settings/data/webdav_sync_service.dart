import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/core/network/starflow_http_client.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/search/domain/favorite_sync_document.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/domain/webdav_sync_config.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:xml/xml.dart';

export 'package:starflow/features/settings/domain/webdav_sync_config.dart';

final webDavSyncPreferencesProvider = Provider((ref) {
  final preferences = WebDavSyncPreferences(
    loadConfig: () async =>
        (await ref.read(settingsControllerProvider.future)).webDavSync ??
        const WebDavSyncConfig(),
    saveConfig: (config) async {
      await ref.read(settingsControllerProvider.future);
      await ref
          .read(settingsControllerProvider.notifier)
          .saveWebDavSync(config);
    },
  );
  ref.listen(settingsControllerProvider, (previous, next) {
    if (jsonEncode(previous?.value?.webDavSync?.toJson()) !=
        jsonEncode(next.value?.webDavSync?.toJson())) {
      preferences.notifyChanged();
    }
  });
  ref.onDispose(preferences.dispose);
  return preferences;
});

class WebDavSyncPreferences {
  WebDavSyncPreferences({
    Future<WebDavSyncConfig> Function()? loadConfig,
    Future<void> Function(WebDavSyncConfig)? saveConfig,
  })  : _loadConfig = loadConfig,
        _saveConfig = saveConfig;

  final Future<WebDavSyncConfig> Function()? _loadConfig;
  final Future<void> Function(WebDavSyncConfig)? _saveConfig;
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  void dispose() => _changes.close();
  final _store = AppPreferencesStore();
  static const _key = 'starflow.webdavSync.v1';

  void notifyChanged() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<WebDavSyncConfig> load() async {
    if (_loadConfig != null) return _loadConfig();
    final raw = await _store.getString(_key);
    return raw == null
        ? const WebDavSyncConfig()
        : WebDavSyncConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(WebDavSyncConfig config) async {
    if (_saveConfig != null) return _saveConfig(config);
    await _store.setString(_key, jsonEncode(config.toJson()));
    notifyChanged();
  }
}

final webDavSyncServiceProvider = Provider(
  (ref) => WebDavSyncService(ref.watch(starflowHttpClientProvider)),
);

enum WebDavConnectionTestResult {
  directoryAvailable,
  directoryMissing;

  String get message => switch (this) {
        directoryAvailable => '连接成功，同步目录可访问（写入权限尚未验证）',
        directoryMissing => 'WebDAV 连接成功，同步目录尚未创建；首次上传或写入收藏时将尝试创建（写入权限尚未验证）',
      };
}

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
  static final _deviceFileName =
      RegExp(r'^starflow-favorites-[a-f0-9]{32}\.json$');

  Future<
          ({
            List<FavoriteSyncDocument> documents,
            FavoriteSyncDocument? deviceDocument,
            int deviceCount
          })>
      readFavorites(WebDavSyncConfig config, {required String deviceId}) async {
    final ownUri = config.favoriteDeviceFileUri(deviceId);
    final listing = await _request(config, 'PROPFIND', config.directoryUri,
        headers: {'Depth': '1', 'Cache-Control': 'no-cache'});
    _check(listing, {200, 207, 404}, operation: '读取收藏设备列表');
    if (listing.statusCode == 404) {
      return (
        documents: <FavoriteSyncDocument>[],
        deviceDocument: null,
        deviceCount: 0
      );
    }
    final devices = _favoriteDevices(listing, config.directoryUri);
    // Read our own file even if a gateway has not refreshed its directory listing.
    final files = {ownUri, ...devices};
    final documents = <FavoriteSyncDocument>[];
    FavoriteSyncDocument? own;
    var totalBytes = 0;
    var deviceCount = 0;
    for (final uri in files) {
      final response = await _request(config, 'GET', uri,
          headers: {'Cache-Control': 'no-cache'});
      _check(response, {200, 404}, operation: '读取设备收藏');
      if (response.statusCode == 404) {
        if (devices.contains(uri)) {
          throw StateError('设备收藏文件暂时不可读，请再次同步');
        }
        continue;
      }
      totalBytes += response.bodyBytes.length;
      if (totalBytes > _maxBytes) {
        throw const FormatException('设备收藏数据合计超过 16 MB');
      }
      final json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final document = FavoriteSyncDocument.fromJson(json);
      documents.add(document);
      if (uri == ownUri) {
        own = document;
      }
      deviceCount++;
    }
    return (
      documents: documents,
      deviceDocument: own,
      deviceCount: deviceCount
    );
  }

  Set<Uri> _favoriteDevices(http.Response response, Uri directory) {
    try {
      if (!_isDirectory(response, directory)) {
        throw const FormatException('WebDAV 收藏设备目录响应无效');
      }
      final document = XmlDocument.parse(utf8.decode(response.bodyBytes));
      final parent = directory.pathSegments.where((s) => s.isNotEmpty).toList();
      final devices = <Uri>{};
      for (final resource
          in document.rootElement.findElements('response', namespace: 'DAV:')) {
        final href =
            resource.getElement('href', namespace: 'DAV:')?.innerText.trim();
        if (href == null || href.isEmpty) continue;
        final uri = directory.resolve(href);
        final segments = uri.pathSegments;
        if (uri.scheme != directory.scheme ||
            uri.host != directory.host ||
            uri.port != directory.port ||
            uri.userInfo.isNotEmpty ||
            uri.hasQuery ||
            uri.hasFragment ||
            segments.length != parent.length + 1 ||
            !listEquals(segments.take(parent.length).toList(), parent) ||
            _deviceFileName.stringMatch(segments.last) != segments.last) {
          continue;
        }
        final properties = _successfulDavProperties(resource).toList();
        if (properties.isEmpty ||
            properties.any((prop) =>
                prop
                    .getElement('resourcetype', namespace: 'DAV:')
                    ?.getElement('collection', namespace: 'DAV:') !=
                null)) {
          throw const FormatException('设备收藏文件属性无效');
        }
        devices.add(uri);
        if (devices.length > 100) {
          throw StateError('收藏同步设备记录超过 100 份，请检查同步目录');
        }
      }
      return devices;
    } on XmlException {
      throw const FormatException('WebDAV 收藏设备列表无效');
    }
  }

  Future<void> writeFavorites(
      WebDavSyncConfig config, FavoriteSyncDocument document,
      {required String deviceId}) async {
    document.validateCapacity();
    // Only this installation writes this path; other devices own different files.
    final response = await _request(
        config, 'PUT', config.favoriteDeviceFileUri(deviceId),
        body: document.encodeForSync());
    _check(response, {200, 201, 204}, operation: '写入本设备收藏');
  }

  Future<FavoriteSyncDocument> verifyFavoritesWrite(
      WebDavSyncConfig config, FavoriteSyncDocument sent,
      {required String deviceId}) async {
    final response = await _request(
        config, 'GET', config.favoriteDeviceFileUri(deviceId),
        headers: {'Cache-Control': 'no-cache'});
    _check(response, {200, 404}, operation: '验证收藏上传结果');
    if (response.statusCode == 404) {
      throw StateError('服务器已接受上传，但尚未读到收藏文件；未确认同步完成，请稍后手动同步');
    }
    final received =
        FavoriteSyncDocument.decode(utf8.decode(response.bodyBytes));
    // Concurrent additions or newer tombstones are valid; lost sent entries are not.
    if (received.merge(sent).encodeForSync() != received.encodeForSync()) {
      appLogWarning(
          'sync.webdav', 'Favorite readback is missing uploaded changes',
          fields: {'reason': 'readbackMismatch', 'phase': 'verify'});
      throw StateError('上传后的收藏内容未通过读回验证；可能存在缓存延迟或并发覆盖，请再次手动同步');
    }
    return received;
  }

  Future<void> ensureDirectory(WebDavSyncConfig config) async {
    var directory = config.baseUri;
    for (final segment in config.directories) {
      directory = directory.replace(pathSegments: [
        ...directory.pathSegments.where((s) => s.isNotEmpty),
        segment,
        '',
      ]);
      final result = await _request(config, 'MKCOL', directory);
      _check(result, {200, 201, 204, 405}, operation: '创建同步目录');
      // A successful MKCOL or 405 does not prove that a usable collection exists.
      final verification = await _request(config, 'PROPFIND', directory,
          headers: {'Depth': '0', 'Cache-Control': 'no-cache'});
      if (verification.statusCode == 404) {
        throw StateError('创建同步目录后仍无法访问（MKCOL HTTP ${result.statusCode}，'
            'PROPFIND HTTP 404），已停止上传；请检查 WebDAV 新建目录权限及挂载存储状态');
      }
      _check(verification, {200, 207}, operation: '验证同步目录');
      if (!_isDirectory(verification, directory)) {
        throw StateError('验证同步目录失败（MKCOL HTTP ${result.statusCode}，'
            'PROPFIND HTTP ${verification.statusCode}）：'
            '服务器未确认目标路径为目录，已停止上传；请检查同名文件或 WebDAV 响应');
      }
    }
  }

  bool _isDirectory(http.Response response, Uri directory) {
    try {
      return _davProperties(response, directory).any((prop) =>
          prop
              .getElement('resourcetype', namespace: 'DAV:')
              ?.getElement('collection', namespace: 'DAV:') !=
          null);
    } on FormatException {
      return false;
    } on XmlException {
      return false;
    }
  }

  Iterable<XmlElement> _davProperties(
      http.Response response, Uri target) sync* {
    const dav = 'DAV:';
    final expected = target.pathSegments.toList();
    if (expected.isNotEmpty && expected.last.isEmpty) expected.removeLast();
    final document = XmlDocument.parse(utf8.decode(response.bodyBytes));
    if (document.rootElement.name.local != 'multistatus' ||
        document.rootElement.namespaceUri != dav) {
      throw const FormatException('Invalid DAV multistatus');
    }
    for (final resource
        in document.rootElement.findElements('response', namespace: dav)) {
      final href =
          resource.getElement('href', namespace: dav)?.innerText.trim();
      if (href == null || href.isEmpty) continue;
      final uri = target.resolve(href);
      final segments = uri.pathSegments.toList();
      if (segments.isNotEmpty && segments.last.isEmpty) segments.removeLast();
      if (uri.scheme != target.scheme ||
          uri.host != target.host ||
          uri.port != target.port ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          !listEquals(segments, expected)) {
        continue;
      }
      yield* _successfulDavProperties(resource);
    }
  }

  Iterable<XmlElement> _successfulDavProperties(XmlElement resource) sync* {
    for (final propstat
        in resource.findElements('propstat', namespace: 'DAV:')) {
      final status =
          propstat.getElement('status', namespace: 'DAV:')?.innerText;
      if (status == null ||
          !RegExp(r'^HTTP/\S+\s+200(?:\s|$)').hasMatch(status.trim())) {
        continue;
      }
      final prop = propstat.getElement('prop', namespace: 'DAV:');
      if (prop != null) yield prop;
    }
  }

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
      final fields = <String, Object?>{
        'method': method,
        'host': uri.host,
        'path': uri.path,
        'statusCode': response.statusCode,
        if (method == 'PUT' && _deviceFileName.hasMatch(uri.pathSegments.last))
          'writeMode': 'device',
      };
      if (response.statusCode >= 400) {
        appLogWarning('sync.webdav', 'WebDAV response received',
            fields: fields);
      } else {
        appLogInfo('sync.webdav', 'WebDAV response received', fields: fields);
      }
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

  void _check(http.Response response, Set<int> allowed, {String? operation}) {
    if (!allowed.contains(response.statusCode)) {
      final reason = switch (response.statusCode) {
        401 || 403 => '认证失败或没有访问权限',
        404 => '远端同步文件或目录不存在',
        409 when operation == '创建同步目录' => '父目录不存在或挂载存储尚未就绪',
        412 => '远端文件已被其他设备修改，请重新操作',
        >= 300 && < 400 => '服务器返回重定向，请填写最终 WebDAV 地址',
        _ => operation == null
            ? 'WebDAV 请求失败（HTTP ${response.statusCode}）'
            : 'WebDAV 服务器拒绝请求',
      };
      throw StateError(operation == null
          ? reason
          : '$operation失败（HTTP ${response.statusCode}）：$reason');
    }
  }

  Future<WebDavConnectionTestResult> testConnection(
      WebDavSyncConfig config) async {
    // Probe the configured directory without creating or changing remote data.
    final response = await _request(config, 'PROPFIND', config.directoryUri,
        headers: {'Depth': '0'});
    if (response.statusCode == 404) {
      // A new sync subdirectory may not exist yet; this is not a connection failure.
      final base = config.directories.isEmpty
          ? response
          : await _request(config, 'PROPFIND', config.baseUri,
              headers: {'Depth': '0'});
      if (base.statusCode == 404) {
        throw StateError('WebDAV 基础地址不存在，请检查服务器地址是否为 WebDAV 接口；同步目录应单独填写');
      }
      _check(base, {200, 207});
      return WebDavConnectionTestResult.directoryMissing;
    }
    _check(response, {200, 207});
    return WebDavConnectionTestResult.directoryAvailable;
  }

  Future<WebDavSyncSnapshot> download(WebDavSyncConfig config) async {
    final response = await _request(config, 'GET', config.fileUri);
    _check(response, {200}, operation: '下载同步文件');
    final snapshot = WebDavSyncSnapshot.decode(utf8.decode(response.bodyBytes));
    if ((config.settings && snapshot.settings == null) ||
        (config.favorites && snapshot.favorites == null)) {
      throw const FormatException('远端文件不包含所选同步内容');
    }
    return snapshot;
  }

  Future<void> upload(WebDavSyncConfig config, WebDavSyncSnapshot local) async {
    await ensureDirectory(config);
    final previous = await _request(config, 'GET', config.fileUri);
    _check(previous, {200, 404}, operation: '读取远端同步文件');
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
    _check(response, {200, 201, 204}, operation: '上传同步文件');
  }
}
