import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/settings/data/log_export_service_stub.dart'
    if (dart.library.io) 'package:starflow/features/settings/data/log_export_service_io.dart'
    as impl;

final logExportServiceProvider = Provider<LogExportService>((ref) {
  return impl.createLogExportService();
});

class LogExportResult {
  const LogExportResult({
    required this.path,
    required this.bytes,
    required this.sourceFileCount,
  });

  final String path;
  final int bytes;
  final int sourceFileCount;
}

class LogLanExportEvent {
  const LogLanExportEvent({
    required this.message,
    this.isError = false,
  });

  final String message;
  final bool isError;
}

abstract class LogLanExportSession {
  String get accessCode;

  int get port;

  List<String> get urls;

  Stream<LogLanExportEvent> get events;

  Future<void> close();
}

abstract class LogExportService {
  bool get isSupported;

  String get unsupportedReason;

  bool get supportsSystemExport;

  Future<String?> pickExportPath({String? suggestedName});

  Future<String> buildSuggestedExportPath();

  Future<LogExportResult> exportLogs({required String targetPath});

  Future<LogExportResult?> exportLogsWithSystemPicker({
    String? suggestedName,
  });

  Future<LogLanExportSession> startTelevisionExport();
}
