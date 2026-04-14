import 'package:starflow/features/details/application/detail_library_match_service.dart';
import 'package:starflow/features/details/application/detail_subtitle_controller.dart';
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

class DetailLibraryMatchPreferenceResult {
  const DetailLibraryMatchPreferenceResult({
    required this.choices,
    required this.selectedIndex,
    required this.matchedPreferredSource,
  });

  final List<MediaDetailTarget> choices;
  final int selectedIndex;
  final bool matchedPreferredSource;
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
    final preservedResolvedTarget = structuralSeed.isSeries
        ? _libraryMatchService.preserveSeriesStructuralTargetIfNeeded(
            current: structuralSeed,
            resolved: cachedState.target,
          )
        : cachedState.target;

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
    final preferredChoices = prioritizeDetailLibraryMatchChoices(
      pageSeedTarget: pageSeedTarget,
      choices: preservedChoices,
      fallbackSelectedIndex: cachedState.selectedLibraryMatchIndex,
      includePreferredEntryChoice: true,
      currentTarget: preservedResolvedTarget,
    );

    final hasMultiChoices = preferredChoices.choices.length > 1;
    final selectedLibraryMatchIndex =
        hasMultiChoices ? preferredChoices.selectedIndex : 0;
    final shouldRestoreSingleResolvedTarget = !hasMultiChoices &&
        structuralSeed.isSeries &&
        _hasResolvedStructuralResourceState(preservedResolvedTarget) &&
        shouldRestoreSeriesSourceScopedTarget(
          pageSeedTarget: pageSeedTarget,
          restoredTarget: preservedResolvedTarget,
        );

    final normalizedSubtitleIndex = normalizeSubtitleSearchIndex(
      cachedState.selectedSubtitleSearchIndex,
      choices: cachedState.subtitleSearchChoices,
    );

    return DetailCachedStateRestorePlan(
      libraryMatchChoices: hasMultiChoices
          ? preferredChoices.choices
          : const <MediaDetailTarget>[],
      selectedLibraryMatchIndex: selectedLibraryMatchIndex,
      subtitleSearchChoices: cachedState.subtitleSearchChoices,
      selectedSubtitleSearchIndex: normalizedSubtitleIndex,
      manualOverrideTarget: hasMultiChoices
          ? preferredChoices.choices[selectedLibraryMatchIndex]
          : (shouldRestoreSingleResolvedTarget
              ? preservedResolvedTarget
              : null),
      structuralSeedTarget: structuralSeed,
    );
  }
}

DetailLibraryMatchPreferenceResult prioritizeDetailLibraryMatchChoices({
  required MediaDetailTarget pageSeedTarget,
  required List<MediaDetailTarget> choices,
  int fallbackSelectedIndex = 0,
  bool includePreferredEntryChoice = false,
  MediaDetailTarget? currentTarget,
}) {
  final effectiveChoices = includePreferredEntryChoice
      ? prependPreferredEntryLibraryChoice(
          pageSeedTarget: pageSeedTarget,
          choices: choices,
          currentTarget: currentTarget,
        )
      : List<MediaDetailTarget>.unmodifiable(choices);
  if (effectiveChoices.isEmpty) {
    return const DetailLibraryMatchPreferenceResult(
      choices: <MediaDetailTarget>[],
      selectedIndex: 0,
      matchedPreferredSource: false,
    );
  }

  final normalizedFallbackIndex = fallbackSelectedIndex.clamp(
    0,
    effectiveChoices.length - 1,
  );
  final preferredMatches = effectiveChoices
      .where(
        (choice) => _matchesDetailTargetPreferredSource(
          pageSeedTarget: pageSeedTarget,
          candidate: choice,
        ),
      )
      .length;
  if (preferredMatches == effectiveChoices.length) {
    return DetailLibraryMatchPreferenceResult(
      choices: effectiveChoices,
      selectedIndex: normalizedFallbackIndex,
      matchedPreferredSource: true,
    );
  }
  final preferredIndex = _preferredDetailLibraryMatchIndex(
    pageSeedTarget: pageSeedTarget,
    choices: effectiveChoices,
  );
  if (preferredIndex < 0) {
    return DetailLibraryMatchPreferenceResult(
      choices: effectiveChoices,
      selectedIndex: normalizedFallbackIndex,
      matchedPreferredSource: false,
    );
  }

  final prioritized = <MediaDetailTarget>[
    effectiveChoices[preferredIndex],
    for (var index = 0; index < effectiveChoices.length; index++)
      if (index != preferredIndex) effectiveChoices[index],
  ];
  return DetailLibraryMatchPreferenceResult(
    choices: List<MediaDetailTarget>.unmodifiable(prioritized),
    selectedIndex: 0,
    matchedPreferredSource: true,
  );
}

bool shouldAutoMatchSeriesOverviewSources({
  required MediaDetailTarget pageSeedTarget,
  required List<MediaDetailTarget> libraryMatchChoices,
}) {
  return pageSeedTarget.isSeries &&
      libraryMatchChoices.length <= 1 &&
      _hasDetailTargetSourcePreference(pageSeedTarget);
}

bool shouldRestoreSeriesSourceScopedTarget({
  required MediaDetailTarget pageSeedTarget,
  required MediaDetailTarget restoredTarget,
}) {
  if (!_hasDetailTargetSourcePreference(pageSeedTarget)) {
    return true;
  }
  return _matchesDetailTargetPreferredSource(
    pageSeedTarget: pageSeedTarget,
    candidate: restoredTarget,
  );
}

MediaDetailTarget buildSeriesOverviewSourceMatchSeed({
  required MediaDetailTarget pageSeedTarget,
  required MediaDetailTarget resolvedTarget,
}) {
  if (!pageSeedTarget.isSeries) {
    return resolvedTarget;
  }

  return pageSeedTarget.copyWith(
    title: resolvedTarget.title.trim().isNotEmpty
        ? resolvedTarget.title
        : pageSeedTarget.title,
    posterUrl: resolvedTarget.posterUrl.trim().isNotEmpty
        ? resolvedTarget.posterUrl
        : pageSeedTarget.posterUrl,
    posterHeaders: resolvedTarget.posterUrl.trim().isNotEmpty
        ? resolvedTarget.posterHeaders
        : pageSeedTarget.posterHeaders,
    backdropUrl: resolvedTarget.backdropUrl.trim().isNotEmpty
        ? resolvedTarget.backdropUrl
        : pageSeedTarget.backdropUrl,
    backdropHeaders: resolvedTarget.backdropUrl.trim().isNotEmpty
        ? resolvedTarget.backdropHeaders
        : pageSeedTarget.backdropHeaders,
    logoUrl: resolvedTarget.logoUrl.trim().isNotEmpty
        ? resolvedTarget.logoUrl
        : pageSeedTarget.logoUrl,
    logoHeaders: resolvedTarget.logoUrl.trim().isNotEmpty
        ? resolvedTarget.logoHeaders
        : pageSeedTarget.logoHeaders,
    bannerUrl: resolvedTarget.bannerUrl.trim().isNotEmpty
        ? resolvedTarget.bannerUrl
        : pageSeedTarget.bannerUrl,
    bannerHeaders: resolvedTarget.bannerUrl.trim().isNotEmpty
        ? resolvedTarget.bannerHeaders
        : pageSeedTarget.bannerHeaders,
    extraBackdropUrls: resolvedTarget.extraBackdropUrls.isNotEmpty
        ? resolvedTarget.extraBackdropUrls
        : pageSeedTarget.extraBackdropUrls,
    extraBackdropHeaders: resolvedTarget.extraBackdropUrls.isNotEmpty
        ? resolvedTarget.extraBackdropHeaders
        : pageSeedTarget.extraBackdropHeaders,
    overview: resolvedTarget.overview.trim().isNotEmpty
        ? resolvedTarget.overview
        : pageSeedTarget.overview,
    year: resolvedTarget.year > 0 ? resolvedTarget.year : pageSeedTarget.year,
    durationLabel: resolvedTarget.durationLabel.trim().isNotEmpty
        ? resolvedTarget.durationLabel
        : pageSeedTarget.durationLabel,
    ratingLabels: resolvedTarget.ratingLabels.isNotEmpty
        ? resolvedTarget.ratingLabels
        : pageSeedTarget.ratingLabels,
    genres: resolvedTarget.genres.isNotEmpty
        ? resolvedTarget.genres
        : pageSeedTarget.genres,
    directors: resolvedTarget.directors.isNotEmpty
        ? resolvedTarget.directors
        : pageSeedTarget.directors,
    directorProfiles: resolvedTarget.directorProfiles.isNotEmpty
        ? resolvedTarget.directorProfiles
        : pageSeedTarget.directorProfiles,
    actors: resolvedTarget.actors.isNotEmpty
        ? resolvedTarget.actors
        : pageSeedTarget.actors,
    actorProfiles: resolvedTarget.actorProfiles.isNotEmpty
        ? resolvedTarget.actorProfiles
        : pageSeedTarget.actorProfiles,
    platforms: resolvedTarget.platforms.isNotEmpty
        ? resolvedTarget.platforms
        : pageSeedTarget.platforms,
    platformProfiles: resolvedTarget.platformProfiles.isNotEmpty
        ? resolvedTarget.platformProfiles
        : pageSeedTarget.platformProfiles,
    searchQuery: resolvedTarget.searchQuery.trim().isNotEmpty
        ? resolvedTarget.searchQuery
        : pageSeedTarget.searchQuery,
    doubanId: resolvedTarget.doubanId.trim().isNotEmpty
        ? resolvedTarget.doubanId
        : pageSeedTarget.doubanId,
    imdbId: resolvedTarget.imdbId.trim().isNotEmpty
        ? resolvedTarget.imdbId
        : pageSeedTarget.imdbId,
    tmdbId: resolvedTarget.tmdbId.trim().isNotEmpty
        ? resolvedTarget.tmdbId
        : pageSeedTarget.tmdbId,
    tvdbId: resolvedTarget.tvdbId.trim().isNotEmpty
        ? resolvedTarget.tvdbId
        : pageSeedTarget.tvdbId,
    wikidataId: resolvedTarget.wikidataId.trim().isNotEmpty
        ? resolvedTarget.wikidataId
        : pageSeedTarget.wikidataId,
    tmdbSetId: resolvedTarget.tmdbSetId.trim().isNotEmpty
        ? resolvedTarget.tmdbSetId
        : pageSeedTarget.tmdbSetId,
    providerIds: resolvedTarget.providerIds.isNotEmpty
        ? resolvedTarget.providerIds
        : pageSeedTarget.providerIds,
  );
}

bool _hasResolvedStructuralResourceState(MediaDetailTarget target) {
  final availability = target.availabilityLabel.trim();
  return target.isPlayable ||
      (availability.isNotEmpty && availability != '无') ||
      target.sourceId.trim().isNotEmpty ||
      target.itemId.trim().isNotEmpty;
}

bool _hasResolvedDetailLocalResourceState(MediaDetailTarget target) {
  return _hasResolvedStructuralResourceState(target);
}

bool _hasDetailTargetSourcePreference(MediaDetailTarget target) {
  return target.sourceId.trim().isNotEmpty || target.sourceKind != null;
}

bool _matchesDetailTargetPreferredSource({
  required MediaDetailTarget pageSeedTarget,
  required MediaDetailTarget candidate,
}) {
  final preferredSourceId = pageSeedTarget.sourceId.trim();
  if (preferredSourceId.isNotEmpty) {
    return candidate.sourceId.trim() == preferredSourceId ||
        candidate.playbackTarget?.sourceId.trim() == preferredSourceId;
  }

  final preferredKind = pageSeedTarget.sourceKind;
  if (preferredKind != null && candidate.sourceKind != preferredKind) {
    return false;
  }

  final preferredSourceName = pageSeedTarget.sourceName.trim();
  if (preferredSourceName.isEmpty) {
    return preferredKind != null;
  }
  return candidate.sourceName.trim() == preferredSourceName;
}

MediaDetailTarget? resolvePreferredEntryLibraryChoice({
  required MediaDetailTarget pageSeedTarget,
  MediaDetailTarget? currentTarget,
}) {
  if (pageSeedTarget.isSeries) {
    return null;
  }
  for (final candidate in [currentTarget, pageSeedTarget]) {
    if (candidate == null) {
      continue;
    }
    if (!_matchesDetailTargetPreferredSource(
      pageSeedTarget: pageSeedTarget,
      candidate: candidate,
    )) {
      continue;
    }
    if (!_hasResolvedDetailLocalResourceState(candidate)) {
      continue;
    }
    return candidate;
  }
  return null;
}

List<MediaDetailTarget> prependPreferredEntryLibraryChoice({
  required MediaDetailTarget pageSeedTarget,
  required List<MediaDetailTarget> choices,
  MediaDetailTarget? currentTarget,
}) {
  final hasPreferredChoice = choices.any(
    (choice) => _matchesDetailTargetPreferredSource(
      pageSeedTarget: pageSeedTarget,
      candidate: choice,
    ),
  );
  if (hasPreferredChoice) {
    return List<MediaDetailTarget>.unmodifiable(choices);
  }

  final preferredChoice = resolvePreferredEntryLibraryChoice(
    pageSeedTarget: pageSeedTarget,
    currentTarget: currentTarget,
  );
  if (preferredChoice == null) {
    return List<MediaDetailTarget>.unmodifiable(choices);
  }

  final seenKeys = <String>{};
  final merged = <MediaDetailTarget>[];
  for (final choice in [preferredChoice, ...choices]) {
    final key = _detailLibraryChoiceIdentityKey(choice);
    if (!seenKeys.add(key)) {
      continue;
    }
    merged.add(choice);
  }
  return List<MediaDetailTarget>.unmodifiable(merged);
}

int _preferredDetailLibraryMatchIndex({
  required MediaDetailTarget pageSeedTarget,
  required List<MediaDetailTarget> choices,
}) {
  final preferredSourceId = pageSeedTarget.sourceId.trim();
  if (preferredSourceId.isNotEmpty) {
    final exactSourceId = choices.indexWhere(
      (choice) =>
          choice.sourceId.trim() == preferredSourceId ||
          choice.playbackTarget?.sourceId.trim() == preferredSourceId,
    );
    if (exactSourceId >= 0) {
      return exactSourceId;
    }
  }

  final preferredSourceName = pageSeedTarget.sourceName.trim();
  final preferredKind = pageSeedTarget.sourceKind;
  if (preferredKind == null && preferredSourceName.isEmpty) {
    return -1;
  }
  return choices.indexWhere(
    (choice) =>
        (preferredKind == null || choice.sourceKind == preferredKind) &&
        (preferredSourceName.isEmpty ||
            choice.sourceName.trim() == preferredSourceName),
  );
}

String _detailLibraryChoiceIdentityKey(MediaDetailTarget target) {
  final playback = target.playbackTarget;
  return [
    target.sourceId.trim(),
    playback?.sourceId.trim() ?? '',
    target.itemId.trim(),
    playback?.itemId.trim() ?? '',
    playback?.preferredMediaSourceId.trim() ?? '',
    _normalizeDetailLibraryChoicePath(target.resourcePath),
    _normalizeDetailLibraryChoicePath(playback?.actualAddress ?? ''),
    _normalizeDetailLibraryChoicePath(playback?.streamUrl ?? ''),
  ].join('|');
}

String _normalizeDetailLibraryChoicePath(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final uri = Uri.tryParse(trimmed);
  final rawPath = uri != null && uri.hasScheme ? uri.path : trimmed;
  return rawPath.replaceAll('\\', '/').trim();
}

class DetailStartupPlan {
  const DetailStartupPlan({
    required this.shouldStart,
    required this.shouldRestoreCachedState,
    required this.shouldRestoreIndexedEpisodeVariants,
    required this.shouldWarmEnrichedTarget,
    required this.shouldWarmSeriesBrowser,
    required this.shouldAttemptAutoLibraryMatch,
    required this.effectiveTarget,
    required this.resolveTargetForAutoMatch,
  });

  final bool shouldStart;
  final bool shouldRestoreCachedState;
  final bool shouldRestoreIndexedEpisodeVariants;
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
  required bool detailAutoLibraryMatchEnabled,
}) {
  final effectiveTarget = manualOverrideTarget ?? pageSeedTarget;
  final canStart = isPageVisible && !backgroundWorkSuspended;

  return DetailStartupPlan(
    shouldStart: canStart,
    shouldRestoreCachedState: canStart,
    shouldRestoreIndexedEpisodeVariants: canStart,
    shouldWarmEnrichedTarget: canStart,
    shouldWarmSeriesBrowser: canStart && effectiveTarget.isSeries,
    shouldAttemptAutoLibraryMatch: canStart && detailAutoLibraryMatchEnabled,
    effectiveTarget: effectiveTarget,
    resolveTargetForAutoMatch: pageSeedTarget,
  );
}
