enum LivePlaybackErrorCategory {
  http,
  dns,
  timeout,
  tls,
  connection,
  behindLiveWindow,
  cleartext,
  container,
  decoder,
  audio,
  drm,
  io,
  unknown,
}

/// An allowlisted summary; raw native messages may contain IPTV credentials.
class LivePlaybackErrorDetails {
  const LivePlaybackErrorDetails({
    this.category = LivePlaybackErrorCategory.unknown,
    this.nativeErrorCode,
    this.httpStatus,
  });

  factory LivePlaybackErrorDetails.fromNative(Object? value) {
    final map = value is Map ? value : const {};
    final code = map['nativeErrorCode'];
    final status = map['httpStatus'];
    return LivePlaybackErrorDetails(
      category: LivePlaybackErrorCategory.values
              .where((c) => c.name == map['errorCategory'])
              .firstOrNull ??
          LivePlaybackErrorCategory.unknown,
      nativeErrorCode:
          code is int && code >= 0 && code <= 1000000 ? code : null,
      httpStatus:
          status is int && status >= 100 && status <= 599 ? status : null,
    );
  }

  final LivePlaybackErrorCategory category;
  final int? nativeErrorCode;
  final int? httpStatus;

  Map<String, Object> get fields => {
        'errorCategory': category.name,
        if (nativeErrorCode != null) 'nativeErrorCode': nativeErrorCode!,
        if (httpStatus != null) 'httpStatus': httpStatus!,
      };

  String? get label {
    if (httpStatus != null) {
      return switch (httpStatus!) {
        401 || 403 => '直播源拒绝访问（HTTP $httpStatus）',
        404 || 410 => '直播资源不存在或已下线（HTTP $httpStatus）',
        429 => '直播源请求过于频繁（HTTP 429）',
        _ => '直播源响应异常（HTTP $httpStatus）',
      };
    }
    return switch (category) {
      LivePlaybackErrorCategory.dns => '无法解析直播源域名',
      LivePlaybackErrorCategory.timeout => '连接或读取直播源超时',
      LivePlaybackErrorCategory.tls => '直播源安全连接失败',
      LivePlaybackErrorCategory.connection => '无法连接直播源或连接已断开',
      LivePlaybackErrorCategory.behindLiveWindow => '播放位置已落后于直播窗口',
      LivePlaybackErrorCategory.cleartext => '系统不允许此明文连接',
      LivePlaybackErrorCategory.container => '直播流格式无法识别或解析',
      LivePlaybackErrorCategory.decoder => '当前内核无法解码此直播流',
      LivePlaybackErrorCategory.audio => '音频输出失败',
      LivePlaybackErrorCategory.drm => '直播流受保护或授权失败',
      LivePlaybackErrorCategory.io => '直播流读取失败',
      LivePlaybackErrorCategory.http ||
      LivePlaybackErrorCategory.unknown =>
        nativeErrorCode == null ? null : '播放内核错误（$nativeErrorCode）',
    };
  }
}

abstract interface class LivePlaybackErrorSource {
  LivePlaybackErrorDetails? errorFor(int generation);
}
