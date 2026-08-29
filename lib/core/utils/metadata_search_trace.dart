import 'package:starflow/core/logging/app_log_api.dart';
import 'package:starflow/core/logging/app_logger.dart';

bool _metadataSearchTraceCategoryEnabled = false;

bool get metadataSearchTraceEnabled =>
    _metadataSearchTraceCategoryEnabled && appLogger.isEnabled;

void setMetadataSearchTraceEnabled(bool enabled) {
  _metadataSearchTraceCategoryEnabled = enabled;
}

void metadataSearchTrace(
  String stage, {
  Map<String, Object?> fields = const <String, Object?>{},
  Object? error,
  StackTrace? stackTrace,
}) {
  if (error == null && !metadataSearchTraceEnabled) {
    return;
  }
  if (error != null && !appLogger.isEnabled) {
    return;
  }
  appLogger.log(
    error == null ? AppLogLevel.trace : AppLogLevel.error,
    'metadata',
    stage,
    fields: fields,
    error: error,
    stackTrace: stackTrace,
  );
}
