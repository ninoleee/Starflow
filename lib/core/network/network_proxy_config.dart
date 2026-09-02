class NetworkProxyConfig {
  const NetworkProxyConfig({
    this.enabled = false,
    this.host = '',
    this.port = 7890,
    this.username = '',
    this.password = '',
    this.bypassLocalAddresses = true,
  });

  final bool enabled;
  final String host;
  final int port;
  final String username;
  final String password;
  final bool bypassLocalAddresses;

  String get normalizedHost {
    final trimmed = host.trim();
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      return trimmed.substring(1, trimmed.length - 1).trim();
    }
    return trimmed;
  }

  bool get isValid {
    final proxyHost = normalizedHost;
    return proxyHost.isNotEmpty &&
        (RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(proxyHost) ||
            (proxyHost.contains(':') &&
                RegExp(r'^[0-9a-fA-F:.]+$').hasMatch(proxyHost))) &&
        port >= 1 &&
        port <= 65535;
  }

  bool get isActive => enabled && isValid;

  String get displayAddress {
    final proxyHost = normalizedHost;
    if (proxyHost.isEmpty) {
      return '';
    }
    return '${_formatHost(proxyHost)}:$port';
  }

  bool shouldProxy(Uri uri) {
    if (!isActive) {
      return false;
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return false;
    }
    return !bypassLocalAddresses || !isLocalNetworkHost(uri.host);
  }

  String proxyDirectiveFor(Uri uri) {
    if (!shouldProxy(uri)) {
      return 'DIRECT';
    }
    return 'PROXY $displayAddress';
  }

  String mpvProxyUrlFor(Uri uri) {
    if (!shouldProxy(uri)) {
      return '';
    }
    final normalizedUsername = username.trim();
    final userInfo = normalizedUsername.isEmpty
        ? ''
        : '${Uri.encodeComponent(normalizedUsername)}:'
            '${Uri.encodeComponent(password)}@';
    return 'http://$userInfo$displayAddress';
  }

  NetworkProxyConfig copyWith({
    bool? enabled,
    String? host,
    int? port,
    String? username,
    String? password,
    bool? bypassLocalAddresses,
  }) {
    return NetworkProxyConfig(
      enabled: enabled ?? this.enabled,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      bypassLocalAddresses: bypassLocalAddresses ?? this.bypassLocalAddresses,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'enabled': enabled,
      'host': host.trim(),
      'port': port,
      'username': username.trim(),
      'password': password,
      'bypassLocalAddresses': bypassLocalAddresses,
    };
  }

  factory NetworkProxyConfig.fromJson(Map<String, dynamic> json) {
    return NetworkProxyConfig(
      enabled: json['enabled'] as bool? ?? false,
      host: json['host'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 7890,
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      bypassLocalAddresses: json['bypassLocalAddresses'] as bool? ?? true,
    );
  }
}

bool isLocalNetworkHost(String rawHost) {
  final host = rawHost.trim().toLowerCase();
  if (host.isEmpty ||
      host == 'localhost' ||
      host == '::1' ||
      host.endsWith('.localhost') ||
      host.endsWith('.local')) {
    return true;
  }

  final ipv4 = host.split('.').map(int.tryParse).toList(growable: false);
  if (ipv4.length == 4 && ipv4.every((part) => part != null)) {
    final first = ipv4[0]!;
    final second = ipv4[1]!;
    if (ipv4.any((part) => part! < 0 || part > 255)) {
      return false;
    }
    return first == 10 ||
        first == 127 ||
        (first == 169 && second == 254) ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168);
  }

  return host.contains(':') &&
      (host.startsWith('fc') ||
          host.startsWith('fd') ||
          host.startsWith('fe8') ||
          host.startsWith('fe9') ||
          host.startsWith('fea') ||
          host.startsWith('feb'));
}

String _formatHost(String host) {
  return host.contains(':') ? '[$host]' : host;
}
