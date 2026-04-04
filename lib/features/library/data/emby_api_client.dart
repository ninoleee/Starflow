import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

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

    if (sectionId != null && sectionId.trim().isNotEmpty) {
      final sectionItems = await _fetchSectionItems(
        source: source,
        limit: limit,
        sectionId: sectionId,
        sectionName: sectionName,
      );
      return sectionItems;
    }

    final views = await fetchCollections(source);
    if (views.isNotEmpty) {
      final groupedItems = await Future.wait(
        views.map(
          (view) => _fetchSectionItems(
            source: source,
            limit: limit,
            sectionId: view.id,
            sectionName: view.title,
          ),
        ),
      );

      final resolved = _dedupeAndSort(
        groupedItems.expand((items) => items).toList(),
        limit: limit,
      );
      if (resolved.isNotEmpty) {
        return resolved;
      }
    }

    return _fetchItems(
      source: source,
      limit: limit,
      queryMode: _EmbyItemsQueryMode.recursivePlayable,
    );
  }

  Future<PlaybackTarget> resolvePlaybackTarget({
    required MediaSourceConfig source,
    required PlaybackTarget target,
  }) async {
    if (target.streamUrl.trim().isNotEmpty) {
      return target;
    }
    if (target.itemId.trim().isEmpty) {
      throw const EmbyApiException('没有可解析的 Emby 播放目标');
    }
    if (!source.hasActiveSession) {
      throw const EmbyApiException('Emby 会话已失效，请重新登录');
    }

    final response = await _requestJson(
      source.endpoint,
      path: 'Items/${target.itemId}/PlaybackInfo',
      method: 'GET',
      token: source.accessToken,
      deviceId: source.deviceId,
      query: {
        'UserId': source.userId,
        'StartTimeTicks': '0',
        'IsPlayback': 'true',
        if (target.preferredMediaSourceId.trim().isNotEmpty)
          'MediaSourceId': target.preferredMediaSourceId.trim(),
      },
    );

    final playSessionId = response.json['PlaySessionId'] as String? ?? '';
    final mediaSources =
        (response.json['MediaSources'] as List<dynamic>? ?? const [])
            .map((entry) => Map<String, dynamic>.from(entry as Map))
            .toList();
    final selectedSource = _selectPlaybackMediaSource(
      mediaSources: mediaSources,
      preferredMediaSourceId: target.preferredMediaSourceId,
    );

    if (selectedSource == null) {
      throw const EmbyApiException('Emby 没有返回可用的播放地址');
    }

    final resolvedUri = _resolvePlaybackUri(
      baseUri: response.baseUri,
      itemId: target.itemId,
      mediaSource: selectedSource,
      accessToken: source.accessToken,
      playSessionId: playSessionId,
    );
    final requiredHeaders = Map<String, dynamic>.from(
      selectedSource['RequiredHttpHeaders'] as Map? ?? const {},
    );

    return PlaybackTarget(
      title: target.title,
      sourceId: target.sourceId,
      itemId: target.itemId,
      preferredMediaSourceId: selectedSource['Id'] as String? ?? '',
      streamUrl: resolvedUri.toString(),
      sourceName: target.sourceName,
      sourceKind: target.sourceKind,
      subtitle: target.subtitle,
      headers: {
        ...requiredHeaders
            .map((key, value) => MapEntry(key.toString(), value.toString())),
        'X-Emby-Token': source.accessToken,
        'X-Emby-Authorization': _authorizationHeader(
          token: source.accessToken,
          deviceId: source.deviceId,
        ),
      },
    );
  }

  Future<List<MediaItem>> fetchChildren(
    MediaSourceConfig source, {
    required String parentId,
    String sectionId = '',
    String sectionName = '',
    int limit = 200,
  }) async {
    if (!source.hasActiveSession || parentId.trim().isEmpty) {
      return const [];
    }

    final items = await _fetchItems(
      source: source,
      limit: limit,
      parentId: parentId,
      sectionId: sectionId,
      sectionName: sectionName,
      queryMode: _EmbyItemsQueryMode.hierarchyBrowse,
    );
    return _sortHierarchyItems(items);
  }

  Future<List<MediaItem>> _fetchSectionItems({
    required MediaSourceConfig source,
    required int limit,
    required String sectionId,
    required String sectionName,
  }) async {
    final browseItems = await _fetchItems(
      source: source,
      limit: limit,
      parentId: sectionId,
      sectionId: sectionId,
      sectionName: sectionName,
      queryMode: _EmbyItemsQueryMode.genericBrowse,
    );
    final sectionTreeItems = await _scanSectionTree(
      source: source,
      rootItems: browseItems,
      limit: limit,
      sectionId: sectionId,
      sectionName: sectionName,
    );
    if (sectionTreeItems.isNotEmpty) {
      return sectionTreeItems;
    }

    try {
      final recursiveItems = await _fetchItems(
        source: source,
        limit: limit,
        parentId: sectionId,
        sectionId: sectionId,
        sectionName: sectionName,
        queryMode: _EmbyItemsQueryMode.recursivePlayable,
      );
      if (recursiveItems.isNotEmpty) {
        return recursiveItems;
      }
    } catch (_) {
      if (browseItems.isEmpty) {
        rethrow;
      }
    }

    return browseItems;
  }

  Future<List<MediaItem>> _scanSectionTree({
    required MediaSourceConfig source,
    required List<MediaItem> rootItems,
    required int limit,
    required String sectionId,
    required String sectionName,
  }) async {
    final queue = ListQueue<_EmbyFolderCursor>.from(
      rootItems
          .where((item) =>
              _classifyBrowseItem(item) == _EmbyBrowseItemKind.recurse)
          .take(limit)
          .map((folder) => _EmbyFolderCursor(folder.id, 1)),
    );
    final visited = <String>{sectionId};
    final preferredItems = <MediaItem>[
      for (final item in rootItems)
        if (_classifyBrowseItem(item) == _EmbyBrowseItemKind.preferredContent)
          item,
    ];
    final episodeFallback = <MediaItem>[
      for (final item in rootItems)
        if (_classifyBrowseItem(item) == _EmbyBrowseItemKind.episodeFallback)
          item,
    ];

    while (queue.isNotEmpty &&
        preferredItems.length < limit &&
        episodeFallback.length < limit) {
      final cursor = queue.removeFirst();
      if (!visited.add(cursor.parentId)) {
        continue;
      }

      try {
        final items = await _fetchItems(
          source: source,
          limit: limit,
          parentId: cursor.parentId,
          sectionId: sectionId,
          sectionName: sectionName,
          queryMode: _EmbyItemsQueryMode.genericBrowse,
        );
        for (final item in items) {
          switch (_classifyBrowseItem(item)) {
            case _EmbyBrowseItemKind.preferredContent:
              preferredItems.add(item);
              break;
            case _EmbyBrowseItemKind.episodeFallback:
              episodeFallback.add(item);
              break;
            case _EmbyBrowseItemKind.recurse:
              if (cursor.depth < 5) {
                queue.add(_EmbyFolderCursor(item.id, cursor.depth + 1));
              }
              break;
            case _EmbyBrowseItemKind.ignore:
              break;
          }
        }
      } catch (_) {
        continue;
      }
    }

    if (preferredItems.isNotEmpty) {
      return _dedupeAndSort(preferredItems, limit: limit);
    }
    if (episodeFallback.isNotEmpty) {
      return _dedupeAndSort(episodeFallback, limit: limit);
    }
    return const [];
  }

  Future<List<MediaItem>> _fetchItems({
    required MediaSourceConfig source,
    required int limit,
    String? parentId,
    String? sectionId,
    String sectionName = '',
    _EmbyItemsQueryMode queryMode = _EmbyItemsQueryMode.recursivePlayable,
  }) async {
    final response = await _requestJson(
      source.endpoint,
      path: 'Users/${source.userId}/Items',
      method: 'GET',
      token: source.accessToken,
      deviceId: source.deviceId,
      query: _buildItemsQuery(
        limit: limit,
        parentId: parentId,
        queryMode: queryMode,
      ),
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
    final itemType = (item['Type'] as String? ?? '').trim();
    final mediaType = (item['MediaType'] as String? ?? '').trim().toLowerCase();
    final originalTitle = (item['OriginalTitle'] as String? ?? '').trim();
    final sortTitle = (item['SortName'] as String? ?? '').trim();
    final isFolder =
        item['IsFolder'] as bool? ?? _isFolderLikeItemType(itemType);
    final canResolvePlayback = !isFolder &&
        (mediaSource != null ||
            mediaType == 'video' ||
            _isDirectPlayableItemType(itemType));
    final overview = item['Overview'] as String? ?? '';
    final productionYear = item['ProductionYear'] as int? ?? 0;
    final genres = (item['Genres'] as List<dynamic>? ?? const [])
        .map((entry) => '$entry')
        .toList();
    final directors = _resolvePeople(item, const {'director'});
    final actors = _resolvePeople(item, const {'actor', 'gueststar'});
    final createdAt = DateTime.tryParse(item['DateCreated'] as String? ?? '') ??
        DateTime.now();
    final userData = item['UserData'] as Map<String, dynamic>? ?? const {};
    final lastPlayedAt = DateTime.tryParse(
      userData['LastPlayedDate'] as String? ?? '',
    );
    final runTimeTicks = item['RunTimeTicks'] as int?;
    final durationLabel = formatRunTimeTicks(runTimeTicks);
    final playbackProgress =
        _resolvePlaybackProgress(userData, runTimeTicks: runTimeTicks);
    final rawIndexNumber = item['IndexNumber'] as int?;
    final rawParentIndexNumber = item['ParentIndexNumber'] as int?;
    final seasonNumber = itemType.trim().toLowerCase() == 'season'
        ? rawIndexNumber
        : rawParentIndexNumber;
    final episodeNumber =
        itemType.trim().toLowerCase() == 'episode' ? rawIndexNumber : null;
    final imageTag = _resolvePrimaryImageTag(item);

    return MediaItem(
      id: id,
      title: title,
      originalTitle: originalTitle,
      sortTitle: sortTitle,
      overview: overview,
      posterUrl: imageTag.isEmpty
          ? ''
          : buildPosterUri(
              baseUri: baseUri,
              itemId: id,
              imageTag: imageTag,
              accessToken: source.accessToken,
            ).toString(),
      year: productionYear,
      durationLabel: durationLabel,
      genres: genres,
      directors: directors,
      actors: actors,
      itemType: itemType,
      isFolder: isFolder,
      sectionId: (sectionId ?? '').trim(),
      sectionName: sectionName.trim(),
      sourceId: source.id,
      sourceName: source.name,
      sourceKind: source.kind,
      streamUrl: '',
      streamHeaders: const {},
      playbackItemId: canResolvePlayback ? id : '',
      preferredMediaSourceId: mediaSource?['Id'] as String? ?? '',
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      playbackProgress: playbackProgress,
      addedAt: createdAt,
      lastWatchedAt: lastPlayedAt,
    );
  }

  Map<String, String> _buildItemsQuery({
    required int limit,
    required _EmbyItemsQueryMode queryMode,
    String? parentId,
  }) {
    final query = <String, String>{
      'Fields':
          'DateCreated,Genres,IndexNumber,OriginalTitle,Overview,ParentIndexNumber,Path,People,ProductionYear,RunTimeTicks,SortName',
      'EnableImages': 'true',
      'EnableImageTypes': 'Primary',
      'ImageTypeLimit': '1',
      'EnableUserData': 'true',
      'SortBy': 'DateCreated,SortName',
      'SortOrder': 'Descending,Ascending',
      'Limit': '$limit',
      if (parentId != null && parentId.trim().isNotEmpty)
        'ParentId': parentId.trim(),
    };

    switch (queryMode) {
      case _EmbyItemsQueryMode.recursivePlayable:
        query.addAll({
          'Recursive': 'true',
          'IncludeItemTypes': 'Movie,Episode,Video',
          'Filters': 'IsNotFolder',
          'MediaTypes': 'Video',
        });
        break;
      case _EmbyItemsQueryMode.genericBrowse:
        query.addAll({
          'Recursive': 'false',
        });
        break;
      case _EmbyItemsQueryMode.hierarchyBrowse:
        query.addAll({
          'Recursive': 'false',
          'SortBy': 'SortName',
          'SortOrder': 'Ascending',
        });
        break;
    }

    return query;
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
    String playSessionId = '',
  }) {
    final safeContainer = container.trim().isEmpty ? 'mp4' : container.trim();
    return baseUri.replace(
      path: _joinPath(baseUri.path, 'Videos/$itemId/stream.$safeContainer'),
      queryParameters: {
        'static': 'true',
        if (mediaSourceId.trim().isNotEmpty) 'MediaSourceId': mediaSourceId,
        if (playSessionId.trim().isNotEmpty) 'PlaySessionId': playSessionId,
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

  static double? _resolvePlaybackProgress(
    Map<String, dynamic> userData, {
    required int? runTimeTicks,
  }) {
    final playedPercentage = (userData['PlayedPercentage'] as num?)?.toDouble();
    if (playedPercentage != null && playedPercentage > 0) {
      return (playedPercentage / 100).clamp(0.0, 1.0);
    }

    final playbackPositionTicks =
        (userData['PlaybackPositionTicks'] as num?)?.toDouble();
    if (playbackPositionTicks != null &&
        playbackPositionTicks > 0 &&
        runTimeTicks != null &&
        runTimeTicks > 0) {
      return (playbackPositionTicks / runTimeTicks).clamp(0.0, 1.0);
    }

    final played = userData['Played'] as bool?;
    if (played == true) {
      return 1.0;
    }

    return null;
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

  Map<String, dynamic>? _selectPlaybackMediaSource({
    required List<Map<String, dynamic>> mediaSources,
    required String preferredMediaSourceId,
  }) {
    if (mediaSources.isEmpty) {
      return null;
    }

    final preferredId = preferredMediaSourceId.trim();
    if (preferredId.isNotEmpty) {
      for (final source in mediaSources) {
        if ((source['Id'] as String? ?? '').trim() == preferredId) {
          return source;
        }
      }
    }

    for (final source in mediaSources) {
      if ((source['DirectStreamUrl'] as String? ?? '').trim().isNotEmpty) {
        return source;
      }
    }

    for (final source in mediaSources) {
      if ((source['TranscodingUrl'] as String? ?? '').trim().isNotEmpty) {
        return source;
      }
    }

    return mediaSources.first;
  }

  Uri _resolvePlaybackUri({
    required Uri baseUri,
    required String itemId,
    required Map<String, dynamic> mediaSource,
    required String accessToken,
    required String playSessionId,
  }) {
    final directStreamUrl =
        (mediaSource['DirectStreamUrl'] as String? ?? '').trim();
    final transcodingUrl =
        (mediaSource['TranscodingUrl'] as String? ?? '').trim();
    final addApiKey =
        mediaSource['AddApiKeyToDirectStreamUrl'] as bool? ?? false;

    if (directStreamUrl.isNotEmpty) {
      return _resolveRelativeStreamUri(
        baseUri: baseUri,
        rawUrl: directStreamUrl,
        accessToken: accessToken,
        addApiKey: addApiKey,
      );
    }

    if (transcodingUrl.isNotEmpty) {
      return _resolveRelativeStreamUri(
        baseUri: baseUri,
        rawUrl: transcodingUrl,
        accessToken: accessToken,
        addApiKey: addApiKey,
      );
    }

    return buildDirectStreamUri(
      baseUri: baseUri,
      itemId: itemId,
      container: mediaSource['Container'] as String? ?? 'mp4',
      mediaSourceId: mediaSource['Id'] as String? ?? '',
      accessToken: accessToken,
      playSessionId: playSessionId,
    );
  }

  Uri _resolveRelativeStreamUri({
    required Uri baseUri,
    required String rawUrl,
    required String accessToken,
    required bool addApiKey,
  }) {
    final parsed = Uri.parse(rawUrl);
    final normalizedBasePath = _trimTrailingSlash(baseUri.path);
    final hasEmbeddedBasePath = normalizedBasePath.isNotEmpty &&
        (parsed.path == normalizedBasePath ||
            parsed.path.startsWith('$normalizedBasePath/'));
    final resolved = parsed.hasScheme
        ? parsed
        : baseUri.replace(
            path: hasEmbeddedBasePath
                ? parsed.path
                : _joinPath(baseUri.path, parsed.path),
            queryParameters: parsed.hasQuery ? parsed.queryParameters : null,
          );

    if (!addApiKey || accessToken.trim().isEmpty) {
      return resolved;
    }
    if (resolved.queryParameters.containsKey('api_key')) {
      return resolved;
    }

    final queryParameters = Map<String, String>.from(resolved.queryParameters)
      ..['api_key'] = accessToken.trim();
    return resolved.replace(queryParameters: queryParameters);
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

  List<MediaItem> _sortHierarchyItems(List<MediaItem> items) {
    final sorted = [...items]..sort((left, right) {
        final rankComparison =
            _hierarchyItemRank(left).compareTo(_hierarchyItemRank(right));
        if (rankComparison != 0) {
          return rankComparison;
        }

        final seasonComparison =
            (left.seasonNumber ?? 0).compareTo(right.seasonNumber ?? 0);
        if (seasonComparison != 0) {
          return seasonComparison;
        }

        final episodeComparison =
            (left.episodeNumber ?? 0).compareTo(right.episodeNumber ?? 0);
        if (episodeComparison != 0) {
          return episodeComparison;
        }

        return left.title.toLowerCase().compareTo(right.title.toLowerCase());
      });
    return sorted;
  }

  int _hierarchyItemRank(MediaItem item) {
    return switch (item.itemType.trim().toLowerCase()) {
      'season' => 0,
      'episode' => 1,
      _ when item.isPlayable => 2,
      _ => 3,
    };
  }

  _EmbyBrowseItemKind _classifyBrowseItem(MediaItem item) {
    final itemType = item.itemType.trim().toLowerCase();
    if (item.isPlayable) {
      return itemType == 'episode'
          ? _EmbyBrowseItemKind.episodeFallback
          : _EmbyBrowseItemKind.preferredContent;
    }
    if (!item.isFolder) {
      return _EmbyBrowseItemKind.ignore;
    }

    return switch (itemType) {
      'series' || 'boxset' => _EmbyBrowseItemKind.preferredContent,
      'season' || 'folder' || 'collectionfolder' => _EmbyBrowseItemKind.recurse,
      _ => _EmbyBrowseItemKind.recurse,
    };
  }

  bool _isDirectPlayableItemType(String itemType) {
    return switch (itemType.trim().toLowerCase()) {
      'movie' || 'episode' || 'video' || 'musicvideo' => true,
      _ => false,
    };
  }

  bool _isFolderLikeItemType(String itemType) {
    return switch (itemType.trim().toLowerCase()) {
      'series' || 'season' || 'boxset' || 'folder' => true,
      _ => false,
    };
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

enum _EmbyItemsQueryMode {
  recursivePlayable,
  genericBrowse,
  hierarchyBrowse,
}

enum _EmbyBrowseItemKind {
  preferredContent,
  episodeFallback,
  recurse,
  ignore,
}

class _EmbyFolderCursor {
  const _EmbyFolderCursor(this.parentId, this.depth);

  final String parentId;
  final int depth;
}
