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
    if (!config.syncDelete115Enabled) return null;
    final matches = config.syncDelete115WebDavDirectories
        .where((scope) => scope.sourceId == sourceId)
        .map((scope) =>
            cloud115RelativeDeletePath(resourcePath, scope.directoryId))
        .whereType<List<String>>()
        .toList();
    if (matches.isEmpty) return null;
    if (config.syncDeleteQuarkEnabled &&
        config.syncDeleteQuarkWebDavDirectories.any((scope) =>
            cloud115RelativeDeletePath(resourcePath, scope.directoryId) !=
            null)) {
      throw const QuarkSaveException('夸克与 115 删除监听范围重叠，请先调整配置');
    }
    matches.sort((a, b) => a.length.compareTo(b.length));
    final relative = matches.first;
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
        throw const QuarkSaveException('115 同步删除未找到唯一对应路径，未执行删除');
      }
      final entry = candidates.single;
      if (!RegExp(r'^[1-9][0-9]*$').hasMatch(entry.fid) ||
          entry.fid == parentId) {
        throw const QuarkSaveException('115 返回无效删除目标，未执行删除');
      }
      if (last) {
        return Cloud115DeletePlan(
            cookie: config.cloud115Cookie, parentId: parentId, entry: entry);
      }
      parentId = entry.fid;
      parentPath = entry.path;
    }
    return null;
  }

  Future<void> execute(Cloud115DeletePlan plan) => client.deleteEntries(
      cookie: plan.cookie, parentId: plan.parentId, fids: [plan.entry.fid]);
}
