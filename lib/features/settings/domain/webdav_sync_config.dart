class WebDavSyncConfig {
  const WebDavSyncConfig({
    this.url = '',
    this.directory = 'Starflow',
    this.username = '',
    this.password = '',
    this.settings = true,
    this.favorites = true,
    this.autoFavorites = false,
  });

  final String url;
  final String directory;
  final String username;
  final String password;
  final bool settings;
  final bool favorites;
  final bool autoFavorites;

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

  Uri favoriteDeviceFileUri(String deviceId) {
    if (RegExp(r'^[a-f0-9]{32}$').stringMatch(deviceId) != deviceId) {
      throw const FormatException('收藏同步设备标识无效');
    }
    return directoryUri.resolve('starflow-favorites-$deviceId.json');
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'directory': directory,
        'username': username,
        'password': password,
        'settings': settings,
        'favorites': favorites,
        'autoFavorites': autoFavorites,
      };

  factory WebDavSyncConfig.fromJson(Map<String, dynamic> json) =>
      WebDavSyncConfig(
        url: json['url'] as String? ?? '',
        directory: json['directory'] as String? ?? 'Starflow',
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        settings: json['settings'] as bool? ?? true,
        favorites: json['favorites'] as bool? ?? true,
        autoFavorites: json['autoFavorites'] as bool? ?? false,
      );
}
