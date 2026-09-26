import 'package:starflow/features/search/application/aliyun_to115_workflow.dart';
import 'package:starflow/features/search/application/cloud115_sync_delete_service.dart';
import 'package:starflow/features/search/data/aliyun_transfer_client.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/search/domain/cloud_save_rules.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

class AliyunDeletePlan {
  const AliyunDeletePlan(this.session, this.parentId, this.entry);
  final AliyunTransferSession session;
  final String parentId;
  final AliyunTransferFile entry;
}

class AliyunSyncDeleteService {
  const AliyunSyncDeleteService(this.workflow);
  final AliyunTo115Workflow workflow;

  Future<AliyunDeletePlan?> prepare(
      {required NetworkStorageConfig config,
      required String sourceId,
      required String resourcePath}) async {
    // Once the destination changes to 115, Aliyun is only temporary storage.
    if (config.aliyunTo115Enabled || !config.syncDeleteAliyunEnabled) {
      return null;
    }
    final scopes = config.syncDeleteAliyunWebDavDirectories
        .where((s) =>
            s.sourceId.trim().isNotEmpty && s.directoryId.trim().isNotEmpty)
        .toList();
    if (scopes.isEmpty) {
      throw const QuarkSaveException('阿里同步删除未配置 WebDAV 监听目录，本次未删除');
    }
    final paths = scopes
        .where((s) => s.sourceId == sourceId)
        .map((s) => cloud115RelativeDeletePath(resourcePath, s.directoryId))
        .whereType<List<String>>()
        .toList();
    if (paths.isEmpty) return null;
    final otherScopes = [
      if (config.syncDelete115Enabled) ...config.syncDelete115WebDavDirectories,
      if (config.syncDeleteQuarkEnabled)
        ...config.syncDeleteQuarkWebDavDirectories,
    ];
    if (otherScopes.any((s) =>
        s.sourceId == sourceId &&
        cloud115RelativeDeletePath(resourcePath, s.directoryId) != null)) {
      throw const QuarkSaveException('阿里与其他网盘删除监听范围重叠，未执行删除');
    }
    paths.sort((a, b) => a.length.compareTo(b.length));
    final path = paths.first;
    if (path.isEmpty) throw const QuarkSaveException('不能同步删除阿里保存根目录');
    final session = await workflow.connect(config);
    var parent = config.aliyunSaveFolderId;
    for (var i = 0; i < path.length; i++) {
      final last = i == path.length - 1;
      final name = path[i];
      final matches =
          (await workflow.aliyun.listOwned(session, parent)).where((entry) {
        if (!last) return entry.isDirectory && entry.name == name;
        if (entry.name == name) {
          return !name.toLowerCase().endsWith('.strm') || !entry.isDirectory;
        }
        final dot = entry.name.lastIndexOf('.');
        return name.toLowerCase().endsWith('.strm') &&
            !entry.isDirectory &&
            CloudSavePreviewEntry(
                    name: entry.name,
                    relativePath: entry.name,
                    isDirectory: false)
                .isVideo &&
            dot > 0 &&
            entry.name.substring(0, dot) == name.substring(0, name.length - 5);
      }).toList();
      if (matches.length != 1 ||
          matches.single.id == parent ||
          matches.single.id == 'root') {
        throw const QuarkSaveException('阿里同步删除未找到唯一对应路径，未执行删除');
      }
      if (last) return AliyunDeletePlan(session, parent, matches.single);
      parent = matches.single.id;
    }
    return null;
  }

  Future<void> execute(AliyunDeletePlan plan) async {
    final rows = await workflow.aliyun.listOwned(plan.session, plan.parentId);
    final matches = rows.where((e) => e.id == plan.entry.id).toList();
    if (matches.length != 1 ||
        matches.single.name != plan.entry.name ||
        matches.single.isDirectory != plan.entry.isDirectory ||
        matches.single.size != plan.entry.size ||
        matches.single.sha1 != plan.entry.sha1) {
      throw const QuarkSaveException('阿里删除目标已变化，未执行删除');
    }
    await workflow.aliyun
        .recycleOwned(plan.session, plan.parentId, [plan.entry.id]);
  }
}
