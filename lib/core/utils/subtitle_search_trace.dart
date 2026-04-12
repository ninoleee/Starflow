bool _subtitleSearchTraceEnabled = false;

bool get subtitleSearchTraceEnabled => _subtitleSearchTraceEnabled;

void setSubtitleSearchTraceEnabled(bool enabled) {
  _subtitleSearchTraceEnabled = enabled;
}

void subtitleSearchTrace(
  String stage, {
  Map<String, Object?> fields = const <String, Object?>{},
  Object? error,
  StackTrace? stackTrace,
}) {}
