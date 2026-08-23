import 'dart:convert';

import 'package:starflow/features/playback/domain/playback_models.dart';

String buildExternalPlaybackPlaylist(PlaybackTarget target) {
  final lines = <String>[
    '#EXTM3U',
    '#EXTINF:-1,${_sanitizePlaylistValue(target.title)}',
  ];
  if (target.headers.isNotEmpty) {
    lines.add('#EXTHTTP:${jsonEncode(target.headers)}');
    for (final entry in target.headers.entries) {
      final value = _sanitizePlaylistValue(entry.value);
      switch (entry.key.trim().toLowerCase()) {
        case 'user-agent':
          lines.add('#EXTVLCOPT:http-user-agent=$value');
        case 'referer':
        case 'referrer':
          lines.add('#EXTVLCOPT:http-referrer=$value');
        case 'cookie':
          lines.add('#EXTVLCOPT:http-cookie=$value');
      }
    }
  }
  lines
    ..add(_sanitizePlaylistValue(target.streamUrl.trim()))
    ..add('');
  return lines.join('\n');
}

String _sanitizePlaylistValue(String raw) {
  return raw.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
}
