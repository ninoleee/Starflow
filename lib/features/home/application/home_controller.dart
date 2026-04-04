import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/discovery/data/mock_discovery_repository.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
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
    this.playbackTarget,
  });

  final String id;
  final String title;
  final String subtitle;
  final String posterUrl;
  final List<String> badges;
  final String caption;
  final String actionLabel;
  final PlaybackTarget? playbackTarget;
}

class HomeSectionViewModel {
  const HomeSectionViewModel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.emptyMessage,
    required this.items,
  });

  final String id;
  final String title;
  final String subtitle;
  final String emptyMessage;
  final List<HomeCardViewModel> items;
}

final homeSectionsProvider = FutureProvider<List<HomeSectionViewModel>>((
  ref,
) async {
  final settings = ref.watch(appSettingsProvider);
  final mediaRepository = ref.read(mediaRepositoryProvider);
  final discoveryRepository = ref.read(discoveryRepositoryProvider);
  final library = await mediaRepository.fetchLibrary();
  final sections = <HomeSectionViewModel>[];

  for (final module in settings.homeModules.where((item) => item.enabled)) {
    switch (module.type) {
      case HomeModuleType.doubanRecommendations:
        final entries = await discoveryRepository.fetchRecommendations();
        sections.add(_buildDoubanSection(module, entries, library));
        break;
      case HomeModuleType.doubanWishList:
        final entries = await discoveryRepository.fetchWishList();
        sections.add(_buildDoubanSection(module, entries, library));
        break;
      case HomeModuleType.recentlyAdded:
        sections.add(
          _buildLibrarySection(
            module,
            library.take(6).toList(),
            emptyMessage: '最近还没有新增内容，等同步任务跑起来后这里会很有用。',
          ),
        );
        break;
      case HomeModuleType.embyLibrary:
        sections.add(
          _buildLibrarySection(
            module,
            library
                .where((item) => item.sourceKind == MediaSourceKind.emby)
                .take(6)
                .toList(),
            emptyMessage: '当前没有启用中的 Emby 资源源。',
          ),
        );
        break;
      case HomeModuleType.nasLibrary:
        sections.add(
          _buildLibrarySection(
            module,
            library
                .where((item) => item.sourceKind == MediaSourceKind.nas)
                .take(6)
                .toList(),
            emptyMessage: '当前没有可展示的 NAS 资源。',
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
      subtitle: matched != null ? '${matched.sourceName} 已就绪' : '本地还没有匹配到资源',
      posterUrl: entry.posterUrl,
      badges: [
        '${entry.year}',
        matched?.sourceKind.label ?? '待补片',
      ],
      caption: entry.note,
      actionLabel: matched != null ? '立即播放' : '去搜索',
      playbackTarget:
          matched == null ? null : PlaybackTarget.fromMediaItem(matched),
    );
  }).toList();

  return HomeSectionViewModel(
    id: module.id,
    title: module.title,
    subtitle: module.type.description,
    emptyMessage: '先在设置里启用豆瓣账号，或者后续接入你的桥接服务。',
    items: items,
  );
}

HomeSectionViewModel _buildLibrarySection(
  HomeModuleConfig module,
  List<MediaItem> library, {
  required String emptyMessage,
}) {
  final items = library.map((item) {
    return HomeCardViewModel(
      id: item.id,
      title: item.title,
      subtitle: '${item.sourceName} · ${item.durationLabel}',
      posterUrl: item.posterUrl,
      badges: [item.sourceKind.label, '${item.year}'],
      caption: item.overview,
      actionLabel: '打开播放',
      playbackTarget: PlaybackTarget.fromMediaItem(item),
    );
  }).toList();

  return HomeSectionViewModel(
    id: module.id,
    title: module.title,
    subtitle: module.type.description,
    emptyMessage: emptyMessage,
    items: items,
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
