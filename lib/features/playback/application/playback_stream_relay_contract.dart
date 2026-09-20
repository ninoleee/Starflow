import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';

const String kPlaybackRelayPathSegment = 'playback-relay';

bool requiresPlaybackStreamRelay(PlaybackTarget target) =>
    (target.sourceKind == MediaSourceKind.quark ||
        target.sourceKind == MediaSourceKind.nas) &&
    target.headers.entries.any((entry) =>
        entry.value.trim().isNotEmpty &&
        RegExp(r'authorization|cookie|token|authx|api[-_]?key|auth[-_]?key|secret',
                caseSensitive: false)
            .hasMatch(entry.key));

class PlaybackRelayException implements Exception {
  const PlaybackRelayException([this.message = '安全播放代理连接失败，请检查媒体源后重试。']);
  final String message;
  @override
  String toString() => message;
}

const unsupportedRelayMedia = PlaybackRelayException(
    '安全播放代理支持渐进式媒体及标准 HLS 点播/动态清单；低延迟 HLS 仅兼容完整分片，不支持仅部分分片、增量清单、DRM、DASH、其他播放列表或远程光盘。');

abstract class PlaybackStreamRelayService {
  Future<PlaybackTarget> prepareTarget(PlaybackTarget target);

  Future<void> clear({String reason = ''});

  Future<void> close();
}

bool isLoopbackPlaybackRelayUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) {
    return false;
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    return false;
  }
  final host = uri.host.trim().toLowerCase();
  final isLoopbackHost =
      host == '127.0.0.1' || host == 'localhost' || host == '::1';
  if (!isLoopbackHost) {
    return false;
  }
  final segments = uri.pathSegments
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  return segments.isNotEmpty && segments.first == kPlaybackRelayPathSegment;
}
