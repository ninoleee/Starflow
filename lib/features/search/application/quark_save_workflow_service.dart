import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/features/library/application/media_refresh_coordinator.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/search/data/smart_strm_webhook_client.dart';
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

typedef QuarkSaveWorkflowProgressCallback = void Function(
  QuarkSaveWorkflowProgress progress,
);

enum QuarkSaveWorkflowStage {
  saving,
  saveCompleted,
  sanitizingNames,
  namesSanitized,
  triggeringSmartStrm,
  smartStrmTriggered,
  schedulingRefresh,
}

class QuarkSaveWorkflowProgress {
  const QuarkSaveWorkflowProgress({
    required this.stage,
    required this.message,
  });

  final QuarkSaveWorkflowStage stage;
  final String message;
}

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
    QuarkSaveWorkflowProgressCallback? onProgress,
  }) async {
    final cookie = networkStorage.quarkCookie.trim();
    if (cookie.isEmpty) {
      throw const QuarkSaveException('请先在搜索设置里填写夸克 Cookie');
    }

    // Empty unless sanitising is on, so deduplication compares the names the
    // drive will end up with rather than the share's original ones.
    final sanitizedNameCharacters =
        networkStorage.quarkSanitizeSavedNamesEnabled
            ? networkStorage.quarkSanitizedNameCharacters.trim()
            : '';

    _emitProgress(
      onProgress,
      QuarkSaveWorkflowStage.saving,
      '夸克保存中...',
    );
    final saveResult = await _saveShareLink(
      shareUrl: shareUrl,
      cookie: cookie,
      toPdirFid: networkStorage.quarkSaveFolderId,
      toPdirPath: networkStorage.quarkSaveFolderPath,
      saveFolderName: saveFolderName,
      sanitizedNameCharacters: sanitizedNameCharacters,
    );
    final savedAnyFiles = saveResult.savedCount > 0;
    final refreshDelaySeconds = _normalizeDelaySeconds(
      networkStorage.refreshDelaySeconds,
    );
    final smartStrmDelaySeconds = _normalizeDelaySeconds(
      networkStorage.smartStrmDelaySeconds,
    );
    var triggeredSmartStrm = false;
    SmartStrmTriggerResult? smartStrmResult;

    // Must run before SmartStrm is triggered: otherwise .strm files are
    // generated against the pre-rename paths and immediately go stale.
    QuarkNameSanitizeResult? sanitizeResult;
    if (sanitizedNameCharacters.isNotEmpty) {
      final skipReason = !savedAnyFiles
          ? 'nothing-saved'
          : saveResult.savedEntries.isEmpty
              ? 'no-entries-recorded'
              : !saveResult.savedEntriesSettled
                  // Quark never reported the copy as finished, so the entries
                  // are not listable yet and matching them would silently
                  // rename nothing.
                  ? 'save-task-unsettled'
                  : '';
      if (skipReason.isNotEmpty) {
        appLogWarning(
          'quark.save',
          'Saved name sanitising skipped',
          fields: <String, Object?>{
            'reason': skipReason,
            'savedCount': saveResult.savedCount,
            'savedEntryCount': saveResult.savedEntries.length,
            'characters': sanitizedNameCharacters,
          },
        );
      } else {
        _emitProgress(
          onProgress,
          QuarkSaveWorkflowStage.sanitizingNames,
          '已保存 ${saveResult.savedCount} 个，名称修改中...',
        );
        appLogInfo(
          'quark.save',
          'Saved name sanitising started',
          fields: <String, Object?>{
            'savedEntryCount': saveResult.savedEntries.length,
            'characters': sanitizedNameCharacters,
          },
        );
        // The files are already saved; a rename failure must not fail the save.
        try {
          sanitizeResult = await _sanitizeSavedNames(
            cookie: cookie,
            savedEntries: saveResult.savedEntries,
            characters: sanitizedNameCharacters,
          );
          appLogInfo(
            'quark.save',
            'Saved name sanitising completed',
            fields: <String, Object?>{
              'renamedCount': sanitizeResult.renamedCount,
              'listedDirectoryCount': sanitizeResult.listedDirectoryCount,
              'failedCount': sanitizeResult.failedNames.length,
            },
          );
        } on QuarkSaveException catch (error) {
          sanitizeResult = null;
          appLogWarning(
            'quark.save',
            'Saved name sanitising failed',
            error: error,
          );
        }
      }
    }

    if (savedAnyFiles &&
        networkStorage.smartStrmWebhookUrl.trim().isNotEmpty &&
        networkStorage.smartStrmTaskName.trim().isNotEmpty) {
      smartStrmResult = await _triggerSmartStrm(
        webhookUrl: networkStorage.smartStrmWebhookUrl,
        taskName: networkStorage.smartStrmTaskName,
        storagePath: networkStorage.quarkSaveFolderPath == '/'
            ? ''
            : networkStorage.quarkSaveFolderPath,
        delay: smartStrmDelaySeconds,
      );
      triggeredSmartStrm = true;
    }

    final refreshSourceIds = _resolveRefreshSourceIds(
      networkStorage: networkStorage,
      includeConfiguredSources: savedAnyFiles,
    );
    if (refreshSourceIds.isNotEmpty) {
      unawaited(
        _refreshSelectedSources(
          sourceIds: refreshSourceIds,
          delaySeconds: refreshDelaySeconds,
          invalidateWebDavDirectoryCache: savedAnyFiles,
        ),
      );
    }

    return QuarkSaveWorkflowResult(
      saveResult: saveResult,
      sanitizeResult: sanitizeResult,
      triggeredSmartStrm: triggeredSmartStrm,
      smartStrmResult: smartStrmResult,
      refreshSourceIds: refreshSourceIds,
      refreshDelaySeconds: refreshDelaySeconds,
      smartStrmDelaySeconds: smartStrmDelaySeconds,
    );
  }
}

void _emitProgress(
  QuarkSaveWorkflowProgressCallback? callback,
  QuarkSaveWorkflowStage stage,
  String message,
) {
  callback?.call(QuarkSaveWorkflowProgress(stage: stage, message: message));
}

class QuarkSaveWorkflowResult {
  const QuarkSaveWorkflowResult({
    required this.saveResult,
    this.sanitizeResult,
    required this.triggeredSmartStrm,
    required this.smartStrmResult,
    required this.refreshSourceIds,
    required this.refreshDelaySeconds,
    required this.smartStrmDelaySeconds,
  });

  final QuarkSaveResult saveResult;
  final QuarkNameSanitizeResult? sanitizeResult;
  final bool triggeredSmartStrm;
  final SmartStrmTriggerResult? smartStrmResult;
  final List<String> refreshSourceIds;
  final int refreshDelaySeconds;
  final int smartStrmDelaySeconds;

  String buildSuccessMessage() {
    final message = saveResult.taskId.isEmpty
        ? '已提交到夸克，${saveResult.summary}'
        : '已提交到夸克，任务 ${saveResult.taskId}，${saveResult.summary}';
    final smartStrmMessage = triggeredSmartStrm
        ? _buildSmartStrmSuccessMessage(
            smartStrmResult,
            delaySeconds: smartStrmDelaySeconds,
          )
        : '';
    final sanitize = sanitizeResult;
    final sanitizeMessage = sanitize == null || !sanitize.changedAnything
        ? ''
        : '，已修正 ${sanitize.renamedCount} 个名称'
            '${sanitize.failedNames.isEmpty ? '' : '（${sanitize.failedNames.length} 个失败）'}';
    final refreshMessage = refreshSourceIds.isEmpty
        ? ''
        : refreshDelaySeconds > 0
            ? '，$refreshDelaySeconds 秒后刷新媒体源'
            : '，即将刷新媒体源';
    return '$message$sanitizeMessage'
        '${smartStrmMessage.isEmpty ? '' : '，$smartStrmMessage'}$refreshMessage';
  }
}

int _normalizeDelaySeconds(int configuredDelaySeconds) {
  return configuredDelaySeconds <= 0 ? 1 : configuredDelaySeconds;
}

String _buildSmartStrmSuccessMessage(
  SmartStrmTriggerResult? result, {
  int delaySeconds = 0,
}) {
  if (delaySeconds > 0) {
    return 'STRM 已延迟 $delaySeconds 秒触发';
  }
  if (result == null) {
    return '已触发 STRM 任务';
  }
  final addedCount = result.addedCount;
  if (addedCount != null) {
    return 'STRM 新增成功 $addedCount 条';
  }
  final message = result.message.trim();
  if (message.isNotEmpty) {
    return 'STRM $message';
  }
  return '已触发 STRM 任务';
}
