import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/features/search/application/aliyun_to115_workflow.dart';
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
      aliyun: ref.watch(aliyunTo115WorkflowProvider),
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
  const CloudSaveDispatcher(
      {required this.cloud115, required this.quark, this.aliyun});

  final AliyunTo115Workflow? aliyun;

  final Cloud115SaveWorkflowService cloud115;
  final QuarkSaveWorkflowService quark;

  static CloudSaveDrive? driveFor(SearchResult result,
      [NetworkStorageConfig config = const NetworkStorageConfig()]) {
    if (result.detailTarget != null) return null;
    return switch (detectSearchCloudTypeFromUrl(result.resourceUrl)) {
      SearchCloudType.cloud115 => CloudSaveDrive.cloud115,
      SearchCloudType.aliyun => config.aliyunTo115Enabled
          ? CloudSaveDrive.cloud115
          : CloudSaveDrive.aliyun,
      SearchCloudType.quark => CloudSaveDrive.quark,
      _ => null,
    };
  }

  static bool canSave(SearchResult result, NetworkStorageConfig config) =>
      detectSearchCloudTypeFromUrl(result.resourceUrl) == SearchCloudType.aliyun
          ? result.detailTarget == null &&
              config.hasAliyunCredential &&
              (!config.aliyunTo115Enabled ||
                  config.cloud115Cookie.trim().isNotEmpty)
          : switch (driveFor(result)) {
              CloudSaveDrive.cloud115 =>
                config.cloud115Cookie.trim().isNotEmpty,
              CloudSaveDrive.quark => config.quarkCookie.trim().isNotEmpty,
              CloudSaveDrive.aliyun => config.hasAliyunCredential,
              null => false,
            };

  Future<CloudSaveOutcome> save({
    required SearchResult result,
    required NetworkStorageConfig networkStorage,
    required String saveFolderName,
    CloudSaveProgressCallback? onProgress,
    void Function(String)? onBackgroundRefreshFailure,
  }) async {
    final drive = driveFor(result, networkStorage);
    if (drive == null) {
      appLogWarning('cloud-save', 'Cloud save blocked before network', fields: {
        'drive': 'unsupported',
        'failureKind': CloudSaveFailureKind.unsupported.name,
      });
      return const CloudSaveOutcome.failure(
          null, '暂不支持保存此资源', CloudSaveFailureKind.unsupported);
    }
    if (!canSave(result, networkStorage)) {
      appLogWarning('cloud-save', 'Cloud save blocked before network', fields: {
        'drive': drive.name,
        'failureKind': CloudSaveFailureKind.credentials.name,
      });
      return CloudSaveOutcome.failure(
        drive,
        detectSearchCloudTypeFromUrl(result.resourceUrl) ==
                SearchCloudType.aliyun
            ? networkStorage.aliyunTo115Enabled
                ? '请先配置阿里 Refresh Token 和 115 Cookie'
                : '请先配置阿里 Refresh Token'
            : drive == CloudSaveDrive.cloud115
                ? '请先在网盘与转存设置里填写 115 Cookie'
                : '请先在网盘与转存设置里填写夸克 Cookie',
        CloudSaveFailureKind.credentials,
      );
    }
    try {
      appLogInfo('cloud-save', 'Cloud save started', fields: {
        'drive': drive.name,
      });
      final share = prepareSearchResultShareCredentials(result);
      final String message;
      if (detectSearchCloudTypeFromUrl(share.resourceUrl) ==
          SearchCloudType.aliyun) {
        if (aliyun == null) throw const QuarkSaveException('阿里转存服务未初始化');
        if (!networkStorage.aliyunTo115Enabled) {
          message = await aliyun!.saveToAliyun(
              shareUrl: share.resourceUrl,
              password: searchResultSharePassword(share),
              config: networkStorage,
              saveFolderName: saveFolderName,
              onProgress: onProgress,
              onBackgroundRefreshFailure: onBackgroundRefreshFailure);
        } else {
          message = await aliyun!.save(
              shareUrl: share.resourceUrl,
              password: searchResultSharePassword(share),
              config: networkStorage,
              saveFolderName: saveFolderName,
              deleteAliyunCopies: true,
              onProgress: onProgress,
              onBackgroundRefreshFailure: onBackgroundRefreshFailure);
        }
      } else if (drive == CloudSaveDrive.cloud115) {
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
      appLogInfo('cloud-save', 'Cloud save completed', fields: {
        'drive': drive.name,
      });
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
      appLogError('cloud-save', 'Cloud save failed',
          fields: {
            'drive': drive.name,
            'failureKind': kind.name,
            'message': message,
            'errorType': error.runtimeType.toString(),
          },
          error: error,
          stackTrace: stackTrace);
      return CloudSaveOutcome.failure(drive, message, kind,
          error: error, stackTrace: stackTrace);
    }
  }
}
