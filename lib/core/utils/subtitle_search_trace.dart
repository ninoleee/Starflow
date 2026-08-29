import 'package:starflow/core/logging/app_log_api.dart';
import 'package:starflow/core/logging/app_logger.dart';

bool _subtitleSearchTraceCategoryEnabled = false;

bool get subtitleSearchTraceEnabled =>
    _subtitleSearchTraceCategoryEnabled && appLogger.isEnabled;

void setSubtitleSearchTraceEnabled(bool enabled) {
  _subtitleSearchTraceCategoryEnabled = enabled;
}

void subtitleSearchTrace(
  String stage, {
  Map<String, Object?> fields = const <String, Object?>{},
  Object? error,
  StackTrace? stackTrace,
}) {
  if (error == null && !subtitleSearchTraceEnabled) {
    return;
  }
  if (error != null && !appLogger.isEnabled) {
    return;
  }
  appLogger.log(
    error == null ? AppLogLevel.trace : AppLogLevel.error,
    'subtitle',
    stage,
    fields: fields,
    error: error,
    stackTrace: stackTrace,
  );
}
