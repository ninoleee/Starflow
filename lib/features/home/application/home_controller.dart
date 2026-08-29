import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/misc.dart';
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/core/utils/media_rating_labels.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/discovery/data/mock_discovery_repository.dart';
import 'package:starflow/features/discovery/data/douban_network_guard.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/home/application/home_metadata_auto_refresh.dart';
import 'package:starflow/features/home/application/home_feed_load_scheduler.dart';
import 'package:starflow/features/library/application/library_refresh_revision.dart';
import 'package:starflow/features/library/application/nas_media_index_revision.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/library_collection_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/metadata/data/metadata_network_guard.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/domain/playback_memory_models.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'home_settings_slices.dart';

part 'home_controller_models.dart';
part 'home_feed_repository.dart';

const int _defaultHomeSectionItemLimit = 20;

class HomePageController {
  HomePageController();

  HomeResolvedSectionsState resolveSectionStates({
    required List<HomeModuleConfig> enabledModules,
    required AsyncValue<HomeSectionViewModel?> Function(HomeModuleConfig module)
        loadSectionState,
  }) {
    var hasPendingSections = false;
    final sections = <HomeSectionViewModel>[];
    for (final module in enabledModules) {
      final sectionState = loadSectionState(module);
      if (sectionState.isLoading) {
        hasPendingSections = true;
      }
      if (!sectionState.hasValue) {
        continue;
      }
      final section = sectionState.value;
      if (section != null) {
        sections.add(section);
      }
    }

    final resolvedSections = _resolveCanonicalSections(sections);
    final cachedState = _cachedResolvedSectionsState;
    if (identical(resolvedSections, cachedState.sections) &&
        hasPendingSections == cachedState.hasPendingSections) {
      return cachedState;
    }

    _cachedResolvedSectionsState = HomeResolvedSectionsState(
      sections: resolvedSections,
      hasPendingSections: hasPendingSections,
    );
    return _cachedResolvedSectionsState;
  }

  bool _sectionsUnchanged(List<HomeSectionViewModel> sections) {
    if (sections.length != _cachedSections.length) {
      return false;
    }
    for (var i = 0; i < sections.length; i += 1) {
      if (!identical(sections[i], _cachedSections[i])) {
        return false;
      }
    }
    return true;
  }

  List<HomeSectionViewModel> _cachedSections = const [];
  HomeResolvedSectionsState _cachedResolvedSectionsState =
      const HomeResolvedSectionsState();

  List<HomeSectionViewModel> _resolveCanonicalSections(
    Iterable<HomeSectionViewModel> sections,
  ) {
    final mergedSections = sections.toList(growable: false);
    if (_sectionsUnchanged(mergedSections)) {
      return _cachedSections;
    }
    _cachedSections = List<HomeSectionViewModel>.unmodifiable(mergedSections);
    return _cachedSections;
  }

  void primeModulesWithReader(
    T Function<T>(ProviderListenable<T> provider) read,
  ) {
    final modules = read(homeEnabledModulesProvider);
    for (final module in modules) {
      read(homeSectionProvider(module.id).future);
    }
  }

  Future<void> refreshModules(WidgetRef ref) async {
    final stopwatch = Stopwatch()..start();
    ref.invalidate(homeRecentItemsProvider);
    ref.invalidate(homeRecentPlaybackEntriesProvider);
    ref.invalidate(homeCarouselItemsProvider);
    ref.invalidate(_homeSectionSeedProvider);
    ref.invalidate(homeSectionProvider);
    ref.read(homeExplicitRefreshRevisionProvider.notifier).state += 1;
    ref.read(homeMetadataAutoRefreshRevisionProvider.notifier).state += 1;
    primeModulesWithReader(ref.read);
    await Future<void>.delayed(const Duration(milliseconds: 140));
    appLogInfo(
      'home.refresh',
      'Home refresh scheduled',
      fields: <String, Object?>{'durationMs': stopwatch.elapsedMilliseconds},
    );
  }

  Future<void> refreshModulesFromRef(Ref ref) async {
    final stopwatch = Stopwatch()..start();
    ref.invalidate(homeRecentItemsProvider);
    ref.invalidate(homeRecentPlaybackEntriesProvider);
    ref.invalidate(homeCarouselItemsProvider);
    ref.invalidate(_homeSectionSeedProvider);
    ref.invalidate(homeSectionProvider);
    ref.read(homeExplicitRefreshRevisionProvider.notifier).state += 1;
    ref.read(homeMetadataAutoRefreshRevisionProvider.notifier).state += 1;
    primeModulesWithReader(ref.read);
    await Future<void>.delayed(const Duration(milliseconds: 140));
    appLogInfo(
      'home.refresh',
      'Home refresh scheduled',
      fields: <String, Object?>{'durationMs': stopwatch.elapsedMilliseconds},
    );
  }
}

final homeFeedRepositoryProvider = Provider<HomeFeedRepository>((ref) {
  return const HomeFeedRepository();
});

final homePageControllerProvider = Provider<HomePageController>((ref) {
  return HomePageController();
});

final homeEnabledModulesProvider = Provider<List<HomeModuleConfig>>((ref) {
  final modules = ref.watch(homeModulesProvider);
  final selectableSourceIds = ref.watch(homeSelectableMediaSourceIdsProvider);
  return modules
      .where(
        (item) =>
            item.enabled &&
            item.type != HomeModuleType.doubanCarousel &&
            item.type != HomeModuleType.hero &&
            _isEnabledHomeModuleForVisibleSources(item, selectableSourceIds),
      )
      .toList();
});

final homeHeroModuleProvider = Provider<HomeModuleConfig?>((ref) {
  for (final module in ref.watch(homeModulesProvider)) {
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
  return ref.read(homeFeedRepositoryProvider).loadRecentItems(
        enabledModules: enabledModules,
        mediaRepository: ref.read(mediaRepositoryProvider),
      );
});

final homeRecentPlaybackEntriesProvider =
    FutureProvider<List<PlaybackProgressEntry>>((ref) async {
  ref.watch(playbackHistoryRevisionProvider);
  final enabledModules = ref.watch(homeEnabledModulesProvider);
  return ref.read(homeFeedRepositoryProvider).loadRecentPlaybackEntries(
        enabledModules: enabledModules,
        playbackMemoryRepository: ref.read(playbackMemoryRepositoryProvider),
      );
});

final homeCarouselItemsProvider =
    FutureProvider<List<DoubanCarouselEntry>>((ref) async {
  final enabledModules = ref.watch(homeEnabledModulesProvider);
  return ref.read(homeFeedRepositoryProvider).loadCarouselItems(
        enabledModules: enabledModules,
        discoveryRepository: ref.read(discoveryRepositoryProvider),
      );
});

final _homeSectionSeedProvider = FutureProvider.autoDispose
    .family<HomeSectionViewModel?, String>((ref, moduleId) async {
  ref.watch(nasMediaIndexRevisionProvider);
  ref.watch(libraryRefreshRevisionProvider);
  final module = ref.watch(homeModuleByIdProvider(moduleId));
  if (module == null) {
    return null;
  }
  if (module.type == HomeModuleType.recentPlayback) {
    ref.watch(playbackHistoryRevisionProvider);
  }
  final limits = ref.read(homeFeedLoadLimitsProvider);
  final homeFeedRepository = ref.read(homeFeedRepositoryProvider);
  final mediaRepository = ref.read(mediaRepositoryProvider);
  final discoveryRepository = ref.read(discoveryRepositoryProvider);
  final doubanAccount = ref.watch(homeDoubanAccountProvider);
  final mediaSources = ref.watch(homeMediaSourcesProvider);
  final enabledModules = ref.watch(homeEnabledModulesProvider);
  final playbackMemoryRepository = ref.read(playbackMemoryRepositoryProvider);
  return ref.read(homeFeedLoadSchedulerProvider).runLoad(
        moduleId: module.id,
        maxConcurrency: limits.maxConcurrency,
        initialBatchSize: limits.initialBatchSize,
        backgroundBatchDelay: Duration(milliseconds: limits.batchDelayMs),
        task: () async {
          final recentItems = module.type == HomeModuleType.recentlyAdded
              ? homeFeedRepository.loadRecentItems(
                  enabledModules: enabledModules,
                  mediaRepository: mediaRepository,
                )
              : Future<List<MediaItem>>.value(const <MediaItem>[]);
          final recentPlaybackEntries =
              module.type == HomeModuleType.recentPlayback
                  ? homeFeedRepository.loadRecentPlaybackEntries(
                      enabledModules: enabledModules,
                      playbackMemoryRepository: playbackMemoryRepository,
                    )
                  : Future<List<PlaybackProgressEntry>>.value(
                      const <PlaybackProgressEntry>[],
                    );
          final carouselItems = module.type == HomeModuleType.doubanCarousel
              ? homeFeedRepository.loadCarouselItems(
                  enabledModules: enabledModules,
                  discoveryRepository: discoveryRepository,
                )
              : Future<List<DoubanCarouselEntry>>.value(
                  const <DoubanCarouselEntry>[],
                );
          return homeFeedRepository.buildSectionSeed(
            module: module,
            mediaRepository: mediaRepository,
            discoveryRepository: discoveryRepository,
            doubanAccount: doubanAccount,
            mediaSources: mediaSources,
            recentItems: recentItems,
            recentPlaybackEntries: recentPlaybackEntries,
            carouselItems: carouselItems,
          );
        },
      );
});

final homeSectionProvider =
    FutureProvider.family<HomeSectionViewModel?, String>((ref, moduleId) async {
  // Keep Home visually stable after initial load. Cached metadata should only
  // be reapplied on explicit refresh boundaries such as startup/settings save,
  // instead of every background cache write.
  ref.watch(homeMetadataAutoRefreshRevisionProvider);
  final scheduler = ref.read(homeFeedLoadSchedulerProvider);
  final homeFeedRepository = ref.read(homeFeedRepositoryProvider);
  final localStorageCacheRepository =
      ref.read(localStorageCacheRepositoryProvider);
  final seedSection =
      await ref.watch(_homeSectionSeedProvider(moduleId).future);
  if (seedSection == null) {
    return null;
  }
  return scheduler.runSerializedApply(
    moduleId: moduleId,
    task: () => homeFeedRepository.applyCachedSection(
      section: seedSection,
      localStorageCacheRepository: localStorageCacheRepository,
    ),
  );
});

final homeSectionsProvider = Provider<List<HomeSectionViewModel>>((ref) {
  return ref.watch(
    homeResolvedSectionsProvider.select((state) => state.sections),
  );
});

final homeResolvedSectionsProvider = Provider<HomeResolvedSectionsState>((ref) {
  final enabledModules = ref.watch(homeEnabledModulesProvider);
  return ref.read(homePageControllerProvider).resolveSectionStates(
        enabledModules: enabledModules,
        loadSectionState: (module) => ref.watch(homeSectionProvider(module.id)),
      );
});

void primeHomeModules(Ref ref) {
  ref.read(homePageControllerProvider).primeModulesWithReader(ref.read);
}

void primeHomeModulesFromWidget(WidgetRef ref) {
  ref.read(homePageControllerProvider).primeModulesWithReader(ref.read);
}

Future<void> refreshHomeModules(
  WidgetRef ref, {
  bool allowNetworkProbe = false,
}) async {
  if (allowNetworkProbe) {
    ref
        .read(doubanNetworkGuardProvider)
        .allowManualProbe(reason: 'manual-home-refresh');
    ref
        .read(metadataNetworkGuardProvider)
        .allowManualProbe(reason: 'manual-home-refresh');
  }
  return ref.read(homePageControllerProvider).refreshModules(ref);
}

Future<void> refreshHomeModulesFromRef(Ref ref) async {
  return ref.read(homePageControllerProvider).refreshModulesFromRef(ref);
}

bool _isEnabledHomeModuleForVisibleSources(
  HomeModuleConfig module,
  Set<String> selectableSourceIds,
) {
  if (!module.isLibrarySection) {
    return true;
  }
  return selectableSourceIds.contains(module.sourceId.trim());
}
