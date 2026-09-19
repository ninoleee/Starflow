import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/features/search/data/smart_strm_webhook_client.dart';
import 'package:starflow/features/search/domain/cloud_save_feedback.dart';

int cloudSaveDelaySeconds(int value) => value <= 0 ? 1 : value;

Future<({SmartStrmTriggerResult? result, String failure})>
    triggerSavedCloudStrm({
  required CloudSaveDrive drive,
  required Future<SmartStrmTriggerResult> Function() trigger,
}) async {
  try {
    return (result: await trigger(), failure: '');
  } catch (error) {
    appLogWarning('${drive.name}.save', 'SmartStrm trigger failed', fields: {
      'errorType': error.runtimeType.toString(),
    });
    return (
      result: null,
      failure: error is SmartStrmWebhookException
          ? error.message
          : '请检查 SmartStrm 任务',
    );
  }
}

Future<void> refreshSavedCloudMedia({
  required CloudSaveDrive drive,
  required Future<void> Function() refresh,
  void Function(String)? onFailure,
}) async {
  try {
    await refresh();
  } catch (error) {
    appLogWarning('${drive.name}.save', 'Post-save media refresh failed',
        fields: {
          'errorType': error.runtimeType.toString(),
        });
    onFailure?.call(drive.refreshFailureMessage);
  }
}
