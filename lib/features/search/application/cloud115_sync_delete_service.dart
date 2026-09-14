import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/features/search/data/cloud115_save_client.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

List<String>? cloud115RelativeDeletePath(String resource, String scope) {
  final resourceUri = Uri.tryParse(resource);
  final scopeUri = Uri.tryParse(scope);
  if (resourceUri == null || scopeUri == null) return null;
  if (scopeUri.hasAuthority &&
      (scopeUri.scheme != resourceUri.scheme ||
          scopeUri.authority != resourceUri.authority)) {
    return null;
  }
  final root = scopeUri.pathSegments.where((s) => s.isNotEmpty).toList();
  final path = resourceUri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (path.any((s) =>
          s == '.' || s == '..' || s.contains('/') || s.contains('\\')) ||
      root.length > path.length) {
    return null;
  }
  for (var i = 0; i < root.length; i++) {
    if (root[i] != path[i]) return null;
  }
  return path.sublist(root.length);
}

class Cloud115DeletePlan {
  const Cloud115DeletePlan(
      {required this.cookie, required this.parentId, required this.entry});
  final String cookie;
  final String parentId;
  final QuarkFileEntry entry;
}

class Cloud115SyncDeleteService {
  const Cloud115SyncDeleteService(this.client);
  final Cloud115SaveClient client;

  Future<Cloud115DeletePlan?> prepare(
      {required NetworkStorageConfig config,
      required String sourceId,
      required String resourcePath}) async {
    try {
      return await _prepare(
        config: config,
        sourceId: sourceId,
        resourcePath: resourcePath,
      );
    } catch (error) {
      appLogWarning(
        '115.sync-delete',
        '115 sync deletion preflight failed; no deletion submitted',
        fields: {
          'sourceId': sourceId,
          'errorType': error.runtimeType.toString()
        },
      );
      rethrow;
    }
  }

  Future<Cloud115DeletePlan?> _prepare(
      {required NetworkStorageConfig config,
      required String sourceId,
      required String resourcePath}) async {
    if (!config.syncDelete115Enabled) {
      appLogInfo('115.sync-delete', '115 sync deletion skipped', fields: {
        'sourceId': sourceId,
        'reason': 'setting_disabled',
      });
      return null;
    }
    final directories = config.syncDelete115WebDavDirectories
        .where((scope) =>
            scope.sourceId.trim().isNotEmpty &&
            scope.directoryId.trim().isNotEmpty)
        .toList(growable: false);
    if (directories.isEmpty) {
      appLogWarning('115.sync-delete', '115 deletion scope is not configured',
          fields: {
            'sourceId': sourceId,
            'reason': 'no_directories_configured',
            'scopeCount': 0,
          });
      throw const QuarkSaveException(
          '115 同步删除已开启，但未选择 WebDAV 删除监听目录；请先在 115 网盘设置中添加监听目录或关闭同步删除，本次未执行删除');
    }
    final matches = directories
        .where((scope) => scope.sourceId == sourceId)
        .map((scope) =>
            cloud115RelativeDeletePath(resourcePath, scope.directoryId))
        .whereType<List<String>>()
        .toList();
    if (matches.isEmpty) {
      appLogInfo('115.sync-delete', '115 sync deletion skipped', fields: {
        'sourceId': sourceId,
        'reason': 'resource_outside_selected_scope',
        'scopeCount': directories.length,
        'sourceScopeCount':
            directories.where((scope) => scope.sourceId == sourceId).length,
      });
      return null;
    }
    if (config.syncDeleteQuarkEnabled &&
        config.syncDeleteQuarkWebDavDirectories.any((scope) =>
            cloud115RelativeDeletePath(resourcePath, scope.directoryId) !=
            null)) {
      throw const QuarkSaveException('夸克与 115 删除监听范围重叠，请先调整配置');
    }
    matches.sort((a, b) => a.length.compareTo(b.length));
    final relative = matches.first;
    appLogInfo('115.sync-delete', '115 deletion scope matched', fields: {
      'sourceId': sourceId,
      'relativeDepth': relative.length,
    });
    if (relative.isEmpty) throw const QuarkSaveException('不能同步删除 115 保存根目录');
    if (config.cloud115Cookie.trim().isEmpty) {
      throw const QuarkSaveException('115 同步删除需要配置 Cookie');
    }
    var parentId = config.cloud115SaveFolderId;
    var parentPath = config.cloud115SaveFolderPath;
    for (var i = 0; i < relative.length; i++) {
      final entries = await client.listEntries(
          cookie: config.cloud115Cookie,
          parentFid: parentId,
          parentPath: parentPath);
      final name = relative[i];
      final last = i == relative.length - 1;
      final candidates = entries.where((entry) {
        if (!last) return entry.isDirectory && entry.name == name;
        if (entry.name == name) {
          return !name.toLowerCase().endsWith('.strm') || !entry.isDirectory;
        }
        if (!entry.isDirectory &&
            name.toLowerCase().endsWith('.strm') &&
            entry.isVideo) {
          final dot = entry.name.lastIndexOf('.');
          return dot > 0 &&
              entry.name.substring(0, dot) ==
                  name.substring(0, name.length - 5);
        }
        return false;
      }).toList();
      if (candidates.length != 1) {
        appLogWarning('115.sync-delete', '115 deletion target is not unique',
            fields: {
              'sourceId': sourceId,
              'pathDepth': i + 1,
              'candidateCount': candidates.length,
            });
        throw const QuarkSaveException('115 同步删除未找到唯一对应路径，未执行删除');
      }
      final entry = candidates.single;
      if (!RegExp(r'^[1-9][0-9]*$').hasMatch(entry.fid) ||
          entry.fid == parentId) {
        throw const QuarkSaveException('115 返回无效删除目标，未执行删除');
      }
      if (last) {
        appLogInfo('115.sync-delete', '115 deletion target prepared', fields: {
          'sourceId': sourceId,
          'isDirectory': entry.isDirectory,
          'relativeDepth': relative.length,
        });
        return Cloud115DeletePlan(
            cookie: config.cloud115Cookie, parentId: parentId, entry: entry);
      }
      parentId = entry.fid;
      parentPath = entry.path;
    }
    return null;
  }

  Future<void> execute(Cloud115DeletePlan plan) async {
    final stopwatch = Stopwatch()..start();
    appLogInfo('115.sync-delete', '115 recycle deletion started', fields: {
      'isDirectory': plan.entry.isDirectory,
    });
    try {
      await client.deleteEntries(
          cookie: plan.cookie, parentId: plan.parentId, fids: [plan.entry.fid]);
      final remaining = await client.listEntries(
          cookie: plan.cookie, parentFid: plan.parentId);
      if (remaining.any((entry) => entry.fid == plan.entry.fid)) {
        throw const QuarkSaveException('115 删除未生效：远端文件或目录仍然存在');
      }
      appLogInfo('115.sync-delete', '115 recycle deletion confirmed', fields: {
        'durationMs': stopwatch.elapsedMilliseconds,
      });
    } catch (error) {
      appLogWarning('115.sync-delete', '115 recycle deletion not confirmed',
          fields: {
            'durationMs': stopwatch.elapsedMilliseconds,
            'errorType': error.runtimeType.toString(),
          });
      rethrow;
    }
  }
}
