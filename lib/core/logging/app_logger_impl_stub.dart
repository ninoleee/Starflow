import 'package:starflow/core/logging/app_log_api.dart';

AppLogService createAppLogService() => _StubAppLogService();

class _StubAppLogService implements AppLogService {
  bool _enabled = false;
  int _maxBytes = 0;
  Set<AppLogLevel> _recordedLevels = kDefaultRecordedAppLogLevels;

  @override
  bool get isEnabled => _enabled;

  @override
  bool get isSupported => false;

  @override
  int get maxBytes => _maxBytes;

  @override
  Set<AppLogLevel> get recordedLevels => Set<AppLogLevel>.unmodifiable(
        _recordedLevels,
      );

  @override
  Future<void> configure({
    required bool enabled,
    required int maxBytes,
    required Set<AppLogLevel> recordedLevels,
  }) async {
    _enabled = enabled;
    _maxBytes = maxBytes;
    _recordedLevels = Set<AppLogLevel>.from(recordedLevels);
  }

  @override
  void log(
    AppLogLevel level,
    String category,
    String message, {
    Map<String, Object?> fields = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  }) {}

  @override
  Future<void> logCritical(
    String category,
    String message, {
    Map<String, Object?> fields = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  }) async {}

  @override
  Future<void> flush() async {}

  @override
  Future<AppLogSummary> inspect() async {
    return const AppLogSummary(
      supported: false,
      fileCount: 0,
      totalBytes: 0,
    );
  }

  @override
  Future<List<AppLogEntry>> read({int limit = 300}) async {
    return const <AppLogEntry>[];
  }

  @override
  Future<AppLogExportData> export() async {
    return const AppLogExportData(bytes: <int>[], fileCount: 0);
  }

  @override
  Future<void> clear() async {}
}
