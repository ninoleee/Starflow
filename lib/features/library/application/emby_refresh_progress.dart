import 'dart:async';

import 'package:flutter_riverpod/legacy.dart';
import 'package:starflow/features/library/domain/media_models.dart';

enum EmbyRefreshTaskStatus {
  running,
  succeeded,
  failed,
}

enum EmbyRefreshStage {
  preparing,
  refreshing,
  finalizing,
}

extension EmbyRefreshStageX on EmbyRefreshStage {
  String get label {
    switch (this) {
      case EmbyRefreshStage.preparing:
        return '准备更新';
      case EmbyRefreshStage.refreshing:
        return '更新中';
      case EmbyRefreshStage.finalizing:
        return '整理缓存';
    }
  }
}

class EmbyRefreshSourceProgress {
  const EmbyRefreshSourceProgress({
    required this.sourceId,
    required this.sourceName,
  });

  final String sourceId;
  final String sourceName;
}

class EmbyRefreshProgressState {
  const EmbyRefreshProgressState({
    required this.runId,
    required this.status,
    required this.stage,
    required this.sources,
    this.activeSourceIndex = 0,
    this.completedSourceCount = 0,
    this.message = '',
  });

  final int runId;
  final EmbyRefreshTaskStatus status;
  final EmbyRefreshStage stage;
  final List<EmbyRefreshSourceProgress> sources;
  final int activeSourceIndex;
  final int completedSourceCount;
  final String message;

  bool get isRunning => status == EmbyRefreshTaskStatus.running;

  int get totalSourceCount => sources.length;

  EmbyRefreshSourceProgress? get activeSource {
    if (sources.isEmpty) {
      return null;
    }
    final index = activeSourceIndex.clamp(0, sources.length - 1);
    return sources[index];
  }

  double? get fraction {
    if (status == EmbyRefreshTaskStatus.succeeded) {
      return 1;
    }
    if (totalSourceCount <= 0) {
      return null;
    }
    if (isRunning && totalSourceCount == 1 && completedSourceCount == 0) {
      return null;
    }
    return completedSourceCount.clamp(0, totalSourceCount) / totalSourceCount;
  }

  String get title {
    switch (status) {
      case EmbyRefreshTaskStatus.running:
        return 'Emby 后台更新';
      case EmbyRefreshTaskStatus.succeeded:
        return 'Emby 更新完成';
      case EmbyRefreshTaskStatus.failed:
        return 'Emby 更新失败';
    }
  }

  String get summaryLabel {
    final resolvedMessage = message.trim();
    if (resolvedMessage.isNotEmpty) {
      return resolvedMessage;
    }
    final source = activeSource;
    final sourceName = source == null || source.sourceName.trim().isEmpty
        ? ''
        : source.sourceName.trim();
    final sourcePart = sourceName.isEmpty ? '' : ' · $sourceName';
    if (totalSourceCount <= 1) {
      return '${stage.label}$sourcePart';
    }
    final currentSourceNumber =
        activeSourceIndex.clamp(0, totalSourceCount - 1) + 1;
    return '${stage.label}$sourcePart · $currentSourceNumber / $totalSourceCount';
  }

  EmbyRefreshProgressState copyWith({
    EmbyRefreshTaskStatus? status,
    EmbyRefreshStage? stage,
    int? activeSourceIndex,
    int? completedSourceCount,
    String? message,
  }) {
    return EmbyRefreshProgressState(
      runId: runId,
      status: status ?? this.status,
      stage: stage ?? this.stage,
      sources: sources,
      activeSourceIndex: activeSourceIndex ?? this.activeSourceIndex,
      completedSourceCount: completedSourceCount ?? this.completedSourceCount,
      message: message ?? this.message,
    );
  }
}

final embyRefreshProgressProvider = StateNotifierProvider<
    EmbyRefreshProgressController, EmbyRefreshProgressState?>((ref) {
  return EmbyRefreshProgressController();
});

class EmbyRefreshProgressController
    extends StateNotifier<EmbyRefreshProgressState?> {
  EmbyRefreshProgressController() : super(null);

  int _nextRunId = 0;
  Timer? _clearTimer;

  void startTask(List<MediaSourceConfig> sources) {
    final progressSources = sources
        .map(
          (source) => EmbyRefreshSourceProgress(
            sourceId: source.id.trim(),
            sourceName:
                source.name.trim().isEmpty ? source.id.trim() : source.name,
          ),
        )
        .where((source) => source.sourceId.isNotEmpty)
        .toList(growable: false);
    if (progressSources.isEmpty) {
      state = null;
      return;
    }
    _clearTimer?.cancel();
    _clearTimer = null;
    state = EmbyRefreshProgressState(
      runId: ++_nextRunId,
      status: EmbyRefreshTaskStatus.running,
      stage: EmbyRefreshStage.preparing,
      sources: progressSources,
    );
  }

  void activateSource({
    required int sourceIndex,
  }) {
    final current = state;
    if (current == null || !current.isRunning) {
      return;
    }
    final boundedIndex = sourceIndex.clamp(0, current.totalSourceCount - 1);
    state = current.copyWith(
      stage: EmbyRefreshStage.refreshing,
      activeSourceIndex: boundedIndex,
      completedSourceCount: current.completedSourceCount.clamp(0, boundedIndex),
      message: '',
    );
  }

  void completeSource({
    required int sourceIndex,
  }) {
    final current = state;
    if (current == null || !current.isRunning) {
      return;
    }
    final completed = (sourceIndex + 1).clamp(0, current.totalSourceCount);
    state = current.copyWith(
      completedSourceCount: completed,
      message: '',
    );
  }

  void completeTask(String message) {
    final current = state;
    if (current == null) {
      return;
    }
    state = current.copyWith(
      status: EmbyRefreshTaskStatus.succeeded,
      stage: EmbyRefreshStage.finalizing,
      completedSourceCount: current.totalSourceCount,
      message: message,
    );
    _scheduleClear(const Duration(seconds: 4));
  }

  void failTask(String message) {
    final current = state;
    if (current == null) {
      return;
    }
    state = current.copyWith(
      status: EmbyRefreshTaskStatus.failed,
      message: message,
    );
    _scheduleClear(const Duration(seconds: 8));
  }

  void clear() {
    _clearTimer?.cancel();
    _clearTimer = null;
    state = null;
  }

  @override
  void dispose() {
    _clearTimer?.cancel();
    super.dispose();
  }

  void _scheduleClear(Duration delay) {
    _clearTimer?.cancel();
    _clearTimer = Timer(delay, () {
      state = null;
      _clearTimer = null;
    });
  }
}
