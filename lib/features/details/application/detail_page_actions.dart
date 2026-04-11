import 'package:starflow/features/details/application/detail_library_match_service.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

String detailProviderInvalidationKey(MediaDetailTarget target) {
  return [
    target.sourceId.trim(),
    target.itemId.trim(),
    target.title.trim(),
    target.searchQuery.trim(),
    target.itemType.trim(),
  ].join('|');
}

List<MediaDetailTarget> dedupeDetailInvalidationTargets({
  required MediaDetailTarget seedTarget,
  MediaDetailTarget? manualOverrideTarget,
  Iterable<MediaDetailTarget> additionalTargets = const [],
}) {
  final seenKeys = <String>{};
  final deduped = <MediaDetailTarget>[];
  final candidates = <MediaDetailTarget>[
    seedTarget,
    if (manualOverrideTarget != null) manualOverrideTarget,
    ...additionalTargets,
  ];
  for (final target in candidates) {
    if (seenKeys.add(detailProviderInvalidationKey(target))) {
      deduped.add(target);
    }
  }
  return deduped;
}

class DetailCachedStateRestorePlan {
  const DetailCachedStateRestorePlan({
    required this.libraryMatchChoices,
    required this.selectedLibraryMatchIndex,
    required this.subtitleSearchChoices,
    required this.selectedSubtitleSearchIndex,
    required this.manualOverrideTarget,
    required this.structuralSeedTarget,
  });

  final List<MediaDetailTarget> libraryMatchChoices;
  final int selectedLibraryMatchIndex;
  final List<CachedSubtitleSearchOption> subtitleSearchChoices;
  final int selectedSubtitleSearchIndex;
  final MediaDetailTarget? manualOverrideTarget;
  final MediaDetailTarget structuralSeedTarget;
}

class DetailCachedStateRestorer {
  DetailCachedStateRestorer({
    DetailLibraryMatchService? libraryMatchService,
  }) : _libraryMatchService =
            libraryMatchService ?? const DetailLibraryMatchService();

  final DetailLibraryMatchService _libraryMatchService;

  DetailCachedStateRestorePlan buildPlan({
    required MediaDetailTarget pageSeedTarget,
    required CachedDetailState cachedState,
  }) {
    final structuralSeed =
        cachedState.target.isSeries ? cachedState.target : pageSeedTarget;

    final preservedChoices = structuralSeed.isSeries
        ? cachedState.libraryMatchChoices
            .map(
              (choice) =>
                  _libraryMatchService.preserveSeriesStructuralTargetIfNeeded(
                current: structuralSeed,
                resolved: choice,
              ),
            )
            .toList(growable: false)
        : cachedState.libraryMatchChoices;

    final hasMultiChoices = preservedChoices.length > 1;
    final selectedLibraryMatchIndex = hasMultiChoices
        ? cachedState.selectedLibraryMatchIndex.clamp(
            0,
            preservedChoices.length - 1,
          )
        : 0;

    final normalizedSubtitleIndex = normalizeSubtitleSearchIndex(
      cachedState.selectedSubtitleSearchIndex,
      choices: cachedState.subtitleSearchChoices,
    );

    return DetailCachedStateRestorePlan(
      libraryMatchChoices:
          hasMultiChoices ? preservedChoices : const <MediaDetailTarget>[],
      selectedLibraryMatchIndex: selectedLibraryMatchIndex,
      subtitleSearchChoices: cachedState.subtitleSearchChoices,
      selectedSubtitleSearchIndex: normalizedSubtitleIndex,
      manualOverrideTarget:
          hasMultiChoices ? preservedChoices[selectedLibraryMatchIndex] : null,
      structuralSeedTarget: structuralSeed,
    );
  }
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

class DetailStartupPlan {
  const DetailStartupPlan({
    required this.shouldStart,
    required this.shouldRestoreCachedState,
    required this.shouldRestoreIndexedEpisodeVariants,
    required this.shouldRunInitialSubtitleSearch,
    required this.shouldWarmEnrichedTarget,
    required this.shouldWarmSeriesBrowser,
    required this.shouldAttemptAutoLibraryMatch,
    required this.effectiveTarget,
    required this.resolveTargetForAutoMatch,
  });

  final bool shouldStart;
  final bool shouldRestoreCachedState;
  final bool shouldRestoreIndexedEpisodeVariants;
  final bool shouldRunInitialSubtitleSearch;
  final bool shouldWarmEnrichedTarget;
  final bool shouldWarmSeriesBrowser;
  final bool shouldAttemptAutoLibraryMatch;
  final MediaDetailTarget effectiveTarget;
  final MediaDetailTarget resolveTargetForAutoMatch;
}

DetailStartupPlan buildDetailStartupPlan({
  required bool isPageVisible,
  required bool backgroundWorkSuspended,
  required MediaDetailTarget pageSeedTarget,
  required MediaDetailTarget? manualOverrideTarget,
  required bool hasSubtitleChoices,
  required bool hasOnlineSubtitleSources,
  required bool detailAutoLibraryMatchEnabled,
}) {
  final effectiveTarget = manualOverrideTarget ?? pageSeedTarget;
  final canStart = isPageVisible && !backgroundWorkSuspended;
  final shouldRunInitialSubtitleSearch = canStart &&
      !hasSubtitleChoices &&
      hasOnlineSubtitleSources &&
      effectiveTarget.isPlayable &&
      effectiveTarget.playbackTarget != null;

  return DetailStartupPlan(
    shouldStart: canStart,
    shouldRestoreCachedState: canStart,
    shouldRestoreIndexedEpisodeVariants: canStart,
    shouldRunInitialSubtitleSearch: shouldRunInitialSubtitleSearch,
    shouldWarmEnrichedTarget: canStart,
    shouldWarmSeriesBrowser: canStart && effectiveTarget.isSeries,
    shouldAttemptAutoLibraryMatch: canStart && detailAutoLibraryMatchEnabled,
    effectiveTarget: effectiveTarget,
    resolveTargetForAutoMatch: pageSeedTarget,
  );
}
