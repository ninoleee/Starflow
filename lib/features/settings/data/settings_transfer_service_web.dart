import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:starflow/features/settings/data/settings_transfer_service.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

SettingsTransferService createSettingsTransferService() {
  return const WebSettingsTransferService();
}

class WebSettingsTransferService implements SettingsTransferService {
  const WebSettingsTransferService();

  static final Map<String, AppSettings> _pendingImports =
      <String, AppSettings>{};

  @override
  bool get isSupported => true;

  @override
  String get unsupportedReason => '';

  @override
  bool get supportsSystemExport => true;

  @override
  Future<String?> pickExportPath({String? suggestedName}) async {
    return _normalizeSuggestedExportFileName(suggestedName);
  }

  @override
  Future<String?> pickImportPath() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'JSON',
          extensions: ['json'],
          mimeTypes: ['application/json', 'text/json'],
          uniformTypeIdentifiers: ['public.json'],
          webWildCards: ['.json', 'application/json'],
        ),
      ],
      confirmButtonText: '导入这个文件',
    );
    if (file == null) {
      return null;
    }

    final raw = await file.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('配置文件格式不正确，需要 JSON 对象。');
    }

    final token =
        'web-import:${DateTime.now().microsecondsSinceEpoch}:${file.name}';
    _pendingImports[token] =
        AppSettings.fromJson(Map<String, dynamic>.from(decoded));
    return token;
  }

  @override
  Future<String> buildSuggestedExportPath() async {
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    return 'starflow-settings-$timestamp.json';
  }

  @override
  Future<SettingsExportResult> exportSettings({
    required AppSettings settings,
    required String targetPath,
  }) async {
    final fileName = _normalizeSuggestedExportFileName(targetPath);
    return _downloadSettings(
      settings: settings,
      suggestedName: fileName,
    );
  }

  @override
  Future<SettingsExportResult?> exportSettingsWithSystemPicker({
    required AppSettings settings,
    String? suggestedName,
  }) async {
    return _downloadSettings(
      settings: settings,
      suggestedName: _normalizeSuggestedExportFileName(suggestedName),
    );
  }

  @override
  Future<AppSettings> importSettings(String sourcePath) async {
    final normalizedPath = sourcePath.trim();
    if (normalizedPath.isEmpty) {
      throw const FormatException('导入路径不能为空。');
    }

    final imported = _pendingImports.remove(normalizedPath);
    if (imported == null) {
      throw const FormatException('找不到待导入的 Web 配置文件。请重新选择。');
    }
    return imported;
  }

  Future<SettingsExportResult> _downloadSettings({
    required AppSettings settings,
    required String suggestedName,
  }) async {
    final payload =
        const JsonEncoder.withIndent('  ').convert(settings.toJson());
    final bytes = Uint8List.fromList(utf8.encode(payload));
    final file = XFile.fromData(
      bytes,
      mimeType: 'application/json',
      name: suggestedName,
    );
    await file.saveTo(suggestedName);
    return SettingsExportResult(
      path: suggestedName,
      bytes: bytes.length,
    );
  }

  String _normalizeSuggestedExportFileName(String? suggestedName) {
    final trimmed = (suggestedName ?? '').trim();
    if (trimmed.isEmpty) {
      return 'starflow-settings.json';
    }
    return trimmed.toLowerCase().endsWith('.json') ? trimmed : '$trimmed.json';
  }
}
