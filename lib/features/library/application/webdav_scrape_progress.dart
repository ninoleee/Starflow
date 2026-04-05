import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    this.detail = '',
  });

  final String sourceId;
  final String sourceName;
  final WebDavScrapeStage stage;
  final int current;
  final int total;
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
    if (stage == WebDavScrapeStage.scanning) {
      return stage.label;
    }
    if (total <= 0) {
      return stage.label;
    }
    return '${stage.label} $current / $total';
  }

  WebDavScrapeProgress copyWith({
    String? sourceId,
    String? sourceName,
    WebDavScrapeStage? stage,
    int? current,
    int? total,
    String? detail,
  }) {
    return WebDavScrapeProgress(
      sourceId: sourceId ?? this.sourceId,
      sourceName: sourceName ?? this.sourceName,
      stage: stage ?? this.stage,
      current: current ?? this.current,
      total: total ?? this.total,
      detail: detail ?? this.detail,
    );
  }
}

final webDavScrapeProgressProvider = StateNotifierProvider<
    WebDavScrapeProgressController, Map<String, WebDavScrapeProgress>>((ref) {
  return WebDavScrapeProgressController();
});

class WebDavScrapeProgressController
    extends StateNotifier<Map<String, WebDavScrapeProgress>> {
  WebDavScrapeProgressController() : super(const {});

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
        detail: detail,
      ),
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
    );
  }

  void startIndexing({
    required String sourceId,
    required int totalItems,
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
        detail: detail,
      ),
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
    );
  }

  void clear(String sourceId) {
    final normalized = sourceId.trim();
    if (normalized.isEmpty || !state.containsKey(normalized)) {
      return;
    }
    final next = {...state};
    next.remove(normalized);
    state = next;
  }

  void _upsert(WebDavScrapeProgress progress) {
    state = {
      ...state,
      progress.sourceId: progress,
    };
  }
}
