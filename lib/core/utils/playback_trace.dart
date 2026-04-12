bool _playbackTraceEnabled = false;

bool get playbackTraceEnabled => _playbackTraceEnabled;

void setPlaybackTraceEnabled(bool enabled) {
  _playbackTraceEnabled = enabled;
}

void playbackTrace(
  String stage, {
  Map<String, Object?> fields = const <String, Object?>{},
  Object? error,
  StackTrace? stackTrace,
}) {}
