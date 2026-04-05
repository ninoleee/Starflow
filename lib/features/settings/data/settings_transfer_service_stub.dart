import 'package:starflow/features/settings/data/settings_transfer_service.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

SettingsTransferService createSettingsTransferService() {
  return const UnsupportedSettingsTransferService();
}

class UnsupportedSettingsTransferService implements SettingsTransferService {
  const UnsupportedSettingsTransferService();

  @override
  bool get isSupported => false;

  @override
  String get unsupportedReason => '当前平台暂不支持本地文件导入导出。';

  @override
  Future<String?> pickExportPath({String? suggestedName}) async {
    return null;
  }

  @override
  Future<String?> pickImportPath() async {
    return null;
  }

  @override
  Future<String> buildSuggestedExportPath() async {
    throw UnsupportedError(unsupportedReason);
  }

  @override
  Future<SettingsExportResult> exportSettings({
    required AppSettings settings,
    required String targetPath,
  }) async {
    throw UnsupportedError(unsupportedReason);
  }

  @override
  Future<AppSettings> importSettings(String sourcePath) async {
    throw UnsupportedError(unsupportedReason);
  }
}
