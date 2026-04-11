part of 'home_controller.dart';

class HomeFeedRepository {
  const HomeFeedRepository();

  Future<List<MediaItem>> loadRecentItems({
    required List<HomeModuleConfig> enabledModules,
    required MediaRepository mediaRepository,
  }) async {
    if (!_needsRecentlyAdded(enabledModules)) {
      return const [];
    }
    return mediaRepository.fetchRecentlyAdded(
      limit: _defaultHomeSectionItemLimit,
    );
  }

  Future<List<PlaybackProgressEntry>> loadRecentPlaybackEntries({
    required List<HomeModuleConfig> enabledModules,
    required PlaybackMemoryRepository playbackMemoryRepository,
  }) async {
    if (!_needsRecentPlayback(enabledModules)) {
      return const [];
    }
    return playbackMemoryRepository.loadRecentDisplayEntries(
      limit: _defaultHomeSectionItemLimit,
    );
  }

  Future<List<DoubanCarouselEntry>> loadCarouselItems({
    required List<HomeModuleConfig> enabledModules,
    required DiscoveryRepository discoveryRepository,
  }) async {
    if (!_needsCarousel(enabledModules)) {
      return const [];
    }
    return discoveryRepository.fetchCarouselItems();
  }

  Future<HomeSectionViewModel?> buildSectionSeed({
    required HomeModuleConfig module,
    required MediaRepository mediaRepository,
    required DiscoveryRepository discoveryRepository,
    required DoubanAccountConfig doubanAccount,
    required List<MediaSourceConfig> mediaSources,
    required Future<List<MediaItem>> recentItems,
    required Future<List<PlaybackProgressEntry>> recentPlaybackEntries,
    required Future<List<DoubanCarouselEntry>> carouselItems,
  }) async {
    switch (module.type) {
      case HomeModuleType.hero:
        return null;
      case HomeModuleType.recentlyAdded:
        return _buildLibrarySectionSeed(
          module: module,
          items: await recentItems,
          subtitle: module.description,
        );
      case HomeModuleType.recentPlayback:
        return _buildRecentPlaybackSectionSeed(
          module: module,
          entries: await recentPlaybackEntries,
        );
      case HomeModuleType.librarySection:
        final sourceKind = _resolveSourceKind(mediaSources, module.sourceId);
        final sectionItems = module.isLibrarySection
            ? await mediaRepository.fetchLibrary(
                sourceId: module.sourceId,
                sectionId: module.sectionId,
                limit: _homeModuleFetchLimit(module, sourceKind: sourceKind),
              )
            : const <MediaItem>[];
        return _buildLibrarySectionSeed(
          module: module,
          items: sectionItems,
          subtitle: module.description,
          viewAllTarget: module.isLibrarySection
              ? LibraryCollectionTarget(
                  title: module.title,
                  sourceId: module.sourceId,
                  sourceName: module.sourceName,
                  sourceKind: sourceKind,
                  sectionId: module.sectionId,
                  subtitle: module.sectionName,
                )
              : null,
        );
      case HomeModuleType.doubanInterest:
      case HomeModuleType.doubanSuggestion:
      case HomeModuleType.doubanList:
        final entries = await discoveryRepository.fetchEntries(module);
        return _buildDoubanSectionSeed(
          module: module,
          entries: entries,
          emptyMessage: _resolveDoubanEmptyMessage(module, doubanAccount),
        );
      case HomeModuleType.doubanCarousel:
        return _buildCarouselSectionSeed(
          module: module,
          items: await carouselItems,
          emptyMessage: _resolveDoubanEmptyMessage(module, doubanAccount),
        );
    }
  }

  Future<HomeSectionViewModel> applyCachedSection({
    required HomeSectionViewModel section,
    required LocalStorageCacheRepository localStorageCacheRepository,
  }) {
    return _applyCachedHomeSection(
      section: section,
      localStorageCacheRepository: localStorageCacheRepository,
    );
  }
}

int _homeModuleFetchLimit(
  HomeModuleConfig module, {
  required MediaSourceKind sourceKind,
}) {
  return _defaultHomeSectionItemLimit;
}

bool _needsRecentlyAdded(List<HomeModuleConfig> modules) {
  return modules.any((item) => item.type == HomeModuleType.recentlyAdded);
}

bool _needsRecentPlayback(List<HomeModuleConfig> modules) {
  return modules.any((item) => item.type == HomeModuleType.recentPlayback);
}

bool _needsCarousel(List<HomeModuleConfig> modules) {
  return modules.any((item) => item.type == HomeModuleType.doubanCarousel);
}

Future<HomeSectionViewModel> _buildLibrarySectionSeed({
  required HomeModuleConfig module,
  required List<MediaItem> items,
  required String subtitle,
  LibraryCollectionTarget? viewAllTarget,
}) async {
  final seedTargets =
      items.map(MediaDetailTarget.fromMediaItem).toList(growable: false);
  final detailTargets = seedTargets;
  final viewModels = <HomeCardViewModel>[];
  for (var index = 0; index < items.length; index += 1) {
    final item = items[index];
    final detailTarget = detailTargets[index];
    viewModels.add(
      HomeCardViewModel(
        id: item.id,
        title: detailTarget.title.trim().isNotEmpty
            ? detailTarget.title
            : item.title,
        subtitle: item.year > 0 ? '${item.year}' : '',
        posterUrl: detailTarget.posterUrl.trim().isNotEmpty
            ? detailTarget.posterUrl
            : item.posterUrl,
        detailTarget: detailTarget,
      ),
    );
  }

  return HomeSectionViewModel(
    id: module.id,
    title: module.title,
    subtitle: subtitle,
    emptyMessage: '无',
    layout: HomeSectionLayout.posterRail,
    items: viewModels,
    viewAllTarget: viewAllTarget == null
        ? null
        : HomeSectionViewAllTarget.collection(viewAllTarget),
  );
}

Future<HomeSectionViewModel> _applyCachedHomeSection({
  required HomeSectionViewModel section,
  required LocalStorageCacheRepository localStorageCacheRepository,
}) async {
  if (section.layout == HomeSectionLayout.posterRail) {
    final items = section.items;
    if (items.isEmpty) {
      return section;
    }
    final mergedTargets = await _resolveCachedHomeDetailTargetsBatch(
      seedTargets:
          items.map((item) => item.detailTarget).toList(growable: false),
      localStorageCacheRepository: localStorageCacheRepository,
    );
    final mergedItems = <HomeCardViewModel>[];
    for (var index = 0; index < items.length; index += 1) {
      final item = items[index];
      final mergedTarget = mergedTargets[index];
      mergedItems.add(
        HomeCardViewModel(
          id: item.id,
          title: mergedTarget.title.trim().isNotEmpty
              ? mergedTarget.title
              : item.title,
          subtitle: item.subtitle,
          posterUrl: mergedTarget.posterUrl.trim().isNotEmpty
              ? mergedTarget.posterUrl
              : item.posterUrl,
          detailTarget: mergedTarget,
        ),
      );
    }
    return HomeSectionViewModel(
      id: section.id,
      title: section.title,
      subtitle: section.subtitle,
      emptyMessage: section.emptyMessage,
      layout: section.layout,
      items: mergedItems,
      carouselItems: section.carouselItems,
      viewAllTarget: section.viewAllTarget,
    );
  }

  final carouselItems = section.carouselItems;
  if (carouselItems.isEmpty) {
    return section;
  }
  final mergedTargets = await _resolveCachedHomeDetailTargetsBatch(
    seedTargets:
        carouselItems.map((item) => item.detailTarget).toList(growable: false),
    localStorageCacheRepository: localStorageCacheRepository,
  );
  final mergedCarouselItems = <HomeCarouselItemViewModel>[];
  for (var index = 0; index < carouselItems.length; index += 1) {
    final item = carouselItems[index];
    final mergedTarget = mergedTargets[index];
    final imageUrl = item.imageUrl.trim().isNotEmpty
        ? item.imageUrl
        : (mergedTarget.posterUrl.trim().isNotEmpty
            ? mergedTarget.posterUrl
            : item.imageUrl);
    mergedCarouselItems.add(
      HomeCarouselItemViewModel(
        id: item.id,
        title: mergedTarget.title.trim().isNotEmpty
            ? mergedTarget.title
            : item.title,
        subtitle: item.subtitle,
        imageUrl: imageUrl,
        detailTarget: mergedTarget,
      ),
    );
  }
  return HomeSectionViewModel(
    id: section.id,
    title: section.title,
    subtitle: section.subtitle,
    emptyMessage: section.emptyMessage,
    layout: section.layout,
    items: section.items,
    carouselItems: mergedCarouselItems,
    viewAllTarget: section.viewAllTarget,
  );
}

Future<List<MediaDetailTarget>> _resolveCachedHomeDetailTargetsBatch({
  required List<MediaDetailTarget> seedTargets,
  required LocalStorageCacheRepository localStorageCacheRepository,
}) async {
  if (seedTargets.isEmpty) {
    return const <MediaDetailTarget>[];
  }
  final cachedTargets =
      await localStorageCacheRepository.loadDetailTargetsBatch(seedTargets);
  return List<MediaDetailTarget>.generate(seedTargets.length, (index) {
    final seedTarget = seedTargets[index];
    final cachedTarget =
        index < cachedTargets.length ? cachedTargets[index] : null;
    if (cachedTarget == null) {
      return seedTarget;
    }
    return _mergeCachedHomeDetailTarget(seedTarget, cachedTarget);
  }, growable: false);
}

MediaDetailTarget _mergeCachedHomeDetailTarget(
  MediaDetailTarget seed,
  MediaDetailTarget cached,
) {
  final preferCachedResourceState =
      _homeHasResolvedLocalResourceState(cached) &&
          !_homeHasResolvedLocalResourceState(seed);
  final preferCachedAvailability =
      _homeShouldPreferCachedAvailability(seed, cached) ||
          preferCachedResourceState;
  final preferCachedSourceContext =
      _homeShouldPreferCachedSourceContext(seed, cached) ||
          preferCachedResourceState;
  final resolvedPosterUrl =
      cached.posterUrl.trim().isNotEmpty ? cached.posterUrl : seed.posterUrl;
  final resolvedPosterHeaders = cached.posterUrl.trim().isNotEmpty
      ? (cached.posterHeaders.isNotEmpty
          ? cached.posterHeaders
          : seed.posterHeaders)
      : (seed.posterHeaders.isNotEmpty
          ? seed.posterHeaders
          : cached.posterHeaders);
  return seed.copyWith(
    title: cached.title.trim().isNotEmpty ? cached.title : seed.title,
    posterUrl: resolvedPosterUrl,
    posterHeaders: resolvedPosterHeaders,
    backdropUrl: seed.backdropUrl.trim().isNotEmpty
        ? seed.backdropUrl
        : cached.backdropUrl,
    backdropHeaders: seed.backdropHeaders.isNotEmpty
        ? seed.backdropHeaders
        : cached.backdropHeaders,
    logoUrl: seed.logoUrl.trim().isNotEmpty ? seed.logoUrl : cached.logoUrl,
    logoHeaders:
        seed.logoHeaders.isNotEmpty ? seed.logoHeaders : cached.logoHeaders,
    bannerUrl:
        seed.bannerUrl.trim().isNotEmpty ? seed.bannerUrl : cached.bannerUrl,
    bannerHeaders: seed.bannerHeaders.isNotEmpty
        ? seed.bannerHeaders
        : cached.bannerHeaders,
    extraBackdropUrls: seed.extraBackdropUrls.isNotEmpty
        ? seed.extraBackdropUrls
        : cached.extraBackdropUrls,
    extraBackdropHeaders: seed.extraBackdropHeaders.isNotEmpty
        ? seed.extraBackdropHeaders
        : cached.extraBackdropHeaders,
    overview: seed.hasUsefulOverview ? seed.overview : cached.overview,
    durationLabel: seed.durationLabel.trim().isNotEmpty
        ? seed.durationLabel
        : cached.durationLabel,
    ratingLabels:
        mergeDistinctRatingLabels(cached.ratingLabels, seed.ratingLabels),
    genres: seed.genres.isNotEmpty ? seed.genres : cached.genres,
    directors: seed.directors.isNotEmpty ? seed.directors : cached.directors,
    directorProfiles: seed.directorProfiles.isNotEmpty
        ? seed.directorProfiles
        : cached.directorProfiles,
    actors: seed.actors.isNotEmpty ? seed.actors : cached.actors,
    actorProfiles: seed.actorProfiles.isNotEmpty
        ? seed.actorProfiles
        : cached.actorProfiles,
    platforms: seed.platforms.isNotEmpty ? seed.platforms : cached.platforms,
    platformProfiles: seed.platformProfiles.isNotEmpty
        ? seed.platformProfiles
        : cached.platformProfiles,
    doubanId: seed.doubanId.trim().isNotEmpty ? seed.doubanId : cached.doubanId,
    imdbId: seed.imdbId.trim().isNotEmpty ? seed.imdbId : cached.imdbId,
    tmdbId: seed.tmdbId.trim().isNotEmpty ? seed.tmdbId : cached.tmdbId,
    availabilityLabel: preferCachedAvailability
        ? (cached.availabilityLabel.trim().isNotEmpty
            ? cached.availabilityLabel
            : seed.availabilityLabel)
        : (seed.availabilityLabel.trim().isNotEmpty
            ? seed.availabilityLabel
            : cached.availabilityLabel),
    searchQuery: seed.searchQuery.trim().isNotEmpty
        ? seed.searchQuery
        : cached.searchQuery,
    playbackTarget: seed.playbackTarget ?? cached.playbackTarget,
    itemId: preferCachedSourceContext
        ? (cached.itemId.trim().isNotEmpty ? cached.itemId : seed.itemId)
        : (seed.itemId.trim().isNotEmpty ? seed.itemId : cached.itemId),
    sourceId: preferCachedSourceContext
        ? (cached.sourceId.trim().isNotEmpty ? cached.sourceId : seed.sourceId)
        : (seed.sourceId.trim().isNotEmpty ? seed.sourceId : cached.sourceId),
    itemType: preferCachedSourceContext
        ? (cached.itemType.trim().isNotEmpty ? cached.itemType : seed.itemType)
        : (seed.itemType.trim().isNotEmpty ? seed.itemType : cached.itemType),
    seasonNumber: preferCachedSourceContext
        ? (cached.seasonNumber ?? seed.seasonNumber)
        : (seed.seasonNumber ?? cached.seasonNumber),
    episodeNumber: preferCachedSourceContext
        ? (cached.episodeNumber ?? seed.episodeNumber)
        : (seed.episodeNumber ?? cached.episodeNumber),
    sectionId: preferCachedSourceContext
        ? (cached.sectionId.trim().isNotEmpty
            ? cached.sectionId
            : seed.sectionId)
        : (seed.sectionId.trim().isNotEmpty
            ? seed.sectionId
            : cached.sectionId),
    sectionName: preferCachedSourceContext
        ? (cached.sectionName.trim().isNotEmpty
            ? cached.sectionName
            : seed.sectionName)
        : (seed.sectionName.trim().isNotEmpty
            ? seed.sectionName
            : cached.sectionName),
    resourcePath: preferCachedSourceContext
        ? (cached.resourcePath.trim().isNotEmpty
            ? cached.resourcePath
            : seed.resourcePath)
        : (seed.resourcePath.trim().isNotEmpty
            ? seed.resourcePath
            : cached.resourcePath),
    sourceKind: preferCachedSourceContext
        ? (cached.sourceKind ?? seed.sourceKind)
        : (seed.sourceKind ?? cached.sourceKind),
    sourceName: preferCachedSourceContext
        ? (cached.sourceName.trim().isNotEmpty
            ? cached.sourceName
            : seed.sourceName)
        : (seed.sourceName.trim().isNotEmpty
            ? seed.sourceName
            : cached.sourceName),
  );
}

Future<HomeSectionViewModel> _buildRecentPlaybackSectionSeed({
  required HomeModuleConfig module,
  required List<PlaybackProgressEntry> entries,
}) async {
  final seedTargets =
      entries.map(_buildRecentPlaybackDetailTarget).toList(growable: false);
  final detailTargets = seedTargets;
  final items = <HomeCardViewModel>[];
  for (var index = 0; index < entries.length; index += 1) {
    final entry = entries[index];
    final detailTarget = detailTargets[index];
    items.add(
      HomeCardViewModel(
        id: entry.key,
        title: _resolveRecentPlaybackDisplayTitle(
          entry: entry,
          detailTarget: detailTarget,
        ),
        subtitle: _buildRecentPlaybackSubtitle(entry),
        posterUrl: detailTarget.posterUrl,
        detailTarget: detailTarget,
      ),
    );
  }

  return HomeSectionViewModel(
    id: module.id,
    title: module.title,
    subtitle: module.description,
    emptyMessage: '暂无最近播放',
    layout: HomeSectionLayout.posterRail,
    items: items,
  );
}

MediaDetailTarget _buildRecentPlaybackDetailTarget(
    PlaybackProgressEntry entry) {
  final target = entry.target;
  final seriesTitle = _resolveRecentPlaybackSeriesTitle(
    entry: entry,
    detailTarget: null,
  );
  final useSeriesTarget = seriesTitle.isNotEmpty &&
      (target.isEpisode ||
          target.isSeries ||
          target.seriesId.trim().isNotEmpty ||
          entry.seriesKey.trim().isNotEmpty);
  final resolvedTitle = useSeriesTarget ? seriesTitle : target.title;
  final resolvedItemId = useSeriesTarget && target.seriesId.trim().isNotEmpty
      ? target.seriesId
      : target.itemId;
  final resolvedItemType = useSeriesTarget ? 'series' : target.itemType;
  final resolvedSearchQuery = seriesTitle.isNotEmpty
      ? seriesTitle
      : (target.title.trim().isNotEmpty ? target.title : target.subtitle);
  return MediaDetailTarget(
    title: resolvedTitle,
    posterUrl: '',
    overview: target.subtitle,
    year: target.year,
    availabilityLabel: target.canPlay
        ? '资源已就绪：${target.sourceKind.label} · ${target.sourceName}'
        : '',
    searchQuery: resolvedSearchQuery,
    playbackTarget: target,
    itemId: resolvedItemId,
    sourceId: target.sourceId,
    itemType: resolvedItemType,
    seasonNumber: useSeriesTarget ? null : target.seasonNumber,
    episodeNumber: useSeriesTarget ? null : target.episodeNumber,
    resourcePath: target.actualAddress,
    sourceKind: target.sourceKind,
    sourceName: target.sourceName,
  );
}

String _buildRecentPlaybackSubtitle(PlaybackProgressEntry entry) {
  final parts = <String>[];
  final target = entry.target;
  if (target.seasonNumber != null && target.episodeNumber != null) {
    parts.add(
      'S${target.seasonNumber!.toString().padLeft(2, '0')}'
      'E${target.episodeNumber!.toString().padLeft(2, '0')}',
    );
  } else if (target.year > 0) {
    parts.add('${target.year}');
  }

  if (entry.canResume) {
    final duration = entry.duration;
    if (duration > Duration.zero) {
      parts.add(
        '${_formatClockDuration(entry.position)} / ${_formatClockDuration(duration)}',
      );
    } else {
      parts.add('继续看到 ${_formatClockDuration(entry.position)}');
    }
  } else if (entry.completed) {
    parts.add('已看完');
  }

  return parts.join(' · ');
}

String _resolveRecentPlaybackDisplayTitle({
  required PlaybackProgressEntry entry,
  required MediaDetailTarget detailTarget,
}) {
  final seriesTitle = _resolveRecentPlaybackSeriesTitle(
    entry: entry,
    detailTarget: detailTarget,
  );
  final candidates = <String>[
    detailTarget.title,
    if (seriesTitle.isNotEmpty) seriesTitle,
    detailTarget.searchQuery,
    entry.target.title,
  ];
  for (final candidate in candidates) {
    final trimmed = candidate.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return '';
}

String _resolveRecentPlaybackSeriesTitle({
  required PlaybackProgressEntry entry,
  required MediaDetailTarget? detailTarget,
}) {
  final detailPlayback = detailTarget?.playbackTarget;
  final candidates = <String>[
    detailTarget?.title ?? '',
    detailPlayback?.resolvedSeriesTitle ?? '',
    entry.seriesTitle,
    entry.target.resolvedSeriesTitle,
    detailTarget?.searchQuery ?? '',
  ];
  for (final candidate in candidates) {
    final trimmed = candidate.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return '';
}

bool _homeHasResolvedLocalResourceState(MediaDetailTarget target) {
  if (target.playbackTarget?.canPlay == true) {
    return true;
  }
  if (target.sourceId.trim().isNotEmpty && target.itemId.trim().isNotEmpty) {
    return true;
  }
  final availability = target.availabilityLabel.trim();
  if (availability.isNotEmpty &&
      availability != '无' &&
      (target.sourceName.trim().isNotEmpty ||
          target.resourcePath.trim().isNotEmpty)) {
    return true;
  }
  return false;
}

bool _homeShouldPreferCachedAvailability(
  MediaDetailTarget seed,
  MediaDetailTarget cached,
) {
  final cachedAvailability = cached.availabilityLabel.trim();
  if (cachedAvailability.isEmpty || cachedAvailability == '无') {
    return false;
  }
  final seedAvailability = seed.availabilityLabel.trim();
  return seedAvailability.isEmpty || seedAvailability == '无';
}

bool _homeShouldPreferCachedSourceContext(
  MediaDetailTarget seed,
  MediaDetailTarget cached,
) {
  if (!_homeHasResolvedLocalResourceState(cached)) {
    return false;
  }
  final seedHasResolvedIdentity =
      seed.sourceId.trim().isNotEmpty && seed.itemId.trim().isNotEmpty;
  if (!seedHasResolvedIdentity) {
    return true;
  }
  if (seed.sourceKind == null && cached.sourceKind != null) {
    return true;
  }
  if (seed.sourceName.trim().isEmpty && cached.sourceName.trim().isNotEmpty) {
    return true;
  }
  return false;
}

Future<HomeSectionViewModel> _buildDoubanSectionSeed({
  required HomeModuleConfig module,
  required List<DoubanEntry> entries,
  required String emptyMessage,
}) async {
  final seedTargets = entries
      .map(
        (entry) => MediaDetailTarget(
          title: entry.title,
          posterUrl: entry.posterUrl.trim(),
          overview: entry.note,
          year: entry.year,
          durationLabel: entry.durationLabel,
          ratingLabels:
              entry.ratingLabel.trim().isEmpty ? const [] : [entry.ratingLabel],
          genres: entry.genres.isNotEmpty
              ? entry.genres
              : (entry.subjectType.trim().isEmpty
                  ? const []
                  : [entry.subjectType]),
          directors: entry.directors,
          actors: entry.actors,
          availabilityLabel: '无',
          searchQuery: entry.title,
          itemType: resolveDoubanItemType(entry.subjectType),
          doubanId: entry.id,
          sourceName: '豆瓣',
        ),
      )
      .toList(growable: false);
  final detailTargets = seedTargets;
  final items = <HomeCardViewModel>[];
  for (var index = 0; index < entries.length; index += 1) {
    final entry = entries[index];
    final detailTarget = detailTargets[index];
    final posterUrl = entry.posterUrl.trim();
    items.add(HomeCardViewModel(
      id: entry.id,
      title: detailTarget.title.trim().isNotEmpty
          ? detailTarget.title
          : entry.title,
      subtitle: entry.year > 0 ? '${entry.year}' : '',
      posterUrl: detailTarget.posterUrl.trim().isNotEmpty
          ? detailTarget.posterUrl
          : posterUrl,
      detailTarget: detailTarget,
    ));
  }

  return HomeSectionViewModel(
    id: module.id,
    title: module.title,
    subtitle: module.description,
    emptyMessage: emptyMessage,
    layout: HomeSectionLayout.posterRail,
    items: items,
    viewAllTarget: HomeSectionViewAllTarget.module(module),
  );
}

Future<HomeSectionViewModel> _buildCarouselSectionSeed({
  required HomeModuleConfig module,
  required List<DoubanCarouselEntry> items,
  required String emptyMessage,
}) async {
  final seedTargets = items
      .map(
        (item) => MediaDetailTarget(
          title: item.title,
          posterUrl: item.posterUrl.trim(),
          overview: item.overview,
          year: item.year,
          ratingLabels:
              item.ratingLabel.trim().isEmpty ? const [] : [item.ratingLabel],
          availabilityLabel: '无',
          searchQuery: item.title,
          itemType: resolveDoubanItemType(item.mediaType),
          doubanId: item.id,
          sourceName: '豆瓣',
        ),
      )
      .toList(growable: false);
  final detailTargets = seedTargets;
  final carouselItems = <HomeCarouselItemViewModel>[];
  for (var index = 0; index < items.length; index += 1) {
    final item = items[index];
    final posterUrl = item.posterUrl.trim();
    final detailTarget = detailTargets[index];
    final imageUrl = item.imageUrl.trim().isNotEmpty
        ? item.imageUrl
        : (detailTarget.posterUrl.trim().isNotEmpty
            ? detailTarget.posterUrl
            : posterUrl);
    carouselItems.add(HomeCarouselItemViewModel(
      id: item.id,
      title: detailTarget.title.trim().isNotEmpty
          ? detailTarget.title
          : item.title,
      subtitle: [
        if (item.ratingLabel.trim().isNotEmpty) item.ratingLabel,
        if (item.year > 0) '${item.year}',
      ].join(' · '),
      imageUrl: imageUrl,
      detailTarget: detailTarget,
    ));
  }

  return HomeSectionViewModel(
    id: module.id,
    title: module.title,
    subtitle: module.description,
    emptyMessage: emptyMessage,
    layout: HomeSectionLayout.carousel,
    carouselItems: carouselItems,
  );
}

String _resolveDoubanEmptyMessage(
  HomeModuleConfig module,
  DoubanAccountConfig account,
) {
  if (!account.enabled) {
    return '请先启用豆瓣模块';
  }
  if (module.type == HomeModuleType.doubanInterest &&
      account.userId.trim().isEmpty) {
    return '请先在设置里填写 Douban User ID';
  }
  if (module.type == HomeModuleType.doubanSuggestion &&
      account.sessionCookie.trim().isEmpty) {
    return '请先在设置里填写豆瓣 Cookie';
  }
  if (module.type == HomeModuleType.doubanList &&
      module.doubanListUrl.trim().isEmpty) {
    return '请先填写豆瓣片单地址';
  }
  return '无';
}

String _formatClockDuration(Duration value) {
  final totalSeconds = value.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

MediaSourceKind _resolveSourceKind(
  List<MediaSourceConfig> sources,
  String sourceId,
) {
  final source = sources.cast<MediaSourceConfig?>().firstWhere(
        (item) => item?.id == sourceId,
        orElse: () => null,
      );
  return source?.kind ?? MediaSourceKind.emby;
}
