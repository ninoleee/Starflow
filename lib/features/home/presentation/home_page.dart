import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/app_network_image.dart';
import 'package:starflow/core/widgets/desktop_horizontal_pager.dart';
import 'package:starflow/core/widgets/media_poster_tile.dart';
import 'package:starflow/core/widgets/starflow_logo.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/media_detail_page.dart';
import 'package:starflow/features/home/application/home_controller.dart';
import 'package:starflow/features/library/data/nas_media_indexer.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_session.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  String _focusedHeroId = '';
  String _pinnedHeroSectionId = '';
  String _lastHeroSourceModuleId = '';
  final ScrollController _scrollController = ScrollController();
  final TvFocusMemoryController _tvFocusMemoryController =
      TvFocusMemoryController();
  final Set<String> _heroMetadataRefreshScheduledKeys = <String>{};
  final GlobalKey<_FeaturedHeroState> _featuredHeroKey =
      GlobalKey<_FeaturedHeroState>();
  final FocusNode _heroNextSectionFocusNode =
      FocusNode(debugLabel: 'home-hero-next-section');
  int _heroFocusBelowRequestVersion = 0;

  bool get _showHeroPagerButtons {
    if (kIsWeb) {
      return true;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows => true,
      TargetPlatform.macOS => true,
      TargetPlatform.linux => true,
      _ => false,
    };
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _heroNextSectionFocusNode.dispose();
    _tvFocusMemoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTelevision = ref.watch(isTelevisionProvider).valueOrNull ?? false;
    final heroModule = ref.watch(homeHeroModuleProvider);
    final enabledModules = ref.watch(homeEnabledModulesProvider);
    final sectionStates = <String, AsyncValue<HomeSectionViewModel?>>{
      for (final module in enabledModules)
        module.id: ref.watch(homeSectionProvider(module.id)),
    };
    final heroDisplayMode = ref.watch(
      appSettingsProvider.select((settings) => settings.homeHeroDisplayMode),
    );
    final heroStyle = ref.watch(
      appSettingsProvider.select((settings) => settings.homeHeroStyle),
    );
    final heroSourceModuleId = ref.watch(
      appSettingsProvider.select((settings) => settings.homeHeroSourceModuleId),
    );
    final heroBackgroundEnabled = ref.watch(
      appSettingsProvider.select(
        (settings) => settings.homeHeroBackgroundEnabled,
      ),
    );
    final heroLogoTitleEnabled = ref.watch(
      appSettingsProvider.select(
        (settings) => settings.homeHeroLogoTitleEnabled,
      ),
    );
    final translucentEffectsEnabled = ref.watch(
      appSettingsProvider.select(
        (settings) => settings.translucentEffectsEnabled,
      ),
    );
    final performanceStaticHomeHeroEnabled = ref.watch(
      appSettingsProvider
          .select((settings) => settings.performanceStaticHomeHeroEnabled),
    );
    final performanceLightweightHomeHeroEnabled = ref.watch(
      appSettingsProvider.select(
        (settings) => settings.performanceLightweightHomeHeroEnabled,
      ),
    );
    final effectiveTranslucentEffectsEnabled = translucentEffectsEnabled;
    final effectiveHeroBackgroundEnabled = heroBackgroundEnabled;
    final resolvedSections = <HomeSectionViewModel>[];
    var hasPendingSections = false;

    for (final module in enabledModules) {
      final state = sectionStates[module.id];
      final section = state?.valueOrNull;
      if (section != null) {
        resolvedSections.add(section);
      }
      if (state?.isLoading ?? false) {
        hasPendingSections = true;
      }
    }

    return TvPageFocusScope(
      controller: _tvFocusMemoryController,
      scopeId: 'home',
      isTelevision: isTelevision,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: enabledModules.isEmpty
            ? const _HomeShell(
                backgroundImageUrl: '',
                backgroundImageHeaders: {},
                child: _EmptyHomeState(),
              )
            : _buildLoadedHome(
                context: context,
                enabledModules: enabledModules,
                sectionStates: sectionStates,
                resolvedSections: resolvedSections,
                hasPendingSections: hasPendingSections,
                heroEnabled: heroModule?.enabled ?? false,
                heroSourceModuleId: heroSourceModuleId,
                heroLogoTitleEnabled: heroLogoTitleEnabled,
                heroBackgroundEnabled: effectiveHeroBackgroundEnabled,
                translucentEffectsEnabled: effectiveTranslucentEffectsEnabled,
                staticHomeHeroEnabled: performanceStaticHomeHeroEnabled,
                lightweightHomeHeroEnabled:
                    performanceLightweightHomeHeroEnabled,
                isTelevision: isTelevision,
                heroDisplayMode: heroDisplayMode,
                heroStyle: heroStyle,
              ),
      ),
    );
  }

  Widget _buildLoadedHome({
    required BuildContext context,
    required List<HomeModuleConfig> enabledModules,
    required Map<String, AsyncValue<HomeSectionViewModel?>> sectionStates,
    required List<HomeSectionViewModel> resolvedSections,
    required bool hasPendingSections,
    required bool heroEnabled,
    required String heroSourceModuleId,
    required bool heroLogoTitleEnabled,
    required bool heroBackgroundEnabled,
    required bool translucentEffectsEnabled,
    required bool staticHomeHeroEnabled,
    required bool lightweightHomeHeroEnabled,
    required bool isTelevision,
    required HomeHeroDisplayMode heroDisplayMode,
    required HomeHeroStyle heroStyle,
  }) {
    final featuredSection = heroEnabled
        ? _resolveStableHeroSection(
            resolvedSections: resolvedSections,
            sectionStates: sectionStates,
            preferredModuleId: heroSourceModuleId,
          )
        : null;

    final featuredItems = !heroEnabled
        ? const <_FeaturedHeroItem>[]
        : _buildFeaturedItems(
            featuredSection: featuredSection,
            resolvedSections: resolvedSections,
            preferredModuleId: heroSourceModuleId,
          );
    _scheduleHeroMetadataRefresh(featuredItems);
    final activeHero = _resolveActiveHeroItem(featuredItems);
    final featuredSectionId = featuredSection?.id;
    final firstFocusableSectionId = _resolveFirstFocusableSectionId(
      enabledModules: enabledModules,
      sectionStates: sectionStates,
      featuredSectionId: featuredSectionId,
    );

    return _HomeShell(
      backgroundImageUrl:
          heroBackgroundEnabled ? activeHero?.backgroundImage.url ?? '' : '',
      backgroundImageHeaders: heroBackgroundEnabled
          ? activeHero?.backgroundImage.headers ?? const {}
          : const {},
      translucentEffectsEnabled: translucentEffectsEnabled,
      child: RefreshIndicator(
        color: Colors.white,
        backgroundColor: const Color(0xFF102033),
        onRefresh: () => refreshHomeModules(ref),
        child: ListView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: EdgeInsets.zero,
          children: [
            if (heroEnabled && featuredItems.isNotEmpty)
              Padding(
                padding: heroDisplayMode.heroPadding(context),
                child: _FeaturedHero(
                  key: _featuredHeroKey,
                  items: featuredItems,
                  isTelevision: isTelevision,
                  staticModeEnabled: staticHomeHeroEnabled,
                  lightweightVisualEnabled: lightweightHomeHeroEnabled,
                  showPagerButtons: _showHeroPagerButtons || isTelevision,
                  logoTitleEnabled: heroLogoTitleEnabled,
                  translucentEffectsEnabled: translucentEffectsEnabled,
                  displayMode: heroDisplayMode,
                  style: heroStyle,
                  focusScopePrefix: 'home:hero',
                  onFocusBelowControl: _focusBelowHeroContent,
                  onFocusedItemChanged: _handleFocusedHeroChanged,
                ),
              )
            else if (heroEnabled && hasPendingSections)
              Padding(
                padding: heroDisplayMode.heroPadding(context),
                child: _HomeHeroPlaceholder(displayMode: heroDisplayMode),
              ),
            ...enabledModules.asMap().entries.map((entry) {
              final index = entry.key;
              final module = entry.value;
              final state = sectionStates[module.id] ??
                  const AsyncLoading<HomeSectionViewModel?>();
              return Padding(
                padding: EdgeInsets.only(
                  top: !heroEnabled && index == 0 ? 20 : 0,
                  bottom: 26,
                ),
                child: _buildSectionSlot(
                  context: context,
                  module: module,
                  state: state,
                  featuredSectionId: featuredSectionId,
                  firstFocusableSectionId: firstFocusableSectionId,
                ),
              );
            }),
            const SizedBox(height: 6),
            const _HomeEditButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionSlot({
    required BuildContext context,
    required HomeModuleConfig module,
    required AsyncValue<HomeSectionViewModel?> state,
    required String? featuredSectionId,
    required String? firstFocusableSectionId,
  }) {
    final section = state.valueOrNull;
    if (section != null) {
      if (section.id == featuredSectionId) {
        return const SizedBox.shrink();
      }
      return _buildResolvedSection(
        context,
        section,
        useHeroNextSectionFocusNode: section.id == firstFocusableSectionId,
      );
    }

    if (state.hasError) {
      return _HomeSection(
        title: module.title,
        child: const _SectionEmptyState(message: '加载失败'),
      );
    }

    return _HomeSectionLoading(
      title: module.title,
      layout: module.type == HomeModuleType.doubanCarousel
          ? HomeSectionLayout.carousel
          : HomeSectionLayout.posterRail,
    );
  }

  Widget _buildResolvedSection(
    BuildContext context,
    HomeSectionViewModel section, {
    required bool useHeroNextSectionFocusNode,
  }) {
    final viewAllTarget = section.viewAllTarget;
    final openViewAll = viewAllTarget == null
        ? null
        : () {
            context.pushNamed(
              viewAllTarget.routeName,
              extra: viewAllTarget.extra,
            );
          };
    return _HomeSection(
      title: section.title,
      child: section.layout == HomeSectionLayout.carousel
          ? _HomeCarousel(
              items: section.carouselItems,
              focusScopePrefix: 'home:carousel:${section.id}',
              firstItemFocusNode: useHeroNextSectionFocusNode
                  ? _heroNextSectionFocusNode
                  : null,
            )
          : section.items.isEmpty
              ? _SectionEmptyState(message: section.emptyMessage)
              : SizedBox(
                  height: 246,
                  child: DesktopHorizontalPager(
                    builder: (context, controller) => ListView.separated(
                      controller: controller,
                      primary: false,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      scrollDirection: Axis.horizontal,
                      itemCount:
                          section.items.length + (openViewAll == null ? 0 : 1),
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        if (index >= section.items.length) {
                          return _HomeSectionViewAllTile(
                            focusId: 'home:section:${section.id}:view-all',
                            onTap: openViewAll!,
                          );
                        }
                        final item = section.items[index];
                        return MediaPosterTile(
                          title: item.title,
                          subtitle: item.subtitle,
                          posterUrl: item.posterUrl,
                          tvPosterFocusOutlineOnly: true,
                          focusNode: useHeroNextSectionFocusNode && index == 0
                              ? _heroNextSectionFocusNode
                              : null,
                          focusId:
                              'home:section:${section.id}:item:${item.detailTarget.itemId.isNotEmpty ? item.detailTarget.itemId : item.title}',
                          autofocus: index == 0,
                          posterHeaders: item.detailTarget.posterHeaders,
                          posterFallbackSources:
                              _buildPosterFallbackSources(item.detailTarget),
                          titleColor: Colors.white,
                          subtitleColor: const Color(0xFF98A7C2),
                          onTap: () {
                            context.pushNamed(
                              'detail',
                              extra: item.detailTarget,
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
    );
  }

  String? _resolveFirstFocusableSectionId({
    required List<HomeModuleConfig> enabledModules,
    required Map<String, AsyncValue<HomeSectionViewModel?>> sectionStates,
    required String? featuredSectionId,
  }) {
    for (final module in enabledModules) {
      final section = sectionStates[module.id]?.valueOrNull;
      if (section == null ||
          section.id == featuredSectionId ||
          !_sectionHasFocusableContent(section)) {
        continue;
      }
      return section.id;
    }
    return null;
  }

  bool _sectionHasFocusableContent(HomeSectionViewModel section) {
    return switch (section.layout) {
      HomeSectionLayout.carousel => section.carouselItems.isNotEmpty,
      HomeSectionLayout.posterRail => section.items.isNotEmpty,
    };
  }

  void _focusBelowHeroContent() {
    unawaited(_focusBelowHeroContentAsync());
  }

  Future<void> _focusBelowHeroContentAsync() async {
    final requestVersion = ++_heroFocusBelowRequestVersion;
    if (_requestHeroNextSectionFocus()) {
      return;
    }

    if (!mounted || requestVersion != _heroFocusBelowRequestVersion) {
      return;
    }

    for (var attempt = 0; attempt < 3; attempt++) {
      await _waitForNextFrame();
      if (!mounted || requestVersion != _heroFocusBelowRequestVersion) {
        return;
      }
      if (_requestHeroNextSectionFocus()) {
        return;
      }
    }

    FocusManager.instance.primaryFocus?.focusInDirection(
      TraversalDirection.down,
    );
  }

  bool _requestHeroNextSectionFocus() {
    final targetContext = _heroNextSectionFocusNode.context;
    if (targetContext == null || !_heroNextSectionFocusNode.canRequestFocus) {
      return false;
    }
    FocusScope.of(targetContext).requestFocus(_heroNextSectionFocusNode);
    return true;
  }

  Future<void> _waitForNextFrame() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    return completer.future;
  }

  _FeaturedHeroItem? _resolveActiveHeroItem(List<_FeaturedHeroItem> items) {
    if (items.isEmpty) {
      return null;
    }
    for (final item in items) {
      if (item.id == _focusedHeroId) {
        return item;
      }
    }
    return items.first;
  }

  void _handleFocusedHeroChanged(_FeaturedHeroItem item) {
    if (_focusedHeroId == item.id) {
      return;
    }
    setState(() {
      _focusedHeroId = item.id;
    });
  }

  void _scheduleHeroMetadataRefresh(List<_FeaturedHeroItem> items) {
    if (items.isEmpty || ref.read(backgroundWorkSuspendedProvider)) {
      return;
    }

    final candidates = <MediaDetailTarget>[];
    for (final item in items) {
      final target = item.detailTarget;
      if (!_needsHeroMetadataRefresh(target)) {
        continue;
      }
      final refreshKey = _heroMetadataRefreshKey(target);
      if (refreshKey.isEmpty ||
          !_heroMetadataRefreshScheduledKeys.add(refreshKey)) {
        continue;
      }
      candidates.add(target);
    }
    if (candidates.isEmpty) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ref.read(backgroundWorkSuspendedProvider)) {
        return;
      }
      unawaited(_refreshHeroMetadataInBackground(candidates));
    });
  }

  Future<void> _refreshHeroMetadataInBackground(
    List<MediaDetailTarget> targets,
  ) async {
    if (ref.read(backgroundWorkSuspendedProvider)) {
      return;
    }
    try {
      await Future.wait(
        targets.map(_refreshSingleHeroMetadataIfNeeded),
        eagerError: false,
      );
    } catch (_) {
      // Hero metadata refresh is best-effort and should never block home UI.
    }
  }

  Future<void> _refreshSingleHeroMetadataIfNeeded(
    MediaDetailTarget target,
  ) async {
    if (ref.read(backgroundWorkSuspendedProvider)) {
      return;
    }
    try {
      if (!_needsHeroMetadataRefresh(target)) {
        return;
      }

      if (target.sourceKind == MediaSourceKind.nas &&
          target.sourceId.trim().isNotEmpty &&
          target.itemId.trim().isNotEmpty) {
        final updatedTarget = await ref
            .read(nasMediaIndexerProvider)
            .enrichDetailTargetMetadataIfNeeded(target);
        if (updatedTarget == null ||
            !_heroMetadataRefreshProducedUpdate(target, updatedTarget)) {
          return;
        }
        await ref.read(localStorageCacheRepositoryProvider).saveDetailTarget(
              seedTarget: target,
              resolvedTarget: updatedTarget,
            );
        return;
      }

      final settings = ref.read(appSettingsProvider);
      if (!_canAttemptHeroMetadataRefresh(settings, target)) {
        return;
      }

      if (ref.read(backgroundWorkSuspendedProvider)) {
        return;
      }

      final cacheRepository = ref.read(localStorageCacheRepositoryProvider);
      final refreshStatus =
          await cacheRepository.loadDetailMetadataRefreshStatus(target);
      if (refreshStatus != DetailMetadataRefreshStatus.never) {
        return;
      }

      try {
        final updatedTarget =
            await ref.read(enrichedDetailTargetProvider(target).future);
        await cacheRepository.saveDetailTarget(
          seedTarget: target,
          resolvedTarget: updatedTarget,
          metadataRefreshStatus:
              _heroMetadataRefreshProducedUpdate(target, updatedTarget)
                  ? DetailMetadataRefreshStatus.succeeded
                  : DetailMetadataRefreshStatus.failed,
        );
      } catch (_) {
        await cacheRepository.saveDetailTarget(
          seedTarget: target,
          resolvedTarget: target,
          metadataRefreshStatus: DetailMetadataRefreshStatus.failed,
        );
      }
    } catch (_) {
      // Background hero refresh is best-effort.
    }
  }

  String _heroMetadataRefreshKey(MediaDetailTarget target) {
    final parts = [
      target.sourceKind?.name ?? '',
      target.sourceId.trim(),
      target.itemId.trim(),
      target.doubanId.trim(),
      target.imdbId.trim().toLowerCase(),
      target.tmdbId.trim(),
      target.title.trim().toLowerCase(),
    ].where((item) => item.isNotEmpty).toList(growable: false);
    return parts.join('|');
  }

  bool _needsHeroMetadataRefresh(MediaDetailTarget target) {
    final hasHeroWideVisual = target.backdropUrl.trim().isNotEmpty ||
        target.bannerUrl.trim().isNotEmpty ||
        target.extraBackdropUrls.any((item) => item.trim().isNotEmpty);
    final hasHeroTitleVisual = target.logoUrl.trim().isNotEmpty;
    return target.needsMetadataMatch ||
        target.needsImdbRatingMatch ||
        !hasHeroWideVisual ||
        !hasHeroTitleVisual;
  }

  bool _canAttemptHeroMetadataRefresh(
    AppSettings settings,
    MediaDetailTarget target,
  ) {
    final query =
        (target.searchQuery.trim().isEmpty ? target.title : target.searchQuery)
            .trim();
    if (query.isEmpty && target.doubanId.trim().isEmpty) {
      return false;
    }

    final needsWmdb = settings.wmdbMetadataMatchEnabled &&
        (target.needsMetadataMatch ||
            _missingRatingKeyword(target.ratingLabels, '豆瓣') ||
            target.needsImdbRatingMatch ||
            target.doubanId.trim().isEmpty ||
            target.imdbId.trim().isEmpty);
    final needsTmdb = settings.tmdbMetadataMatchEnabled &&
        settings.tmdbReadAccessToken.trim().isNotEmpty &&
        (target.needsMetadataMatch ||
            target.imdbId.trim().isEmpty ||
            target.backdropUrl.trim().isEmpty ||
            target.logoUrl.trim().isEmpty);
    final needsImdb = settings.imdbRatingMatchEnabled &&
        (!settings.tmdbMetadataMatchEnabled ||
            settings.tmdbReadAccessToken.trim().isEmpty) &&
        target.needsImdbRatingMatch;
    return needsWmdb || needsTmdb || needsImdb;
  }

  bool _heroMetadataRefreshProducedUpdate(
    MediaDetailTarget current,
    MediaDetailTarget next,
  ) {
    if (!_needsHeroMetadataRefresh(next)) {
      return true;
    }
    return current.posterUrl.trim() != next.posterUrl.trim() ||
        current.backdropUrl.trim() != next.backdropUrl.trim() ||
        current.logoUrl.trim() != next.logoUrl.trim() ||
        current.bannerUrl.trim() != next.bannerUrl.trim() ||
        !listEquals(current.extraBackdropUrls, next.extraBackdropUrls) ||
        current.overview.trim() != next.overview.trim() ||
        current.durationLabel.trim() != next.durationLabel.trim() ||
        current.year != next.year ||
        !listEquals(current.ratingLabels, next.ratingLabels) ||
        !listEquals(current.genres, next.genres) ||
        !listEquals(current.directors, next.directors) ||
        !listEquals(current.actors, next.actors) ||
        current.doubanId.trim() != next.doubanId.trim() ||
        current.imdbId.trim().toLowerCase() !=
            next.imdbId.trim().toLowerCase() ||
        current.tmdbId.trim() != next.tmdbId.trim() ||
        current.tvdbId.trim() != next.tvdbId.trim();
  }

  bool _missingRatingKeyword(Iterable<String> labels, String keyword) {
    final normalizedKeyword = keyword.trim().toLowerCase();
    if (normalizedKeyword.isEmpty) {
      return false;
    }
    return !labels.any(
      (label) => label.trim().toLowerCase().contains(normalizedKeyword),
    );
  }

  HomeSectionViewModel? _resolveStableHeroSection({
    required List<HomeSectionViewModel> resolvedSections,
    required Map<String, AsyncValue<HomeSectionViewModel?>> sectionStates,
    required String preferredModuleId,
  }) {
    final normalizedPreferredModuleId = preferredModuleId.trim();
    if (_lastHeroSourceModuleId != normalizedPreferredModuleId) {
      _lastHeroSourceModuleId = normalizedPreferredModuleId;
      _pinnedHeroSectionId = '';
    }

    final sectionsById = <String, HomeSectionViewModel>{
      for (final section in resolvedSections) section.id: section,
    };

    HomeSectionViewModel? resolvePinnedSection() {
      final pinnedSection = sectionsById[_pinnedHeroSectionId];
      if (!_sectionHasHeroContent(pinnedSection)) {
        return null;
      }
      return pinnedSection;
    }

    if (normalizedPreferredModuleId.isNotEmpty) {
      final preferredSection = sectionsById[normalizedPreferredModuleId];
      if (_sectionHasHeroContent(preferredSection)) {
        _pinnedHeroSectionId = normalizedPreferredModuleId;
        return preferredSection;
      }

      final preferredState = sectionStates[normalizedPreferredModuleId];
      final preferredStillLoading =
          preferredState == null || preferredState.isLoading;
      if (preferredStillLoading) {
        // When a source is explicitly configured, keep startup stable and wait
        // for that source instead of flashing through fallback sections first.
        final pinnedSection = resolvePinnedSection();
        if (pinnedSection != null &&
            pinnedSection.id == normalizedPreferredModuleId) {
          return pinnedSection;
        }
        return null;
      }

      if (_pinnedHeroSectionId == normalizedPreferredModuleId) {
        _pinnedHeroSectionId = '';
      }
    }

    final pinnedSection = resolvePinnedSection();
    if (pinnedSection != null) {
      return pinnedSection;
    }

    final candidate = _pickHeroSectionCandidate(
      resolvedSections: resolvedSections,
    );
    if (_sectionHasHeroContent(candidate)) {
      _pinnedHeroSectionId = candidate!.id;
    }
    return candidate;
  }
}

List<_FeaturedHeroItem> _fallbackFeaturedItems(
    List<HomeSectionViewModel> sections) {
  for (final section in sections) {
    if (section.items.isNotEmpty) {
      return section.items.take(5).map(_FeaturedHeroItem.fromPoster).toList();
    }
  }
  return const [];
}

HomeSectionViewModel? _pickHeroSectionCandidate({
  required List<HomeSectionViewModel> resolvedSections,
}) {
  for (final section in resolvedSections) {
    if (section.layout == HomeSectionLayout.carousel &&
        section.carouselItems.isNotEmpty) {
      return section;
    }
  }

  for (final section in resolvedSections) {
    if (section.items.isNotEmpty || section.carouselItems.isNotEmpty) {
      return section;
    }
  }
  return null;
}

bool _sectionHasHeroContent(HomeSectionViewModel? section) {
  if (section == null) {
    return false;
  }
  return section.items.isNotEmpty || section.carouselItems.isNotEmpty;
}

List<_FeaturedHeroItem> _buildFeaturedItems({
  required HomeSectionViewModel? featuredSection,
  required List<HomeSectionViewModel> resolvedSections,
  required String preferredModuleId,
}) {
  if (featuredSection == null) {
    return const [];
  }
  if (featuredSection.layout == HomeSectionLayout.carousel &&
      featuredSection.carouselItems.isNotEmpty) {
    return featuredSection.carouselItems
        .take(5)
        .map(_FeaturedHeroItem.fromCarousel)
        .toList();
  }
  if (featuredSection.items.isNotEmpty) {
    return featuredSection.items
        .take(5)
        .map(_FeaturedHeroItem.fromPoster)
        .toList();
  }
  if (preferredModuleId.trim().isNotEmpty) {
    return _fallbackFeaturedItems(
      resolvedSections
          .where((section) => section.id != preferredModuleId)
          .toList(),
    );
  }
  return _fallbackFeaturedItems(resolvedSections);
}

extension _HomeHeroDisplayModeLayoutX on HomeHeroDisplayMode {
  EdgeInsets heroPadding(BuildContext context) {
    return switch (this) {
      HomeHeroDisplayMode.normal => EdgeInsets.fromLTRB(
          12,
          MediaQuery.paddingOf(context).top + 6,
          12,
          5,
        ),
      HomeHeroDisplayMode.borderless => const EdgeInsets.fromLTRB(0, 0, 0, 5),
    };
  }

  double get heroHeight => switch (this) {
        HomeHeroDisplayMode.borderless => 500,
        HomeHeroDisplayMode.normal => 440,
      };

  double get viewportFraction => switch (this) {
        HomeHeroDisplayMode.borderless => 1,
        HomeHeroDisplayMode.normal => 0.78,
      };

  double get cardGap => switch (this) {
        HomeHeroDisplayMode.borderless => 0,
        HomeHeroDisplayMode.normal => 12,
      };

  double get cardBorderRadius => switch (this) {
        HomeHeroDisplayMode.borderless => 0,
        HomeHeroDisplayMode.normal => 30,
      };

  bool get showShadow => this != HomeHeroDisplayMode.borderless;

  bool get usesFrostedBackdrop => this == HomeHeroDisplayMode.borderless;

  EdgeInsets get textPadding => switch (this) {
        HomeHeroDisplayMode.normal => const EdgeInsets.fromLTRB(22, 24, 22, 24),
        HomeHeroDisplayMode.borderless =>
          const EdgeInsets.fromLTRB(20, 28, 20, 22),
      };
}

extension _HomeHeroArtworkStyleX on HomeHeroStyle {
  bool get usesPosterArtwork => this == HomeHeroStyle.poster;
}

double _resolveHeroTextWidthFactor({
  required HomeHeroDisplayMode displayMode,
  required HomeHeroStyle style,
}) {
  final baseWidthFactor = switch (displayMode) {
    HomeHeroDisplayMode.normal => 0.92,
    HomeHeroDisplayMode.borderless => 0.62,
  };
  if (style != HomeHeroStyle.poster) {
    return baseWidthFactor;
  }
  return baseWidthFactor < 0.74 ? baseWidthFactor : 0.74;
}

double _resolveHeroTitleFontSize({
  required HomeHeroDisplayMode displayMode,
  required HomeHeroStyle style,
}) {
  return switch (displayMode) {
    HomeHeroDisplayMode.normal => style == HomeHeroStyle.poster ? 32 : 30,
    HomeHeroDisplayMode.borderless => 36,
  };
}

BoxConstraints _resolveHeroLogoConstraints({
  required HomeHeroDisplayMode displayMode,
  required HomeHeroStyle style,
}) {
  final useLargeLogo = displayMode == HomeHeroDisplayMode.borderless ||
      style == HomeHeroStyle.poster;
  return BoxConstraints(
    maxWidth: useLargeLogo ? 360 : 320,
    maxHeight: useLargeLogo ? 96 : 84,
  );
}

class _HomeShell extends StatelessWidget {
  const _HomeShell({
    required this.backgroundImageUrl,
    this.backgroundImageHeaders = const {},
    this.translucentEffectsEnabled = true,
    required this.child,
  });

  final String backgroundImageUrl;
  final Map<String, String> backgroundImageHeaders;
  final bool translucentEffectsEnabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final verticalInsets = EdgeInsets.only(
      top: appPageTopInset(context),
      bottom: appPageBottomInset(
        context,
        includeBottomNavigationBar: true,
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        _DynamicHeroBackdrop(
          imageUrl: backgroundImageUrl,
          imageHeaders: backgroundImageHeaders,
          translucentEffectsEnabled: translucentEffectsEnabled,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.black.withValues(alpha: 0.08),
                const Color(0x7A07111D),
                const Color(0x52030914),
                Colors.transparent,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.42, 0.82, 1],
            ),
          ),
        ),
        Padding(
          padding: verticalInsets,
          child: child,
        ),
      ],
    );
  }
}

class _DynamicHeroBackdrop extends StatelessWidget {
  const _DynamicHeroBackdrop({
    required this.imageUrl,
    this.imageHeaders = const {},
    this.translucentEffectsEnabled = true,
  });

  final String imageUrl;
  final Map<String, String> imageHeaders;
  final bool translucentEffectsEnabled;

  @override
  Widget build(BuildContext context) {
    if (!translucentEffectsEnabled) {
      return IgnorePointer(
        child: _DynamicHeroBackdropLayer(
          key: ValueKey(imageUrl.trim().isEmpty ? 'empty' : imageUrl),
          imageUrl: imageUrl,
          imageHeaders: imageHeaders,
          translucentEffectsEnabled: translucentEffectsEnabled,
        ),
      );
    }

    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 550),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: _DynamicHeroBackdropLayer(
          key: ValueKey(imageUrl.trim().isEmpty ? 'empty' : imageUrl),
          imageUrl: imageUrl,
          imageHeaders: imageHeaders,
          translucentEffectsEnabled: translucentEffectsEnabled,
        ),
      ),
    );
  }
}

class _DynamicHeroBackdropLayer extends StatelessWidget {
  const _DynamicHeroBackdropLayer({
    super.key,
    required this.imageUrl,
    this.imageHeaders = const {},
    this.translucentEffectsEnabled = true,
  });

  final String imageUrl;
  final Map<String, String> imageHeaders;
  final bool translucentEffectsEnabled;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF030914)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl.trim().isNotEmpty)
            Transform.scale(
              scale: 1.16,
              child: translucentEffectsEnabled
                  ? ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                      child: Opacity(
                        opacity: 0.72,
                        child: AppNetworkImage(
                          imageUrl,
                          headers: imageHeaders,
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                        ),
                      ),
                    )
                  : Opacity(
                      opacity: 0.12,
                      child: AppNetworkImage(
                        imageUrl,
                        headers: imageHeaders,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                      ),
                    ),
            ),
          if (!translucentEffectsEnabled)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF07111D).withValues(alpha: 0.32),
                    const Color(0xFF07111D).withValues(alpha: 0.64),
                    const Color(0xFF030914).withValues(alpha: 0.82),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0x26000000),
                  Colors.black.withValues(alpha: 0.16),
                  Colors.black.withValues(alpha: 0.14),
                  Colors.transparent,
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.48, 0.84, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeHeroPlaceholder extends StatelessWidget {
  const _HomeHeroPlaceholder({required this.displayMode});

  final HomeHeroDisplayMode displayMode;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(displayMode.cardBorderRadius);

    return SizedBox(
      height: displayMode.heroHeight,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            gradient: LinearGradient(
              colors: [
                const Color(0xFF142235),
                const Color(0xFF0C1626),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _HomeSectionLoading extends StatelessWidget {
  const _HomeSectionLoading({
    required this.title,
    required this.layout,
  });

  final String title;
  final HomeSectionLayout layout;

  @override
  Widget build(BuildContext context) {
    return _HomeSection(
      title: title,
      child: layout == HomeSectionLayout.carousel
          ? Container(
              height: 184,
              decoration: BoxDecoration(
                color: const Color(0xFF0B1631).withValues(alpha: 0.56),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          : SizedBox(
              height: 246,
              child: ListView.separated(
                primary: false,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                itemCount: 3,
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  return const _PosterPlaceholderCard();
                },
              ),
            ),
    );
  }
}

class _PosterPlaceholderCard extends StatelessWidget {
  const _PosterPlaceholderCard();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 154,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!constraints.hasBoundedHeight) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 206,
                  decoration: BoxDecoration(
                    color: const Color(0xFF112036).withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  height: 14,
                  width: 118,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 12,
                  width: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ],
            );
          }

          const detailsReservedHeight = 42.0;
          final availablePosterHeight =
              (constraints.maxHeight - detailsReservedHeight)
                  .clamp(0.0, constraints.maxHeight)
                  .toDouble();
          final naturalPosterHeight =
              constraints.hasBoundedWidth ? constraints.maxWidth / 0.7 : 0.0;
          final posterHeight = naturalPosterHeight < availablePosterHeight
              ? naturalPosterHeight
              : availablePosterHeight;

          return ClipRect(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: posterHeight,
                  width: double.infinity,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF112036).withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ClipRect(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            height: 14,
                            width: 118,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            height: 12,
                            width: 44,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HomeSection extends StatelessWidget {
  const _HomeSection({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final titleWidget = Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: titleWidget,
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _HomeSectionViewAllTile extends ConsumerWidget {
  const _HomeSectionViewAllTile({
    required this.onTap,
    this.focusId,
  });

  final VoidCallback onTap;
  final String? focusId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTelevision = ref.watch(isTelevisionProvider).valueOrNull ?? false;
    final content = SizedBox(
      width: 140,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const detailsReservedHeight = 42.0;
          final availablePosterHeight =
              (constraints.maxHeight - detailsReservedHeight)
                  .clamp(0.0, constraints.maxHeight)
                  .toDouble();
          final naturalPosterHeight =
              constraints.hasBoundedWidth ? constraints.maxWidth / 0.7 : 0.0;
          final posterHeight = naturalPosterHeight < availablePosterHeight
              ? naturalPosterHeight
              : availablePosterHeight;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: posterHeight,
                width: double.infinity,
                child: Center(
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 42,
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Expanded(child: SizedBox.shrink()),
            ],
          );
        },
      ),
    );

    if (isTelevision) {
      return TvFocusableAction(
        onPressed: onTap,
        focusId: focusId,
        borderRadius: BorderRadius.circular(18),
        visualStyle: TvFocusVisualStyle.floating,
        child: content,
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: content,
    );
  }
}

class _FeaturedHeroItem {
  const _FeaturedHeroItem({
    required this.id,
    required this.title,
    required this.landscapeImage,
    required this.portraitImage,
    required this.backgroundImage,
    required this.metadata,
    required this.overview,
    required this.detailTarget,
  });

  final String id;
  final String title;
  final _FeaturedHeroImage landscapeImage;
  final _FeaturedHeroImage portraitImage;
  final _FeaturedHeroImage backgroundImage;
  final String metadata;
  final String overview;
  final MediaDetailTarget detailTarget;

  bool get onlyHasSingleUsableImage {
    final imageUrls = <String>{
      landscapeImage.url.trim(),
      portraitImage.url.trim(),
      backgroundImage.url.trim(),
    }..removeWhere((url) => url.isEmpty);
    return imageUrls.length == 1;
  }

  factory _FeaturedHeroItem.fromCarousel(HomeCarouselItemViewModel item) {
    final fallbackImage = item.imageUrl.trim().isEmpty
        ? _FeaturedHeroImage(
            url: item.detailTarget.posterUrl,
            headers: item.detailTarget.posterHeaders,
            preferContain: true,
          )
        : _FeaturedHeroImage(url: item.imageUrl);
    final landscapeImage = _resolveFeaturedHeroLandscapeImage(
      target: item.detailTarget,
      fallbackImage: fallbackImage,
    );
    final portraitImage = _resolveFeaturedHeroPortraitImage(
      target: item.detailTarget,
      fallbackImage: fallbackImage,
      landscapeImage: landscapeImage,
    );
    return _FeaturedHeroItem(
      id: item.id,
      title: item.title,
      landscapeImage: landscapeImage,
      portraitImage: portraitImage,
      backgroundImage: _resolveFeaturedHeroBackgroundImage(
        target: item.detailTarget,
        fallbackImage: landscapeImage,
      ),
      metadata: _buildHeroMetadata(item.detailTarget, fallback: item.subtitle),
      overview: item.detailTarget.overview.trim().isEmpty
          ? item.subtitle
          : item.detailTarget.overview,
      detailTarget: item.detailTarget,
    );
  }

  factory _FeaturedHeroItem.fromPoster(HomeCardViewModel item) {
    final fallbackImage = _FeaturedHeroImage(
      url: item.posterUrl,
      headers: item.detailTarget.posterHeaders,
      preferContain: true,
    );
    final landscapeImage = _resolveFeaturedHeroLandscapeImage(
      target: item.detailTarget,
      fallbackImage: fallbackImage,
    );
    final portraitImage = _resolveFeaturedHeroPortraitImage(
      target: item.detailTarget,
      fallbackImage: fallbackImage,
      landscapeImage: landscapeImage,
    );
    return _FeaturedHeroItem(
      id: item.id,
      title: item.title,
      landscapeImage: landscapeImage,
      portraitImage: portraitImage,
      backgroundImage: _resolveFeaturedHeroBackgroundImage(
        target: item.detailTarget,
        fallbackImage: landscapeImage,
      ),
      metadata: _buildHeroMetadata(
        item.detailTarget,
        fallback: item.subtitle,
      ),
      overview: item.detailTarget.overview,
      detailTarget: item.detailTarget,
    );
  }
}

class _FeaturedHeroImage {
  const _FeaturedHeroImage({
    required this.url,
    this.headers = const {},
    this.preferContain = false,
  });

  final String url;
  final Map<String, String> headers;
  final bool preferContain;
}

_FeaturedHeroImage _resolveFeaturedHeroLandscapeImage({
  required MediaDetailTarget target,
  required _FeaturedHeroImage fallbackImage,
}) {
  final wideCandidates = <_FeaturedHeroImage>[
    if (target.backdropUrl.trim().isNotEmpty)
      _FeaturedHeroImage(
        url: target.backdropUrl,
        headers: target.backdropHeaders,
      ),
    if (target.bannerUrl.trim().isNotEmpty)
      _FeaturedHeroImage(
        url: target.bannerUrl,
        headers: target.bannerHeaders,
      ),
    for (final imageUrl in target.extraBackdropUrls)
      if (imageUrl.trim().isNotEmpty)
        _FeaturedHeroImage(
          url: imageUrl,
          headers: target.extraBackdropHeaders,
        ),
    if (fallbackImage.url.trim().isNotEmpty &&
        fallbackImage.url.trim() != target.posterUrl.trim())
      fallbackImage,
  ];

  if (wideCandidates.isNotEmpty) {
    return wideCandidates.first;
  }

  if (target.posterUrl.trim().isNotEmpty) {
    return _FeaturedHeroImage(
      url: target.posterUrl,
      headers: target.posterHeaders,
      preferContain: true,
    );
  }

  if (fallbackImage.url.trim().isNotEmpty) {
    return _FeaturedHeroImage(
      url: fallbackImage.url,
      headers: fallbackImage.headers,
      preferContain: true,
    );
  }

  return const _FeaturedHeroImage(url: '');
}

_FeaturedHeroImage _resolveFeaturedHeroPortraitImage({
  required MediaDetailTarget target,
  required _FeaturedHeroImage fallbackImage,
  required _FeaturedHeroImage landscapeImage,
}) {
  if (target.posterUrl.trim().isNotEmpty) {
    return _FeaturedHeroImage(
      url: target.posterUrl,
      headers: target.posterHeaders,
      preferContain: true,
    );
  }

  if (fallbackImage.url.trim().isNotEmpty && fallbackImage.preferContain) {
    return _FeaturedHeroImage(
      url: fallbackImage.url,
      headers: fallbackImage.headers,
      preferContain: true,
    );
  }

  if (landscapeImage.url.trim().isNotEmpty) {
    return landscapeImage;
  }

  if (fallbackImage.url.trim().isNotEmpty) {
    return fallbackImage;
  }

  return const _FeaturedHeroImage(url: '');
}

_FeaturedHeroImage _resolveFeaturedHeroBackgroundImage({
  required MediaDetailTarget target,
  required _FeaturedHeroImage fallbackImage,
}) {
  if (target.backdropUrl.trim().isNotEmpty) {
    return _FeaturedHeroImage(
      url: target.backdropUrl,
      headers: target.backdropHeaders,
    );
  }
  if (target.bannerUrl.trim().isNotEmpty) {
    return _FeaturedHeroImage(
      url: target.bannerUrl,
      headers: target.bannerHeaders,
    );
  }
  for (final imageUrl in target.extraBackdropUrls) {
    if (imageUrl.trim().isNotEmpty) {
      return _FeaturedHeroImage(
        url: imageUrl,
        headers: target.extraBackdropHeaders,
      );
    }
  }
  if (target.posterUrl.trim().isNotEmpty) {
    return _FeaturedHeroImage(
      url: target.posterUrl,
      headers: target.posterHeaders,
      preferContain: true,
    );
  }
  return fallbackImage;
}

String _buildHeroMetadata(
  MediaDetailTarget target, {
  String fallback = '',
}) {
  final entries = <String>[
    if (target.year > 0) '${target.year}',
    if (target.durationLabel.trim().isNotEmpty) target.durationLabel,
    ...target.genres.take(2).where((item) => item.trim().isNotEmpty),
  ];

  if (entries.isEmpty && fallback.trim().isNotEmpty) {
    entries.add(fallback.trim());
  }
  return entries.join(' · ');
}

class _FeaturedHero extends StatefulWidget {
  const _FeaturedHero({
    super.key,
    required this.items,
    required this.displayMode,
    required this.style,
    required this.isTelevision,
    required this.staticModeEnabled,
    required this.lightweightVisualEnabled,
    required this.showPagerButtons,
    required this.logoTitleEnabled,
    required this.translucentEffectsEnabled,
    required this.focusScopePrefix,
    this.onFocusBelowControl,
    this.onFocusedItemChanged,
  });

  final List<_FeaturedHeroItem> items;
  final HomeHeroDisplayMode displayMode;
  final HomeHeroStyle style;
  final bool isTelevision;
  final bool staticModeEnabled;
  final bool lightweightVisualEnabled;
  final bool showPagerButtons;
  final bool logoTitleEnabled;
  final bool translucentEffectsEnabled;
  final String focusScopePrefix;
  final VoidCallback? onFocusBelowControl;
  final ValueChanged<_FeaturedHeroItem>? onFocusedItemChanged;

  @override
  State<_FeaturedHero> createState() => _FeaturedHeroState();
}

class _FeaturedHeroState extends State<_FeaturedHero> {
  late PageController _controller;
  final Map<String, FocusNode> _cardFocusNodes = <String, FocusNode>{};
  final FocusNode _previousPagerButtonFocusNode =
      FocusNode(debugLabel: 'home-hero-prev');
  final FocusNode _nextPagerButtonFocusNode =
      FocusNode(debugLabel: 'home-hero-next');
  double _page = 0;
  int _lastReportedIndex = -1;
  double? _pendingPage;
  bool _pageUpdateScheduled = false;

  @override
  void initState() {
    super.initState();
    _syncCardFocusNodes();
    _controller = _buildController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyFocusedItem(0);
    });
  }

  @override
  void didUpdateWidget(covariant _FeaturedHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncCardFocusNodes();
    if (oldWidget.displayMode != widget.displayMode ||
        oldWidget.style != widget.style) {
      final int nextPage = widget.items.isEmpty
          ? 0
          : _page.round().clamp(0, widget.items.length - 1);
      _controller
        ..removeListener(_handlePageChange)
        ..dispose();
      _controller = _buildController(initialPage: nextPage);
      _page = nextPage.toDouble();
      _lastReportedIndex = -1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _notifyFocusedItem(nextPage);
      });
    }
  }

  @override
  void dispose() {
    for (final focusNode in _cardFocusNodes.values) {
      focusNode.dispose();
    }
    _previousPagerButtonFocusNode.dispose();
    _nextPagerButtonFocusNode.dispose();
    _controller
      ..removeListener(_handlePageChange)
      ..dispose();
    super.dispose();
  }

  int get _currentPageIndex => widget.items.isEmpty
      ? 0
      : _page.round().clamp(0, widget.items.length - 1);

  void _syncCardFocusNodes() {
    final validIds = widget.items
        .map((item) => item.id)
        .where((item) => item.trim().isNotEmpty)
        .toSet();
    final obsoleteIds = _cardFocusNodes.keys
        .where((item) => !validIds.contains(item))
        .toList(growable: false);
    for (final id in obsoleteIds) {
      _cardFocusNodes.remove(id)?.dispose();
    }
  }

  FocusNode _focusNodeForItem(String itemId) {
    return _cardFocusNodes.putIfAbsent(
      itemId,
      () => FocusNode(debugLabel: 'home-hero-card:$itemId'),
    );
  }

  PageController _buildController({int initialPage = 0}) {
    return PageController(
      initialPage: initialPage,
      viewportFraction: widget.displayMode.viewportFraction,
    )..addListener(_handlePageChange);
  }

  void _handlePageChange() {
    if (!mounted) {
      return;
    }
    final double page = _controller.hasClients ? _controller.page ?? 0.0 : 0.0;
    _applyPageChange(page);
  }

  void _applyPageChange(double page) {
    final binding = WidgetsBinding.instance;
    final schedulerPhase = binding.schedulerPhase;
    final canUpdateNow = schedulerPhase == SchedulerPhase.idle ||
        schedulerPhase == SchedulerPhase.postFrameCallbacks;

    if (canUpdateNow) {
      _commitPageChange(page);
      return;
    }

    _pendingPage = page;
    if (_pageUpdateScheduled) {
      return;
    }
    _pageUpdateScheduled = true;
    binding.addPostFrameCallback((_) {
      _pageUpdateScheduled = false;
      final pendingPage = _pendingPage;
      _pendingPage = null;
      if (!mounted || pendingPage == null) {
        return;
      }
      _commitPageChange(pendingPage);
    });
  }

  void _commitPageChange(double page) {
    if (!mounted) {
      return;
    }
    _notifyFocusedItem(page.round());
    if ((_page - page).abs() < 0.0001) {
      return;
    }
    setState(() {
      _page = page;
    });
  }

  void _notifyFocusedItem(int index) {
    if (index < 0 || index >= widget.items.length) {
      return;
    }
    if (_lastReportedIndex == index) {
      return;
    }
    _lastReportedIndex = index;
    widget.onFocusedItemChanged?.call(widget.items[index]);
  }

  Future<void> _moveToIndex(int index) async {
    if (index < 0 || index >= widget.items.length) {
      return;
    }
    if (widget.staticModeEnabled) {
      _controller.jumpToPage(index);
      return;
    }
    await _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _focusPagerButton(FocusNode focusNode) {
    if (!focusNode.canRequestFocus) {
      return;
    }
    focusNode.requestFocus();
  }

  void _focusCurrentCard() {
    if (widget.items.isEmpty) {
      return;
    }
    final node = _focusNodeForItem(widget.items[_currentPageIndex].id);
    if (!node.canRequestFocus) {
      return;
    }
    node.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _currentPageIndex;
    final simplifyVisualEffects = widget.lightweightVisualEnabled;

    return Column(
      children: [
        SizedBox(
          height: widget.displayMode.heroHeight,
          child: Stack(
            children: [
              Focus(
                canRequestFocus: false,
                skipTraversal: true,
                descendantsAreFocusable: true,
                child: PageView.builder(
                  controller: _controller,
                  physics: widget.isTelevision
                      ? const NeverScrollableScrollPhysics()
                      : const PageScrollPhysics(),
                  itemCount: widget.items.length,
                  itemBuilder: (context, index) {
                    final item = widget.items[index];
                    return Padding(
                      padding: EdgeInsets.only(
                        right: index == widget.items.length - 1
                            ? 0
                            : widget.displayMode.cardGap,
                      ),
                      child: _FeaturedHeroCard(
                        item: item,
                        displayMode: widget.displayMode,
                        style: widget.style,
                        isTelevision: widget.isTelevision,
                        logoTitleEnabled: widget.logoTitleEnabled,
                        translucentEffectsEnabled:
                            widget.translucentEffectsEnabled,
                        simplifyVisualEffects: simplifyVisualEffects,
                        focusNode: _focusNodeForItem(item.id),
                        focusId: '${widget.focusScopePrefix}:${item.id}',
                        autofocus: index == currentIndex,
                        onFocusPreviousControl: () =>
                            _focusPagerButton(_previousPagerButtonFocusNode),
                        onFocusNextControl: () =>
                            _focusPagerButton(_nextPagerButtonFocusNode),
                        onFocusBelowControl: widget.onFocusBelowControl,
                      ),
                    );
                  },
                ),
              ),
              if (widget.showPagerButtons && widget.items.length > 1) ...[
                Positioned(
                  left: 16,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _HeroPagerButton(
                      isTelevision: widget.isTelevision,
                      staticModeEnabled: widget.staticModeEnabled,
                      icon: Icons.chevron_left_rounded,
                      focusNode: _previousPagerButtonFocusNode,
                      focusId: '${widget.focusScopePrefix}:pager-prev',
                      enabled: currentIndex > 0,
                      onMoveRight: _focusCurrentCard,
                      onFocusBelowControl: widget.onFocusBelowControl,
                      onPressed: currentIndex > 0
                          ? () => _moveToIndex(currentIndex - 1)
                          : null,
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _HeroPagerButton(
                      isTelevision: widget.isTelevision,
                      staticModeEnabled: widget.staticModeEnabled,
                      icon: Icons.chevron_right_rounded,
                      focusNode: _nextPagerButtonFocusNode,
                      focusId: '${widget.focusScopePrefix}:pager-next',
                      enabled: currentIndex < widget.items.length - 1,
                      onMoveLeft: _focusCurrentCard,
                      onFocusBelowControl: widget.onFocusBelowControl,
                      onPressed: currentIndex < widget.items.length - 1
                          ? () => _moveToIndex(currentIndex + 1)
                          : null,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (widget.items.length > 1) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.items.length, (index) {
              final isActive = (_page.round() == index);
              if (widget.staticModeEnabled) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: isActive ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(999),
                  ),
                );
              }
              return AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: isActive ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isActive
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(999),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}

class _HeroPagerButton extends StatelessWidget {
  const _HeroPagerButton({
    required this.isTelevision,
    required this.staticModeEnabled,
    required this.icon,
    this.focusNode,
    this.focusId,
    required this.enabled,
    this.onMoveLeft,
    this.onMoveRight,
    this.onFocusBelowControl,
    this.onPressed,
  });

  final bool isTelevision;
  final bool staticModeEnabled;
  final IconData icon;
  final FocusNode? focusNode;
  final String? focusId;
  final bool enabled;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;
  final VoidCallback? onFocusBelowControl;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final child = AnimatedOpacity(
      duration:
          staticModeEnabled ? Duration.zero : const Duration(milliseconds: 180),
      opacity: enabled ? 0.92 : 0.35,
      child: Material(
        color: Colors.black.withValues(alpha: 0.26),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 54,
          height: 54,
          child: Icon(icon, color: Colors.white, size: 30),
        ),
      ),
    );

    if (!isTelevision) {
      return Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: child,
        ),
      );
    }

    return TvDirectionalActionPanel(
      enabled: isTelevision,
      onMoveLeft: onMoveLeft,
      onMoveRight: onMoveRight,
      onMoveDown: onFocusBelowControl,
      child: TvFocusableAction(
        onPressed: onPressed ?? () {},
        focusNode: focusNode,
        focusId: focusId,
        borderRadius: BorderRadius.circular(999),
        child: child,
      ),
    );
  }
}

class _FeaturedHeroCard extends StatelessWidget {
  const _FeaturedHeroCard({
    required this.item,
    required this.displayMode,
    required this.style,
    required this.isTelevision,
    required this.logoTitleEnabled,
    required this.translucentEffectsEnabled,
    required this.simplifyVisualEffects,
    this.focusNode,
    required this.focusId,
    required this.autofocus,
    this.onFocusPreviousControl,
    this.onFocusNextControl,
    this.onFocusBelowControl,
  });

  final _FeaturedHeroItem item;
  final HomeHeroDisplayMode displayMode;
  final HomeHeroStyle style;
  final bool isTelevision;
  final bool logoTitleEnabled;
  final bool translucentEffectsEnabled;
  final bool simplifyVisualEffects;
  final FocusNode? focusNode;
  final String focusId;
  final bool autofocus;
  final VoidCallback? onFocusPreviousControl;
  final VoidCallback? onFocusNextControl;
  final VoidCallback? onFocusBelowControl;

  @override
  Widget build(BuildContext context) {
    final configuredStyle =
        simplifyVisualEffects ? HomeHeroStyle.poster : style;
    final effectiveArtworkStyle = _resolveFeaturedHeroArtworkStyle(
      configuredStyle: configuredStyle,
      item: item,
    );
    final usesPosterHeroStyle = effectiveArtworkStyle.usesPosterArtwork;
    final usesCompositeBackdrop = !simplifyVisualEffects &&
        displayMode.usesFrostedBackdrop &&
        !usesPosterHeroStyle;
    final borderRadius = BorderRadius.circular(displayMode.cardBorderRadius);
    final Gradient contentGradient = simplifyVisualEffects
        ? LinearGradient(
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.16),
              Colors.black.withValues(alpha: 0.62),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0, 0.56, 1],
          )
        : RadialGradient(
            center: const Alignment(-0.92, 0.96),
            radius: 1.1,
            colors: [
              Colors.black.withValues(alpha: 0.82),
              Colors.black.withValues(alpha: 0.52),
              Colors.black.withValues(alpha: 0.18),
              Colors.transparent,
            ],
            stops: const [0, 0.36, 0.72, 1],
          );

    final card = Ink(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: usesCompositeBackdrop
            ? Colors.white.withValues(
                alpha: translucentEffectsEnabled ? 0.04 : 0.02,
              )
            : const Color(0xFF0B1628),
        boxShadow: !simplifyVisualEffects && displayMode.showShadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 34,
                  offset: const Offset(0, 18),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (usesCompositeBackdrop)
              ClipRect(
                child: translucentEffectsEnabled
                    ? BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0.08),
                                const Color(0xFF0A1628).withValues(alpha: 0.22),
                                const Color(0xFF07111E).withValues(alpha: 0.32),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      )
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0.03),
                              const Color(0xFF0A1628).withValues(alpha: 0.14),
                              const Color(0xFF07111E).withValues(alpha: 0.24),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
              ),
            _FeaturedHeroArtwork(
              item: item,
              displayMode: displayMode,
              style: effectiveArtworkStyle,
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: IgnorePointer(
                child: FractionallySizedBox(
                  widthFactor: _resolveHeroTextWidthFactor(
                    displayMode: displayMode,
                    style: effectiveArtworkStyle,
                  ),
                  heightFactor: 0.72,
                  alignment: Alignment.bottomLeft,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: contentGradient,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: displayMode.textPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  if (item.metadata.trim().isNotEmpty)
                    Text(
                      item.metadata,
                      style: const TextStyle(
                        color: Color(0xFFDCE7FF),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (item.metadata.trim().isNotEmpty)
                    const SizedBox(height: 10),
                  _HeroTitle(
                    item: item,
                    displayMode: displayMode,
                    style: effectiveArtworkStyle,
                    logoTitleEnabled: logoTitleEnabled,
                    simplifyVisualEffects: simplifyVisualEffects,
                  ),
                  const SizedBox(height: 10),
                  if (item.overview.trim().isNotEmpty)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Text(
                        item.overview,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xFFE4ECFF),
                          fontSize: 15,
                          height: 1.45,
                          shadows: simplifyVisualEffects
                              ? null
                              : const [
                                  Shadow(
                                    color: Color(0x9A000000),
                                    blurRadius: 16,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (!isTelevision) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: () => context.pushNamed('detail', extra: item.detailTarget),
          child: card,
        ),
      );
    }

    return FocusableActionDetector(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowLeft):
            DirectionalFocusIntent(TraversalDirection.left),
        SingleActivator(LogicalKeyboardKey.arrowRight):
            DirectionalFocusIntent(TraversalDirection.right),
        SingleActivator(LogicalKeyboardKey.arrowDown):
            DirectionalFocusIntent(TraversalDirection.down),
      },
      actions: <Type, Action<Intent>>{
        DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
          onInvoke: (intent) {
            if (intent.direction == TraversalDirection.left) {
              final focusPreviousControl = onFocusPreviousControl;
              if (focusPreviousControl != null) {
                focusPreviousControl();
              } else {
                TvMenuButtonScope.maybeOf(context)?.onMenuButtonPressed();
              }
            } else if (intent.direction == TraversalDirection.right) {
              onFocusNextControl?.call();
            } else if (intent.direction == TraversalDirection.down) {
              final focusBelowControl = onFocusBelowControl;
              if (focusBelowControl != null) {
                focusBelowControl();
              } else {
                FocusManager.instance.primaryFocus?.focusInDirection(
                  TraversalDirection.down,
                );
              }
            }
            return null;
          },
        ),
      },
      child: TvFocusableAction(
        onPressed: () => context.pushNamed('detail', extra: item.detailTarget),
        focusNode: focusNode,
        focusId: focusId,
        autofocus: autofocus,
        borderRadius: borderRadius,
        child: card,
      ),
    );
  }
}

class _FeaturedHeroArtwork extends StatelessWidget {
  const _FeaturedHeroArtwork({
    required this.item,
    required this.displayMode,
    required this.style,
  });

  final _FeaturedHeroItem item;
  final HomeHeroDisplayMode displayMode;
  final HomeHeroStyle style;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final isPortraitScreen = screenSize.height > screenSize.width;
    final selectedImage = isPortraitScreen
        ? (item.portraitImage.url.trim().isNotEmpty
            ? item.portraitImage
            : item.landscapeImage)
        : (item.landscapeImage.url.trim().isNotEmpty
            ? item.landscapeImage
            : item.portraitImage);

    if (selectedImage.url.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    if (style.usesPosterArtwork && !selectedImage.preferContain) {
      return AppNetworkImage(
        selectedImage.url,
        headers: selectedImage.headers,
        fit: BoxFit.cover,
        alignment: Alignment.center,
      );
    }

    if (style.usesPosterArtwork) {
      return Align(
        alignment: Alignment.centerRight,
        child: FractionallySizedBox(
          widthFactor: isPortraitScreen
              ? (displayMode == HomeHeroDisplayMode.normal ? 0.68 : 0.58)
              : (displayMode == HomeHeroDisplayMode.normal ? 0.54 : 0.42),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              0,
              displayMode == HomeHeroDisplayMode.normal ? 22 : 28,
              displayMode == HomeHeroDisplayMode.normal ? 18 : 24,
              displayMode == HomeHeroDisplayMode.normal ? 22 : 28,
            ),
            child: AppNetworkImage(
              selectedImage.url,
              headers: selectedImage.headers,
              fit: BoxFit.contain,
              alignment: Alignment.centerRight,
            ),
          ),
        ),
      );
    }

    if (!selectedImage.preferContain) {
      return AppNetworkImage(
        selectedImage.url,
        headers: selectedImage.headers,
        fit: BoxFit.cover,
        alignment: Alignment.center,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (item.backgroundImage.url.trim().isNotEmpty)
          Opacity(
            opacity: 0.24,
            child: AppNetworkImage(
              item.backgroundImage.url,
              headers: item.backgroundImage.headers,
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: FractionallySizedBox(
            widthFactor: isPortraitScreen
                ? (displayMode == HomeHeroDisplayMode.normal ? 0.68 : 0.58)
                : (displayMode == HomeHeroDisplayMode.normal ? 0.54 : 0.42),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                0,
                displayMode == HomeHeroDisplayMode.normal ? 22 : 28,
                displayMode == HomeHeroDisplayMode.normal ? 18 : 24,
                displayMode == HomeHeroDisplayMode.normal ? 22 : 28,
              ),
              child: AppNetworkImage(
                selectedImage.url,
                headers: selectedImage.headers,
                fit: BoxFit.contain,
                alignment: Alignment.centerRight,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

HomeHeroStyle _resolveFeaturedHeroArtworkStyle({
  required HomeHeroStyle configuredStyle,
  required _FeaturedHeroItem item,
}) {
  if (configuredStyle == HomeHeroStyle.poster) {
    return HomeHeroStyle.poster;
  }
  if (item.onlyHasSingleUsableImage) {
    return HomeHeroStyle.poster;
  }
  return configuredStyle;
}

class _HeroTitle extends StatelessWidget {
  const _HeroTitle({
    required this.item,
    required this.displayMode,
    required this.style,
    required this.logoTitleEnabled,
    required this.simplifyVisualEffects,
  });

  final _FeaturedHeroItem item;
  final HomeHeroDisplayMode displayMode;
  final HomeHeroStyle style;
  final bool logoTitleEnabled;
  final bool simplifyVisualEffects;

  @override
  Widget build(BuildContext context) {
    final hasLogo =
        logoTitleEnabled && item.detailTarget.logoUrl.trim().isNotEmpty;
    if (hasLogo) {
      return ConstrainedBox(
        constraints: _resolveHeroLogoConstraints(
          displayMode: displayMode,
          style: style,
        ),
        child: AppNetworkImage(
          item.detailTarget.logoUrl,
          headers: item.detailTarget.logoHeaders,
          fit: BoxFit.contain,
          alignment: Alignment.centerLeft,
          errorBuilder: (context, error, stackTrace) {
            return _HeroTitleText(
              item: item,
              displayMode: displayMode,
              style: style,
              simplifyVisualEffects: simplifyVisualEffects,
            );
          },
        ),
      );
    }
    return _HeroTitleText(
      item: item,
      displayMode: displayMode,
      style: style,
      simplifyVisualEffects: simplifyVisualEffects,
    );
  }
}

class _HeroTitleText extends StatelessWidget {
  const _HeroTitleText({
    required this.item,
    required this.displayMode,
    required this.style,
    required this.simplifyVisualEffects,
  });

  final _FeaturedHeroItem item;
  final HomeHeroDisplayMode displayMode;
  final HomeHeroStyle style;
  final bool simplifyVisualEffects;

  @override
  Widget build(BuildContext context) {
    return Text(
      item.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: _resolveHeroTitleFontSize(
              displayMode: displayMode,
              style: style,
            ),
            height: 1.05,
            shadows: simplifyVisualEffects
                ? null
                : [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
    );
  }
}

class _HomeCarousel extends ConsumerWidget {
  const _HomeCarousel({
    required this.items,
    required this.focusScopePrefix,
    this.firstItemFocusNode,
  });

  final List<HomeCarouselItemViewModel> items;
  final String focusScopePrefix;
  final FocusNode? firstItemFocusNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTelevision = ref.watch(isTelevisionProvider).valueOrNull ?? false;
    if (items.isEmpty) {
      return const _SectionEmptyState(message: '无');
    }

    if (isTelevision) {
      return SizedBox(
        height: 184,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (context, index) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final item = items[index];
            return SizedBox(
              width: 320,
              child: TvFocusableAction(
                focusId:
                    '$focusScopePrefix:${item.detailTarget.itemId.isNotEmpty ? item.detailTarget.itemId : item.title}',
                focusNode: index == 0 ? firstItemFocusNode : null,
                autofocus: index == 0,
                onPressed: () {
                  context.pushNamed('detail', extra: item.detailTarget);
                },
                borderRadius: BorderRadius.circular(18),
                child: _HomeCarouselCard(item: item),
              ),
            );
          },
        ),
      );
    }

    return SizedBox(
      height: 184,
      child: PageView.builder(
        controller: PageController(viewportFraction: 0.96),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return Padding(
            padding: EdgeInsets.only(right: index == items.length - 1 ? 0 : 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                context.pushNamed('detail', extra: item.detailTarget);
              },
              child: _HomeCarouselCard(item: item),
            ),
          );
        },
      ),
    );
  }
}

class _HomeCarouselCard extends StatelessWidget {
  const _HomeCarouselCard({required this.item});

  final HomeCarouselItemViewModel item;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF0B1631),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (item.imageUrl.trim().isNotEmpty)
            AppNetworkImage(
              item.imageUrl,
              fit: BoxFit.cover,
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withValues(alpha: 0.18),
                  Colors.black.withValues(alpha: 0.72),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(),
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.subtitle.trim().isEmpty ? '点击查看详情' : item.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFE5EDFF),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeEditButton extends ConsumerWidget {
  const _HomeEditButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTelevision = ref.watch(isTelevisionProvider).valueOrNull ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: kBottomReservedSpacing),
      child: Center(
        child: Opacity(
          opacity: 0.46,
          child: isTelevision
              ? TvAdaptiveButton(
                  label: '编辑首页',
                  icon: Icons.tune_rounded,
                  onPressed: () => context.pushNamed('home-editor'),
                  variant: TvButtonVariant.text,
                )
              : TextButton.icon(
                  onPressed: () => context.pushNamed('home-editor'),
                  icon: const Icon(Icons.tune_rounded, size: 14),
                  label: const Text('编辑首页'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF8FA0BD),
                    textStyle:
                        Theme.of(context).textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                    minimumSize: const Size(0, 32),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
        ),
      ),
    );
  }
}

class _EmptyHomeState extends StatelessWidget {
  const _EmptyHomeState();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StarflowLogo(
                    iconSize: 112,
                    showWordmark: true,
                    wordmarkSize: 34,
                  ),
                  SizedBox(height: 18),
                  _HomeEditButton(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

List<AppNetworkImageSource> _buildPosterFallbackSources(
  MediaDetailTarget target,
) {
  final sources = <AppNetworkImageSource>[];
  final seen = <String>{target.posterUrl.trim()};

  void add(String url, Map<String, String> headers) {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty || !seen.add(trimmedUrl)) {
      return;
    }
    sources.add(
      AppNetworkImageSource(
        url: trimmedUrl,
        headers: headers,
      ),
    );
  }

  add(target.bannerUrl, target.bannerHeaders);
  add(target.backdropUrl, target.backdropHeaders);
  for (final url in target.extraBackdropUrls) {
    add(url, target.extraBackdropHeaders);
  }
  return sources;
}

class _SectionEmptyState extends StatelessWidget {
  const _SectionEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF90A0BD),
            ),
      ),
    );
  }
}
