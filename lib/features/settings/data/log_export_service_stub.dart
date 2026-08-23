import 'package:starflow/features/settings/data/log_export_service.dart';

LogExportService createLogExportService() {
  return const UnsupportedLogExportService();
}

class UnsupportedLogExportService implements LogExportService {
  const UnsupportedLogExportService();

  @override
  bool get isSupported => false;

  @override
  String get unsupportedReason => '当前平台暂不支持导出本地日志。';

  @override
  bool get supportsSystemExport => false;

  @override
  Future<String?> pickExportPath({String? suggestedName}) async => null;

  @override
  Future<String> buildSuggestedExportPath() {
    throw UnsupportedError(unsupportedReason);
  }

  @override
  Future<LogExportResult> exportLogs({required String targetPath}) {
    throw UnsupportedError(unsupportedReason);
  }

  @override
  Future<LogExportResult?> exportLogsWithSystemPicker({
    String? suggestedName,
  }) {
    throw UnsupportedError(unsupportedReason);
  }

  @override
  Future<LogLanExportSession> startTelevisionExport() {
    throw UnsupportedError(unsupportedReason);
  }
}
