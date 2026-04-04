import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/discovery/data/mock_discovery_repository.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/library_collection_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
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
  final enabledModules =
      settings.homeModules.where((item) => item.enabled).toList();
  final needsLibraryMatching = enabledModules.any(
    (item) =>
        item.type == HomeModuleType.doubanInterest ||
        item.type == HomeModuleType.doubanSuggestion ||
        item.type == HomeModuleType.doubanList ||
        item.type == HomeModuleType.doubanCarousel,
  );
  final needsRecentlyAdded = enabledModules.any(
    (item) => item.type == HomeModuleType.recentlyAdded,
  );
  final needsCarousel = enabledModules.any(
    (item) => item.type == HomeModuleType.doubanCarousel,
  );

  final warmups = await Future.wait([
    needsLibraryMatching
        ? mediaRepository.fetchLibrary()
        : Future.value(const <MediaItem>[]),
    needsRecentlyAdded
        ? mediaRepository.fetchRecentlyAdded(limit: 6)
        : Future.value(const <MediaItem>[]),
    needsCarousel
        ? discoveryRepository.fetchCarouselItems()
        : Future.value(const <DoubanCarouselEntry>[]),
  ]);

  final library = warmups[0] as List<MediaItem>;
  final recentItems = warmups[1] as List<MediaItem>;
  final carouselItems = warmups[2] as List<DoubanCarouselEntry>;

  final sections = await Future.wait(
    enabledModules.map(
      (module) => _buildSectionForModule(
        module: module,
        settings: settings,
        mediaRepository: mediaRepository,
        discoveryRepository: discoveryRepository,
        library: library,
        recentItems: recentItems,
        carouselItems: carouselItems,
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
  required List<MediaItem> library,
  required List<MediaItem> recentItems,
  required List<DoubanCarouselEntry> carouselItems,
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
        entries: entries,
        library: library,
        emptyMessage:
            _resolveDoubanEmptyMessage(module, settings.doubanAccount),
      );
    case HomeModuleType.doubanCarousel:
      return _buildCarouselSection(
        module: module,
        items: carouselItems,
        library: library,
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

HomeSectionViewModel _buildDoubanSection({
  required HomeModuleConfig module,
  required List<DoubanEntry> entries,
  required List<MediaItem> library,
  required String emptyMessage,
}) {
  final items = entries.map((entry) {
    final matched = _matchByTitle(library, entry.title);
    return HomeCardViewModel(
      id: entry.id,
      title: entry.title,
      subtitle: entry.year > 0 ? '${entry.year}' : '',
      posterUrl: entry.posterUrl,
      detailTarget: matched == null
          ? MediaDetailTarget(
              title: entry.title,
              posterUrl: entry.posterUrl,
              overview: entry.note,
              year: entry.year,
              availabilityLabel: '无',
              searchQuery: entry.title,
            )
          : MediaDetailTarget.fromMediaItem(
              matched,
              availabilityLabel:
                  '豆瓣条目已关联到 ${matched.sourceKind.label} · ${matched.sourceName}',
              searchQuery: entry.title,
            ),
    );
  }).toList();

  return HomeSectionViewModel(
    id: module.id,
    title: module.title,
    subtitle: module.description,
    emptyMessage: emptyMessage,
    layout: HomeSectionLayout.posterRail,
    items: items,
  );
}

HomeSectionViewModel _buildCarouselSection({
  required HomeModuleConfig module,
  required List<DoubanCarouselEntry> items,
  required List<MediaItem> library,
  required String emptyMessage,
}) {
  final carouselItems = items.map((item) {
    final matched = _matchByTitle(library, item.title);
    return HomeCarouselItemViewModel(
      id: item.id,
      title: item.title,
      subtitle: [
        if (item.ratingLabel.trim().isNotEmpty) item.ratingLabel,
        if (item.year > 0) '${item.year}',
        if (matched != null) '${matched.sourceKind.label} 已就绪',
      ].join(' · '),
      imageUrl: item.imageUrl,
      detailTarget: matched == null
          ? MediaDetailTarget(
              title: item.title,
              posterUrl:
                  item.posterUrl.isEmpty ? item.imageUrl : item.posterUrl,
              overview: item.overview,
              year: item.year,
              availabilityLabel: '无',
              searchQuery: item.title,
            )
          : MediaDetailTarget.fromMediaItem(
              matched,
              availabilityLabel:
                  '豆瓣轮播条目已关联到 ${matched.sourceKind.label} · ${matched.sourceName}',
              searchQuery: item.title,
            ),
    );
  }).toList();

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

MediaItem? _matchByTitle(List<MediaItem> library, String title) {
  final normalized = _normalize(title);
  for (final item in library) {
    final candidate = _normalize(item.title);
    if (candidate == normalized ||
        candidate.contains(normalized) ||
        normalized.contains(candidate)) {
      return item;
    }
  }
  return null;
}

String _normalize(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
}
