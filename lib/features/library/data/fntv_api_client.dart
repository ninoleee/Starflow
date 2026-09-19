import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/core/network/starflow_http_client.dart';
import 'package:starflow/features/library/data/media_server_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

final fntvApiClientProvider = Provider<FntvApiClient>(
  (ref) => FntvApiClient(ref.watch(starflowHttpClientProvider)),
);

/// Direct-address fnOS Video v1 client. Playback uses the NAS range endpoint,
/// leaving seeking and container support to the selected player.
class FntvApiClient implements MediaServerClient {
  FntvApiClient(this._client);

  final http.Client _client;
  static const _apiPath = '/v/api/v1';
  // Public web-client signing constants, not account credentials.
  static const _apiKey = 'NDzZTVxnRKP8Z0jXg1VAMonaG8akvh';
  static const _apiSecret = '16CCEB3D-AB42-077D-36A1-F355324E4237';
  static const _playbackUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36';
  static const _browseTypes = <String>[
    'Movie',
    'TV',
    'Directory',
    'Video',
    'LiveChannel',
  ];

  static Uri baseUri(String endpoint) {
    final uri = Uri.tryParse(endpoint.trim());
    if (uri == null ||
        !const ['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FntvApiException('请填写完整的飞牛影视 HTTP / HTTPS 服务器地址');
    }
    var path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    if (path.endsWith(_apiPath)) {
      path = path.substring(0, path.length - _apiPath.length);
    } else if (path.endsWith('/v')) {
      path = path.substring(0, path.length - 2);
    }
    return uri.replace(path: path);
  }

  static Map<String, String> sessionHeaders(MediaSourceConfig source) => {
        if (source.hasAccessToken) 'Authorization': source.accessToken.trim(),
        if (source.hasAccessToken)
          'Cookie': 'Trim-MC-token=${source.accessToken.trim()}',
      };

  static Map<String, String> imageHeaders(
      MediaSourceConfig source, String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
            const ['http', 'https'].contains(uri.scheme) &&
            uri.host.isNotEmpty &&
            uri.origin == baseUri(source.endpoint).origin
        ? sessionHeaders(source)
        : const {};
  }

  static String buildAuthx({
    required String path,
    required String nonce,
    required int timestamp,
    String body = '',
    Map<String, String> query = const {},
  }) {
    final keys = query.keys.toList()..sort();
    final data = body.isNotEmpty
        ? body
        : keys.map((key) => '$key=${query[key]}').join('&');
    String digest(String value) => md5.convert(utf8.encode(value)).toString();
    final sign = digest(
      [_apiKey, path, nonce, '$timestamp', digest(data), _apiSecret].join('_'),
    );
    return 'nonce=$nonce&timestamp=$timestamp&sign=$sign';
  }

  Future<MediaSourceConfig> authenticate({
    required MediaSourceConfig source,
    required String password,
  }) async {
    final endpoint = baseUri(source.endpoint).toString();
    if (source.username.trim().isEmpty || password.isEmpty) {
      throw const FntvApiException('请填写飞牛影视用户名和密码');
    }
    final draft =
        source.copyWith(endpoint: endpoint, accessToken: '', userId: '');
    final login = _map(await _request(draft, 'login', body: {
      'username': source.username.trim(),
      'password': password,
      'app_name': 'trimemedia-web',
    }));
    final token = _text(login['token']);
    if (token.isEmpty) {
      throw const FntvApiException('飞牛影视没有返回有效登录会话');
    }
    final authenticated = draft.copyWith(accessToken: token);
    final user = _map(await _request(authenticated, 'user/info'));
    final userId = _text(user['guid']);
    if (userId.isEmpty) {
      throw const FntvApiException('飞牛影视没有返回有效用户信息');
    }
    return authenticated.copyWith(
      userId: userId,
      username: _text(user['username']).isEmpty
          ? source.username.trim()
          : _text(user['username']),
    );
  }

  @override
  Future<List<MediaCollection>> fetchCollections(
      MediaSourceConfig source) async {
    _requireSession(source);
    final data = await _request(source, 'mediadb/list');
    if (data is! List) throw const FntvApiException('飞牛影视分区返回格式错误');
    final rows = _rows(data);
    return [
      for (final row in rows)
        if (_text(row['guid']).isNotEmpty &&
            !const ['iptv', 'music']
                .contains(_text(row['category']).toLowerCase()))
          MediaCollection(
            id: _text(row['guid']),
            title: _text(row['title']).isEmpty ? '未命名分区' : _text(row['title']),
            sourceId: source.id,
            sourceName: source.name,
            sourceKind: source.kind,
            subtitle: '飞牛影视',
          ),
    ];
  }

  @override
  Future<List<MediaItem>> fetchLibrary(
    MediaSourceConfig source, {
    int limit = 200,
    String? sectionId,
    String sectionName = '',
  }) async {
    _requireSession(source);
    if (limit <= 0 || source.hasExplicitNoSectionsSelected) return const [];
    final selected = source.selectedSectionIds;
    final section = sectionId?.trim() ?? '';
    if (section.isNotEmpty) {
      if (selected.isNotEmpty && !selected.contains(section)) return const [];
      return _listItems(source,
          limit: limit, sectionId: section, sectionName: sectionName);
    }
    final collections = await fetchCollections(source);
    final items = <String, MediaItem>{};
    for (final collection in collections) {
      if (selected.isNotEmpty && !selected.contains(collection.id)) continue;
      for (final item in await _listItems(source,
          limit: limit,
          sectionId: collection.id,
          sectionName: collection.title)) {
        items[item.id] = item;
      }
    }
    final sorted = items.values.toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return sorted.take(limit).toList(growable: false);
  }

  Future<List<MediaItem>> _listItems(
    MediaSourceConfig source, {
    required int limit,
    String sectionId = '',
    String sectionName = '',
    String parentId = '',
    bool folderListing = false,
  }) async {
    final items = <String, MediaItem>{};
    var seenRows = 0;
    for (var page = 1; items.length < limit; page++) {
      final data = _map(await _request(source, 'item/list', body: {
        if (sectionId.isNotEmpty) 'ancestor_guid': sectionId,
        if (parentId.isNotEmpty) 'parent_guid': parentId,
        // The web client suppresses Episode rows at library level so TV items
        // stay grouped. Folder browsing must keep them visible.
        'exclude_grouped_video': folderListing ? 0 : 1,
        'sort_type': folderListing ? 'ASC' : 'DESC',
        'sort_column': folderListing ? 'sort_title' : 'create_time',
        'page_size': min(limit, 100),
        'page': page,
        'tags': {'type': _browseTypes},
      }));
      if (data['list'] is! List) throw const FntvApiException('飞牛影视条目返回格式错误');
      final rows = _rows(data['list']);
      if (rows.isEmpty) break;
      var added = 0;
      for (final row in rows) {
        final item =
            _item(source, row, sectionId: sectionId, sectionName: sectionName);
        if (item != null && !items.containsKey(item.id)) {
          items[item.id] = item;
          added++;
        }
      }
      seenRows += rows.length;
      final total = _number(data['total']);
      if (added == 0 ||
          rows.length < min(limit, 100) ||
          (total != null && seenRows >= total)) {
        break;
      }
    }
    return items.values.take(limit).toList(growable: false);
  }

  @override
  Future<List<MediaItem>> fetchChildren(
    MediaSourceConfig source, {
    required String parentId,
    String sectionId = '',
    String sectionName = '',
    int limit = 200,
  }) async {
    _requireSession(source);
    if (parentId.isEmpty ||
        limit <= 0 ||
        source.hasExplicitNoSectionsSelected) {
      return const [];
    }
    if (sectionId.isNotEmpty &&
        source.selectedSectionIds.isNotEmpty &&
        !source.selectedSectionIds.contains(sectionId)) {
      return const [];
    }
    final parent =
        _map(await _request(source, 'item/${Uri.encodeComponent(parentId)}'));
    final type = _text(parent['type']).toLowerCase();
    final route = switch (type) {
      'tv' || 'series' => 'season/list',
      'season' => 'episode/list',
      _ => '',
    };
    if (route.isEmpty) {
      return _listItems(source,
          limit: limit,
          parentId: parentId,
          sectionId: sectionId,
          sectionName: sectionName,
          folderListing: true);
    }
    final rows = _rows(
        await _request(source, '$route/${Uri.encodeComponent(parentId)}'));
    final items = rows
        .map((row) =>
            _item(source, row, sectionId: sectionId, sectionName: sectionName))
        .whereType<MediaItem>()
        .toList();
    items.sort((a, b) {
      final season = (a.seasonNumber ?? 0).compareTo(b.seasonNumber ?? 0);
      return season != 0
          ? season
          : (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0);
    });
    return items.take(limit).toList(growable: false);
  }

  Future<void> requestLibraryRefresh(MediaSourceConfig source) async {
    _requireSession(source);
    if (source.hasExplicitNoSectionsSelected) return;
    var sectionIds = source.selectedSectionIds.toList(growable: false);
    if (sectionIds.isEmpty) {
      sectionIds = (await fetchCollections(source))
          .map((collection) => collection.id)
          .where((id) => id.trim().isNotEmpty)
          .toList(growable: false);
    }
    for (final sectionId in sectionIds) {
      await _request(
        source,
        'item/refresh',
        operation: '通知媒体库刷新',
        body: {'item_guid': sectionId.trim()},
      );
    }
  }

  @override
  Future<PlaybackTarget> resolvePlaybackTarget({
    required MediaSourceConfig source,
    required PlaybackTarget target,
  }) async {
    _requireSession(source);
    if (target.itemId.isEmpty) {
      throw const FntvApiException('没有可解析的飞牛影视播放目标');
    }
    final info =
        _map(await _request(source, 'play/info', operation: '读取播放信息', body: {
      'item_guid': target.itemId,
      if (target.preferredMediaSourceId.isNotEmpty)
        'media_guid': target.preferredMediaSourceId,
    }));
    final mediaId = target.preferredMediaSourceId.isNotEmpty
        ? target.preferredMediaSourceId
        : _text(info['media_guid']);
    if (mediaId.isEmpty) {
      throw const FntvApiException('飞牛影视没有返回可播放文件');
    }
    final stream =
        _map(await _request(source, 'stream', operation: '解析媒体流', body: {
      'media_guid': mediaId,
      // fnOS calls the session's MD5 digest "ip"; it is not a device address.
      'ip': md5.convert(utf8.encode(source.accessToken.trim())).toString(),
      'level': 1,
      'header': {
        'User-Agent': [_playbackUserAgent],
      },
    }));
    final file = _map(stream['file_stream']);
    if (_number(file['can_play']) == 0) {
      throw const FntvApiException('飞牛影视文件当前不可播放');
    }
    final video = _map(stream['video_stream']);
    final audioStreams = _rows(stream['audio_streams'])
        .map(_audioStream)
        .whereType<PlaybackAudioStream>()
        .toList(growable: false);
    final subtitleStreams = _rows(stream['subtitle_streams'])
        .map(_subtitleStream)
        .whereType<PlaybackSubtitleStream>()
        .toList(growable: false);
    final cloud = _map(stream['cloud_storage_info']);
    final qualities = _rows(stream['direct_link_qualities'])
        .asMap()
        .entries
        .map((entry) => _playbackQuality(entry.key, entry.value))
        .whereType<FntvPlaybackQuality>()
        .toList(growable: false);
    var url = _uri(source, 'media/range/${Uri.encodeComponent(mediaId)}');
    final cloudType = _number(cloud['cloud_storage_type']);
    final selectedQuality = qualities.isEmpty
        ? null
        : qualities.firstWhere(
            (quality) => quality.index == target.preferredPlaybackQualityIndex,
            orElse: () => qualities.first,
          );
    if (qualities.isNotEmpty) {
      final quality = selectedQuality!;
      if (const [2, 5, 9001].contains(cloudType) ||
          (cloudType == 3 && !quality.isM3u8)) {
        final direct = Uri.tryParse(quality.url);
        if (direct == null ||
            !const ['http', 'https'].contains(direct.scheme) ||
            direct.host.isEmpty) {
          throw const FntvApiException('飞牛影视返回了无效播放地址');
        }
        url = direct;
      } else {
        url = url.replace(queryParameters: {
          'direct_link_quality_index': '${quality.index}',
        });
      }
    }
    final sameOrigin = url.origin == baseUri(source.endpoint).origin;
    final providerHeaders = _map(stream['header']);
    final headers = <String, String>{
      if (sameOrigin ||
          !providerHeaders.keys.any((key) => key.toLowerCase() == 'user-agent'))
        'User-Agent': _playbackUserAgent,
      if (sameOrigin) ...sessionHeaders(source),
      if (sameOrigin && providerHeaders.isNotEmpty)
        'X-Wp-Header': jsonEncode(providerHeaders),
      if (!sameOrigin)
        for (final entry in providerHeaders.entries)
          if (!const ['authorization', 'cookie', 'host', 'authx']
              .contains(entry.key.toLowerCase()))
            entry.key: entry.value is List
                ? (entry.value as List).join(', ')
                : '${entry.value}',
    };
    final path = _text(file['path']);
    return target.copyWith(
      streamUrl: url.toString(),
      preferredMediaSourceId: mediaId,
      actualAddress: path.isEmpty ? target.actualAddress : path,
      headers: headers,
      posterHeaders: imageHeaders(source, target.posterUrl),
      backdropHeaders: imageHeaders(source, target.backdropUrl),
      width: _number(video['width']),
      height: _number(video['height']),
      bitrate: _number(video['bps']) ?? _number(video['bit_rate']),
      container: _text(video['wrapper']),
      fileSizeBytes: _number(file['size']),
      videoCodec: _text(video['codec_name']),
      audioCodec: audioStreams.isEmpty ? '' : audioStreams.first.codec,
      audioStreams: audioStreams,
      subtitleStreams: subtitleStreams,
      preferredAudioStreamId: _text(info['audio_guid']),
      preferredSubtitleStreamId: _text(info['subtitle_guid']),
      videoStreamId: _text(video['guid']),
      playbackQualities: qualities,
      preferredPlaybackQualityIndex: selectedQuality?.index,
    );
  }

  @override
  Future<List<PlaybackTarget>> fetchPlaybackVariants({
    required MediaSourceConfig source,
    required PlaybackTarget target,
  }) async {
    _requireSession(source);
    final data = _map(await _request(
        source, 'stream/list/${Uri.encodeComponent(target.itemId)}'));
    return [
      for (final file in _rows(data['files']))
        if (_text(file['guid']).isNotEmpty && _number(file['can_play']) != 0)
          target.copyWith(
              streamUrl: '',
              preferredMediaSourceId: _text(file['guid']),
              actualAddress: _text(file['path']),
              fileSizeBytes: _number(file['size']),
              headers: const {}),
    ];
  }

  @override
  Future<String> downloadExternalSubtitle({
    required MediaSourceConfig source,
    required String subtitleId,
  }) async {
    _requireSession(source);
    final normalizedId = subtitleId.trim();
    if (normalizedId.isEmpty) {
      throw const FntvApiException('没有可下载的飞牛字幕');
    }
    return _requestText(
      source,
      'subtitle/dl/${Uri.encodeComponent(normalizedId)}',
      operation: '下载字幕',
    );
  }

  @override
  Future<List<int>> downloadExternalSubtitleBytes({
    required MediaSourceConfig source,
    required String subtitleId,
  }) async {
    _requireSession(source);
    final normalizedId = subtitleId.trim();
    if (normalizedId.isEmpty) {
      throw const FntvApiException('没有可下载的飞牛字幕');
    }
    return _requestBytes(
      source,
      'subtitle/dl/${Uri.encodeComponent(normalizedId)}',
      operation: '下载字幕',
    );
  }

  @override
  Future<void> reportPlaybackProgress({
    required MediaSourceConfig source,
    required PlaybackTarget target,
    required Duration position,
    required Duration duration,
  }) async {
    _requireSession(source);
    final itemGuid = target.itemId.trim();
    final mediaGuid = target.preferredMediaSourceId.trim();
    final videoGuid = target.videoStreamId.trim();
    if (itemGuid.isEmpty || mediaGuid.isEmpty || videoGuid.isEmpty) return;
    final safeDuration = duration.inSeconds.clamp(0, 2147483647);
    final safePosition = position.inSeconds.clamp(0, safeDuration);
    final deviceId = source.deviceId.trim().isNotEmpty
        ? source.deviceId.trim()
        : md5
            .convert(utf8.encode('${source.endpoint}\n${source.userId}'))
            .toString();
    final selectedQuality =
        target.playbackQualities.cast<FntvPlaybackQuality?>().firstWhere(
              (quality) =>
                  quality?.index == (target.preferredPlaybackQualityIndex ?? 0),
              orElse: () => null,
            );
    await _request(source, 'play/record', operation: '回写播放进度', body: {
      'item_guid': itemGuid,
      'media_guid': mediaGuid,
      'video_guid': videoGuid,
      'audio_guid': target.preferredAudioStreamId,
      'subtitle_guid': target.preferredSubtitleStreamId,
      'resolution': selectedQuality?.resolution.isNotEmpty == true
          ? selectedQuality!.resolution
          : target.resolutionLabel,
      'bitrate': selectedQuality?.bitrate ?? target.bitrate ?? 0,
      'ts': safePosition,
      'duration': safeDuration,
      'play_link': target.streamUrl,
      'device_id': deviceId,
      'direct_link_audio_index': -1,
      'lan': 'zh-CN',
      'device_name': 'Starflow',
    });
  }

  FntvPlaybackQuality? _playbackQuality(
    int index,
    Map<String, dynamic> row,
  ) {
    final url = _text(row['url']);
    final resolution = _text(row['resolution']).isNotEmpty
        ? _text(row['resolution'])
        : _text(row['resolution_type']);
    final bitrate = _number(row['bitrate']) ?? _number(row['bps']) ?? 0;
    final isM3u8 = row['is_m3u8'] == true || _number(row['is_m3u8']) == 1;
    final progressive =
        row['progressive'] == true || _number(row['progressive']) == 1;
    if (url.isEmpty && resolution.isEmpty && bitrate <= 0) return null;
    return FntvPlaybackQuality(
      index: index,
      resolution: resolution,
      bitrate: bitrate,
      url: url,
      isM3u8: isM3u8,
      progressive: progressive,
    );
  }

  PlaybackAudioStream? _audioStream(Map<String, dynamic> row) {
    final id = _text(row['guid']);
    if (id.isEmpty) return null;
    return PlaybackAudioStream(
      id: id,
      title: _text(row['title']),
      language: _text(row['language']),
      codec: _text(row['codec_name']),
      channels: _number(row['channels']) ?? 0,
      isDefault: _number(row['is_default']) == 1,
      index: _number(row['index']) ?? 0,
    );
  }

  PlaybackSubtitleStream? _subtitleStream(Map<String, dynamic> row) {
    final id = _text(row['guid']);
    if (id.isEmpty) return null;
    return PlaybackSubtitleStream(
      id: id,
      title: _text(row['title']),
      language: _text(row['language']),
      codec: _text(row['codec_name']).isEmpty
          ? _text(row['format'])
          : _text(row['codec_name']),
      isDefault: _number(row['is_default']) == 1,
      isForced: _number(row['forced']) == 1,
      isExternal: _number(row['is_external']) == 1,
      isBitmap: _number(row['is_bitmap']) == 1,
      index: _number(row['index']) ?? 0,
    );
  }

  MediaItem? _item(
    MediaSourceConfig source,
    Map<String, dynamic> row, {
    String sectionId = '',
    String sectionName = '',
  }) {
    final id = _text(row['guid']);
    final title = _text(row['title']);
    if (id.isEmpty || title.isEmpty) return null;
    final type = switch (_text(row['type']).toLowerCase()) {
      'tv' => 'Series',
      'directory' => 'Folder',
      final value => value,
    };
    final folder =
        const ['series', 'season', 'folder'].contains(type.toLowerCase());
    final playable =
        const ['movie', 'episode', 'video'].contains(type.toLowerCase());
    final posterPaths = row['poster_list'];
    final poster = _imageUri(
        source,
        [
          _text(row['poster']),
          _text(row['posters']),
          if (posterPaths is List && posterPaths.isNotEmpty)
            _text(posterPaths.first),
        ].firstWhere((path) => path.isNotEmpty, orElse: () => ''));
    final backdrop = _imageUri(source, _text(row['backdrops']));
    final duration = _number(row['duration']) ?? 0;
    final ts = _number(row['ts']) ?? _number(row['watched_ts']) ?? 0;
    final date = _text(row['release_date']).isNotEmpty
        ? _text(row['release_date'])
        : _text(row['first_air_date']);
    final created = _number(row['create_time']);
    return MediaItem(
      id: id,
      title: title,
      originalTitle: _text(row['original_title']),
      overview: _text(row['overview']),
      posterUrl: poster,
      posterHeaders: imageHeaders(source, poster),
      backdropUrl: backdrop,
      backdropHeaders: imageHeaders(source, backdrop),
      year: DateTime.tryParse(date)?.year ?? 0,
      durationLabel: duration > 0 ? '${duration ~/ 60}m' : '时长未知',
      genres: const [],
      itemType: type,
      isFolder: folder,
      sectionId: sectionId.isEmpty ? _text(row['ancestor_guid']) : sectionId,
      sectionName:
          sectionName.isEmpty ? _text(row['ancestor_name']) : sectionName,
      sourceId: source.id,
      sourceName: source.name,
      sourceKind: source.kind,
      streamUrl: '',
      playbackItemId: playable ? id : '',
      seasonNumber: _number(row['season_number']),
      episodeNumber: type.toLowerCase() == 'episode'
          ? _number(row['episode_number'])
          : null,
      imdbId: _text(row['imdb_id']),
      tmdbId: _text(row['tmdb_id']),
      doubanId: _text(row['douban_id']),
      playbackProgress: _number(row['watched']) == 1
          ? 1
          : duration > 0 && ts > 0
              ? (ts / duration).clamp(0.0, 1.0)
              : null,
      addedAt: created == null
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.fromMillisecondsSinceEpoch(
              created < 100000000000 ? created * 1000 : created),
    );
  }

  String _imageUri(MediaSourceConfig source, String path) {
    if (path.isEmpty) return '';
    final parsed = Uri.tryParse(path);
    if (parsed == null) return '';
    if (parsed.hasScheme) {
      return const ['http', 'https'].contains(parsed.scheme) &&
              parsed.host.isNotEmpty
          ? parsed.toString()
          : '';
    }
    final normalizedPath = '/${parsed.path.replaceFirst(RegExp(r'^/+'), '')}';
    final imagePath = normalizedPath.startsWith('$_apiPath/sys/img')
        ? normalizedPath
        : '$_apiPath/sys/img$normalizedPath';
    return baseUri(source.endpoint).replace(
      path: '${baseUri(source.endpoint).path}$imagePath',
      queryParameters: {...parsed.queryParameters, 'w': '480'},
    ).toString();
  }

  Uri _uri(MediaSourceConfig source, String route) {
    final base = baseUri(source.endpoint);
    return base.replace(path: '${base.path}$_apiPath/$route');
  }

  Future<Object?> _request(
    MediaSourceConfig source,
    String route, {
    Map<String, dynamic>? body,
    String operation = '请求',
  }) async {
    final uri = _uri(source, route);
    final encoded = body == null ? '' : jsonEncode(body);
    final request = http.Request(body == null ? 'GET' : 'POST', uri)
      ..followRedirects = false
      ..headers.addAll({
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'User-Agent': 'Starflow',
        'x-trim-client': 'web',
        'x-trim-client-version': '616',
        ...sessionHeaders(source),
        'Authx': buildAuthx(
            path: '$_apiPath/$route',
            body: encoded,
            nonce: '${100000 + Random.secure().nextInt(900000)}',
            timestamp: DateTime.now().millisecondsSinceEpoch),
      });
    if (body != null) request.body = encoded;
    final response = await (() async =>
            http.Response.fromStream(await _client.send(request)))()
        .timeout(const Duration(seconds: 20));
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const FntvApiException('飞牛影视登录失效或无访问权限，请重新测试登录');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FntvApiException('飞牛影视请求失败：HTTP ${response.statusCode}，请检查服务器地址');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const FntvApiException('飞牛影视返回格式错误，请检查是否填写了影视服务地址');
    }
    if (decoded is List && route.startsWith('episode/list/')) return decoded;
    if (decoded is! Map || _number(decoded['code']) != 0) {
      // Do not echo arbitrary server text: it may contain credentials or URLs.
      final code = decoded is Map ? _number(decoded['code']) : null;
      appLogWarning(
        'library.fntv',
        'FNTV API returned a business error',
        fields: {
          'operation': operation,
          'statusCode': response.statusCode,
          'businessCode': code,
        },
      );
      throw FntvApiException('飞牛影视$operation未成功（错误码 ${code ?? '未知'}）');
    }
    return decoded['data'];
  }

  Future<String> _requestText(
    MediaSourceConfig source,
    String route, {
    String operation = '请求',
  }) async {
    final uri = _uri(source, route);
    final request = http.Request('GET', uri)
      ..followRedirects = false
      ..headers.addAll({
        'Accept': '*/*',
        'User-Agent': 'Starflow',
        'x-trim-client': 'web',
        'x-trim-client-version': '616',
        ...sessionHeaders(source),
        'Authx': buildAuthx(
          path: '$_apiPath/$route',
          nonce: '${100000 + Random.secure().nextInt(900000)}',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      });
    final response = await (() async =>
            http.Response.fromStream(await _client.send(request)))()
        .timeout(const Duration(seconds: 20));
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const FntvApiException('飞牛影视登录失效或无访问权限，请重新测试登录');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FntvApiException(
          '飞牛影视$operation失败：HTTP ${response.statusCode}，请检查服务器地址');
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  Future<List<int>> _requestBytes(
    MediaSourceConfig source,
    String route, {
    String operation = '请求',
  }) async {
    final uri = _uri(source, route);
    final request = http.Request('GET', uri)
      ..followRedirects = false
      ..headers.addAll({
        'Accept': '*/*',
        'User-Agent': 'Starflow',
        'x-trim-client': 'web',
        'x-trim-client-version': '616',
        ...sessionHeaders(source),
        'Authx': buildAuthx(
          path: '$_apiPath/$route',
          nonce: '${100000 + Random.secure().nextInt(900000)}',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      });
    final response = await (() async =>
            http.Response.fromStream(await _client.send(request)))()
        .timeout(const Duration(seconds: 20));
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const FntvApiException('飞牛影视登录失效或无访问权限，请重新测试登录');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FntvApiException(
          '飞牛影视$operation失败：HTTP ${response.statusCode}，请检查服务器地址');
    }
    return response.bodyBytes;
  }

  static void _requireSession(MediaSourceConfig source) {
    if (!source.hasActiveSession) throw const FntvApiException('请先测试登录飞牛影视');
  }

  static String _text(Object? value) => value == null ? '' : '$value'.trim();
  static int? _number(Object? value) =>
      value is num ? value.toInt() : int.tryParse(_text(value));
  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};
  static List<Map<String, dynamic>> _rows(Object? value) => value is List
      ? value
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList()
      : const [];
}

class FntvApiException implements Exception {
  const FntvApiException(this.message);
  final String message;
  @override
  String toString() => message;
}
