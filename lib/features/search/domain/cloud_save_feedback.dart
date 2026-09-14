enum CloudSaveDrive {
  quark('夸克'),
  cloud115('115');

  const CloudSaveDrive(this.label);
  final String label;

  String get _prefix => this == cloud115 ? '$label ' : label;
  String get _inline => this == cloud115 ? ' $label' : label;

  String get savingMessage => '$_prefix保存中...';
  String get refreshFailureMessage => '$_prefix保存成功，但媒体源刷新失败，请手动刷新';

  String smartStrmFailureMessage(String reason) =>
      '$_prefix保存成功，但 STRM 触发失败：$reason';
}

enum CloudSaveStage { saving, sanitizingNames }

typedef CloudSaveProgressCallback = void Function(CloudSaveProgress progress);

class CloudSaveProgress {
  const CloudSaveProgress.saving(this.drive)
      : stage = CloudSaveStage.saving,
        savedCount = 0;

  const CloudSaveProgress.sanitizingNames(this.drive, this.savedCount)
      : stage = CloudSaveStage.sanitizingNames;

  final CloudSaveDrive drive;
  final CloudSaveStage stage;
  final int savedCount;

  String get message => switch (stage) {
        CloudSaveStage.saving => drive.savingMessage,
        CloudSaveStage.sanitizingNames => '已保存 $savedCount 个，名称修改中...',
      };
}

class CloudSaveSummary {
  const CloudSaveSummary({
    required this.drive,
    required this.savedCount,
    required this.skippedCount,
    this.taskId = '',
    this.renamedCount = 0,
    this.renameFailedCount = 0,
    this.nameWarning = '',
    this.smartStrmTriggered = false,
    this.smartStrmDelaySeconds = 0,
    this.smartStrmAddedCount,
    this.smartStrmMessage = '',
    this.smartStrmFailure = '',
    this.refreshDelaySeconds,
  });

  final CloudSaveDrive drive;
  final int savedCount;
  final int skippedCount;
  final String taskId;
  final int renamedCount;
  final int renameFailedCount;
  final String nameWarning;
  final bool smartStrmTriggered;
  final int smartStrmDelaySeconds;
  final int? smartStrmAddedCount;
  final String smartStrmMessage;
  final String smartStrmFailure;
  final int? refreshDelaySeconds;

  String buildSuccessMessage() {
    return [
      '已提交到${drive._inline}',
      if (taskId.isNotEmpty) '任务 $taskId',
      '保存 $savedCount 个',
      '略过 $skippedCount 个',
      if (renamedCount > 0)
        '已修正 $renamedCount 个名称'
            '${renameFailedCount == 0 ? '' : '（$renameFailedCount 个失败）'}',
      if (nameWarning.isNotEmpty) nameWarning,
      if (smartStrmFailure.isNotEmpty)
        '但 STRM 触发失败：$smartStrmFailure'
      else if (smartStrmTriggered)
        _smartStrmSuccessMessage,
      if (refreshDelaySeconds != null)
        refreshDelaySeconds! > 0 ? '$refreshDelaySeconds 秒后刷新媒体源' : '即将刷新媒体源',
    ].join('，');
  }

  String get _smartStrmSuccessMessage {
    if (smartStrmDelaySeconds > 0) {
      return 'STRM 已延迟 $smartStrmDelaySeconds 秒触发';
    }
    if (smartStrmAddedCount != null) {
      return 'STRM 新增成功 $smartStrmAddedCount 条';
    }
    final message = smartStrmMessage.trim();
    return message.isEmpty ? '已触发 STRM 任务' : 'STRM $message';
  }
}
