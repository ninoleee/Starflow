import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/discovery/data/mock_discovery_repository.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/library_collection_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/domain/media_title_matcher.dart';
import 'package:starflow/features/metadata/data/metadata_match_resolver.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';
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
  final LibraryCollectionTarget? viewAllTarget;
}

final homeEnabledModulesProvider = Provider<List<HomeModuleConfig>>((ref) {
  final settings = ref.watch(appSettingsProvider);
  return settings.homeModules.where((item) => item.enabled).toList();
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

final homeLibrarySnapshotProvider =
    FutureProvider<List<MediaItem>>((ref) async {
  final settings = ref.watch(appSettingsProvider);
  final enabledModules = ref.watch(homeEnabledModulesProvider);
  final shouldWarmPosterLibrarySnapshot =
      _needsDoubanPosterCandidates(enabledModules) &&
          !_hasRemoteMetadataPosterFallback(settings);
  if (!shouldWarmPosterLibrarySnapshot) {
    return const [];
  }

  return ref.read(mediaRepositoryProvider).fetchLibrary(limit: 2000);
});

final homeRecentItemsProvider = FutureProvider<List<MediaItem>>((ref) async {
  final enabledModules = ref.watch(homeEnabledModulesProvider);
  if (!_needsRecentlyAdded(enabledModules)) {
    return const [];
  }

  final sharedSnapshot = await ref.watch(homeLibrarySnapshotProvider.future);
  if (sharedSnapshot.isNotEmpty) {
    return sharedSnapshot.take(6).toList();
  }

  return ref.read(mediaRepositoryProvider).fetchRecentlyAdded(limit: 6);
});

final homePosterCandidatesProvider =
    FutureProvider<List<MediaItem>>((ref) async {
  final enabledModules = ref.watch(homeEnabledModulesProvider);
  if (!_needsDoubanPosterCandidates(enabledModules)) {
    return const [];
  }

  final sharedSnapshot = await ref.watch(homeLibrarySnapshotProvider.future);
  final source = sharedSnapshot.isNotEmpty
      ? sharedSnapshot
      : await ref.watch(homeRecentItemsProvider.future);
  return source.where((item) => item.posterUrl.trim().isNotEmpty).toList();
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
  final module = ref.watch(homeModuleByIdProvider(moduleId));
  if (module == null) {
    return null;
  }

  final settings = ref.watch(appSettingsProvider);
  final mediaRepository = ref.read(mediaRepositoryProvider);
  final discoveryRepository = ref.read(discoveryRepositoryProvider);
  final metadataMatchResolver = ref.read(metadataMatchResolverProvider);

  switch (module.type) {
    case HomeModuleType.recentlyAdded:
      final recentItems = await ref.watch(homeRecentItemsProvider.future);
      return _buildLibrarySection(
        module: module,
        items: recentItems,
        subtitle: module.description,
      );
    case HomeModuleType.librarySection:
      final sectionItems = module.isLibrarySection
          ? await mediaRepository.fetchLibrary(
              sourceId: module.sourceId,
              sectionId: module.sectionId,
              limit: 6,
            )
          : const <MediaItem>[];
      return _buildLibrarySection(
        module: module,
        items: sectionItems,
        subtitle: module.description,
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
      final posterCandidates =
          await ref.watch(homePosterCandidatesProvider.future);
      return _buildDoubanSection(
        module: module,
        settings: settings,
        metadataMatchResolver: metadataMatchResolver,
        entries: entries,
        posterCandidates: posterCandidates,
        emptyMessage:
            _resolveDoubanEmptyMessage(module, settings.doubanAccount),
      );
    case HomeModuleType.doubanCarousel:
      final carouselItems = await ref.watch(homeCarouselItemsProvider.future);
      final posterCandidates =
          await ref.watch(homePosterCandidatesProvider.future);
      return _buildCarouselSection(
        module: module,
        settings: settings,
        metadataMatchResolver: metadataMatchResolver,
        items: carouselItems,
        posterCandidates: posterCandidates,
        emptyMessage:
            _resolveDoubanEmptyMessage(module, settings.doubanAccount),
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

void primeHomeModulesFromWidget(WidgetRef ref) {
  _primeHomeModulesWithReader(ref.read);
}

void _primeHomeModulesWithReader(
  T Function<T>(ProviderListenable<T> provider) read,
) {
  final modules = read(homeEnabledModulesProvider);
  unawaited(read(homeLibrarySnapshotProvider.future));
  unawaited(read(homeRecentItemsProvider.future));
  unawaited(read(homePosterCandidatesProvider.future));
  unawaited(read(homeCarouselItemsProvider.future));
  for (final module in modules) {
    unawaited(read(homeSectionProvider(module.id).future));
  }
}

Future<void> refreshHomeModules(WidgetRef ref) async {
  ref.invalidate(homeLibrarySnapshotProvider);
  ref.invalidate(homeRecentItemsProvider);
  ref.invalidate(homePosterCandidatesProvider);
  ref.invalidate(homeCarouselItemsProvider);
  ref.invalidate(homeSectionProvider);
  ref.invalidate(homeSectionsProvider);
  primeHomeModulesFromWidget(ref);
  await Future<void>.delayed(const Duration(milliseconds: 140));
}

bool _hasRemoteMetadataPosterFallback(AppSettings settings) {
  return settings.wmdbMetadataMatchEnabled ||
      (settings.tmdbMetadataMatchEnabled &&
          settings.tmdbReadAccessToken.trim().isNotEmpty);
}

bool _needsRecentlyAdded(List<HomeModuleConfig> modules) {
  return modules.any((item) => item.type == HomeModuleType.recentlyAdded);
}

bool _needsCarousel(List<HomeModuleConfig> modules) {
  return modules.any((item) => item.type == HomeModuleType.doubanCarousel);
}

bool _needsDoubanPosterCandidates(List<HomeModuleConfig> modules) {
  return modules.any(
    (item) =>
        item.type == HomeModuleType.doubanInterest ||
        item.type == HomeModuleType.doubanSuggestion ||
        item.type == HomeModuleType.doubanList ||
        item.type == HomeModuleType.doubanCarousel,
  );
}

HomeSectionViewModel _buildLibrarySection({
  required HomeModuleConfig module,
  required List<MediaItem> items,
  required String subtitle,
  LibraryCollectionTarget? viewAllTarget,
}) {
  final viewModels = items.map((item) {
    return HomeCardViewModel(
      id: item.id,
      title: item.title,
      subtitle: item.year > 0 ? '${item.year}' : '',
      posterUrl: item.posterUrl,
      detailTarget: MediaDetailTarget.fromMediaItem(item),
    );
  }).toList();

  return HomeSectionViewModel(
    id: module.id,
    title: module.title,
    subtitle: subtitle,
    emptyMessage: '无',
    layout: HomeSectionLayout.posterRail,
    items: viewModels,
    viewAllTarget: viewAllTarget,
  );
}

Future<HomeSectionViewModel> _buildDoubanSection({
  required HomeModuleConfig module,
  required AppSettings settings,
  required MetadataMatchResolver metadataMatchResolver,
  required List<DoubanEntry> entries,
  required List<MediaItem> posterCandidates,
  required String emptyMessage,
}) async {
  final items = await Future.wait(entries.map((entry) async {
    final resolvedPosterUrl = await _resolveDoubanPosterUrl(
      primaryPosterUrl: entry.posterUrl,
      title: entry.title,
      doubanId: entry.id,
      year: entry.year,
      preferSeries: _preferSeriesForEntry(
        subjectType: entry.subjectType,
      ),
      actors: entry.actors,
      posterCandidates: posterCandidates,
      settings: settings,
      metadataMatchResolver: metadataMatchResolver,
    );
    return HomeCardViewModel(
      id: entry.id,
      title: entry.title,
      subtitle: entry.year > 0 ? '${entry.year}' : '',
      posterUrl: resolvedPosterUrl,
      detailTarget: MediaDetailTarget(
        title: entry.title,
        posterUrl: resolvedPosterUrl,
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
        doubanId: entry.id,
        sourceName: '豆瓣',
      ),
    );
  }));

  return HomeSectionViewModel(
    id: module.id,
    title: module.title,
    subtitle: module.description,
    emptyMessage: emptyMessage,
    layout: HomeSectionLayout.posterRail,
    items: items,
  );
}

Future<HomeSectionViewModel> _buildCarouselSection({
  required HomeModuleConfig module,
  required AppSettings settings,
  required MetadataMatchResolver metadataMatchResolver,
  required List<DoubanCarouselEntry> items,
  required List<MediaItem> posterCandidates,
  required String emptyMessage,
}) async {
  final carouselItems = await Future.wait(items.map((item) async {
    final resolvedPosterUrl = await _resolveDoubanPosterUrl(
      primaryPosterUrl: item.posterUrl,
      title: item.title,
      doubanId: item.id,
      year: item.year,
      preferSeries: _preferSeriesForEntry(subjectType: item.mediaType),
      actors: const [],
      posterCandidates: posterCandidates,
      settings: settings,
      metadataMatchResolver: metadataMatchResolver,
    );
    final resolvedImageUrl = _firstNonEmpty(
      item.imageUrl,
      resolvedPosterUrl,
    );
    return HomeCarouselItemViewModel(
      id: item.id,
      title: item.title,
      subtitle: [
        if (item.ratingLabel.trim().isNotEmpty) item.ratingLabel,
        if (item.year > 0) '${item.year}',
      ].join(' · '),
      imageUrl: resolvedImageUrl,
      detailTarget: MediaDetailTarget(
        title: item.title,
        posterUrl: resolvedPosterUrl,
        overview: item.overview,
        year: item.year,
        ratingLabels:
            item.ratingLabel.trim().isEmpty ? const [] : [item.ratingLabel],
        availabilityLabel: '无',
        searchQuery: item.title,
        doubanId: item.id,
        sourceName: '豆瓣',
      ),
    );
  }));

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

MediaSourceKind _resolveSourceKind(AppSettings settings, String sourceId) {
  final source = settings.mediaSources.cast<MediaSourceConfig?>().firstWhere(
        (item) => item?.id == sourceId,
        orElse: () => null,
      );
  return source?.kind ?? MediaSourceKind.emby;
}

Future<String> _resolveDoubanPosterUrl({
  required String primaryPosterUrl,
  required String title,
  required String doubanId,
  required int year,
  required bool preferSeries,
  required List<String> actors,
  required List<MediaItem> posterCandidates,
  required AppSettings settings,
  required MetadataMatchResolver metadataMatchResolver,
}) async {
  final preferredPosterUrl = primaryPosterUrl.trim();
  if (preferredPosterUrl.isNotEmpty) {
    return preferredPosterUrl;
  }

  final matchedPoster = matchMediaItemByTitles(
    posterCandidates,
    titles: [title],
    year: year,
  )?.posterUrl.trim();
  if ((matchedPoster ?? '').isNotEmpty) {
    return matchedPoster!;
  }

  if (!_hasRemoteMetadataPosterFallback(settings)) {
    return '';
  }

  try {
    final match = await metadataMatchResolver.match(
      settings: settings,
      request: MetadataMatchRequest(
        query: title,
        doubanId: doubanId,
        year: year,
        preferSeries: preferSeries,
        actors: actors,
      ),
    );
    return match?.posterUrl.trim() ?? '';
  } catch (_) {
    return '';
  }
}

bool _preferSeriesForEntry({required String subjectType}) {
  final normalized = subjectType.trim().toLowerCase();
  return normalized.contains('tv') ||
      normalized.contains('series') ||
      normalized.contains('剧') ||
      normalized.contains('电视');
}

String _firstNonEmpty(String primary, String fallback) {
  final primaryTrimmed = primary.trim();
  if (primaryTrimmed.isNotEmpty) {
    return primaryTrimmed;
  }
  return fallback.trim();
}
