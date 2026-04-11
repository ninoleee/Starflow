import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    }) {
      return ref.read(quarkSaveClientProvider).saveShareLink(
            shareUrl: shareUrl,
            cookie: cookie,
            toPdirFid: toPdirFid,
            toPdirPath: toPdirPath,
            saveFolderName: saveFolderName,
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
    }) {
      return ref.read(mediaRefreshCoordinatorProvider).refreshSelectedSources(
            sourceIds: sourceIds,
            delaySeconds: delaySeconds,
          );
    },
  );
});

class QuarkSaveWorkflowService {
  const QuarkSaveWorkflowService({
    required QuarkSaveWorkflowSaveShareLink saveShareLink,
    required QuarkSaveWorkflowTriggerSmartStrm triggerSmartStrm,
    required QuarkSaveWorkflowResolveRefreshSourceIds resolveRefreshSourceIds,
    required QuarkSaveWorkflowRefreshSelectedSources refreshSelectedSources,
  })  : _saveShareLink = saveShareLink,
        _triggerSmartStrm = triggerSmartStrm,
        _resolveRefreshSourceIds = resolveRefreshSourceIds,
        _refreshSelectedSources = refreshSelectedSources;

  final QuarkSaveWorkflowSaveShareLink _saveShareLink;
  final QuarkSaveWorkflowTriggerSmartStrm _triggerSmartStrm;
  final QuarkSaveWorkflowResolveRefreshSourceIds _resolveRefreshSourceIds;
  final QuarkSaveWorkflowRefreshSelectedSources _refreshSelectedSources;

  Future<QuarkSaveWorkflowResult> saveToQuark({
    required String shareUrl,
    required String saveFolderName,
    required NetworkStorageConfig networkStorage,
  }) async {
    final cookie = networkStorage.quarkCookie.trim();
    if (cookie.isEmpty) {
      throw const QuarkSaveException('请先在搜索设置里填写夸克 Cookie');
    }

    final saveResult = await _saveShareLink(
      shareUrl: shareUrl,
      cookie: cookie,
      toPdirFid: networkStorage.quarkSaveFolderId,
      toPdirPath: networkStorage.quarkSaveFolderPath,
      saveFolderName: saveFolderName,
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
        ),
      );
    }

    return QuarkSaveWorkflowResult(
      saveResult: saveResult,
      triggeredSmartStrm: triggeredSmartStrm,
      smartStrmResult: smartStrmResult,
      refreshSourceIds: refreshSourceIds,
      refreshDelaySeconds: refreshDelaySeconds,
      smartStrmDelaySeconds: smartStrmDelaySeconds,
    );
  }
}

class QuarkSaveWorkflowResult {
  const QuarkSaveWorkflowResult({
    required this.saveResult,
    required this.triggeredSmartStrm,
    required this.smartStrmResult,
    required this.refreshSourceIds,
    required this.refreshDelaySeconds,
    required this.smartStrmDelaySeconds,
  });

  final QuarkSaveResult saveResult;
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
    final refreshMessage = refreshSourceIds.isEmpty
        ? ''
        : refreshDelaySeconds > 0
            ? '，$refreshDelaySeconds 秒后刷新媒体源'
            : '，即将刷新媒体源';
    return '$message${smartStrmMessage.isEmpty ? '' : '，$smartStrmMessage'}$refreshMessage';
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
