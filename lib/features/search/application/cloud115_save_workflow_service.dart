import 'dart:async';
import 'package:starflow/features/search/application/cloud_save_postprocessing.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/features/library/application/media_refresh_coordinator.dart';
import 'package:starflow/features/search/application/cloud_saved_name_sanitizer.dart';
import 'package:starflow/features/search/data/cloud115_save_client.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/search/data/smart_strm_webhook_client.dart';
import 'package:starflow/features/search/domain/cloud_save_feedback.dart';
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
      String password = '',
      String saveFolderName = '',
      CloudSaveProgressCallback? onProgress,
      void Function(String)? onBackgroundRefreshFailure}) async {
    if (config.cloud115SaveFolderId.isEmpty) {
      throw const QuarkSaveException('115 账号已变化，请重新选择保存目录');
    }
    onProgress?.call(const CloudSaveProgress.saving(CloudSaveDrive.cloud115));
    final stopwatch = Stopwatch()..start();
    final characters = config.effective115NameCharacters;
    appLogInfo('115.save', '115 share save started');
    late final Cloud115SaveResult result;
    try {
      result = await client.saveShareLink(
          shareUrl: shareUrl,
          cookie: config.cloud115Cookie,
          folderId: config.cloud115SaveFolderId,
          folderPath: config.cloud115SaveFolderPath,
          saveFolderName: saveFolderName,
          sanitizedNameCharacters: characters,
          password: password);
    } catch (error) {
      appLogWarning('115.save', '115 share save not confirmed', fields: {
        'durationMs': stopwatch.elapsedMilliseconds,
        'errorType': error.runtimeType.toString(),
      });
      rethrow;
    }
    return finishSavedResult(
        result: result,
        config: config,
        onProgress: onProgress,
        onBackgroundRefreshFailure: onBackgroundRefreshFailure);
  }

  Future<String> finishSavedResult(
      {required Cloud115SaveResult result,
      required NetworkStorageConfig config,
      CloudSaveProgressCallback? onProgress,
      void Function(String)? onBackgroundRefreshFailure}) async {
    final characters = config.effective115NameCharacters;
    final count = result.savedCount;
    appLogInfo('115.save', '115 share save confirmed', fields: {
      'savedCount': count,
      'skippedCount': result.skippedCount,
    });
    if (count == 0) {
      return CloudSaveSummary(
        drive: CloudSaveDrive.cloud115,
        savedCount: count,
        skippedCount: result.skippedCount,
      ).buildSuccessMessage();
    }
    final smartStrmDelay = cloudSaveDelaySeconds(config.smartStrmDelaySeconds);
    final nameOutcome = await processCloudSavedNames(
      characters: characters,
      savedCount: count,
      savedEntries: result.savedEntries,
      settled: true,
      onStart: () {
        onProgress?.call(
            CloudSaveProgress.sanitizingNames(CloudSaveDrive.cloud115, count));
        appLogInfo('115.save', 'Saved name sanitising started');
      },
      sanitize: () => client.sanitizeSavedEntries(
        cookie: config.cloud115Cookie,
        savedEntries: result.savedEntries,
        characters: characters,
      ),
    );
    final sanitizeResult = nameOutcome.result;
    if (sanitizeResult != null) {
      appLogInfo('115.save', 'Saved name sanitising completed', fields: {
        'renamedCount': sanitizeResult.renamedCount,
        'listedDirectoryCount': sanitizeResult.listedDirectoryCount,
        'failedCount': sanitizeResult.failedNames.length,
      });
    }
    if (!nameOutcome.canTriggerSmartStrm) {
      appLogWarning('115.save', 'Saved names not confirmed; STRM skipped');
    }
    SmartStrmTriggerResult? smartStrmResult;
    var smartStrmFailure = '';
    if (nameOutcome.canTriggerSmartStrm &&
        config.smartStrmWebhookUrl.trim().isNotEmpty &&
        config.cloud115SmartStrmTaskName.trim().isNotEmpty) {
      final path = result.targetFolderPath;
      appLogInfo('115.save', '115 SmartStrm trigger started', fields: {
        'delaySeconds': smartStrmDelay,
      });
      final outcome = await triggerSavedCloudStrm(
          drive: CloudSaveDrive.cloud115,
          trigger: () => smartStrm.triggerTask(
                webhookUrl: config.smartStrmWebhookUrl,
                taskName: config.cloud115SmartStrmTaskName,
                storagePath: path == '/' ? '' : path,
                delay: smartStrmDelay,
              ));
      smartStrmResult = outcome.result;
      smartStrmFailure = outcome.failure;
    }
    int? refreshDelay;
    if (config.refreshMediaSourceIds.isNotEmpty) {
      refreshDelay = cloudSaveDelaySeconds(config.refreshDelaySeconds);
      appLogInfo('115.save', '115 post-save media refresh scheduled', fields: {
        'sourceCount': config.refreshMediaSourceIds.length,
        'delaySeconds': refreshDelay,
      });
      final delay = refreshDelay;
      unawaited(refreshSavedCloudMedia(
          drive: CloudSaveDrive.cloud115,
          refresh: () => refresh(config.refreshMediaSourceIds, delay),
          onFailure: onBackgroundRefreshFailure));
    }
    return CloudSaveSummary(
      drive: CloudSaveDrive.cloud115,
      savedCount: count,
      skippedCount: result.skippedCount,
      smartStrmTriggered: smartStrmResult != null,
      renamedCount: sanitizeResult?.renamedCount ?? 0,
      renameFailedCount: sanitizeResult?.failedNames.length ?? 0,
      nameWarning: nameOutcome.warning,
      smartStrmDelaySeconds: smartStrmDelay,
      smartStrmAddedCount: smartStrmResult?.addedCount,
      smartStrmMessage: smartStrmResult?.message ?? '',
      smartStrmFailure: smartStrmFailure,
      refreshDelaySeconds: refreshDelay,
    ).buildSuccessMessage();
  }
}
