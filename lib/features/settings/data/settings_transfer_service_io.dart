import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:starflow/features/settings/data/settings_transfer_service.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

SettingsTransferService createSettingsTransferService() {
  return const LocalFileSettingsTransferService();
}

class LocalFileSettingsTransferService implements SettingsTransferService {
  const LocalFileSettingsTransferService();

  @override
  bool get isSupported => true;

  @override
  String get unsupportedReason => '';

  @override
  Future<String?> pickExportPath({String? suggestedName}) async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final exportDirectory = p.join(
      documentsDirectory.path,
      'exports',
      'settings',
    );
    if (Platform.isIOS) {
      return p.join(exportDirectory, suggestedName ?? 'starflow-settings.json');
    }
    try {
      final directory = await getDirectoryPath(
        initialDirectory: exportDirectory,
        confirmButtonText: '选择这个目录',
      );
      if (directory == null || directory.trim().isEmpty) {
        return null;
      }
      return p.join(directory, suggestedName ?? 'starflow-settings.json');
    } on PlatformException catch (error) {
      throw FileSystemException(
        '当前设备无法打开目录选择器，请手动填写导出路径。',
        error.message,
      );
    } catch (error) {
      throw FileSystemException('当前设备无法打开目录选择器，请手动填写导出路径。', '$error');
    }
  }

  @override
  Future<String?> pickImportPath() async {
    try {
      if (Platform.isIOS) {
        final file = await openFile();
        return file?.path;
      }
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'JSON',
            extensions: ['json'],
            uniformTypeIdentifiers: ['public.json'],
          ),
        ],
        confirmButtonText: '导入这个文件',
      );
      return file?.path;
    } on PlatformException catch (error) {
      throw FileSystemException(
        '当前设备无法打开文件选择器，请手动填写 JSON 文件路径。',
        error.message,
      );
    } catch (error) {
      throw FileSystemException('当前设备无法打开文件选择器，请手动填写 JSON 文件路径。', '$error');
    }
  }

  @override
  Future<String> buildSuggestedExportPath() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final exportDirectory = Directory(
      p.join(documentsDirectory.path, 'exports', 'settings'),
    );
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    return p.join(exportDirectory.path, 'starflow-settings-$timestamp.json');
  }

  @override
  Future<SettingsExportResult> exportSettings({
    required AppSettings settings,
    required String targetPath,
  }) async {
    final normalizedPath = targetPath.trim();
    if (normalizedPath.isEmpty) {
      throw const FileSystemException('导出路径不能为空。');
    }

    final file = File(normalizedPath);
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    final payload = encoder.convert(settings.toJson());
    await file.writeAsString(payload, flush: true);
    final bytes = await file.length();
    return SettingsExportResult(path: file.path, bytes: bytes);
  }

  @override
  Future<AppSettings> importSettings(String sourcePath) async {
    final normalizedPath = sourcePath.trim();
    if (normalizedPath.isEmpty) {
      throw const FileSystemException('导入路径不能为空。');
    }

    final file = File(normalizedPath);
    if (!await file.exists()) {
      throw FileSystemException('找不到配置文件。', normalizedPath);
    }

    final raw = await file.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('配置文件格式不正确，需要 JSON 对象。');
    }
    return AppSettings.fromJson(
      Map<String, dynamic>.from(decoded),
    );
  }
}
