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

  static const MethodChannel _platformChannel = MethodChannel(
    'starflow/platform',
  );

  @override
  bool get isSupported => true;

  @override
  String get unsupportedReason => '';

  @override
  bool get supportsSystemExport => Platform.isIOS;

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
    final payload = _encodeSettingsPayload(settings);
    await file.writeAsString(payload, flush: true);
    final bytes = await file.length();
    return SettingsExportResult(path: file.path, bytes: bytes);
  }

  @override
  Future<SettingsExportResult?> exportSettingsWithSystemPicker({
    required AppSettings settings,
    String? suggestedName,
  }) async {
    if (!Platform.isIOS) {
      throw const FileSystemException('当前平台不支持系统文件导出器。');
    }

    final normalizedSuggestedName = _normalizeSuggestedExportFileName(
      suggestedName,
    );
    final temporaryDirectory = await getTemporaryDirectory();
    final temporaryFile = File(
      p.join(
        temporaryDirectory.path,
        'exports',
        'settings',
        normalizedSuggestedName,
      ),
    );
    final payload = _encodeSettingsPayload(settings);
    await temporaryFile.parent.create(recursive: true);
    await temporaryFile.writeAsString(payload, flush: true);

    try {
      final response = await _platformChannel.invokeMapMethod<String, dynamic>(
        'exportDocument',
        {
          'sourcePath': temporaryFile.path,
        },
      );
      if (response == null) {
        return null;
      }
      final exportedPath = (response['path'] as String?)?.trim();
      final bytes = await temporaryFile.length();
      return SettingsExportResult(
        path: exportedPath == null || exportedPath.isEmpty
            ? normalizedSuggestedName
            : exportedPath,
        bytes: bytes,
      );
    } on PlatformException catch (error) {
      throw FileSystemException(
        '当前设备无法打开系统文件导出器。',
        error.message,
      );
    } catch (error) {
      throw FileSystemException('当前设备无法打开系统文件导出器。', '$error');
    } finally {
      if (await temporaryFile.exists()) {
        await temporaryFile.delete();
      }
    }
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

  String _encodeSettingsPayload(AppSettings settings) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(settings.toJson());
  }

  String _normalizeSuggestedExportFileName(String? suggestedName) {
    final trimmed = (suggestedName ?? '').trim();
    if (trimmed.isEmpty) {
      return 'starflow-settings.json';
    }
    return trimmed.toLowerCase().endsWith('.json') ? trimmed : '$trimmed.json';
  }
}
