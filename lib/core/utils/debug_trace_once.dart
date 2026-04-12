import 'package:starflow/core/utils/metadata_search_trace.dart';

class DebugTraceOnce {
  DebugTraceOnce._();

  static final Set<String> _trackedMetadataKeys = <String>{};

  static bool trackMetadata(String key) {
    final normalized = key.trim();
    if (normalized.isEmpty) {
      return false;
    }
    return _trackedMetadataKeys.add(normalized);
  }

  static void logMetadata(String key, String phase, String message) {
    metadataSearchTrace(
      'detail.$phase',
      fields: <String, Object?>{
        'key': key.trim().isEmpty ? 'detail' : key.trim(),
        'message': message,
      },
    );
  }
}
