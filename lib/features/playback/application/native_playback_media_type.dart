import 'package:starflow/features/playback/application/playback_remote_preflight.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

const String kNativePlaybackHlsMimeType = 'application/x-mpegURL';
const String kNativePlaybackMp4MimeType = 'video/mp4';

bool shouldProbeNativeSmartStrmMediaType(PlaybackTarget target) {
  final url = target.streamUrl.trim().toLowerCase();
  if ((!url.startsWith('http://') && !url.startsWith('https://')) ||
      !_smartStrmPathPattern.hasMatch(url)) {
    return false;
  }
  if (url.contains('#') || url.contains('%23')) {
    return true;
  }
  if (!_smartStrmFidPathPattern.hasMatch(url)) {
    return false;
  }
  final container = target.container.trim().toLowerCase();
  final extension = _playbackExtension(url);
  return container == 'mp4' ||
      container == 'm4v' ||
      extension == 'mp4' ||
      extension == 'm4v' ||
      (container.isEmpty && extension.isEmpty);
}

final RegExp _smartStrmPathPattern = RegExp(r'/smartstrm(?:_[^/]+)?/');
final RegExp _smartStrmFidPathPattern = RegExp(r'/smartstrm_fid/');

String _playbackExtension(String url) {
  final path = Uri.tryParse(url)?.path ?? url;
  final fileName = path.split('/').last;
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex == fileName.length - 1) {
    return '';
  }
  return fileName.substring(dotIndex + 1).toLowerCase();
}

String? resolveNativePlaybackMimeType(
  PlaybackRemotePreflightResult result,
) {
  if (!result.canStream) {
    return null;
  }
  if (_hasMp4FileTypeBox(result.samplePrefix)) {
    return kNativePlaybackMp4MimeType;
  }
  if (_hasHlsPlaylistHeader(result.samplePrefix) || result.isHlsStream) {
    return kNativePlaybackHlsMimeType;
  }
  return null;
}

bool _hasMp4FileTypeBox(List<int> bytes) {
  return bytes.length >= 8 &&
      bytes[4] == 0x66 &&
      bytes[5] == 0x74 &&
      bytes[6] == 0x79 &&
      bytes[7] == 0x70;
}

bool _hasHlsPlaylistHeader(List<int> bytes) {
  var offset = 0;
  if (bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf) {
    offset = 3;
  }
  while (offset < bytes.length && _isAsciiWhitespace(bytes[offset])) {
    offset += 1;
  }
  const marker = <int>[0x23, 0x45, 0x58, 0x54, 0x4d, 0x33, 0x55];
  if (bytes.length - offset < marker.length) {
    return false;
  }
  for (var index = 0; index < marker.length; index++) {
    if (bytes[offset + index] != marker[index]) {
      return false;
    }
  }
  return true;
}

bool _isAsciiWhitespace(int value) {
  return value == 0x09 || value == 0x0a || value == 0x0d || value == 0x20;
}
