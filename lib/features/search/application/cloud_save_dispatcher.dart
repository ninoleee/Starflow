import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/search/application/cloud115_save_workflow_service.dart';
import 'package:starflow/features/search/application/quark_save_workflow_service.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/search/data/smart_strm_webhook_client.dart';
import 'package:starflow/features/search/domain/cloud_save_feedback.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

final cloudSaveDispatcherProvider = Provider((ref) => CloudSaveDispatcher(
      cloud115: ref.watch(cloud115SaveWorkflowProvider),
      quark: ref.watch(quarkSaveWorkflowServiceProvider),
    ));

enum CloudSaveFailureKind {
  credentials,
  unsupported,
  save,
  smartStrm,
  unexpected
}

class CloudSaveOutcome {
  const CloudSaveOutcome.success(this.drive, this.message)
      : failureKind = null,
        error = null,
        stackTrace = null;

  const CloudSaveOutcome.failure(this.drive, this.message, this.failureKind,
      {this.error, this.stackTrace});

  final CloudSaveDrive? drive;
  final String message;
  final CloudSaveFailureKind? failureKind;
  final Object? error;
  final StackTrace? stackTrace;
  bool get isSuccess => failureKind == null;
}

/// Shared entry point; protocol-specific saves and postprocessing stay in their
/// existing workflows. Failures retain their cause for caller-owned tracing.
class CloudSaveDispatcher {
  const CloudSaveDispatcher({required this.cloud115, required this.quark});

  final Cloud115SaveWorkflowService cloud115;
  final QuarkSaveWorkflowService quark;

  static CloudSaveDrive? driveFor(SearchResult result) {
    if (result.detailTarget != null) return null;
    return switch (detectSearchCloudTypeFromUrl(result.resourceUrl)) {
      SearchCloudType.cloud115 => CloudSaveDrive.cloud115,
      SearchCloudType.quark => CloudSaveDrive.quark,
      _ => null,
    };
  }

  static bool canSave(SearchResult result, NetworkStorageConfig config) =>
      switch (driveFor(result)) {
        CloudSaveDrive.cloud115 => config.cloud115Cookie.trim().isNotEmpty,
        CloudSaveDrive.quark => config.quarkCookie.trim().isNotEmpty,
        null => false,
      };

  Future<CloudSaveOutcome> save({
    required SearchResult result,
    required NetworkStorageConfig networkStorage,
    required String saveFolderName,
    CloudSaveProgressCallback? onProgress,
    void Function(String)? onBackgroundRefreshFailure,
  }) async {
    final drive = driveFor(result);
    if (drive == null) {
      return const CloudSaveOutcome.failure(
          null, '暂不支持保存此资源', CloudSaveFailureKind.unsupported);
    }
    if (!canSave(result, networkStorage)) {
      return CloudSaveOutcome.failure(
        drive,
        drive == CloudSaveDrive.cloud115
            ? '请先在网盘与转存设置里填写 115 Cookie'
            : '请先在网盘与转存设置里填写夸克 Cookie',
        CloudSaveFailureKind.credentials,
      );
    }
    try {
      final share = prepareSearchResultShareCredentials(result);
      final String message;
      if (drive == CloudSaveDrive.cloud115) {
        message = await cloud115.save(
          shareUrl: share.resourceUrl,
          password: searchResultSharePassword(share),
          config: networkStorage,
          saveFolderName: saveFolderName,
          onProgress: onProgress,
          onBackgroundRefreshFailure: onBackgroundRefreshFailure,
        );
      } else {
        final response = await quark.saveToQuark(
          shareUrl: share.resourceUrl,
          networkStorage: networkStorage,
          saveFolderName: saveFolderName,
          onProgress: onProgress,
          onBackgroundRefreshFailure: onBackgroundRefreshFailure,
        );
        message = response.buildSuccessMessage();
      }
      return CloudSaveOutcome.success(drive, message);
    } catch (error, stackTrace) {
      final (kind, message) = switch (error) {
        QuarkSaveException() => (CloudSaveFailureKind.save, error.message),
        SmartStrmWebhookException() => (
            CloudSaveFailureKind.smartStrm,
            drive.smartStrmFailureMessage(error.message),
          ),
        _ => (
            CloudSaveFailureKind.unexpected,
            drive == CloudSaveDrive.cloud115
                ? '115 保存未确认，请检查网盘后再重试'
                : '保存失败：$error',
          ),
      };
      return CloudSaveOutcome.failure(drive, message, kind,
          error: error, stackTrace: stackTrace);
    }
  }
}
