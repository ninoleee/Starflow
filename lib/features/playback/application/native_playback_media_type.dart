import 'package:starflow/features/playback/application/playback_remote_preflight.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

const String kNativePlaybackHlsMimeType = 'application/x-mpegURL';

bool shouldProbeNativeSmartStrmMediaType(PlaybackTarget target) {
  final url = target.streamUrl.trim().toLowerCase();
  if ((!url.startsWith('http://') && !url.startsWith('https://')) ||
      !_smartStrmPathPattern.hasMatch(url)) {
    return false;
  }
  return url.contains('#') || url.contains('%23');
}

final RegExp _smartStrmPathPattern = RegExp(r'/smartstrm(?:_[^/]+)?/');

String? resolveNativePlaybackMimeType(
  PlaybackRemotePreflightResult result,
) {
  if (!result.canStream || !result.isHlsStream) {
    return null;
  }
  return kNativePlaybackHlsMimeType;
}
