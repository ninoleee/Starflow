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
        (item) => item.enabled && item.type != HomeModuleType.doubanCarousel,
      )
      .toList();
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
  final enabledModules = ref.watch(homeEnabledModulesProvider);
  if (!_needsRecentlyAdded(enabledModules)) {
    return const [];
  }

  return ref.read(mediaRepositoryProvider).fetchRecentlyAdded(limit: 6);
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
      return _buildDoubanSection(
        module: module,
        entries: entries,
        emptyMessage:
            _resolveDoubanEmptyMessage(module, settings.doubanAccount),
      );
    case HomeModuleType.doubanCarousel:
      final carouselItems = await ref.watch(homeCarouselItemsProvider.future);
      return _buildCarouselSection(
        module: module,
        items: carouselItems,
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
  read(homeRecentItemsProvider.future);
  read(homeCarouselItemsProvider.future);
  for (final module in modules) {
    read(homeSectionProvider(module.id).future);
  }
}

Future<void> refreshHomeModules(WidgetRef ref) async {
  ref.invalidate(homeRecentItemsProvider);
  ref.invalidate(homeCarouselItemsProvider);
  ref.invalidate(homeSectionProvider);
  ref.invalidate(homeSectionsProvider);
  primeHomeModulesFromWidget(ref);
  await Future<void>.delayed(const Duration(milliseconds: 140));
}

bool _needsRecentlyAdded(List<HomeModuleConfig> modules) {
  return modules.any((item) => item.type == HomeModuleType.recentlyAdded);
}

bool _needsCarousel(List<HomeModuleConfig> modules) {
  return modules.any((item) => item.type == HomeModuleType.doubanCarousel);
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
    viewAllTarget: viewAllTarget == null
        ? null
        : HomeSectionViewAllTarget.collection(viewAllTarget),
  );
}

HomeSectionViewModel _buildDoubanSection({
  required HomeModuleConfig module,
  required List<DoubanEntry> entries,
  required String emptyMessage,
}) {
  final items = entries.map((entry) {
    final posterUrl = entry.posterUrl.trim();
    return HomeCardViewModel(
      id: entry.id,
      title: entry.title,
      subtitle: entry.year > 0 ? '${entry.year}' : '',
      posterUrl: posterUrl,
      detailTarget: MediaDetailTarget(
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
    );
  }).toList();

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

HomeSectionViewModel _buildCarouselSection({
  required HomeModuleConfig module,
  required List<DoubanCarouselEntry> items,
  required String emptyMessage,
}) {
  final carouselItems = items.map((item) {
    final posterUrl = item.posterUrl.trim();
    final imageUrl =
        item.imageUrl.trim().isNotEmpty ? item.imageUrl : posterUrl;
    return HomeCarouselItemViewModel(
      id: item.id,
      title: item.title,
      subtitle: [
        if (item.ratingLabel.trim().isNotEmpty) item.ratingLabel,
        if (item.year > 0) '${item.year}',
      ].join(' · '),
      imageUrl: imageUrl,
      detailTarget: MediaDetailTarget(
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
