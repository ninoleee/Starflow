import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/library/application/media_refresh_coordinator.dart';
import 'package:starflow/features/search/data/cloud115_save_client.dart';
import 'package:starflow/features/search/data/smart_strm_webhook_client.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

final cloud115SaveWorkflowProvider = Provider((ref) {
  return Cloud115SaveWorkflowService(
    ref.watch(cloud115SaveClientProvider),
    (ids, delay) =>
        ref.read(mediaRefreshCoordinatorProvider).refreshSelectedSources(
              sourceIds: ids,
              delaySeconds: delay,
              invalidateWebDavDirectoryCache: true,
            ),
    smartStrm: ref.watch(smartStrmWebhookClientProvider),
  );
});

class Cloud115SaveWorkflowService {
  const Cloud115SaveWorkflowService(this.client, this.refresh,
      {required this.smartStrm});
  final Cloud115SaveClient client;
  final SmartStrmWebhookClient smartStrm;
  final Future<void> Function(List<String>, int) refresh;

  Future<String> save(
      {required String shareUrl,
      required NetworkStorageConfig config,
      String password = ''}) async {
    final count = await client.saveShareLink(
        shareUrl: shareUrl,
        cookie: config.cloud115Cookie,
        folderId: config.cloud115SaveFolderId,
        password: password);
    final messages = ['已保存到 115，共 $count 个文件或目录'];
    if (count > 0 &&
        config.smartStrmWebhookUrl.trim().isNotEmpty &&
        config.cloud115SmartStrmTaskName.trim().isNotEmpty) {
      final delay =
          config.smartStrmDelaySeconds <= 0 ? 1 : config.smartStrmDelaySeconds;
      final path = config.cloud115SaveFolderPath.trim();
      try {
        await smartStrm.triggerTask(
          webhookUrl: config.smartStrmWebhookUrl,
          taskName: config.cloud115SmartStrmTaskName,
          storagePath: path == '/' ? '' : path,
          delay: delay,
        );
        messages.add('STRM 已延迟 $delay 秒触发');
      } catch (_) {
        // Saving already succeeded; still attempt the independent refresh.
        messages.add('但 STRM 触发失败，请检查 SmartStrm 任务');
      }
    }
    if (config.refreshMediaSourceIds.isEmpty) return messages.join('，');
    try {
      await refresh(config.refreshMediaSourceIds,
          config.refreshDelaySeconds <= 0 ? 1 : config.refreshDelaySeconds);
      messages.add('已执行媒体源刷新');
    } catch (_) {
      messages.add('但媒体源刷新失败，请手动刷新');
    }
    return messages.join('，');
  }
}
