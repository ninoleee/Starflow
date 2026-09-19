import 'package:starflow/core/utils/metadata_search_trace.dart';

class DebugTraceOnce {
  DebugTraceOnce._();

  static void logMetadata(
    String key,
    String phase,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    metadataSearchTrace(
      'detail.$phase',
      fields: <String, Object?>{
        'key': key.trim().isEmpty ? 'detail' : key.trim(),
        'message': message,
      },
      error: error,
      stackTrace: stackTrace,
    );
  }
}
