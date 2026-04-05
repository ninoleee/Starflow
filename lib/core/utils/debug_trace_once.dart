import 'package:flutter/foundation.dart';

class DebugTraceOnce {
  DebugTraceOnce._();

  static String? _activeMetadataKey;

  static bool trackMetadata(String key) {
    if (kReleaseMode) {
      return false;
    }
    final normalized = key.trim();
    if (normalized.isEmpty) {
      return false;
    }
    if (_activeMetadataKey == null) {
      _activeMetadataKey = normalized;
      return true;
    }
    return _activeMetadataKey == normalized;
  }

  static void logMetadata(String key, String phase, String message) {
    if (!trackMetadata(key)) {
      return;
    }
    debugPrint('[MetadataTrace][$phase] $message');
  }
}
