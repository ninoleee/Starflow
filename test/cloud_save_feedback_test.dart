import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/search/domain/cloud_save_feedback.dart';

void main() {
  for (final drive in CloudSaveDrive.values) {
    final name = drive == CloudSaveDrive.cloud115 ? ' 115' : drive.label;

    test('$drive uses the same concise progress and summary format', () {
      final progress = CloudSaveProgress.saving(drive);
      expect(progress.stage, CloudSaveStage.saving);
      expect(
          progress.message,
          drive == CloudSaveDrive.cloud115
              ? '115 保存中...'
              : '${drive.label}保存中...');
      final renaming = CloudSaveProgress.sanitizingNames(drive, 3);
      expect(renaming.stage, CloudSaveStage.sanitizingNames);
      expect(renaming.message, '已保存 3 个，名称修改中...');
      expect(
          CloudSaveSummary(
            drive: drive,
            savedCount: 3,
            skippedCount: 1,
            smartStrmTriggered: true,
            smartStrmDelaySeconds: 4,
            refreshDelaySeconds: 6,
          ).buildSuccessMessage(),
          '已提交到$name，保存 3 个，略过 1 个，STRM 已延迟 4 秒触发，6 秒后刷新媒体源');
    });

    test('$drive reports zero additions without inventing follow-up work', () {
      expect(
          CloudSaveSummary(
            drive: drive,
            savedCount: 0,
            skippedCount: 12,
          ).buildSuccessMessage(),
          '已提交到$name，保存 0 个，略过 12 个');
    });

    test('$drive includes only real task, rename, and refresh outcomes', () {
      expect(
          CloudSaveSummary(
            drive: drive,
            taskId: 'task-1',
            savedCount: 3,
            skippedCount: 0,
            renamedCount: 2,
            renameFailedCount: 1,
            smartStrmTriggered: true,
            smartStrmAddedCount: 8,
            refreshDelaySeconds: 0,
          ).buildSuccessMessage(),
          '已提交到$name，任务 task-1，保存 3 个，略过 0 个，已修正 2 个名称（1 个失败），STRM 新增成功 8 条，即将刷新媒体源');
    });

    test('$drive preserves confirmed saves when a downstream step fails', () {
      final message = CloudSaveSummary(
        drive: drive,
        savedCount: 1,
        skippedCount: 4,
        smartStrmFailure: 'HTTP 500',
        refreshDelaySeconds: 5,
      ).buildSuccessMessage();
      expect(message, '已提交到$name，保存 1 个，略过 4 个，但 STRM 触发失败：HTTP 500，5 秒后刷新媒体源');
      expect(drive.refreshFailureMessage, contains('保存成功，但媒体源刷新失败'));
    });
  }

  test('SmartStrm fallback messages retain the Quark result precedence', () {
    String summary({int delay = 0, int? count, String message = ''}) =>
        CloudSaveSummary(
          drive: CloudSaveDrive.quark,
          savedCount: 1,
          skippedCount: 0,
          smartStrmTriggered: true,
          smartStrmDelaySeconds: delay,
          smartStrmAddedCount: count,
          smartStrmMessage: message,
        ).buildSuccessMessage();
    expect(
        summary(delay: 3, count: 2, message: 'ok'), endsWith('STRM 已延迟 3 秒触发'));
    expect(summary(count: 0, message: 'ok'), endsWith('STRM 新增成功 0 条'));
    expect(summary(message: ' ok '), endsWith('STRM ok'));
    expect(summary(message: ' '), endsWith('已触发 STRM 任务'));
  });
}
