import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/discovery/data/mock_discovery_repository.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/library_collection_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/domain/media_title_matcher.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';
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

final homeSectionsProvider = FutureProvider<List<HomeSectionViewModel>>((
  ref,
) async {
  final settings = ref.watch(appSettingsProvider);
  final mediaRepository = ref.read(mediaRepositoryProvider);
  final discoveryRepository = ref.read(discoveryRepositoryProvider);
  final tmdbMetadataClient = ref.read(tmdbMetadataClientProvider);
  final enabledModules =
      settings.homeModules.where((item) => item.enabled).toList();
  final needsRecentlyAdded = enabledModules.any(
    (item) => item.type == HomeModuleType.recentlyAdded,
  );
  final needsCarousel = enabledModules.any(
    (item) => item.type == HomeModuleType.doubanCarousel,
  );
  final needsDoubanPosterCandidates = enabledModules.any(
    (item) =>
        item.type == HomeModuleType.doubanInterest ||
        item.type == HomeModuleType.doubanSuggestion ||
        item.type == HomeModuleType.doubanList ||
        item.type == HomeModuleType.doubanCarousel,
  );

  final warmups = await Future.wait([
    needsRecentlyAdded
        ? mediaRepository.fetchRecentlyAdded(limit: 6)
        : Future.value(const <MediaItem>[]),
    needsCarousel
        ? discoveryRepository.fetchCarouselItems()
        : Future.value(const <DoubanCarouselEntry>[]),
    needsDoubanPosterCandidates
        ? mediaRepository.fetchLibrary(limit: 2000)
        : Future.value(const <MediaItem>[]),
  ]);

  final recentItems = warmups[0] as List<MediaItem>;
  final carouselItems = warmups[1] as List<DoubanCarouselEntry>;
  final posterCandidates = (warmups[2] as List<MediaItem>)
      .where((item) => item.posterUrl.trim().isNotEmpty)
      .toList();

  final sections = await Future.wait(
    enabledModules.map(
      (module) => _buildSectionForModule(
        module: module,
        settings: settings,
        mediaRepository: mediaRepository,
        discoveryRepository: discoveryRepository,
        tmdbMetadataClient: tmdbMetadataClient,
        recentItems: recentItems,
        carouselItems: carouselItems,
        posterCandidates: posterCandidates,
      ),
    ),
  );

  return sections.whereType<HomeSectionViewModel>().toList();
});

Future<HomeSectionViewModel?> _buildSectionForModule({
  required HomeModuleConfig module,
  required AppSettings settings,
  required MediaRepository mediaRepository,
  required DiscoveryRepository discoveryRepository,
  required TmdbMetadataClient tmdbMetadataClient,
  required List<MediaItem> recentItems,
  required List<DoubanCarouselEntry> carouselItems,
  required List<MediaItem> posterCandidates,
}) async {
  switch (module.type) {
    case HomeModuleType.recentlyAdded:
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
      return _buildDoubanSection(
        module: module,
        settings: settings,
        tmdbMetadataClient: tmdbMetadataClient,
        entries: entries,
        posterCandidates: posterCandidates,
        emptyMessage:
            _resolveDoubanEmptyMessage(module, settings.doubanAccount),
      );
    case HomeModuleType.doubanCarousel:
      return _buildCarouselSection(
        module: module,
        settings: settings,
        tmdbMetadataClient: tmdbMetadataClient,
        items: carouselItems,
        posterCandidates: posterCandidates,
        emptyMessage:
            _resolveDoubanEmptyMessage(module, settings.doubanAccount),
      );
  }
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
  required TmdbMetadataClient tmdbMetadataClient,
  required List<DoubanEntry> entries,
  required List<MediaItem> posterCandidates,
  required String emptyMessage,
}) async {
  final items = await Future.wait(entries.map((entry) async {
    final resolvedPosterUrl = await _resolveDoubanPosterUrl(
      primaryPosterUrl: entry.posterUrl,
      title: entry.title,
      year: entry.year,
      preferSeries: _preferSeriesForEntry(
        subjectType: entry.subjectType,
      ),
      posterCandidates: posterCandidates,
      settings: settings,
      tmdbMetadataClient: tmdbMetadataClient,
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
  required TmdbMetadataClient tmdbMetadataClient,
  required List<DoubanCarouselEntry> items,
  required List<MediaItem> posterCandidates,
  required String emptyMessage,
}) async {
  final carouselItems = await Future.wait(items.map((item) async {
    final resolvedPosterUrl = await _resolveDoubanPosterUrl(
      primaryPosterUrl: item.posterUrl,
      title: item.title,
      year: item.year,
      preferSeries: _preferSeriesForEntry(subjectType: item.mediaType),
      posterCandidates: posterCandidates,
      settings: settings,
      tmdbMetadataClient: tmdbMetadataClient,
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
  required int year,
  required bool preferSeries,
  required List<MediaItem> posterCandidates,
  required AppSettings settings,
  required TmdbMetadataClient tmdbMetadataClient,
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

  if (!settings.tmdbMetadataMatchEnabled ||
      settings.tmdbReadAccessToken.trim().isEmpty) {
    return '';
  }

  try {
    final match = await tmdbMetadataClient.matchTitle(
      query: title,
      readAccessToken: settings.tmdbReadAccessToken,
      year: year,
      preferSeries: preferSeries,
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
