import 'package:flutter/foundation.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/playback/domain/online_subtitle_structured_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';

const Object detailSubtitleSearchViewUnchanged = Object();

@immutable
class DetailSubtitleSearchViewState {
  const DetailSubtitleSearchViewState({
    this.choices = const <CachedSubtitleSearchOption>[],
    this.selectedIndex = -1,
    this.isSearching = false,
    this.busyResultId,
    this.statusMessage,
  });

  final List<CachedSubtitleSearchOption> choices;
  final int selectedIndex;
  final bool isSearching;
  final String? busyResultId;
  final String? statusMessage;

  int get effectiveSelectedIndex {
    if (choices.isEmpty) {
      return -1;
    }
    return selectedIndex.clamp(-1, choices.length - 1);
  }

  CachedSubtitleSearchOption? get selectedChoice {
    final index = effectiveSelectedIndex;
    if (index < 0 || index >= choices.length) {
      return null;
    }
    return choices[index];
  }

  DetailSubtitleSearchViewState copyWith({
    List<CachedSubtitleSearchOption>? choices,
    int? selectedIndex,
    bool? isSearching,
    Object? busyResultId = detailSubtitleSearchViewUnchanged,
    Object? statusMessage = detailSubtitleSearchViewUnchanged,
  }) {
    return DetailSubtitleSearchViewState(
      choices: choices ?? this.choices,
      selectedIndex: selectedIndex ?? this.selectedIndex,
      isSearching: isSearching ?? this.isSearching,
      busyResultId: identical(busyResultId, detailSubtitleSearchViewUnchanged)
          ? this.busyResultId
          : busyResultId as String?,
      statusMessage: identical(statusMessage, detailSubtitleSearchViewUnchanged)
          ? this.statusMessage
          : statusMessage as String?,
    );
  }
}

sealed class DetailSubtitleSelectionDecision {
  const DetailSubtitleSelectionDecision({
    required this.nextViewData,
  });

  final DetailSubtitleSearchViewState nextViewData;
}

class DetailSubtitleSelectionIgnored extends DetailSubtitleSelectionDecision {
  const DetailSubtitleSelectionIgnored({
    required this.reason,
    required super.nextViewData,
  });

  final String reason;
}

class DetailSubtitleSelectionCleared extends DetailSubtitleSelectionDecision {
  const DetailSubtitleSelectionCleared({
    required this.persistedSelectedIndex,
    required super.nextViewData,
  });

  final int persistedSelectedIndex;
}

class DetailSubtitleSelectionUseCached extends DetailSubtitleSelectionDecision {
  const DetailSubtitleSelectionUseCached({
    required this.persistedSelectedIndex,
    required this.selectedOption,
    required super.nextViewData,
  });

  final int persistedSelectedIndex;
  final CachedSubtitleSearchOption selectedOption;
}

class DetailSubtitleSelectionNeedsDownload
    extends DetailSubtitleSelectionDecision {
  const DetailSubtitleSelectionNeedsDownload({
    required this.selectionIndex,
    required this.previousSelectedIndex,
    required this.selectedOption,
    required super.nextViewData,
  });

  final int selectionIndex;
  final int previousSelectedIndex;
  final CachedSubtitleSearchOption selectedOption;
}

class DetailSubtitleSearchResolveResult {
  const DetailSubtitleSearchResolveResult({
    required this.nextViewData,
    required this.usableChoices,
    required this.statusMessage,
  });

  final DetailSubtitleSearchViewState nextViewData;
  final List<CachedSubtitleSearchOption> usableChoices;
  final String? statusMessage;
}

int normalizeSubtitleSearchIndex(
  int index, {
  List<CachedSubtitleSearchOption>? choices,
}) {
  final resolvedChoices = choices ?? const <CachedSubtitleSearchOption>[];
  if (resolvedChoices.isEmpty) {
    return -1;
  }
  return index.clamp(-1, resolvedChoices.length - 1);
}

class DetailSubtitleController {
  const DetailSubtitleController();

  MediaDetailTarget decorateTargetWithSelectedSubtitle(
    MediaDetailTarget target, {
    required DetailSubtitleSearchViewState viewData,
  }) {
    final playbackTarget = target.playbackTarget;
    if (playbackTarget == null) {
      return target;
    }
    final selection = viewData.selectedChoice?.selection;
    final canApply = selection?.subtitleFilePath?.trim().isNotEmpty == true;
    final decoratedPlayback = playbackTarget.copyWith(
      externalSubtitleFilePath:
          canApply ? selection!.subtitleFilePath!.trim() : '',
      externalSubtitleDisplayName:
          canApply ? selection!.displayName.trim() : '',
    );
    return target.copyWith(playbackTarget: decoratedPlayback);
  }

  DetailSubtitleSearchResolveResult resolveSearchResults({
    required DetailSubtitleSearchViewState currentViewData,
    required List<SubtitleSearchResult> results,
    int maxChoices = 10,
  }) {
    final previousSelectedId = currentViewData.selectedChoice?.result.id;
    final nextChoices = mergeSubtitleSearchChoices(
      previousChoices: currentViewData.choices,
      results: results,
      maxChoices: maxChoices,
    );
    final statusMessage = buildSubtitleSearchStatusMessage(
      results: results,
      usableChoices: nextChoices,
    );
    final nextSelectedIndex = previousSelectedId == null
        ? -1
        : nextChoices
            .indexWhere((item) => item.result.id == previousSelectedId);
    final resolvedSelectedIndex = normalizeSubtitleSearchIndex(
      nextSelectedIndex,
      choices: nextChoices,
    );

    final nextView = currentViewData.copyWith(
      choices: nextChoices,
      selectedIndex: resolvedSelectedIndex,
      isSearching: false,
      statusMessage: statusMessage,
    );
    return DetailSubtitleSearchResolveResult(
      nextViewData: nextView,
      usableChoices: nextChoices,
      statusMessage: statusMessage,
    );
  }

  DetailSubtitleSearchResolveResult resolveValidatedCandidates({
    required DetailSubtitleSearchViewState currentViewData,
    required List<ValidatedSubtitleCandidate> candidates,
    int maxChoices = 10,
  }) {
    final previousSelectedId = currentViewData.selectedChoice?.result.id;
    final nextChoices = mergeValidatedSubtitleSearchChoices(
      previousChoices: currentViewData.choices,
      candidates: candidates,
      maxChoices: maxChoices,
    );
    final statusMessage = nextChoices.isEmpty ? '没有找到可直接加载的字幕结果' : null;
    final nextSelectedIndex = previousSelectedId == null
        ? -1
        : nextChoices
            .indexWhere((item) => item.result.id == previousSelectedId);
    final resolvedSelectedIndex = normalizeSubtitleSearchIndex(
      nextSelectedIndex,
      choices: nextChoices,
    );
    final nextView = currentViewData.copyWith(
      choices: nextChoices,
      selectedIndex: resolvedSelectedIndex,
      isSearching: false,
      statusMessage: statusMessage,
    );
    return DetailSubtitleSearchResolveResult(
      nextViewData: nextView,
      usableChoices: nextChoices,
      statusMessage: statusMessage,
    );
  }

  DetailSubtitleSelectionDecision decideSelectionAction({
    required DetailSubtitleSearchViewState currentViewData,
    required int requestedIndex,
  }) {
    if (currentViewData.isSearching || currentViewData.choices.isEmpty) {
      return DetailSubtitleSelectionIgnored(
        reason: currentViewData.isSearching
            ? 'searching-in-progress'
            : 'empty-choices',
        nextViewData: currentViewData,
      );
    }

    final resolvedIndex = normalizeSubtitleSearchIndex(
      requestedIndex,
      choices: currentViewData.choices,
    );
    if (resolvedIndex < 0) {
      return DetailSubtitleSelectionCleared(
        persistedSelectedIndex: -1,
        nextViewData: currentViewData.copyWith(selectedIndex: -1),
      );
    }

    final selected = currentViewData.choices[resolvedIndex];
    if (selected.selection?.canApply == true) {
      return DetailSubtitleSelectionUseCached(
        persistedSelectedIndex: resolvedIndex,
        selectedOption: selected,
        nextViewData: currentViewData.copyWith(selectedIndex: resolvedIndex),
      );
    }

    final hasBusy = (currentViewData.busyResultId ?? '').trim().isNotEmpty;
    if (hasBusy) {
      return DetailSubtitleSelectionIgnored(
        reason: 'busy-downloading',
        nextViewData: currentViewData,
      );
    }

    return DetailSubtitleSelectionNeedsDownload(
      selectionIndex: resolvedIndex,
      previousSelectedIndex: currentViewData.selectedIndex,
      selectedOption: selected,
      nextViewData: currentViewData.copyWith(
        selectedIndex: resolvedIndex,
        busyResultId: selected.result.id,
        statusMessage: '正在缓存所选字幕...',
      ),
    );
  }

  SubtitleSearchSelection selectionFromDownloadResult(
    SubtitleDownloadResult download,
  ) {
    return SubtitleSearchSelection(
      cachedPath: download.cachedPath,
      displayName: download.displayName,
      subtitleFilePath: download.subtitleFilePath,
    );
  }

  DetailSubtitleSearchViewState applyDownloadedSelectionSuccess({
    required DetailSubtitleSearchViewState currentViewData,
    required int selectionIndex,
    required SubtitleSearchSelection selection,
  }) {
    final resolvedIndex = normalizeSubtitleSearchIndex(
      selectionIndex,
      choices: currentViewData.choices,
    );
    if (resolvedIndex < 0) {
      return currentViewData.copyWith(busyResultId: null);
    }
    final nextChoices = <CachedSubtitleSearchOption>[
      for (var i = 0; i < currentViewData.choices.length; i++)
        if (i == resolvedIndex)
          currentViewData.choices[i].copyWith(selection: selection)
        else
          currentViewData.choices[i],
    ];
    return currentViewData.copyWith(
      choices: nextChoices,
      selectedIndex: resolvedIndex,
      busyResultId: null,
      statusMessage: null,
    );
  }

  DetailSubtitleSearchViewState applyDownloadedSelectionFailure({
    required DetailSubtitleSearchViewState currentViewData,
    required int fallbackSelectedIndex,
    required Object error,
  }) {
    final resolvedSelectedIndex = normalizeSubtitleSearchIndex(
      fallbackSelectedIndex,
      choices: currentViewData.choices,
    );
    return currentViewData.copyWith(
      selectedIndex: resolvedSelectedIndex,
      busyResultId: null,
      statusMessage: '$error',
    );
  }

  List<CachedSubtitleSearchOption> mergeSubtitleSearchChoices({
    required List<CachedSubtitleSearchOption> previousChoices,
    required List<SubtitleSearchResult> results,
    int maxChoices = 10,
  }) {
    final previousById = <String, CachedSubtitleSearchOption>{
      for (final choice in previousChoices) choice.result.id: choice,
    };
    return results
        .where((item) => item.canAutoLoad && item.canDownload)
        .take(maxChoices)
        .map(
          (result) =>
              previousById[result.id]?.copyWith(result: result) ??
              CachedSubtitleSearchOption(result: result),
        )
        .toList(growable: false);
  }

  List<CachedSubtitleSearchOption> mergeValidatedSubtitleSearchChoices({
    required List<CachedSubtitleSearchOption> previousChoices,
    required List<ValidatedSubtitleCandidate> candidates,
    int maxChoices = 10,
  }) {
    final previousById = <String, CachedSubtitleSearchOption>{
      for (final choice in previousChoices) choice.result.id: choice,
    };
    return candidates
        .where((item) => item.canApply)
        .take(maxChoices)
        .map((candidate) {
      final selection = SubtitleSearchSelection(
        cachedPath: candidate.cachedPath,
        displayName: candidate.displayName,
        subtitleFilePath: candidate.subtitleFilePath,
      );
      return previousById[candidate.hit.id]?.copyWith(
            result: candidate.toSearchResult(),
            selection: selection,
          ) ??
          CachedSubtitleSearchOption(
            result: candidate.toSearchResult(),
            selection: selection,
          );
    }).toList(growable: false);
  }

  String? buildSubtitleSearchStatusMessage({
    required List<SubtitleSearchResult> results,
    required List<CachedSubtitleSearchOption> usableChoices,
  }) {
    if (usableChoices.isNotEmpty) {
      return null;
    }
    if (results.isEmpty) {
      return '没有找到可直接加载的字幕结果';
    }

    final autoLoadableOnlyCount =
        results.where((item) => item.canAutoLoad && !item.canDownload).length;
    if (autoLoadableOnlyCount > 0) {
      return '已搜到 $autoLoadableOnlyCount 条字幕，但当前来源暂不支持应用内直接下载';
    }

    final downloadOnlyCount =
        results.where((item) => item.canDownload && !item.canAutoLoad).length;
    if (downloadOnlyCount > 0) {
      return '已搜到 $downloadOnlyCount 条字幕，但当前结果暂不能自动挂载播放';
    }

    return '没有找到可直接加载的字幕结果';
  }

  String subtitleSearchChoiceLabel(CachedSubtitleSearchOption choice) {
    final parts = <String>[
      if (choice.result.title.trim().isNotEmpty) choice.result.title.trim(),
      if (choice.result.summaryLine.trim().isNotEmpty)
        choice.result.summaryLine.trim(),
      if (choice.selection?.canApply == true) '已缓存',
    ];
    return parts.join(' · ');
  }

  String subtitleResultSample(List<SubtitleSearchResult> results) {
    if (results.isEmpty) {
      return '';
    }
    return results
        .take(3)
        .map((item) => '${item.providerLabel}:${item.title}')
        .join(' | ');
  }

  String subtitleChoiceSample(List<CachedSubtitleSearchOption> choices) {
    if (choices.isEmpty) {
      return '';
    }
    return choices
        .take(3)
        .map((item) => '${item.result.providerLabel}:${item.result.title}')
        .join(' | ');
  }
}
