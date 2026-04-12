import 'dart:async';

import 'package:flutter_riverpod/legacy.dart';
import 'package:starflow/features/playback/application/playback_session.dart';

enum WebDavScrapeStage {
  scanning,
  indexing,
}

extension WebDavScrapeStageX on WebDavScrapeStage {
  String get label {
    switch (this) {
      case WebDavScrapeStage.scanning:
        return '扫描目录中';
      case WebDavScrapeStage.indexing:
        return '刮削整理中';
    }
  }
}

class WebDavScrapeProgress {
  const WebDavScrapeProgress({
    required this.sourceId,
    required this.sourceName,
    required this.stage,
    required this.current,
    required this.total,
    this.activityLabel = '',
    this.detail = '',
  });

  final String sourceId;
  final String sourceName;
  final WebDavScrapeStage stage;
  final int current;
  final int total;
  final String activityLabel;
  final String detail;

  double? get fraction {
    if (stage == WebDavScrapeStage.scanning) {
      return null;
    }
    if (total <= 0) {
      return null;
    }
    final clamped = current.clamp(0, total);
    return clamped / total;
  }

  String get summaryLabel {
    final resolvedLabel =
        activityLabel.trim().isEmpty ? stage.label : activityLabel;
    if (stage == WebDavScrapeStage.scanning) {
      return resolvedLabel;
    }
    if (total <= 0) {
      return resolvedLabel;
    }
    return '$resolvedLabel $current / $total';
  }

  WebDavScrapeProgress copyWith({
    String? sourceId,
    String? sourceName,
    WebDavScrapeStage? stage,
    int? current,
    int? total,
    String? activityLabel,
    String? detail,
  }) {
    return WebDavScrapeProgress(
      sourceId: sourceId ?? this.sourceId,
      sourceName: sourceName ?? this.sourceName,
      stage: stage ?? this.stage,
      current: current ?? this.current,
      total: total ?? this.total,
      activityLabel: activityLabel ?? this.activityLabel,
      detail: detail ?? this.detail,
    );
  }
}

final webDavScrapeProgressProvider = StateNotifierProvider<
    WebDavScrapeProgressController, Map<String, WebDavScrapeProgress>>((ref) {
  final controller = WebDavScrapeProgressController(
    updateMode: ref.read(playbackPerformanceModeProvider)
        ? WebDavScrapeProgressUpdateMode.prioritizePlayback
        : WebDavScrapeProgressUpdateMode.prioritizeUi,
  );
  ref.listen<bool>(playbackPerformanceModeProvider, (previous, next) {
    controller.setUpdateMode(
      next
          ? WebDavScrapeProgressUpdateMode.prioritizePlayback
          : WebDavScrapeProgressUpdateMode.prioritizeUi,
    );
  });
  return controller;
});

enum WebDavScrapeProgressUpdateMode {
  prioritizeUi,
  prioritizePlayback,
}

class WebDavScrapeProgressController
    extends StateNotifier<Map<String, WebDavScrapeProgress>> {
  WebDavScrapeProgressController({
    this.updateMode = WebDavScrapeProgressUpdateMode.prioritizeUi,
    this.normalModeMinUpdateInterval = const Duration(milliseconds: 120),
    this.playbackModeMinUpdateInterval = const Duration(milliseconds: 480),
  }) : super(const {});

  WebDavScrapeProgressUpdateMode updateMode;
  final Duration normalModeMinUpdateInterval;
  final Duration playbackModeMinUpdateInterval;
  final Map<String, WebDavScrapeProgress> _pendingProgressBySourceId =
      <String, WebDavScrapeProgress>{};
  DateTime? _lastProgressEmissionAt;
  Timer? _pendingFlushTimer;

  Duration get _effectiveMinUpdateInterval => switch (updateMode) {
        WebDavScrapeProgressUpdateMode.prioritizeUi =>
          normalModeMinUpdateInterval,
        WebDavScrapeProgressUpdateMode.prioritizePlayback =>
          playbackModeMinUpdateInterval,
      };

  void setUpdateMode(WebDavScrapeProgressUpdateMode nextMode) {
    if (updateMode == nextMode) {
      return;
    }
    updateMode = nextMode;
    _reschedulePendingFlush();
  }

  void startScanning({
    required String sourceId,
    required String sourceName,
    required int totalCollections,
    String detail = '',
  }) {
    _upsert(
      WebDavScrapeProgress(
        sourceId: sourceId,
        sourceName: sourceName,
        stage: WebDavScrapeStage.scanning,
        current: totalCollections > 0 ? 0 : 1,
        total: totalCollections > 0 ? totalCollections : 1,
        activityLabel: WebDavScrapeStage.scanning.label,
        detail: detail,
      ),
      allowThrottle: false,
    );
  }

  void updateScanning({
    required String sourceId,
    required int current,
    required int total,
    String detail = '',
  }) {
    final existing = state[sourceId];
    if (existing == null) {
      return;
    }
    _upsert(
      existing.copyWith(
        stage: WebDavScrapeStage.scanning,
        current: current,
        total: total > 0 ? total : 1,
        detail: detail,
      ),
      allowThrottle: true,
      forceEmit: current >= (total > 0 ? total : 1),
    );
  }

  void startIndexing({
    required String sourceId,
    required int totalItems,
    String activityLabel = '',
    String detail = '',
  }) {
    final existing = state[sourceId];
    if (existing == null) {
      return;
    }
    _upsert(
      existing.copyWith(
        stage: WebDavScrapeStage.indexing,
        current: totalItems > 0 ? 0 : 1,
        total: totalItems > 0 ? totalItems : 1,
        activityLabel: activityLabel.trim().isEmpty
            ? WebDavScrapeStage.indexing.label
            : activityLabel,
        detail: detail,
      ),
      allowThrottle: false,
    );
  }

  void updateIndexing({
    required String sourceId,
    required int current,
    required int total,
    String detail = '',
  }) {
    final existing = state[sourceId];
    if (existing == null) {
      return;
    }
    _upsert(
      existing.copyWith(
        stage: WebDavScrapeStage.indexing,
        current: current,
        total: total > 0 ? total : 1,
        detail: detail,
      ),
      allowThrottle: true,
      forceEmit: current >= (total > 0 ? total : 1),
    );
  }

  void clear(String sourceId) {
    final normalized = sourceId.trim();
    if (normalized.isEmpty) {
      return;
    }
    _pendingProgressBySourceId.remove(normalized);
    _cleanupPendingFlushIfIdle();
    if (!state.containsKey(normalized)) {
      return;
    }
    final next = {...state};
    next.remove(normalized);
    state = next;
  }

  @override
  void dispose() {
    _pendingFlushTimer?.cancel();
    super.dispose();
  }

  void _upsert(
    WebDavScrapeProgress progress, {
    required bool allowThrottle,
    bool forceEmit = false,
  }) {
    final normalizedSourceId = progress.sourceId.trim();
    if (normalizedSourceId.isEmpty) {
      return;
    }
    final normalizedProgress = progress.copyWith(sourceId: normalizedSourceId);
    if (!allowThrottle || forceEmit || !_shouldThrottleProgressUpdates()) {
      _pendingProgressBySourceId.remove(normalizedSourceId);
      _emitProgress(normalizedProgress);
      return;
    }
    _pendingProgressBySourceId[normalizedSourceId] = normalizedProgress;
    _schedulePendingFlush();
  }

  bool _shouldThrottleProgressUpdates() {
    final lastProgressEmissionAt = _lastProgressEmissionAt;
    if (lastProgressEmissionAt == null) {
      return false;
    }
    return DateTime.now().difference(lastProgressEmissionAt) <
        _effectiveMinUpdateInterval;
  }

  Duration _remainingThrottleWindow() {
    final lastProgressEmissionAt = _lastProgressEmissionAt;
    if (lastProgressEmissionAt == null) {
      return Duration.zero;
    }
    final remaining = _effectiveMinUpdateInterval -
        DateTime.now().difference(lastProgressEmissionAt);
    if (remaining <= Duration.zero) {
      return Duration.zero;
    }
    return remaining;
  }

  void _schedulePendingFlush() {
    if (_pendingProgressBySourceId.isEmpty) {
      _cleanupPendingFlushIfIdle();
      return;
    }
    final remaining = _remainingThrottleWindow();
    if (remaining <= Duration.zero) {
      _flushPendingProgress();
      return;
    }
    _pendingFlushTimer ??= Timer(remaining, _flushPendingProgress);
  }

  void _reschedulePendingFlush() {
    _pendingFlushTimer?.cancel();
    _pendingFlushTimer = null;
    _schedulePendingFlush();
  }

  void _cleanupPendingFlushIfIdle() {
    if (_pendingProgressBySourceId.isNotEmpty) {
      return;
    }
    _pendingFlushTimer?.cancel();
    _pendingFlushTimer = null;
  }

  void _emitProgress(WebDavScrapeProgress progress) {
    _lastProgressEmissionAt = DateTime.now();
    state = {
      ...state,
      progress.sourceId: progress,
    };
  }

  void _flushPendingProgress() {
    _pendingFlushTimer?.cancel();
    _pendingFlushTimer = null;
    if (_pendingProgressBySourceId.isEmpty) {
      return;
    }
    _lastProgressEmissionAt = DateTime.now();
    final nextState = {...state};
    for (final progress in _pendingProgressBySourceId.values) {
      nextState[progress.sourceId] = progress;
    }
    _pendingProgressBySourceId.clear();
    state = nextState;
  }
}
