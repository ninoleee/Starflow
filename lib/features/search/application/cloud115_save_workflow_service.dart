import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/features/library/application/media_refresh_coordinator.dart';
import 'package:starflow/features/search/application/cloud_saved_name_sanitizer.dart';
import 'package:starflow/features/search/data/cloud115_save_client.dart';
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
    onProgress?.call(const CloudSaveProgress.saving(CloudSaveDrive.cloud115));
    final stopwatch = Stopwatch()..start();
    final characters = config.cloud115SanitizeSavedNamesEnabled
        ? config.cloud115SanitizedNameCharacters.trim()
        : '';
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
    final count = result.savedCount;
    appLogInfo('115.save', '115 share save confirmed', fields: {
      'savedCount': count,
      'skippedCount': result.skippedCount,
      'durationMs': stopwatch.elapsedMilliseconds,
    });
    if (count == 0) {
      return CloudSaveSummary(
        drive: CloudSaveDrive.cloud115,
        savedCount: count,
        skippedCount: result.skippedCount,
      ).buildSuccessMessage();
    }
    final smartStrmDelay =
        config.smartStrmDelaySeconds <= 0 ? 1 : config.smartStrmDelaySeconds;
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
      try {
        smartStrmResult = await smartStrm.triggerTask(
          webhookUrl: config.smartStrmWebhookUrl,
          taskName: config.cloud115SmartStrmTaskName,
          storagePath: path == '/' ? '' : path,
          delay: smartStrmDelay,
        );
        appLogInfo('115.save', '115 SmartStrm trigger accepted');
      } catch (error) {
        // Saving already succeeded; still attempt the independent refresh.
        smartStrmFailure = error is SmartStrmWebhookException
            ? error.message
            : '请检查 SmartStrm 任务';
        appLogWarning('115.save', '115 SmartStrm trigger failed', fields: {
          'errorType': error.runtimeType.toString(),
        });
      }
    }
    int? refreshDelay;
    if (config.refreshMediaSourceIds.isNotEmpty) {
      refreshDelay =
          config.refreshDelaySeconds <= 0 ? 1 : config.refreshDelaySeconds;
      appLogInfo('115.save', '115 post-save media refresh scheduled', fields: {
        'sourceCount': config.refreshMediaSourceIds.length,
        'delaySeconds': refreshDelay,
      });
      unawaited(_refreshInBackground(config.refreshMediaSourceIds, refreshDelay,
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

  Future<void> _refreshInBackground(List<String> sourceIds, int delay,
      {void Function(String)? onFailure}) async {
    try {
      await refresh(sourceIds, delay);
    } catch (error) {
      appLogWarning('115.save', '115 post-save media refresh failed', fields: {
        'sourceCount': sourceIds.length,
        'errorType': error.runtimeType.toString(),
      });
      onFailure?.call(CloudSaveDrive.cloud115.refreshFailureMessage);
    }
  }
}
