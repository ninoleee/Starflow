import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/discovery/data/mock_discovery_repository.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/application/nas_media_index_revision.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/library_collection_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_session.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
import 'package:starflow/features/playback/domain/playback_memory_models.dart';
import 'package:starflow/features/storage/application/local_storage_cache_revision.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

enum HomeSectionLayout {
  posterRail,
  carousel,
}

class HomeCardViewModel {
  const HomeCardViewModel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.posterUrl,
    required this.detailTarget,
  });

  final String id;
  final String title;
  final String subtitle;
  final String posterUrl;
  final MediaDetailTarget detailTarget;
}

class HomeCarouselItemViewModel {
  const HomeCarouselItemViewModel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.detailTarget,
  });

  final String id;
  final String title;
  final String subtitle;
  final String imageUrl;
  final MediaDetailTarget detailTarget;
}

class HomeSectionViewAllTarget {
  const HomeSectionViewAllTarget.collection(this.extra)
      : routeName = 'collection';

  const HomeSectionViewAllTarget.module(this.extra)
      : routeName = 'home-module-list';

  final String routeName;
  final Object extra;
}

class HomeSectionViewModel {
  const HomeSectionViewModel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.emptyMessage,
    required this.layout,
    this.items = const [],
    this.carouselItems = const [],
    this.viewAllTarget,
  });

  final String id;
  final String title;
  final String subtitle;
  final String emptyMessage;
  final HomeSectionLayout layout;
  final List<HomeCardViewModel> items;
  final List<HomeCarouselItemViewModel> carouselItems;
  final HomeSectionViewAllTarget? viewAllTarget;
}

final homeEnabledModulesProvider = Provider<List<HomeModuleConfig>>((ref) {
  final settings = ref.watch(appSettingsProvider);
  return settings.homeModules
      .where(
        (item) =>
            item.enabled &&
            item.type != HomeModuleType.doubanCarousel &&
            item.type != HomeModuleType.hero,
      )
      .toList();
});

final homeHeroModuleProvider = Provider<HomeModuleConfig?>((ref) {
  final settings = ref.watch(appSettingsProvider);
  for (final module in settings.homeModules) {
    if (module.type == HomeModuleType.hero ||
        module.id == HomeModuleConfig.heroModuleId) {
      return module;
    }
  }
  return null;
});

final homeHeroModuleCandidatesProvider =
    Provider<List<HomeModuleConfig>>((ref) {
  return ref.watch(homeEnabledModulesProvider);
});

final homeModuleByIdProvider =
    Provider.family<HomeModuleConfig?, String>((ref, moduleId) {
  final normalizedModuleId = moduleId.trim();
  if (normalizedModuleId.isEmpty) {
    return null;
  }

  for (final module in ref.watch(homeEnabledModulesProvider)) {
    if (module.id == normalizedModuleId) {
      return module;
    }
  }
  return null;
});

final homeRecentItemsProvider = FutureProvider<List<MediaItem>>((ref) async {
  ref.watch(nasMediaIndexRevisionProvider);
  final enabledModules = ref.watch(homeEnabledModulesProvider);
  if (!_needsRecentlyAdded(enabledModules)) {
    return const [];
  }

  return ref.read(mediaRepositoryProvider).fetchRecentlyAdded(limit: 6);
});

final homeRecentPlaybackEntriesProvider =
    FutureProvider<List<PlaybackProgressEntry>>((ref) async {
  ref.watch(playbackHistoryRevisionProvider);
  final enabledModules = ref.watch(homeEnabledModulesProvider);
  if (!_needsRecentPlayback(enabledModules)) {
    return const [];
  }

  return ref
      .read(playbackMemoryRepositoryProvider)
      .loadRecentDisplayEntries(limit: 6);
});

final homeCarouselItemsProvider =
    FutureProvider<List<DoubanCarouselEntry>>((ref) async {
  final enabledModules = ref.watch(homeEnabledModulesProvider);
  if (!_needsCarousel(enabledModules)) {
    return const [];
  }

  return ref.read(discoveryRepositoryProvider).fetchCarouselItems();
});

final homeSectionProvider =
    FutureProvider.family<HomeSectionViewModel?, String>((ref, moduleId) async {
  ref.watch(nasMediaIndexRevisionProvider);
  ref.watch(localStorageDetailCacheRevisionProvider);
  final module = ref.watch(homeModuleByIdProvider(moduleId));
  if (module == null) {
    return null;
  }

  final settings = ref.watch(appSettingsProvider);
  final mediaRepository = ref.read(mediaRepositoryProvider);
  final discoveryRepository = ref.read(discoveryRepositoryProvider);
  final localStorageCacheRepository =
      ref.read(localStorageCacheRepositoryProvider);

  switch (module.type) {
    case HomeModuleType.hero:
      return null;
    case HomeModuleType.recentlyAdded:
      final recentItems = await ref.watch(homeRecentItemsProvider.future);
      return _buildLibrarySection(
        module: module,
        items: recentItems,
        subtitle: module.description,
        localStorageCacheRepository: localStorageCacheRepository,
      );
    case HomeModuleType.recentPlayback:
      final recentEntries =
          await ref.watch(homeRecentPlaybackEntriesProvider.future);
      return _buildRecentPlaybackSection(
        module: module,
        entries: recentEntries,
        localStorageCacheRepository: localStorageCacheRepository,
      );
    case HomeModuleType.librarySection:
      final sourceKind = _resolveSourceKind(settings, module.sourceId);
      final sectionItems = module.isLibrarySection
          ? await mediaRepository.fetchLibrary(
              sourceId: module.sourceId,
              sectionId: module.sectionId,
              limit: _homeModuleFetchLimit(module, sourceKind: sourceKind),
            )
          : const <MediaItem>[];
      return _buildLibrarySection(
        module: module,
        items: sectionItems,
        subtitle: module.description,
        localStorageCacheRepository: localStorageCacheRepository,
        viewAllTarget: module.isLibrarySection
            ? LibraryCollectionTarget(
                title: module.title,
                sourceId: module.sourceId,
                sourceName: module.sourceName,
                sourceKind: _resolveSourceKind(settings, module.sourceId),
                sectionId: module.sectionId,
                subtitle: module.sectionName,
              )
            : null,
      );
    case HomeModuleType.doubanInterest:
    case HomeModuleType.doubanSuggestion:
    case HomeModuleType.doubanList:
      final entries = await discoveryRepository.fetchEntries(module);
      return _buildDoubanSection(
        module: module,
        entries: entries,
        emptyMessage:
            _resolveDoubanEmptyMessage(module, settings.doubanAccount),
        localStorageCacheRepository: localStorageCacheRepository,
      );
    case HomeModuleType.doubanCarousel:
      final carouselItems = await ref.watch(homeCarouselItemsProvider.future);
      return _buildCarouselSection(
        module: module,
        items: carouselItems,
        emptyMessage:
            _resolveDoubanEmptyMessage(module, settings.doubanAccount),
        localStorageCacheRepository: localStorageCacheRepository,
      );
  }
});

final homeSectionsProvider = FutureProvider<List<HomeSectionViewModel>>((
  ref,
) async {
  final enabledModules = ref.watch(homeEnabledModulesProvider);
  final sections = await Future.wait(
    enabledModules.map(
      (module) => ref.watch(homeSectionProvider(module.id).future),
    ),
  );

  return sections.whereType<HomeSectionViewModel>().toList();
});

void primeHomeModules(Ref ref) {
  _primeHomeModulesWithReader(ref.read);
}

int _homeModuleFetchLimit(
  HomeModuleConfig module, {
  required MediaSourceKind sourceKind,
}) {
  if (module.type == HomeModuleType.librarySection &&
      sourceKind == MediaSourceKind.emby) {
    return 20;
  }
  return 6;
}

void primeHomeModulesFromWidget(WidgetRef ref) {
  _primeHomeModulesWithReader(ref.read);
}

void _primeHomeModulesWithReader(
  T Function<T>(ProviderListenable<T> provider) read,
) {
  if (read(playbackPerformanceModeProvider)) {
    return;
  }
  final modules = read(homeEnabledModulesProvider);
  read(homeRecentItemsProvider.future);
  read(homeRecentPlaybackEntriesProvider.future);
  read(homeCarouselItemsProvider.future);
  for (final module in modules) {
    read(homeSectionProvider(module.id).future);
  }
}

Future<void> refreshHomeModules(WidgetRef ref) async {
  if (ref.read(playbackPerformanceModeProvider)) {
    return;
  }
  ref.invalidate(homeRecentItemsProvider);
  ref.invalidate(homeRecentPlaybackEntriesProvider);
  ref.invalidate(homeCarouselItemsProvider);
  ref.invalidate(homeSectionProvider);
  ref.invalidate(homeSectionsProvider);
  primeHomeModulesFromWidget(ref);
  await Future<void>.delayed(const Duration(milliseconds: 140));
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

Future<HomeSectionViewModel> _buildLibrarySection({
  required HomeModuleConfig module,
  required List<MediaItem> items,
  required String subtitle,
  required LocalStorageCacheRepository localStorageCacheRepository,
  LibraryCollectionTarget? viewAllTarget,
}) async {
  final viewModels = <HomeCardViewModel>[];
  for (final item in items) {
    final detailTarget = await _resolveCachedHomeDetailTarget(
      seedTarget: MediaDetailTarget.fromMediaItem(item),
      localStorageCacheRepository: localStorageCacheRepository,
    );
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

Future<MediaDetailTarget> _resolveCachedHomeDetailTarget({
  required MediaDetailTarget seedTarget,
  required LocalStorageCacheRepository localStorageCacheRepository,
}) async {
  final cachedTarget =
      await localStorageCacheRepository.loadDetailTarget(seedTarget);
  if (cachedTarget == null) {
    return seedTarget;
  }
  return _mergeCachedHomeDetailTarget(seedTarget, cachedTarget);
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
        seed.ratingLabels.isNotEmpty ? seed.ratingLabels : cached.ratingLabels,
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

Future<HomeSectionViewModel> _buildRecentPlaybackSection({
  required HomeModuleConfig module,
  required List<PlaybackProgressEntry> entries,
  required LocalStorageCacheRepository localStorageCacheRepository,
}) async {
  final items = <HomeCardViewModel>[];
  for (final entry in entries) {
    final detailTarget = await _resolveCachedHomeDetailTarget(
      seedTarget: _buildRecentPlaybackDetailTarget(entry),
      localStorageCacheRepository: localStorageCacheRepository,
    );
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

Future<HomeSectionViewModel> _buildDoubanSection({
  required HomeModuleConfig module,
  required List<DoubanEntry> entries,
  required String emptyMessage,
  required LocalStorageCacheRepository localStorageCacheRepository,
}) async {
  final items = <HomeCardViewModel>[];
  for (final entry in entries) {
    final posterUrl = entry.posterUrl.trim();
    final detailTarget = await _resolveCachedHomeDetailTarget(
      seedTarget: MediaDetailTarget(
        title: entry.title,
        posterUrl: posterUrl,
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
      localStorageCacheRepository: localStorageCacheRepository,
    );
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

Future<HomeSectionViewModel> _buildCarouselSection({
  required HomeModuleConfig module,
  required List<DoubanCarouselEntry> items,
  required String emptyMessage,
  required LocalStorageCacheRepository localStorageCacheRepository,
}) async {
  final carouselItems = <HomeCarouselItemViewModel>[];
  for (final item in items) {
    final posterUrl = item.posterUrl.trim();
    final detailTarget = await _resolveCachedHomeDetailTarget(
      seedTarget: MediaDetailTarget(
        title: item.title,
        posterUrl: posterUrl,
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
      localStorageCacheRepository: localStorageCacheRepository,
    );
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

MediaSourceKind _resolveSourceKind(AppSettings settings, String sourceId) {
  final source = settings.mediaSources.cast<MediaSourceConfig?>().firstWhere(
        (item) => item?.id == sourceId,
        orElse: () => null,
      );
  return source?.kind ?? MediaSourceKind.emby;
}
