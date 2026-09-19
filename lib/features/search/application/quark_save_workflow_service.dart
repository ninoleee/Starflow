import 'dart:async';
import 'package:starflow/features/search/application/cloud_save_postprocessing.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/features/library/application/media_refresh_coordinator.dart';
import 'package:starflow/features/search/application/cloud_saved_name_sanitizer.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/search/data/smart_strm_webhook_client.dart';
import 'package:starflow/features/search/domain/cloud_save_feedback.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

typedef QuarkSaveWorkflowSaveShareLink = Future<QuarkSaveResult> Function({
  required String shareUrl,
  required String cookie,
  String toPdirFid,
  String toPdirPath,
  String saveFolderName,
  String sanitizedNameCharacters,
});

typedef QuarkSaveWorkflowSanitizeSavedNames = Future<QuarkNameSanitizeResult>
    Function({
  required String cookie,
  required List<QuarkSavedEntry> savedEntries,
  required String characters,
});

typedef QuarkSaveWorkflowTriggerSmartStrm = Future<SmartStrmTriggerResult>
    Function({
  required String webhookUrl,
  required String taskName,
  String storagePath,
  int delay,
});

typedef QuarkSaveWorkflowResolveRefreshSourceIds = List<String> Function({
  required NetworkStorageConfig networkStorage,
  required bool includeConfiguredSources,
});

typedef QuarkSaveWorkflowRefreshSelectedSources = Future<void> Function({
  required List<String> sourceIds,
  required int delaySeconds,
  required bool invalidateWebDavDirectoryCache,
});

final quarkSaveWorkflowServiceProvider = Provider<QuarkSaveWorkflowService>((
  ref,
) {
  return QuarkSaveWorkflowService(
    saveShareLink: ({
      required String shareUrl,
      required String cookie,
      String toPdirFid = '0',
      String toPdirPath = '/',
      String saveFolderName = '',
      String sanitizedNameCharacters = '',
    }) {
      return ref.read(quarkSaveClientProvider).saveShareLink(
            shareUrl: shareUrl,
            cookie: cookie,
            toPdirFid: toPdirFid,
            toPdirPath: toPdirPath,
            saveFolderName: saveFolderName,
            sanitizedNameCharacters: sanitizedNameCharacters,
          );
    },
    sanitizeSavedNames: ({
      required String cookie,
      required List<QuarkSavedEntry> savedEntries,
      required String characters,
    }) {
      return ref.read(quarkSaveClientProvider).sanitizeSavedEntries(
            cookie: cookie,
            savedEntries: savedEntries,
            characters: characters,
          );
    },
    triggerSmartStrm: ({
      required String webhookUrl,
      required String taskName,
      String storagePath = '',
      int delay = 0,
    }) {
      return ref.read(smartStrmWebhookClientProvider).triggerTask(
            webhookUrl: webhookUrl,
            taskName: taskName,
            storagePath: storagePath,
            delay: delay,
          );
    },
    resolveRefreshSourceIds: ({
      required NetworkStorageConfig networkStorage,
      required bool includeConfiguredSources,
    }) {
      final settings = ref.read(appSettingsProvider);
      return resolveRefreshSourceIdsForQuarkSave(
        mediaSources: settings.mediaSources,
        configuredRefreshSourceIds: networkStorage.refreshMediaSourceIds,
        includeConfiguredSources: includeConfiguredSources,
      );
    },
    refreshSelectedSources: ({
      required List<String> sourceIds,
      required int delaySeconds,
      required bool invalidateWebDavDirectoryCache,
    }) {
      return ref.read(mediaRefreshCoordinatorProvider).refreshSelectedSources(
            sourceIds: sourceIds,
            delaySeconds: delaySeconds,
            invalidateWebDavDirectoryCache: invalidateWebDavDirectoryCache,
          );
    },
  );
});

class QuarkSaveWorkflowService {
  const QuarkSaveWorkflowService({
    required QuarkSaveWorkflowSaveShareLink saveShareLink,
    required QuarkSaveWorkflowSanitizeSavedNames sanitizeSavedNames,
    required QuarkSaveWorkflowTriggerSmartStrm triggerSmartStrm,
    required QuarkSaveWorkflowResolveRefreshSourceIds resolveRefreshSourceIds,
    required QuarkSaveWorkflowRefreshSelectedSources refreshSelectedSources,
  })  : _saveShareLink = saveShareLink,
        _sanitizeSavedNames = sanitizeSavedNames,
        _triggerSmartStrm = triggerSmartStrm,
        _resolveRefreshSourceIds = resolveRefreshSourceIds,
        _refreshSelectedSources = refreshSelectedSources;

  final QuarkSaveWorkflowSaveShareLink _saveShareLink;
  final QuarkSaveWorkflowSanitizeSavedNames _sanitizeSavedNames;
  final QuarkSaveWorkflowTriggerSmartStrm _triggerSmartStrm;
  final QuarkSaveWorkflowResolveRefreshSourceIds _resolveRefreshSourceIds;
  final QuarkSaveWorkflowRefreshSelectedSources _refreshSelectedSources;

  Future<QuarkSaveWorkflowResult> saveToQuark({
    required String shareUrl,
    required String saveFolderName,
    required NetworkStorageConfig networkStorage,
    CloudSaveProgressCallback? onProgress,
    void Function(String)? onBackgroundRefreshFailure,
  }) async {
    final cookie = networkStorage.quarkCookie.trim();
    if (cookie.isEmpty) {
      throw const QuarkSaveException('请先在网盘与转存设置里填写夸克 Cookie');
    }

    // Empty unless sanitising is on, so deduplication compares the names the
    // drive will end up with rather than the share's original ones.
    final sanitizedNameCharacters =
        networkStorage.quarkSanitizeSavedNamesEnabled
            ? networkStorage.quarkSanitizedNameCharacters.trim()
            : '';

    onProgress?.call(const CloudSaveProgress.saving(CloudSaveDrive.quark));
    final saveResult = await _saveShareLink(
      shareUrl: shareUrl,
      cookie: cookie,
      toPdirFid: networkStorage.quarkSaveFolderId,
      toPdirPath: networkStorage.quarkSaveFolderPath,
      saveFolderName: saveFolderName,
      sanitizedNameCharacters: sanitizedNameCharacters,
    );
    final savedAnyFiles = saveResult.savedCount > 0;
    final refreshDelaySeconds = cloudSaveDelaySeconds(
      networkStorage.refreshDelaySeconds,
    );
    final smartStrmDelaySeconds = cloudSaveDelaySeconds(
      networkStorage.smartStrmDelaySeconds,
    );
    var triggeredSmartStrm = false;
    SmartStrmTriggerResult? smartStrmResult;
    var smartStrmFailure = '';

    final nameOutcome = await processCloudSavedNames(
      characters: sanitizedNameCharacters,
      savedCount: saveResult.savedCount,
      savedEntries: saveResult.savedEntries,
      settled: saveResult.savedEntriesSettled,
      onStart: () {
        onProgress?.call(CloudSaveProgress.sanitizingNames(
          CloudSaveDrive.quark,
          saveResult.savedCount,
        ));
        appLogInfo('quark.save', 'Saved name sanitising started');
      },
      sanitize: () => _sanitizeSavedNames(
        cookie: cookie,
        savedEntries: saveResult.savedEntries,
        characters: sanitizedNameCharacters,
      ),
    );
    final sanitizeResult = nameOutcome.result;
    if (sanitizeResult != null) {
      appLogInfo('quark.save', 'Saved name sanitising completed', fields: {
        'renamedCount': sanitizeResult.renamedCount,
        'listedDirectoryCount': sanitizeResult.listedDirectoryCount,
        'failedCount': sanitizeResult.failedNames.length,
      });
    }
    if (!nameOutcome.canTriggerSmartStrm) {
      appLogWarning('quark.save', 'Saved names not confirmed; STRM skipped');
    }

    if (savedAnyFiles &&
        nameOutcome.canTriggerSmartStrm &&
        networkStorage.smartStrmWebhookUrl.trim().isNotEmpty &&
        networkStorage.smartStrmTaskName.trim().isNotEmpty) {
      final outcome = await triggerSavedCloudStrm(
          drive: CloudSaveDrive.quark,
          trigger: () => _triggerSmartStrm(
                webhookUrl: networkStorage.smartStrmWebhookUrl,
                taskName: networkStorage.smartStrmTaskName,
                storagePath: saveResult.targetFolderPath == '/'
                    ? ''
                    : saveResult.targetFolderPath,
                delay: smartStrmDelaySeconds,
              ));
      smartStrmResult = outcome.result;
      smartStrmFailure = outcome.failure;
      triggeredSmartStrm = smartStrmResult != null;
    }

    final refreshSourceIds = _resolveRefreshSourceIds(
      networkStorage: networkStorage,
      includeConfiguredSources: savedAnyFiles,
    );
    if (refreshSourceIds.isNotEmpty) {
      unawaited(
        refreshSavedCloudMedia(
          drive: CloudSaveDrive.quark,
          refresh: () => _refreshSelectedSources(
            sourceIds: refreshSourceIds,
            delaySeconds: refreshDelaySeconds,
            invalidateWebDavDirectoryCache: savedAnyFiles,
          ),
          onFailure: onBackgroundRefreshFailure,
        ),
      );
    }

    return QuarkSaveWorkflowResult(
      saveResult: saveResult,
      sanitizeResult: sanitizeResult,
      nameWarning: nameOutcome.warning,
      triggeredSmartStrm: triggeredSmartStrm,
      smartStrmResult: smartStrmResult,
      smartStrmFailure: smartStrmFailure,
      refreshSourceIds: refreshSourceIds,
      refreshDelaySeconds: refreshDelaySeconds,
      smartStrmDelaySeconds: smartStrmDelaySeconds,
    );
  }
}

class QuarkSaveWorkflowResult {
  const QuarkSaveWorkflowResult({
    required this.saveResult,
    this.sanitizeResult,
    this.nameWarning = '',
    this.smartStrmFailure = '',
    required this.triggeredSmartStrm,
    required this.smartStrmResult,
    required this.refreshSourceIds,
    required this.refreshDelaySeconds,
    required this.smartStrmDelaySeconds,
  });

  final QuarkSaveResult saveResult;
  final QuarkNameSanitizeResult? sanitizeResult;
  final String nameWarning;
  final String smartStrmFailure;
  final bool triggeredSmartStrm;
  final SmartStrmTriggerResult? smartStrmResult;
  final List<String> refreshSourceIds;
  final int refreshDelaySeconds;
  final int smartStrmDelaySeconds;

  String buildSuccessMessage() {
    return CloudSaveSummary(
      drive: CloudSaveDrive.quark,
      savedCount: saveResult.savedCount,
      skippedCount: saveResult.skippedCount,
      taskId: saveResult.taskId,
      renamedCount: sanitizeResult?.renamedCount ?? 0,
      renameFailedCount: sanitizeResult?.failedNames.length ?? 0,
      nameWarning: nameWarning,
      smartStrmFailure: smartStrmFailure,
      smartStrmTriggered: triggeredSmartStrm,
      smartStrmDelaySeconds: smartStrmDelaySeconds,
      smartStrmAddedCount: smartStrmResult?.addedCount,
      smartStrmMessage: smartStrmResult?.message ?? '',
      refreshDelaySeconds:
          refreshSourceIds.isEmpty ? null : refreshDelaySeconds,
    ).buildSuccessMessage();
  }
}
