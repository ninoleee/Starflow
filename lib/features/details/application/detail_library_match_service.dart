import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

class DetailLibraryMatchTaskController {
  bool _isCancelled = false;

  bool get cancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }

  void throwIfCancelled() {
    if (_isCancelled) {
      throw const DetailLibraryMatchCancelledException();
    }
  }
}

class DetailLibraryMatchCancelledException implements Exception {
  const DetailLibraryMatchCancelledException();
}

class DetailLibraryMatchCandidate {
  const DetailLibraryMatchCandidate({
    required this.item,
    required this.matchReason,
    required this.score,
  });

  final MediaItem item;
  final String matchReason;
  final double score;
}

enum DetailManualMatchCategory {
  movie,
  series,
  animation,
  variety,
  unknown,
}

class DetailLibraryMatchService {
  const DetailLibraryMatchService();

  List<MediaSourceConfig> resolveLibraryMatchSources(AppSettings settings) {
    final availableSources = settings.mediaSources
        .where(
          (source) =>
              source.enabled &&
              (source.kind == MediaSourceKind.emby ||
                  source.kind == MediaSourceKind.nas ||
                  (source.kind == MediaSourceKind.quark &&
                      source.hasConfiguredQuarkFolder)),
        )
        .toList(growable: false);
    final selectedIds = settings.libraryMatchSourceIds.toSet();
    if (selectedIds.isEmpty) {
      return availableSources;
    }
    final selectedSources = availableSources
        .where((source) => selectedIds.contains(source.id))
        .toList(growable: false);
    return selectedSources.isEmpty ? availableSources : selectedSources;
  }

  List<MediaDetailTarget> candidatesToMergedTargets(
    MediaDetailTarget current,
    List<DetailLibraryMatchCandidate> candidates,
    String query,
  ) {
    return candidates
        .map(
          (candidate) => mergeMatchedLibraryTarget(
            current: current,
            matched: MediaDetailTarget.fromMediaItem(
              candidate.item,
              availabilityLabel: matchedAvailabilityLabel(
                item: candidate.item,
                matchReason: candidate.matchReason,
              ),
              searchQuery: query,
            ),
          ),
        )
        .toList(growable: false);
  }

  String matchedAvailabilityLabel({
    required MediaItem item,
    required String matchReason,
  }) {
    final base = '${item.sourceKind.label} · ${item.sourceName}';
    final suffix = matchReason.isEmpty ? '' : ' · $matchReason';
    if (item.isPlayable) {
      return '资源已就绪：$base$suffix';
    }
    return '已匹配：$base$suffix';
  }

  String availabilityFeedbackLabel(String label) {
    final trimmed = label.trim();
    if (trimmed.startsWith('资源已就绪：')) {
      return trimmed.substring('资源已就绪：'.length).trim();
    }
    if (trimmed.startsWith('已匹配：')) {
      return trimmed.substring('已匹配：'.length).trim();
    }
    return trimmed;
  }

  bool isUnavailableAvailabilityLabel(String label) {
    return availabilityFeedbackLabel(label) == '无';
  }

  String libraryMatchOptionLabel(MediaDetailTarget target) {
    final source = target.sourceName.trim();
    final title = target.title.trim();
    final section = target.sectionName.trim();
    final tail = section.isEmpty ? title : '$title · $section';
    if (source.isEmpty) {
      return tail;
    }
    return '$source · $tail';
  }

  String movieVariantOptionSubtitle(MediaDetailTarget target) {
    final playback = target.playbackTarget;
    final parts = <String>[];
    final availability =
        availabilityFeedbackLabel(target.availabilityLabel).trim();
    if (availability.isNotEmpty && availability != '无') {
      parts.add(availability);
    }
    final format = playback?.formatLabel.trim() ?? '';
    if (format.isNotEmpty) {
      parts.add(format);
    }
    final resolution = playback?.resolutionLabel.trim() ?? '';
    if (resolution.isNotEmpty) {
      parts.add(resolution);
    }
    final fileSize = playback?.fileSizeLabel.trim() ?? '';
    if (fileSize.isNotEmpty) {
      parts.add(fileSize);
    }
    if (parts.isNotEmpty) {
      return parts.join(' · ');
    }
    final actualAddress = playback?.actualAddress.trim() ?? '';
    if (actualAddress.isNotEmpty) {
      return actualAddress;
    }
    return target.resourcePath.trim();
  }

  List<String> buildManualMatchTitles({
    required MediaDetailTarget target,
    required String query,
    MetadataMatchResult? metadataMatch,
  }) {
    final seen = <String>{};
    final titles = <String>[];
    for (final raw in [
      target.title,
      query,
      if (metadataMatch != null) ...metadataMatch.titlesForMatching,
    ]) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final key = trimmed.toLowerCase();
      if (seen.add(key)) {
        titles.add(trimmed);
      }
    }
    return titles;
  }

  int resolveManualMatchYear(
    MediaDetailTarget target,
    MetadataMatchResult? metadataMatch,
  ) {
    if (target.year > 0) {
      return target.year;
    }
    return metadataMatch?.year ?? 0;
  }

  String resolveManualMatchDoubanId(
    MediaDetailTarget target,
    MetadataMatchResult? metadataMatch,
  ) {
    final current = target.doubanId.trim();
    if (current.isNotEmpty) {
      return current;
    }
    return metadataMatch?.doubanId.trim() ?? '';
  }

  String resolveManualMatchImdbId(
    MediaDetailTarget target,
    MetadataMatchResult? metadataMatch,
  ) {
    final current = target.imdbId.trim();
    if (current.isNotEmpty) {
      return current;
    }
    return metadataMatch?.imdbId.trim() ?? '';
  }

  String resolveManualMatchTmdbId(
    MediaDetailTarget target,
    MetadataMatchResult? metadataMatch,
  ) {
    final current = target.tmdbId.trim();
    if (current.isNotEmpty) {
      return current;
    }
    return metadataMatch?.tmdbId.trim() ?? '';
  }

  String resolveManualMatchTvdbId(MediaDetailTarget target) {
    final current = target.tvdbId.trim();
    if (current.isNotEmpty) {
      return current;
    }
    return target.providerIds['Tvdb']?.trim() ??
        target.providerIds['TVDb']?.trim() ??
        target.providerIds['tvdb']?.trim() ??
        '';
  }

  String resolveManualMatchWikidataId(MediaDetailTarget target) {
    final current = target.wikidataId.trim();
    if (current.isNotEmpty) {
      return current;
    }
    return target.providerIds['Wikidata']?.trim() ??
        target.providerIds['WikiData']?.trim() ??
        target.providerIds['wikidata']?.trim() ??
        '';
  }

  String externalIdMatchReason(
    MediaItem item, {
    required String doubanId,
    required String imdbId,
    required String tmdbId,
    required String tvdbId,
    required String wikidataId,
  }) {
    final reasons = <String>[];
    final normalizedDoubanId = doubanId.trim();
    final normalizedImdbId = imdbId.trim().toLowerCase();
    final normalizedTmdbId = tmdbId.trim();
    final normalizedTvdbId = tvdbId.trim();
    final normalizedWikidataId = wikidataId.trim().toUpperCase();

    if (normalizedDoubanId.isNotEmpty &&
        item.doubanId.trim() == normalizedDoubanId) {
      reasons.add('豆瓣 ID');
    }
    if (normalizedImdbId.isNotEmpty &&
        item.imdbId.trim().toLowerCase() == normalizedImdbId) {
      reasons.add('IMDb ID');
    }
    if (normalizedTmdbId.isNotEmpty && item.tmdbId.trim() == normalizedTmdbId) {
      reasons.add('TMDB ID');
    }
    if (normalizedTvdbId.isNotEmpty && item.tvdbId.trim() == normalizedTvdbId) {
      reasons.add('TVDB ID');
    }
    if (normalizedWikidataId.isNotEmpty &&
        item.wikidataId.trim().toUpperCase() == normalizedWikidataId) {
      reasons.add('Wikidata ID');
    }

    if (reasons.isEmpty) {
      return '按外部 ID 匹配';
    }
    if (reasons.length == 1) {
      return '按 ${reasons.first} 匹配';
    }
    return '按 ${reasons.join(' / ')} 匹配';
  }

  String titleMatchReason(int year) {
    return year > 0 ? '按标题 + 年份匹配' : '按标题匹配';
  }

  int scoreManualMatchCollection(
    MediaCollection collection,
    MediaDetailTarget target, {
    MetadataMatchResult? metadataMatch,
  }) {
    final category = resolveManualMatchCategory(
      target,
      metadataMatch: metadataMatch,
    );
    final label =
        '${collection.title} ${collection.subtitle}'.trim().toLowerCase();
    final isMovieSection = _containsAnyKeyword(label, _movieSectionKeywords);
    final isSeriesSection = _containsAnyKeyword(label, _seriesSectionKeywords);
    final isAnimationSection =
        _containsAnyKeyword(label, _animationSectionKeywords);
    final isVarietySection =
        _containsAnyKeyword(label, _varietySectionKeywords);

    return switch (category) {
      DetailManualMatchCategory.movie => isMovieSection
          ? 300
          : isAnimationSection
              ? 150
              : isSeriesSection || isVarietySection
                  ? 40
                  : 0,
      DetailManualMatchCategory.series => isSeriesSection
          ? 300
          : isAnimationSection || isVarietySection
              ? 220
              : isMovieSection
                  ? 40
                  : 0,
      DetailManualMatchCategory.animation => isAnimationSection
          ? 340
          : isSeriesSection
              ? 260
              : isMovieSection
                  ? 140
                  : 0,
      DetailManualMatchCategory.variety => isVarietySection
          ? 340
          : isSeriesSection
              ? 260
              : isMovieSection
                  ? 40
                  : 0,
      DetailManualMatchCategory.unknown => isMovieSection ||
              isSeriesSection ||
              isAnimationSection ||
              isVarietySection
          ? 80
          : 0,
    };
  }

  DetailManualMatchCategory resolveManualMatchCategory(
    MediaDetailTarget target, {
    MetadataMatchResult? metadataMatch,
  }) {
    final itemType = target.itemType.trim().toLowerCase();
    final signals = <String>[
      itemType,
      ...target.genres,
      if (metadataMatch != null) ...metadataMatch.genres,
    ].join(' ').toLowerCase();

    if (_containsAnyKeyword(signals, _animationCategoryKeywords)) {
      return DetailManualMatchCategory.animation;
    }
    if (_containsAnyKeyword(signals, _varietyCategoryKeywords)) {
      return DetailManualMatchCategory.variety;
    }
    if (itemType == 'movie') {
      return DetailManualMatchCategory.movie;
    }
    if (itemType == 'series' || itemType == 'season' || itemType == 'episode') {
      return DetailManualMatchCategory.series;
    }
    if (_containsAnyKeyword(signals, _seriesCategoryKeywords)) {
      return DetailManualMatchCategory.series;
    }
    if (_containsAnyKeyword(signals, _movieCategoryKeywords)) {
      return DetailManualMatchCategory.movie;
    }
    return DetailManualMatchCategory.unknown;
  }

  MediaDetailTarget mergeMatchedLibraryTarget({
    required MediaDetailTarget current,
    required MediaDetailTarget matched,
  }) {
    final merged = matched.copyWith(
      title: current.title,
      posterUrl: firstNonEmpty(matched.posterUrl, current.posterUrl),
      posterHeaders: matched.posterUrl.trim().isNotEmpty
          ? matched.posterHeaders
          : (current.posterHeaders.isNotEmpty
              ? current.posterHeaders
              : matched.posterHeaders),
      backdropUrl: firstNonEmpty(matched.backdropUrl, current.backdropUrl),
      backdropHeaders: matched.backdropUrl.trim().isNotEmpty
          ? matched.backdropHeaders
          : (current.backdropHeaders.isNotEmpty
              ? current.backdropHeaders
              : matched.backdropHeaders),
      logoUrl: firstNonEmpty(matched.logoUrl, current.logoUrl),
      logoHeaders: matched.logoUrl.trim().isNotEmpty
          ? matched.logoHeaders
          : (current.logoHeaders.isNotEmpty
              ? current.logoHeaders
              : matched.logoHeaders),
      bannerUrl: firstNonEmpty(matched.bannerUrl, current.bannerUrl),
      bannerHeaders: matched.bannerUrl.trim().isNotEmpty
          ? matched.bannerHeaders
          : (current.bannerHeaders.isNotEmpty
              ? current.bannerHeaders
              : matched.bannerHeaders),
      extraBackdropUrls: mergeUniqueImageUrls([
        ...matched.extraBackdropUrls,
        ...current.extraBackdropUrls,
      ]),
      extraBackdropHeaders: matched.extraBackdropUrls.isNotEmpty
          ? matched.extraBackdropHeaders
          : (current.extraBackdropHeaders.isNotEmpty
              ? current.extraBackdropHeaders
              : matched.extraBackdropHeaders),
      overview: current.hasUsefulOverview ? current.overview : matched.overview,
      year: current.year > 0 ? current.year : matched.year,
      durationLabel: current.durationLabel.trim().isNotEmpty
          ? current.durationLabel
          : matched.durationLabel,
      genres: current.genres.isNotEmpty ? current.genres : matched.genres,
      directors:
          current.directors.isNotEmpty ? current.directors : matched.directors,
      directorProfiles: current.directorProfiles.isNotEmpty
          ? current.directorProfiles
          : matched.directorProfiles,
      actors: current.actors.isNotEmpty ? current.actors : matched.actors,
      actorProfiles: current.actorProfiles.isNotEmpty
          ? current.actorProfiles
          : matched.actorProfiles,
      platforms:
          current.platforms.isNotEmpty ? current.platforms : matched.platforms,
      platformProfiles: current.platformProfiles.isNotEmpty
          ? current.platformProfiles
          : matched.platformProfiles,
      ratingLabels: mergeLabels(
        matched.ratingLabels,
        current.ratingLabels,
      ),
      doubanId: current.doubanId,
      imdbId: current.imdbId,
      tmdbId:
          current.tmdbId.trim().isNotEmpty ? current.tmdbId : matched.tmdbId,
      tvdbId:
          current.tvdbId.trim().isNotEmpty ? current.tvdbId : matched.tvdbId,
      wikidataId: current.wikidataId.trim().isNotEmpty
          ? current.wikidataId
          : matched.wikidataId,
      tmdbSetId: current.tmdbSetId.trim().isNotEmpty
          ? current.tmdbSetId
          : matched.tmdbSetId,
      providerIds: current.providerIds.isNotEmpty
          ? current.providerIds
          : matched.providerIds,
    );
    return preserveSeriesStructuralTargetIfNeeded(
      current: current,
      resolved: merged,
    );
  }

  MediaDetailTarget applyMetadataMatchToDetailTarget(
    MediaDetailTarget target,
    MetadataMatchResult match, {
    bool replaceExisting = false,
  }) {
    final filteredMatchRatingLabels = filterSupplementalRatingLabels(
      existing: target.ratingLabels,
      supplemental: match.ratingLabels,
    );
    final resolvedDirectorProfiles = match.directorProfiles.isNotEmpty
        ? _toMediaPersonProfiles(match.directorProfiles)
        : const <MediaPersonProfile>[];
    final resolvedActorProfiles = match.actorProfiles.isNotEmpty
        ? _toMediaPersonProfiles(match.actorProfiles)
        : const <MediaPersonProfile>[];
    final resolvedPlatformProfiles = match.platformProfiles.isNotEmpty
        ? _toMediaPersonProfiles(match.platformProfiles)
        : const <MediaPersonProfile>[];
    final shouldReplaceCompanies = match.provider == MetadataMatchProvider.tmdb;
    return target.copyWith(
      posterUrl: replaceExisting
          ? firstNonEmpty(match.posterUrl, target.posterUrl)
          : (target.posterUrl.trim().isNotEmpty
              ? target.posterUrl
              : match.posterUrl),
      posterHeaders: replaceExisting
          ? (match.posterUrl.trim().isNotEmpty
              ? const <String, String>{}
              : target.posterHeaders)
          : target.posterHeaders,
      backdropUrl: replaceExisting
          ? firstNonEmpty(match.backdropUrl, target.backdropUrl)
          : (target.backdropUrl.trim().isNotEmpty
              ? target.backdropUrl
              : match.backdropUrl),
      backdropHeaders: replaceExisting
          ? (match.backdropUrl.trim().isNotEmpty
              ? const <String, String>{}
              : target.backdropHeaders)
          : target.backdropHeaders,
      logoUrl: replaceExisting
          ? firstNonEmpty(match.logoUrl, target.logoUrl)
          : (target.logoUrl.trim().isNotEmpty ? target.logoUrl : match.logoUrl),
      logoHeaders: replaceExisting
          ? (match.logoUrl.trim().isNotEmpty
              ? const <String, String>{}
              : target.logoHeaders)
          : target.logoHeaders,
      bannerUrl: replaceExisting
          ? firstNonEmpty(match.bannerUrl, target.bannerUrl)
          : (target.bannerUrl.trim().isNotEmpty
              ? target.bannerUrl
              : match.bannerUrl),
      bannerHeaders: replaceExisting
          ? (match.bannerUrl.trim().isNotEmpty
              ? const <String, String>{}
              : target.bannerHeaders)
          : target.bannerHeaders,
      extraBackdropUrls: replaceExisting
          ? (match.extraBackdropUrls.isNotEmpty
              ? mergeUniqueImageUrls(match.extraBackdropUrls)
              : target.extraBackdropUrls)
          : mergeUniqueImageUrls([
              ...target.extraBackdropUrls,
              ...match.extraBackdropUrls,
            ]),
      extraBackdropHeaders: replaceExisting
          ? (match.extraBackdropUrls.isNotEmpty
              ? const <String, String>{}
              : target.extraBackdropHeaders)
          : target.extraBackdropHeaders,
      overview: replaceExisting
          ? firstNonEmpty(match.overview, target.overview)
          : (target.hasUsefulOverview
              ? target.overview
              : (match.overview.trim().isNotEmpty
                  ? match.overview
                  : target.overview)),
      year: replaceExisting
          ? (match.year > 0 ? match.year : target.year)
          : (target.year > 0 ? target.year : match.year),
      durationLabel: replaceExisting
          ? firstNonEmpty(match.durationLabel, target.durationLabel)
          : (match.durationLabel.trim().isNotEmpty
              ? (target.durationLabel.trim().isNotEmpty
                  ? target.durationLabel
                  : match.durationLabel)
              : target.durationLabel),
      genres: replaceExisting
          ? (match.genres.isNotEmpty ? match.genres : target.genres)
          : (target.genres.isNotEmpty ? target.genres : match.genres),
      directors: replaceExisting
          ? (match.directors.isNotEmpty ? match.directors : target.directors)
          : (target.directors.isNotEmpty ? target.directors : match.directors),
      directorProfiles: replaceExisting
          ? (resolvedDirectorProfiles.isNotEmpty
              ? resolvedDirectorProfiles
              : target.directorProfiles)
          : (target.directorProfiles.isNotEmpty
              ? target.directorProfiles
              : resolvedDirectorProfiles.isNotEmpty
                  ? resolvedDirectorProfiles
                  : target.directorProfiles),
      actors: replaceExisting
          ? (match.actors.isNotEmpty ? match.actors : target.actors)
          : (target.actors.isNotEmpty ? target.actors : match.actors),
      actorProfiles: replaceExisting
          ? (resolvedActorProfiles.isNotEmpty
              ? resolvedActorProfiles
              : target.actorProfiles)
          : (target.actorProfiles.isNotEmpty
              ? target.actorProfiles
              : resolvedActorProfiles.isNotEmpty
                  ? resolvedActorProfiles
                  : target.actorProfiles),
      platforms: shouldReplaceCompanies
          ? match.platforms
          : (replaceExisting
              ? (match.platforms.isNotEmpty
                  ? match.platforms
                  : target.platforms)
              : (target.platforms.isNotEmpty
                  ? target.platforms
                  : match.platforms)),
      platformProfiles: shouldReplaceCompanies
          ? resolvedPlatformProfiles
          : (replaceExisting
              ? (resolvedPlatformProfiles.isNotEmpty
                  ? resolvedPlatformProfiles
                  : target.platformProfiles)
              : (target.platformProfiles.isNotEmpty
                  ? target.platformProfiles
                  : resolvedPlatformProfiles.isNotEmpty
                      ? resolvedPlatformProfiles
                      : target.platformProfiles)),
      ratingLabels: mergeLabels(target.ratingLabels, filteredMatchRatingLabels),
      doubanId: replaceExisting
          ? firstNonEmpty(match.doubanId, target.doubanId)
          : (target.doubanId.trim().isNotEmpty
              ? target.doubanId
              : match.doubanId),
      imdbId: replaceExisting
          ? firstNonEmpty(match.imdbId, target.imdbId)
          : (target.imdbId.trim().isNotEmpty ? target.imdbId : match.imdbId),
      tmdbId: replaceExisting
          ? firstNonEmpty(match.tmdbId, target.tmdbId)
          : (target.tmdbId.trim().isNotEmpty ? target.tmdbId : match.tmdbId),
    );
  }

  MediaDetailTarget preserveSeriesStructuralTargetIfNeeded({
    required MediaDetailTarget current,
    required MediaDetailTarget resolved,
  }) {
    if (!current.isSeries || resolved.isSeries) {
      return resolved;
    }

    final resolvedPlayback = resolved.playbackTarget;
    final currentPlayback = current.playbackTarget;
    final currentSectionName = current.sectionName.trim();
    final resolvedSectionName = resolved.sectionName.trim();
    final preferredSectionName = resolvedSectionName.isNotEmpty &&
            (currentSectionName.isEmpty ||
                currentSectionName == '剧集' ||
                currentSectionName == '全部剧集')
        ? resolved.sectionName
        : current.sectionName;
    final resolvedSeriesItemId = current.itemId.trim().isNotEmpty
        ? current.itemId
        : (resolvedPlayback?.seriesId.trim().isNotEmpty == true
            ? resolvedPlayback!.seriesId.trim()
            : '');
    final normalizedPlayback = resolvedPlayback?.copyWith(
      seriesId: resolvedSeriesItemId.isNotEmpty
          ? resolvedSeriesItemId
          : resolvedPlayback.seriesId,
      seriesTitle: current.title.trim().isNotEmpty
          ? current.title
          : (resolvedPlayback.seriesTitle.trim().isNotEmpty
              ? resolvedPlayback.seriesTitle
              : currentPlayback?.resolvedSeriesTitle ?? resolved.title),
    );

    return current.copyWith(
      title: current.title.trim().isNotEmpty ? current.title : resolved.title,
      posterUrl: resolved.posterUrl,
      posterHeaders: resolved.posterHeaders,
      backdropUrl: resolved.backdropUrl,
      backdropHeaders: resolved.backdropHeaders,
      logoUrl: resolved.logoUrl,
      logoHeaders: resolved.logoHeaders,
      bannerUrl: resolved.bannerUrl,
      bannerHeaders: resolved.bannerHeaders,
      extraBackdropUrls: resolved.extraBackdropUrls,
      extraBackdropHeaders: resolved.extraBackdropHeaders,
      overview: resolved.overview,
      year: resolved.year,
      durationLabel: resolved.durationLabel,
      ratingLabels: resolved.ratingLabels,
      genres: resolved.genres,
      directors: resolved.directors,
      directorProfiles: resolved.directorProfiles,
      actors: resolved.actors,
      actorProfiles: resolved.actorProfiles,
      platforms: resolved.platforms,
      platformProfiles: resolved.platformProfiles,
      availabilityLabel: resolved.availabilityLabel,
      searchQuery: resolved.searchQuery,
      playbackTarget: normalizedPlayback,
      itemId: resolvedSeriesItemId.isNotEmpty
          ? resolvedSeriesItemId
          : resolved.itemId,
      sourceId: current.sourceId.trim().isNotEmpty
          ? current.sourceId
          : resolved.sourceId,
      itemType:
          current.itemType.trim().isNotEmpty ? current.itemType : 'series',
      sectionId: current.sectionId.trim().isNotEmpty
          ? current.sectionId
          : resolved.sectionId,
      sectionName: preferredSectionName,
      resourcePath: resolved.resourcePath,
      doubanId: current.doubanId.trim().isNotEmpty
          ? current.doubanId
          : resolved.doubanId,
      imdbId:
          current.imdbId.trim().isNotEmpty ? current.imdbId : resolved.imdbId,
      tmdbId:
          current.tmdbId.trim().isNotEmpty ? current.tmdbId : resolved.tmdbId,
      tvdbId:
          current.tvdbId.trim().isNotEmpty ? current.tvdbId : resolved.tvdbId,
      wikidataId: current.wikidataId.trim().isNotEmpty
          ? current.wikidataId
          : resolved.wikidataId,
      tmdbSetId: current.tmdbSetId.trim().isNotEmpty
          ? current.tmdbSetId
          : resolved.tmdbSetId,
      providerIds: current.providerIds.isNotEmpty
          ? current.providerIds
          : resolved.providerIds,
      sourceKind: resolved.sourceKind ?? current.sourceKind,
      sourceName: resolved.sourceName.trim().isNotEmpty
          ? resolved.sourceName
          : current.sourceName,
    );
  }

  MediaDetailTarget normalizeRatingLabelsInTarget(MediaDetailTarget target) {
    return target.copyWith(
      ratingLabels: mergeLabels(const [], target.ratingLabels),
    );
  }

  List<String> filterSupplementalRatingLabels({
    required List<String> existing,
    required List<String> supplemental,
  }) {
    if (!hasRatingLabelKeyword(existing, '豆瓣')) {
      return supplemental;
    }
    return supplemental
        .where((label) => !label.trim().toLowerCase().contains('豆瓣'))
        .toList(growable: false);
  }

  bool hasRatingLabelKeyword(Iterable<String> labels, String keyword) {
    final normalizedKeyword = keyword.trim().toLowerCase();
    if (normalizedKeyword.isEmpty) {
      return false;
    }
    return labels.any(
      (label) => label.trim().toLowerCase().contains(normalizedKeyword),
    );
  }

  String firstNonEmpty(String primary, String fallback) {
    final primaryTrimmed = primary.trim();
    if (primaryTrimmed.isNotEmpty) {
      return primaryTrimmed;
    }
    return fallback.trim();
  }

  List<String> mergeLabels(List<String> primary, List<String> secondary) {
    final seen = <String>{};
    final merged = <String>[];
    for (final value in [...primary, ...secondary]) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final key = _labelMergeKey(trimmed);
      if (seen.add(key)) {
        merged.add(trimmed);
      }
    }
    return merged;
  }

  List<String> mergeUniqueImageUrls(Iterable<String> values) {
    final seen = <String>{};
    final merged = <String>[];
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) {
        continue;
      }
      merged.add(trimmed);
    }
    return merged;
  }

  String _labelMergeKey(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.contains('豆瓣') || normalized.contains('douban')) {
      return 'rating:douban';
    }
    if (normalized.contains('imdb')) {
      return 'rating:imdb';
    }
    if (normalized.contains('tmdb')) {
      return 'rating:tmdb';
    }
    return normalized;
  }

  bool _containsAnyKeyword(String value, List<String> keywords) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    for (final keyword in keywords) {
      if (normalized.contains(keyword)) {
        return true;
      }
    }
    return false;
  }

  List<MediaPersonProfile> _toMediaPersonProfiles(
    List<MetadataPersonProfile> profiles,
  ) {
    return profiles
        .map(
          (item) => MediaPersonProfile(
            name: item.name,
            avatarUrl: item.avatarUrl,
          ),
        )
        .toList(growable: false);
  }
}

const List<String> _movieCategoryKeywords = [
  '电影',
  'movie',
  'film',
  '院线',
  '影院',
];

const List<String> _seriesCategoryKeywords = [
  '剧',
  '剧集',
  '电视剧',
  '连续剧',
  'tv',
  'series',
  'season',
  'episode',
];

const List<String> _animationCategoryKeywords = [
  '动画',
  '动漫',
  '番剧',
  'anime',
  'animation',
  'cartoon',
];

const List<String> _varietyCategoryKeywords = [
  '综艺',
  '真人秀',
  '脱口秀',
  '选秀',
  'variety',
  'talk show',
];

const List<String> _movieSectionKeywords = [
  '电影',
  'movie',
  'movies',
  'film',
  '影院',
];

const List<String> _seriesSectionKeywords = [
  '剧集',
  '电视剧',
  '连续剧',
  'tv',
  'series',
  'show',
  'shows',
];

const List<String> _animationSectionKeywords = [
  '动画',
  '动漫',
  '番剧',
  'anime',
  'animation',
];

const List<String> _varietySectionKeywords = [
  '综艺',
  '真人秀',
  '脱口秀',
  'variety',
];
