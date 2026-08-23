import 'package:starflow/core/logging/app_log_api.dart';
import 'package:starflow/core/logging/app_logger.dart';

bool _detailResourceSwitchTraceCategoryEnabled = true;

bool get detailResourceSwitchTraceEnabled =>
    _detailResourceSwitchTraceCategoryEnabled && appLogger.isEnabled;

void setDetailResourceSwitchTraceEnabled(bool enabled) {
  _detailResourceSwitchTraceCategoryEnabled = enabled;
}

void detailResourceSwitchTrace(
  String stage, {
  String dedupeKey = '',
  Map<String, Object?> fields = const <String, Object?>{},
  Object? error,
  StackTrace? stackTrace,
}) {
  if (!detailResourceSwitchTraceEnabled) {
    return;
  }
  appLogger.log(
    error == null ? AppLogLevel.trace : AppLogLevel.error,
    'detail-resource',
    stage,
    fields: <String, Object?>{
      if (dedupeKey.trim().isNotEmpty) 'dedupeKey': dedupeKey,
      ...fields,
    },
    error: error,
    stackTrace: stackTrace,
  );
}
