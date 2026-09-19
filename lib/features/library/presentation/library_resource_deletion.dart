import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/library/data/media_repository.dart';
import 'package:starflow/features/library/domain/media_models.dart';

Future<void> confirmLibraryResourceDeletion(
    BuildContext context, WidgetRef ref, MediaItem item) async {
  final directResourceUri = Uri.tryParse(item.id.trim());
  final resourcePath = directResourceUri != null && directResourceUri.hasScheme
      ? item.id.trim()
      : item.actualAddress.trim();
  if (resourcePath.isEmpty) {
    return;
  }
  final isDirectory =
      item.isFolder || item.itemType == 'series' || item.itemType == 'season';
  final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(isDirectory ? '删除目录' : '删除文件'),
          content: Text(
            isDirectory
                ? '将从 ${(item.sourceKind == MediaSourceKind.quark ? 'Quark' : 'WebDAV')} 删除“${item.title}”对应目录及其中全部内容（含图片、字幕和 NFO），并从本地索引中移除相关条目。'
                : '将从 ${(item.sourceKind == MediaSourceKind.quark ? 'Quark' : 'WebDAV')} 删除“${item.title}”对应文件，并从本地索引中移除该条目。',
          ),
          actions: [
            StarflowButton(
              label: '取消',
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(false),
              variant: StarflowButtonVariant.ghost,
              compact: true,
            ),
            StarflowButton(
              label: '确认删除',
              onPressed: () => Navigator.of(context).pop(true),
              variant: StarflowButtonVariant.danger,
              compact: true,
            ),
          ],
        ),
      ) ??
      false;
  if (!confirmed || !context.mounted) {
    return;
  }
  final stopwatch = Stopwatch()..start();
  appLogInfo(
    'library.resource',
    'Media resource deletion started',
    fields: <String, Object?>{
      'sourceId': item.sourceId,
      'sourceKind': item.sourceKind.name,
      'itemType': item.itemType,
      'isDirectory': isDirectory,
    },
  );
  try {
    await ref.read(mediaRepositoryProvider).deleteResource(
          sourceId: item.sourceId,
          resourcePath: resourcePath,
          sectionId: item.sectionId,
        );
    appLogInfo(
      'library.resource',
      'Media resource deletion completed',
      fields: <String, Object?>{
        'sourceId': item.sourceId,
        'sourceKind': item.sourceKind.name,
        'itemType': item.itemType,
        'isDirectory': isDirectory,
        'durationMs': stopwatch.elapsedMilliseconds,
      },
    );
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(isDirectory ? '已删除目录' : '已删除文件')),
    );
  } catch (error, stackTrace) {
    appLogError(
      'library.resource',
      'Media resource deletion failed',
      fields: <String, Object?>{
        'sourceId': item.sourceId,
        'sourceKind': item.sourceKind.name,
        'itemType': item.itemType,
        'isDirectory': isDirectory,
        'durationMs': stopwatch.elapsedMilliseconds,
      },
      error: error,
      stackTrace: stackTrace,
    );
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('删除失败：$error')),
    );
  }
}
