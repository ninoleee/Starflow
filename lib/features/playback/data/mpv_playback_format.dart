/// Uses the active decoder properties, not the source library's
/// metadata, which may describe a different rendition after transcoding.
Future<String?> readMpvPlaybackFormat(
  Future<String> Function(String) readProperty,
) async {
  Future<String> read(String name) async {
    try {
      return (await readProperty(name)).trim();
    } catch (_) {
      return '';
    }
  }

  final values = await Future.wait([
    read('video-params/w'),
    read('video-params/h'),
    read('video-format'),
    read('audio-codec-name'),
  ]);
  final width = int.tryParse(values[0]) ?? 0;
  final height = int.tryParse(values[1]) ?? 0;
  final parts = [
    if (width > 0 && height > 0) '${width}x$height',
    if (values[2].isNotEmpty) _codecLabel(values[2]),
    if (values[3].isNotEmpty) _codecLabel(values[3]),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

String _codecLabel(String raw) => switch (raw.toLowerCase()) {
      'h264' => 'H.264',
      'h265' || 'hevc' => 'HEVC',
      'mpeg2video' => 'MPEG-2',
      'truehd' => 'TrueHD',
      _ => raw.toUpperCase(),
    };
