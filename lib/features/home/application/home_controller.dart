import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/discovery/data/mock_discovery_repository.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/library_collection_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

class HomeCardViewModel {
  const HomeCardViewModel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.posterUrl,
    required this.badges,
    required this.caption,
    required this.actionLabel,
    required this.detailTarget,
  });

  final String id;
  final String title;
  final String subtitle;
  final String posterUrl;
  final List<String> badges;
  final String caption;
  final String actionLabel;
  final MediaDetailTarget detailTarget;
}

class HomeSectionViewModel {
  const HomeSectionViewModel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.emptyMessage,
    required this.items,
    this.viewAllTarget,
  });

  final String id;
  final String title;
  final String subtitle;
  final String emptyMessage;
  final List<HomeCardViewModel> items;
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
  final needsRecommendations = enabledModules.any(
    (item) => item.type == HomeModuleType.doubanRecommendations,
  );
  final needsWishList = enabledModules.any(
    (item) => item.type == HomeModuleType.doubanWishList,
  );
  final needsEmbyModules = enabledModules.any(
    (item) => item.type == HomeModuleType.embyLibrary,
  );

  final futures = await Future.wait([
    mediaRepository.fetchLibrary(),
    needsRecommendations
        ? discoveryRepository.fetchRecommendations()
        : Future.value(const <DoubanEntry>[]),
    needsWishList
        ? discoveryRepository.fetchWishList()
        : Future.value(const <DoubanEntry>[]),
    needsEmbyModules
        ? mediaRepository.fetchCollections(kind: MediaSourceKind.emby)
        : Future.value(const <MediaCollection>[]),
  ]);

  final library = futures[0] as List<MediaItem>;
  final recommendations = futures[1] as List<DoubanEntry>;
  final wishList = futures[2] as List<DoubanEntry>;
  final embyCollections = futures[3] as List<MediaCollection>;
  final embyItems = library
      .where((item) => item.sourceKind == MediaSourceKind.emby)
      .take(6)
      .toList();
  final nasItems = library
      .where((item) => item.sourceKind == MediaSourceKind.nas)
      .take(6)
      .toList();
  final recentlyAdded = library.take(6).toList();
  final sections = <HomeSectionViewModel>[];

  for (final module in enabledModules) {
    switch (module.type) {
      case HomeModuleType.doubanRecommendations:
        sections.add(_buildDoubanSection(module, recommendations, library));
        break;
      case HomeModuleType.doubanWishList:
        sections.add(_buildDoubanSection(module, wishList, library));
        break;
      case HomeModuleType.recentlyAdded:
        sections.add(
          _buildLibrarySection(
            module,
            recentlyAdded,
            emptyMessage: '无',
          ),
        );
        break;
      case HomeModuleType.embyLibrary:
        final selectedIds = settings.mediaSources
            .where((item) => item.kind == MediaSourceKind.emby && item.enabled)
            .expand((item) => item.featuredSectionIds)
            .toSet();
        if (selectedIds.isEmpty) {
          sections.add(
            const HomeSectionViewModel(
              id: 'module-emby-library-empty',
              title: 'Emby 分区',
              subtitle: '在媒体源里读取并勾选你想放到首页的分区',
              emptyMessage: '无',
              items: [],
            ),
          );
          break;
        }

        final selectedCollections = embyCollections
            .where((item) => selectedIds.contains(item.id))
            .toList();
        final collectionSections = await Future.wait(
          selectedCollections.map((collection) async {
            final sectionItems = await mediaRepository.fetchLibrary(
              sourceId: collection.sourceId,
              sectionId: collection.id,
              limit: 6,
            );
            return _buildLibrarySection(
              HomeModuleConfig(
                id: 'emby-${collection.id}',
                type: module.type,
                title: collection.title,
                enabled: true,
              ),
              sectionItems,
              subtitle:
                  '${collection.sourceName} · ${collection.subtitle.isEmpty ? 'Emby 分区' : collection.subtitle}',
              emptyMessage: '无',
              viewAllTarget: LibraryCollectionTarget(
                title: collection.title,
                sourceId: collection.sourceId,
                sourceName: collection.sourceName,
                sourceKind: collection.sourceKind,
                sectionId: collection.id,
                subtitle: collection.subtitle,
              ),
            );
          }),
        );
        sections.addAll(collectionSections);
        if (collectionSections.isEmpty && embyItems.isNotEmpty) {
          sections.add(
            _buildLibrarySection(
              module,
              embyItems,
              emptyMessage: '无',
            ),
          );
        }
        break;
      case HomeModuleType.nasLibrary:
        sections.add(
          _buildLibrarySection(
            module,
            nasItems,
            emptyMessage: '无',
          ),
        );
        break;
    }
  }

  return sections;
});

HomeSectionViewModel _buildDoubanSection(
  HomeModuleConfig module,
  List<DoubanEntry> entries,
  List<MediaItem> library,
) {
  final items = entries.map((entry) {
    final matched = _matchByTitle(library, entry.title);
    return HomeCardViewModel(
      id: entry.id,
      title: entry.title,
      subtitle: matched != null ? '${matched.sourceName} 已就绪' : '无',
      posterUrl: entry.posterUrl,
      badges: [
        '${entry.year}',
        matched?.sourceKind.label ?? '待补片',
      ],
      caption: entry.note,
      actionLabel: '查看详情',
      detailTarget: matched == null
          ? MediaDetailTarget(
              title: entry.title,
              posterUrl: entry.posterUrl,
              overview: entry.note,
              year: entry.year,
              genres: const [],
              directors: const [],
              actors: const [],
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
    subtitle: module.type.description,
    emptyMessage: '无',
    items: items,
  );
}

HomeSectionViewModel _buildLibrarySection(
  HomeModuleConfig module,
  List<MediaItem> library, {
  String? subtitle,
  required String emptyMessage,
  LibraryCollectionTarget? viewAllTarget,
}) {
  final items = library.map((item) {
    return HomeCardViewModel(
      id: item.id,
      title: item.title,
      subtitle: '${item.sourceName} · ${item.durationLabel}',
      posterUrl: item.posterUrl,
      badges: [item.sourceKind.label, '${item.year}'],
      caption: item.overview,
      actionLabel: '查看详情',
      detailTarget: MediaDetailTarget.fromMediaItem(item),
    );
  }).toList();

  return HomeSectionViewModel(
    id: module.id,
    title: module.title,
    subtitle: subtitle ?? module.type.description,
    emptyMessage: emptyMessage,
    items: items,
    viewAllTarget: viewAllTarget,
  );
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
