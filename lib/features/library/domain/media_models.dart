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
        return 'NAS';
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
    this.accessToken = '',
    this.userId = '',
    this.serverId = '',
    this.deviceId = '',
  });

  final String id;
  final String name;
  final MediaSourceKind kind;
  final String endpoint;
  final bool enabled;
  final String username;
  final String accessToken;
  final String userId;
  final String serverId;
  final String deviceId;

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
    String? accessToken,
    String? userId,
    String? serverId,
    String? deviceId,
  }) {
    return MediaSourceConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      endpoint: endpoint ?? this.endpoint,
      enabled: enabled ?? this.enabled,
      username: username ?? this.username,
      accessToken: accessToken ?? this.accessToken,
      userId: userId ?? this.userId,
      serverId: serverId ?? this.serverId,
      deviceId: deviceId ?? this.deviceId,
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
      'accessToken': accessToken,
      'userId': userId,
      'serverId': serverId,
      'deviceId': deviceId,
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
      accessToken: json['accessToken'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      serverId: json['serverId'] as String? ?? '',
      deviceId: json['deviceId'] as String? ?? '',
    );
  }
}

class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    required this.overview,
    required this.posterUrl,
    required this.year,
    required this.durationLabel,
    required this.genres,
    required this.sourceId,
    required this.sourceName,
    required this.sourceKind,
    required this.streamUrl,
    this.streamHeaders = const {},
    required this.addedAt,
    this.lastWatchedAt,
  });

  final String id;
  final String title;
  final String overview;
  final String posterUrl;
  final int year;
  final String durationLabel;
  final List<String> genres;
  final String sourceId;
  final String sourceName;
  final MediaSourceKind sourceKind;
  final String streamUrl;
  final Map<String, String> streamHeaders;
  final DateTime addedAt;
  final DateTime? lastWatchedAt;

  bool get isPlayable => streamUrl.isNotEmpty;
}
