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
