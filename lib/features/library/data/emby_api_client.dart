import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/features/library/domain/media_models.dart';

final embyApiClientProvider = Provider<EmbyApiClient>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return EmbyApiClient(client);
});

class EmbyApiClient {
  EmbyApiClient(this._client);

  final http.Client _client;
  static const _clientName = 'Starflow';
  static const _deviceName = 'Starflow';
  static const _appVersion = '0.1.0';

  Future<EmbySession> authenticate({
    required MediaSourceConfig source,
    required String password,
  }) async {
    final username = source.username.trim();
    if (source.endpoint.trim().isEmpty) {
      throw const EmbyApiException('请先填写 Emby Endpoint');
    }
    if (username.isEmpty) {
      throw const EmbyApiException('请先填写 Emby 用户名');
    }
    if (password.trim().isEmpty) {
      throw const EmbyApiException('请先填写 Emby 密码');
    }

    final deviceId = source.deviceId.trim().isEmpty
        ? _generateDeviceId()
        : source.deviceId.trim();
    final response = await _requestJson(
      source.endpoint,
      path: 'Users/AuthenticateByName',
      method: 'POST',
      token: source.accessToken,
      deviceId: deviceId,
      body: {
        'Username': username,
        'Pw': password,
      },
    );

    final token = response.json['AccessToken'] as String? ?? '';
    final user = response.json['User'] as Map<String, dynamic>? ?? const {};
    final userId = user['Id'] as String? ?? '';
    final resolvedUsername = user['Name'] as String? ?? username;
    final serverId = response.json['ServerId'] as String? ?? '';

    if (token.isEmpty || userId.isEmpty) {
      throw const EmbyApiException('Emby 登录成功，但没有拿到有效会话');
    }

    return EmbySession(
      baseUri: response.baseUri,
      accessToken: token,
      userId: userId,
      username: resolvedUsername,
      serverId: serverId,
      deviceId: deviceId,
    );
  }

  Future<List<MediaItem>> fetchLibrary(
    MediaSourceConfig source, {
    int limit = 200,
    String? sectionId,
    String sectionName = '',
  }) async {
    if (!source.hasActiveSession) {
      return const [];
    }

    final rootItems = await _fetchItems(
      source: source,
      limit: limit,
      parentId: sectionId,
      sectionId: sectionId,
      sectionName: sectionName,
    );
    if (sectionId != null && sectionId.trim().isNotEmpty) {
      return rootItems;
    }
    if (rootItems.isNotEmpty) {
      return rootItems;
    }

    final views = await fetchCollections(source);
    if (views.isEmpty) {
      return rootItems;
    }

    final groupedItems = await Future.wait(
      views.map(
        (view) => _fetchItems(
          source: source,
          limit: limit,
          parentId: view.id,
          sectionId: view.id,
          sectionName: view.title,
        ),
      ),
    );

    return _dedupeAndSort(
      groupedItems.expand((items) => items).toList(),
      limit: limit,
    );
  }

  Future<List<MediaItem>> _fetchItems({
    required MediaSourceConfig source,
    required int limit,
    String? parentId,
    String? sectionId,
    String sectionName = '',
  }) async {
    final response = await _requestJson(
      source.endpoint,
      path: 'Users/${source.userId}/Items',
      method: 'GET',
      token: source.accessToken,
      deviceId: source.deviceId,
      query: {
        'Recursive': 'true',
        'IncludeItemTypes': 'Movie,Episode,Video',
        'Filters': 'IsNotFolder',
        'MediaTypes': 'Video',
        'Fields':
            'DateCreated,Genres,Overview,Path,People,ProductionYear,RunTimeTicks,SortName',
        'EnableImages': 'true',
        'EnableImageTypes': 'Primary',
        'ImageTypeLimit': '1',
        'EnableUserData': 'true',
        'SortBy': 'DateCreated,SortName',
        'SortOrder': 'Descending,Ascending',
        'Limit': '$limit',
        if (parentId != null && parentId.trim().isNotEmpty)
          'ParentId': parentId.trim(),
      },
    );

    final items = response.json['Items'] as List<dynamic>? ?? const [];
    return _dedupeAndSort(
      items
          .map(
            (item) => _mapLibraryItem(
              response.baseUri,
              source,
              Map<String, dynamic>.from(item as Map),
              sectionId: sectionId,
              sectionName: sectionName,
            ),
          )
          .whereType<MediaItem>()
          .toList(),
      limit: limit,
    );
  }

  Future<List<MediaCollection>> fetchCollections(
      MediaSourceConfig source) async {
    if (!source.hasActiveSession) {
      return const [];
    }

    final response = await _requestJson(
      source.endpoint,
      path: 'Users/${source.userId}/Views',
      method: 'GET',
      token: source.accessToken,
      deviceId: source.deviceId,
      query: const {
        'IncludeHidden': 'false',
      },
    );

    final items = response.json['Items'] as List<dynamic>? ?? const [];
    return items
        .map((item) => Map<String, dynamic>.from(item as Map))
        .where(_supportsVideoBrowsing)
        .map(
          (item) => _EmbyView(
            id: item['Id'] as String? ?? '',
            title: item['Name'] as String? ?? '',
            collectionType: item['CollectionType'] as String? ?? '',
          ),
        )
        .where((view) => view.id.trim().isNotEmpty)
        .map(
          (view) => MediaCollection(
            id: view.id,
            title: view.title.trim().isEmpty ? '未命名分区' : view.title.trim(),
            sourceId: source.id,
            sourceName: source.name,
            sourceKind: source.kind,
            subtitle: _viewSubtitle(view),
          ),
        )
        .toList();
  }

  List<MediaItem> _dedupeAndSort(
    List<MediaItem> items, {
    required int limit,
  }) {
    final deduped = <String, MediaItem>{};
    for (final item in items) {
      deduped[item.id] = item;
    }

    final sorted = deduped.values.toList()
      ..sort((left, right) => right.addedAt.compareTo(left.addedAt));
    if (sorted.length <= limit) {
      return sorted;
    }
    return sorted.take(limit).toList();
  }

  MediaItem? _mapLibraryItem(
    Uri baseUri,
    MediaSourceConfig source,
    Map<String, dynamic> item, {
    String? sectionId,
    String sectionName = '',
  }) {
    final id = item['Id'] as String? ?? '';
    final title = item['Name'] as String? ?? '';
    if (id.isEmpty || title.isEmpty) {
      return null;
    }

    final mediaSources = (item['MediaSources'] as List<dynamic>? ?? const [])
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList();
    final mediaSource = mediaSources.isEmpty ? null : mediaSources.first;
    final overview = item['Overview'] as String? ?? '';
    final productionYear = item['ProductionYear'] as int? ?? 0;
    final genres = (item['Genres'] as List<dynamic>? ?? const [])
        .map((entry) => '$entry')
        .toList();
    final directors = _resolvePeople(item, const {'director'});
    final actors = _resolvePeople(item, const {'actor', 'gueststar'});
    final createdAt = DateTime.tryParse(item['DateCreated'] as String? ?? '') ??
        DateTime.now();
    final lastPlayedAt = DateTime.tryParse(
      (item['UserData'] as Map<String, dynamic>? ?? const {})['LastPlayedDate']
              as String? ??
          '',
    );
    final runTimeTicks = item['RunTimeTicks'] as int?;
    final durationLabel = formatRunTimeTicks(runTimeTicks);
    final streamUrl = buildDirectStreamUri(
      baseUri: baseUri,
      itemId: id,
      container: _resolveContainer(item, mediaSource),
      mediaSourceId: mediaSource?['Id'] as String? ?? '',
      accessToken: source.accessToken,
    ).toString();

    return MediaItem(
      id: id,
      title: title,
      overview: overview,
      posterUrl: buildPosterUri(
        baseUri: baseUri,
        itemId: id,
        imageTag: _resolvePrimaryImageTag(item),
        accessToken: source.accessToken,
      ).toString(),
      year: productionYear,
      durationLabel: durationLabel,
      genres: genres,
      directors: directors,
      actors: actors,
      sectionId: (sectionId ?? '').trim(),
      sectionName: sectionName.trim(),
      sourceId: source.id,
      sourceName: source.name,
      sourceKind: source.kind,
      streamUrl: streamUrl,
      streamHeaders: {
        'X-Emby-Token': source.accessToken,
        'X-Emby-Authorization': _authorizationHeader(
          token: source.accessToken,
          deviceId: source.deviceId,
        ),
      },
      addedAt: createdAt,
      lastWatchedAt: lastPlayedAt,
    );
  }

  Future<_EmbyJsonResponse> _requestJson(
    String endpoint, {
    required String path,
    required String method,
    required String token,
    required String deviceId,
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final candidates = candidateBaseUris(endpoint);
    EmbyApiException? lastError;

    for (var index = 0; index < candidates.length; index++) {
      final baseUri = candidates[index];
      final uri = baseUri.replace(
        path: _joinPath(baseUri.path, path),
        queryParameters: query,
      );

      try {
        final request = http.Request(method, uri)
          ..headers.addAll({
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'X-Emby-Authorization': _authorizationHeader(
              token: token,
              deviceId: deviceId,
            ),
            if (token.trim().isNotEmpty) 'X-Emby-Token': token.trim(),
          });
        if (body != null) {
          request.body = jsonEncode(body);
        }

        final streamedResponse = await _client.send(request);
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final decoded = jsonDecode(response.body) as Map;
          return _EmbyJsonResponse(
            baseUri: baseUri,
            json: Map<String, dynamic>.from(decoded),
          );
        }

        if (response.statusCode == 404 && index < candidates.length - 1) {
          continue;
        }

        final message = _resolveErrorMessage(response);
        lastError = EmbyApiException(message);
      } catch (error) {
        if (index == candidates.length - 1) {
          lastError = EmbyApiException('连接 Emby 失败：$error');
        }
      }
    }

    throw lastError ?? const EmbyApiException('无法连接到 Emby');
  }

  static List<Uri> candidateBaseUris(String endpoint) {
    final normalized = endpoint.trim();
    if (normalized.isEmpty) {
      return const [];
    }

    final parsed = Uri.parse(normalized);
    final cleaned = Uri(
      scheme: parsed.scheme,
      userInfo: parsed.userInfo,
      host: parsed.host,
      port: parsed.hasPort ? parsed.port : null,
      path: _trimTrailingSlash(parsed.path),
    );

    final candidates = <Uri>[cleaned];
    if (!_pathEndsWithEmby(cleaned.path)) {
      candidates.add(
        cleaned.replace(path: _joinPath(cleaned.path, 'emby')),
      );
    }
    return candidates;
  }

  static Uri buildPosterUri({
    required Uri baseUri,
    required String itemId,
    required String imageTag,
    required String accessToken,
  }) {
    return baseUri.replace(
      path: _joinPath(baseUri.path, 'Items/$itemId/Images/Primary'),
      queryParameters: {
        'maxHeight': '720',
        'quality': '90',
        if (imageTag.isNotEmpty) 'tag': imageTag,
        if (accessToken.trim().isNotEmpty) 'api_key': accessToken.trim(),
      },
    );
  }

  static Uri buildDirectStreamUri({
    required Uri baseUri,
    required String itemId,
    required String container,
    required String mediaSourceId,
    required String accessToken,
  }) {
    final safeContainer = container.trim().isEmpty ? 'mp4' : container.trim();
    return baseUri.replace(
      path: _joinPath(baseUri.path, 'Videos/$itemId/stream.$safeContainer'),
      queryParameters: {
        'static': 'true',
        if (mediaSourceId.trim().isNotEmpty) 'MediaSourceId': mediaSourceId,
        if (accessToken.trim().isNotEmpty) 'api_key': accessToken.trim(),
      },
    );
  }

  static String formatRunTimeTicks(int? runTimeTicks) {
    if (runTimeTicks == null || runTimeTicks <= 0) {
      return '时长未知';
    }

    final totalMinutes = runTimeTicks ~/ 10000000 ~/ 60;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours <= 0) {
      return '${minutes}m';
    }
    return '${hours}h ${minutes}m';
  }

  String _resolveErrorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['Message'] is String) {
        return decoded['Message'] as String;
      }
    } catch (_) {
      // Ignore parse errors and fall back to status-based messages.
    }

    switch (response.statusCode) {
      case 401:
        return 'Emby 登录失败：用户名或密码不正确';
      case 403:
        return 'Emby 拒绝了当前请求';
      case 404:
        return '找不到 Emby API，请检查 Endpoint 是否需要带 /emby';
      default:
        return 'Emby 请求失败：HTTP ${response.statusCode}';
    }
  }

  String _resolvePrimaryImageTag(Map<String, dynamic> item) {
    final imageTags = item['ImageTags'] as Map<String, dynamic>? ?? const {};
    return imageTags['Primary'] as String? ??
        item['PrimaryImageTag'] as String? ??
        '';
  }

  String _resolveContainer(
    Map<String, dynamic> item,
    Map<String, dynamic>? mediaSource,
  ) {
    return mediaSource?['Container'] as String? ??
        item['Container'] as String? ??
        'mp4';
  }

  List<String> _resolvePeople(
    Map<String, dynamic> item,
    Set<String> acceptedTypes,
  ) {
    final seen = <String>{};
    final people = item['People'] as List<dynamic>? ?? const [];
    final names = <String>[];

    for (final entry in people) {
      final person = Map<String, dynamic>.from(entry as Map);
      final type = (person['Type'] as String? ?? '').trim().toLowerCase();
      final name = (person['Name'] as String? ?? '').trim();
      if (!acceptedTypes.contains(type) || name.isEmpty || !seen.add(name)) {
        continue;
      }
      names.add(name);
    }

    return names;
  }

  String _authorizationHeader({
    required String deviceId,
    String token = '',
  }) {
    final safeDeviceId =
        deviceId.trim().isEmpty ? _generateDeviceId() : deviceId;
    final attributes = <String>[
      'Client="$_clientName"',
      'Device="$_deviceName"',
      'DeviceId="$safeDeviceId"',
      'Version="$_appVersion"',
      if (token.trim().isNotEmpty) 'Token="${token.trim()}"',
    ];
    return 'Emby ${attributes.join(', ')}';
  }

  String _generateDeviceId() {
    final random = Random.secure();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'starflow-$timestamp-${random.nextInt(1 << 32)}';
  }

  bool _supportsVideoBrowsing(Map<String, dynamic> item) {
    final collectionType =
        (item['CollectionType'] as String? ?? '').trim().toLowerCase();
    if (collectionType.isEmpty) {
      return true;
    }

    return switch (collectionType) {
      'movies' || 'tvshows' || 'homevideos' || 'musicvideos' => true,
      _ => false,
    };
  }

  String _viewSubtitle(_EmbyView view) {
    return switch (view.collectionType.trim().toLowerCase()) {
      'movies' => '电影分区',
      'tvshows' => '剧集分区',
      'homevideos' => '家庭视频',
      'musicvideos' => '音乐视频',
      _ => 'Emby 分区',
    };
  }

  static bool _pathEndsWithEmby(String path) {
    final trimmed = _trimTrailingSlash(path);
    final segments = trimmed.split('/').where((segment) => segment.isNotEmpty);
    if (segments.isEmpty) {
      return false;
    }
    return segments.last == 'emby';
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

class EmbySession {
  const EmbySession({
    required this.baseUri,
    required this.accessToken,
    required this.userId,
    required this.username,
    required this.serverId,
    required this.deviceId,
  });

  final Uri baseUri;
  final String accessToken;
  final String userId;
  final String username;
  final String serverId;
  final String deviceId;
}

class EmbyApiException implements Exception {
  const EmbyApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _EmbyJsonResponse {
  const _EmbyJsonResponse({
    required this.baseUri,
    required this.json,
  });

  final Uri baseUri;
  final Map<String, dynamic> json;
}

class _EmbyView {
  const _EmbyView({
    required this.id,
    required this.title,
    required this.collectionType,
  });

  final String id;
  final String title;
  final String collectionType;
}
