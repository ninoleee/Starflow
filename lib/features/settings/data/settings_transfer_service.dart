import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/settings/data/settings_transfer_service_stub.dart'
    if (dart.library.io) 'package:starflow/features/settings/data/settings_transfer_service_io.dart'
    if (dart.library.js_interop) 'package:starflow/features/settings/data/settings_transfer_service_web.dart'
    as impl;
import 'package:starflow/features/settings/domain/app_settings.dart';

final settingsTransferServiceProvider =
    Provider<SettingsTransferService>((ref) {
  return impl.createSettingsTransferService();
});

abstract class SettingsTransferService {
  bool get isSupported;

  String get unsupportedReason;

  bool get supportsSystemExport;

  Future<String?> pickExportPath({String? suggestedName});

  Future<String?> pickImportPath();

  Future<String> buildSuggestedExportPath();

  Future<SettingsExportResult> exportSettings({
    required AppSettings settings,
    required String targetPath,
  });

  Future<SettingsExportResult?> exportSettingsWithSystemPicker({
    required AppSettings settings,
    String? suggestedName,
  });

  Future<AppSettings> importSettings(String sourcePath);
}

class SettingsExportResult {
  const SettingsExportResult({
    required this.path,
    required this.bytes,
  });

  final String path;
  final int bytes;
}
