import 'package:starflow/core/logging/app_log_api.dart';
import 'package:starflow/core/logging/app_logger.dart';

bool _playbackTraceCategoryEnabled = true;

bool get playbackTraceEnabled =>
    _playbackTraceCategoryEnabled && appLogger.isEnabled;

void setPlaybackTraceEnabled(bool enabled) {
  _playbackTraceCategoryEnabled = enabled;
}

void playbackTrace(
  String stage, {
  Map<String, Object?> fields = const <String, Object?>{},
  Object? error,
  StackTrace? stackTrace,
}) {
  if (!playbackTraceEnabled) {
    return;
  }
  appLogger.log(
    error == null ? AppLogLevel.trace : AppLogLevel.error,
    'playback',
    stage,
    fields: fields,
    error: error,
    stackTrace: stackTrace,
  );
}
