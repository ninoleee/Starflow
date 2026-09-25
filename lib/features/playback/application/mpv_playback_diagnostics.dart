Future<Map<String, String?>> readMpvShutdownProperties({
  required Future<String?> Function(String name) readProperty,
  required bool includeDiagnostics,
}) async {
  final names = [
    'cache-speed',
    if (includeDiagnostics) ...[
      'hwdec-current',
      'video-codec',
      'decoder-frame-drop-count',
      'frame-drop-count',
      'audio-codec-name',
      'current-ao',
      'audio-params/format',
      'audio-params/channel-count',
      'audio-out-params/samplerate',
      'audio-out-params/channel-count',
      'avsync',
    ],
  ];
  final values = await Future.wait(names.map(readProperty));
  return Map.fromIterables(names, values);
}

Future<Map<String, String?>> readMpvHealthProperties({
  required Future<String?> Function(String name) readProperty,
}) async {
  const names = [
    'demuxer-cache-duration',
    'cache-speed',
    'hwdec-current',
    'decoder-frame-drop-count',
    'frame-drop-count',
    'avsync',
  ];
  final values = await Future.wait(names.map(readProperty));
  return Map.fromIterables(names, values);
}

class MpvHealthLogGate {
  DateTime? _lastAt;

  bool admit(DateTime now) {
    if (_lastAt != null &&
        now.difference(_lastAt!) < const Duration(seconds: 10)) {
      return false;
    }
    _lastAt = now;
    return true;
  }
}
