enum MediaSourceKind {
  emby,
  nas,
}

extension MediaSourceKindX on MediaSourceKind {
  String get label {
    switch (this) {
      case MediaSourceKind.emby:
        return 'Emby';
      case MediaSourceKind.nas:
        return 'WebDAV';
    }
  }

  static MediaSourceKind fromName(String raw) {
    return MediaSourceKind.values.firstWhere(
      (item) => item.name == raw,
      orElse: () => MediaSourceKind.emby,
    );
  }
}

class MediaSourceConfig {
  const MediaSourceConfig({
    required this.id,
    required this.name,
    required this.kind,
    required this.endpoint,
    required this.enabled,
    this.username = '',
    this.password = '',
    this.accessToken = '',
    this.userId = '',
    this.serverId = '',
    this.deviceId = '',
    this.libraryPath = '',
    this.featuredSectionIds = const [],
  });

  final String id;
  final String name;
  final MediaSourceKind kind;
  final String endpoint;
  final bool enabled;
  final String username;
  final String password;
  final String accessToken;
  final String userId;
  final String serverId;
  final String deviceId;
  final String libraryPath;
  final List<String> featuredSectionIds;

  bool get hasAccessToken => accessToken.trim().isNotEmpty;

  bool get hasActiveSession => hasAccessToken && userId.trim().isNotEmpty;

  String get connectionStatusLabel {
    if (kind != MediaSourceKind.emby) {
      return '已配置';
    }
    if (hasActiveSession) {
      return '已登录';
    }
    if (username.trim().isNotEmpty) {
      return '待登录';
    }
    return '未配置';
  }

  MediaSourceConfig copyWith({
    String? id,
    String? name,
    MediaSourceKind? kind,
    String? endpoint,
    bool? enabled,
    String? username,
    String? password,
    String? accessToken,
    String? userId,
    String? serverId,
    String? deviceId,
    String? libraryPath,
    List<String>? featuredSectionIds,
  }) {
    return MediaSourceConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      endpoint: endpoint ?? this.endpoint,
      enabled: enabled ?? this.enabled,
      username: username ?? this.username,
      password: password ?? this.password,
      accessToken: accessToken ?? this.accessToken,
      userId: userId ?? this.userId,
      serverId: serverId ?? this.serverId,
      deviceId: deviceId ?? this.deviceId,
      libraryPath: libraryPath ?? this.libraryPath,
      featuredSectionIds: featuredSectionIds ?? this.featuredSectionIds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'kind': kind.name,
      'endpoint': endpoint,
      'enabled': enabled,
      'username': username,
      'password': password,
      'accessToken': accessToken,
      'userId': userId,
      'serverId': serverId,
      'deviceId': deviceId,
      'libraryPath': libraryPath,
      'featuredSectionIds': featuredSectionIds,
    };
  }

  factory MediaSourceConfig.fromJson(Map<String, dynamic> json) {
    return MediaSourceConfig(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      kind: MediaSourceKindX.fromName(json['kind'] as String? ?? ''),
      endpoint: json['endpoint'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? false,
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      accessToken: json['accessToken'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      serverId: json['serverId'] as String? ?? '',
      deviceId: json['deviceId'] as String? ?? '',
      libraryPath: json['libraryPath'] as String? ?? '',
      featuredSectionIds:
          (json['featuredSectionIds'] as List<dynamic>? ?? const [])
              .map((item) => '$item')
              .where((item) => item.trim().isNotEmpty)
              .toList(),
    );
  }
}

extension MediaSourceConfigEditorX on MediaSourceConfig {
  /// 编辑页「连接状态」说明文案（仅 Emby）。
  String get embyEditorStatusMessage {
    if (hasActiveSession) {
      final serverPart = serverId.trim().isEmpty ? '' : '，Server ID: $serverId';
      return '当前会话可用，登录用户 $username$serverPart';
    }
    if (accessToken.trim().isNotEmpty) {
      return '已经保存 token，但还没有拿到 User ID，建议重新测试登录。';
    }
    return '填写账号密码后可以直接验证 Emby 登录。';
  }
}

class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    this.originalTitle = '',
    this.sortTitle = '',
    required this.overview,
    required this.posterUrl,
    required this.year,
    required this.durationLabel,
    required this.genres,
    this.directors = const [],
    this.actors = const [],
    this.itemType = '',
    this.isFolder = false,
    this.sectionId = '',
    this.sectionName = '',
    required this.sourceId,
    required this.sourceName,
    required this.sourceKind,
    required this.streamUrl,
    this.actualAddress = '',
    this.streamHeaders = const {},
    this.playbackItemId = '',
    this.preferredMediaSourceId = '',
    this.seasonNumber,
    this.episodeNumber,
    this.playbackProgress,
    this.imdbId = '',
    this.tmdbId = '',
    required this.addedAt,
    this.lastWatchedAt,
  });

  final String id;
  final String title;
  final String originalTitle;
  final String sortTitle;
  final String overview;
  final String posterUrl;
  final int year;
  final String durationLabel;
  final List<String> genres;
  final List<String> directors;
  final List<String> actors;
  final String itemType;
  final bool isFolder;
  final String sectionId;
  final String sectionName;
  final String sourceId;
  final String sourceName;
  final MediaSourceKind sourceKind;
  final String streamUrl;
  final String actualAddress;
  final Map<String, String> streamHeaders;
  final String playbackItemId;
  final String preferredMediaSourceId;
  final int? seasonNumber;
  final int? episodeNumber;
  final double? playbackProgress;
  final String imdbId;
  final String tmdbId;
  final DateTime addedAt;
  final DateTime? lastWatchedAt;

  bool get isPlayable =>
      streamUrl.trim().isNotEmpty || playbackItemId.trim().isNotEmpty;
}

class MediaCollection {
  const MediaCollection({
    required this.id,
    required this.title,
    required this.sourceId,
    required this.sourceName,
    required this.sourceKind,
    this.subtitle = '',
  });

  final String id;
  final String title;
  final String sourceId;
  final String sourceName;
  final MediaSourceKind sourceKind;
  final String subtitle;
}
