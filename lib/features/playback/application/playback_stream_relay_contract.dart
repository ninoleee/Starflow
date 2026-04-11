import 'package:starflow/features/playback/domain/playback_models.dart';

const String kPlaybackRelayPathSegment = 'playback-relay';

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
