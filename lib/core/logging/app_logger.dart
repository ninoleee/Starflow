import 'package:starflow/core/logging/app_log_api.dart';
import 'package:starflow/core/logging/app_logger_impl_stub.dart'
    if (dart.library.io) 'package:starflow/core/logging/app_logger_impl_io.dart'
    as impl;

final AppLogService appLogger = impl.createAppLogService();

void appLogTrace(
  String category,
  String message, {
  Map<String, Object?> fields = const <String, Object?>{},
}) {
  appLogger.log(AppLogLevel.trace, category, message, fields: fields);
}

void appLogInfo(
  String category,
  String message, {
  Map<String, Object?> fields = const <String, Object?>{},
}) {
  appLogger.log(AppLogLevel.info, category, message, fields: fields);
}

void appLogWarning(
  String category,
  String message, {
  Map<String, Object?> fields = const <String, Object?>{},
  Object? error,
  StackTrace? stackTrace,
}) {
  appLogger.log(
    AppLogLevel.warning,
    category,
    message,
    fields: fields,
    error: error,
    stackTrace: stackTrace,
  );
}

void appLogError(
  String category,
  String message, {
  Map<String, Object?> fields = const <String, Object?>{},
  Object? error,
  StackTrace? stackTrace,
}) {
  appLogger.log(
    AppLogLevel.error,
    category,
    message,
    fields: fields,
    error: error,
    stackTrace: stackTrace,
  );
}

Future<void> appLogCritical(
  String category,
  String message, {
  Map<String, Object?> fields = const <String, Object?>{},
  Object? error,
  StackTrace? stackTrace,
}) {
  return appLogger.logCritical(
    category,
    message,
    fields: fields,
    error: error,
    stackTrace: stackTrace,
  );
}
