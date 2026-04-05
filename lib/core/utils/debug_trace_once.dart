class DebugTraceOnce {
  DebugTraceOnce._();

  static bool trackMetadata(String key) => false;

  static void logMetadata(String key, String phase, String message) {}
}
