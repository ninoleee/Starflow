import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/navigation/page_activity_mixin.dart';
import 'package:starflow/core/navigation/retained_async_value.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/utils/media_rating_labels.dart';
import 'package:starflow/core/widgets/app_network_image.dart';
import 'package:starflow/core/widgets/desktop_horizontal_pager.dart';
import 'package:starflow/core/widgets/media_poster_tile.dart';
import 'package:starflow/core/widgets/starflow_logo.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/application/detail_rating_prefetch_coordinator.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/home/application/home_controller.dart';
import 'package:starflow/features/home/application/home_hero_prefetch_coordinator.dart';
import 'package:starflow/features/home/application/home_metadata_auto_refresh.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

part 'home_page_hero.dart';
part 'home_page_sections.dart';

class HomeHeroPrefetchDecision {
  const HomeHeroPrefetchDecision({
    this.shouldSchedule = false,
    this.forceMetadataRefresh = false,
  });

  final bool shouldSchedule;
  final bool forceMetadataRefresh;
}

@visibleForTesting
HomeHeroPrefetchDecision resolveHomeHeroPrefetchDecision({
  required bool isPageVisible,
  required int featuredItemCount,
  required bool heroListChanged,
  required int scheduledMetadataRevision,
  required int currentMetadataRevision,
  required int scheduledExplicitRevision,
  required int currentExplicitRevision,
}) {
  final metadataBoundaryChanged =
      scheduledMetadataRevision != currentMetadataRevision;
  final explicitBoundaryChanged =
      scheduledExplicitRevision != currentExplicitRevision;
  final shouldSchedule = isPageVisible &&
      featuredItemCount > 0 &&
      (heroListChanged || metadataBoundaryChanged || explicitBoundaryChanged);
  if (!shouldSchedule) {
    return const HomeHeroPrefetchDecision();
  }
  return const HomeHeroPrefetchDecision(
    shouldSchedule: true,
    forceMetadataRefresh: true,
  );
}

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomeKeepAlive extends StatefulWidget {
  const _HomeKeepAlive({required this.child});

  final Widget child;

  @override
  State<_HomeKeepAlive> createState() => _HomeKeepAliveState();
}

class _HomeKeepAliveState extends State<_HomeKeepAlive>
    with AutomaticKeepAliveClientMixin<_HomeKeepAlive> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _HomePageState extends ConsumerState<HomePage>
    with PageActivityMixin<HomePage> {
  String _pinnedHeroSectionId = '';
  String _lastHeroSourceModuleId = '';
  final ScrollController _scrollController = ScrollController();
  final TvFocusMemoryController _tvFocusMemoryController =
      TvFocusMemoryController();
  final ValueNotifier<_HomeHeroSelection> _heroSelectionNotifier =
      ValueNotifier<_HomeHeroSelection>(const _HomeHeroSelection.empty());
  final HomeHeroPrefetchCoordinator _heroPrefetchCoordinator =
      HomeHeroPrefetchCoordinator();
  final GlobalKey<_FeaturedHeroState> _featuredHeroKey =
      GlobalKey<_FeaturedHeroState>();
  final FocusNode _heroNextSectionFocusNode =
      FocusNode(debugLabel: 'home-hero-next-section');
  int _heroFocusBelowRequestVersion = 0;
  HomeModuleConfig? _cachedHeroModule;
  List<HomeModuleConfig> _cachedEnabledModules = const [];
  HomeResolvedSectionsState _cachedResolvedSectionsState =
      const HomeResolvedSectionsState();
  List<String> _lastFeaturedHeroIds = const [];
  int _observedHomeMetadataAutoRefreshRevision = 0;
  int _scheduledHeroMetadataAutoRefreshRevision = 0;
  int _scheduledHeroExplicitRefreshRevision = 0;

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
    _heroSelectionNotifier.dispose();
    super.dispose();
  }

  @override
  void onPageBecameActive() {
    // Keep stable cached sections when returning to home, and only warm data
    // sources opportunistically.
    primeHomeModulesFromWidget(ref);
  }

  @override
  void onPageBecameInactive() {
    // Inactive should cancel in-flight home-only work, but avoid invalidating
    // section providers to prevent unnecessary re-fetch/rebuild on resume.
    _heroFocusBelowRequestVersion += 1;
    _heroPrefetchCoordinator.reset();
  }

  @override
  Widget build(BuildContext context) {
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    final heroModule =
        isPageVisible ? ref.watch(homeHeroModuleProvider) : _cachedHeroModule;
    if (isPageVisible) {
      _cachedHeroModule = heroModule;
    }
    final enabledModules = isPageVisible
        ? ref.watch(homeEnabledModulesProvider)
        : _cachedEnabledModules;
    if (isPageVisible) {
      _cachedEnabledModules = enabledModules;
    }
    final resolvedSectionsState = isPageVisible
        ? ref.watch(homeResolvedSectionsProvider)
        : _cachedResolvedSectionsState;
    if (isPageVisible) {
      _cachedResolvedSectionsState = resolvedSectionsState;
    }
    final heroDisplayMode = ref.watch(
      appSettingsProvider.select((settings) => settings.homeHeroDisplayMode),
    );
    final heroSourceModuleId = ref.watch(
      appSettingsProvider.select((settings) => settings.homeHeroSourceModuleId),
    );
    final preferredHeroModuleId = heroSourceModuleId.trim();
    final preferredHeroSectionLoading = preferredHeroModuleId.isNotEmpty &&
        isPageVisible &&
        ref.watch(
          homeSectionProvider(
            preferredHeroModuleId,
          ).select((state) => state.isLoading),
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
    final homeMetadataAutoRefreshRevision = ref.watch(
      homeMetadataAutoRefreshRevisionProvider,
    );
    final homeExplicitRefreshRevision = ref.watch(
      homeExplicitRefreshRevisionProvider,
    );
    final effectiveTranslucentEffectsEnabled =
        translucentEffectsEnabled && !performanceLightweightHomeHeroEnabled;
    final effectiveHeroBackgroundEnabled = heroBackgroundEnabled;
    final simplifyHeroBackdrop = performanceLightweightHomeHeroEnabled;
    final resolvedSections = resolvedSectionsState.sections;
    final hasPendingSections = resolvedSectionsState.hasPendingSections;

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
                resolvedSections: resolvedSections,
                hasPendingSections: hasPendingSections,
                preferredHeroSectionLoading: preferredHeroSectionLoading,
                heroEnabled: heroModule?.enabled ?? false,
                heroSourceModuleId: heroSourceModuleId,
                heroLogoTitleEnabled: heroLogoTitleEnabled,
                heroBackgroundEnabled: effectiveHeroBackgroundEnabled,
                translucentEffectsEnabled: effectiveTranslucentEffectsEnabled,
                staticHomeHeroEnabled: performanceStaticHomeHeroEnabled,
                lightweightHomeHeroEnabled:
                    performanceLightweightHomeHeroEnabled,
                simplifyHeroBackdrop: simplifyHeroBackdrop,
                homeMetadataAutoRefreshRevision:
                    homeMetadataAutoRefreshRevision,
                homeExplicitRefreshRevision: homeExplicitRefreshRevision,
                isTelevision: isTelevision,
                heroDisplayMode: heroDisplayMode,
              ),
      ),
    );
  }

  Widget _buildLoadedHome({
    required BuildContext context,
    required List<HomeModuleConfig> enabledModules,
    required List<HomeSectionViewModel> resolvedSections,
    required bool hasPendingSections,
    required bool preferredHeroSectionLoading,
    required bool heroEnabled,
    required String heroSourceModuleId,
    required bool heroLogoTitleEnabled,
    required bool heroBackgroundEnabled,
    required bool translucentEffectsEnabled,
    required bool staticHomeHeroEnabled,
    required bool lightweightHomeHeroEnabled,
    required int homeMetadataAutoRefreshRevision,
    required int homeExplicitRefreshRevision,
    required bool isTelevision,
    required HomeHeroDisplayMode heroDisplayMode,
    required bool simplifyHeroBackdrop,
  }) {
    if (homeMetadataAutoRefreshRevision !=
        _observedHomeMetadataAutoRefreshRevision) {
      _heroPrefetchCoordinator.reset();
      _observedHomeMetadataAutoRefreshRevision =
          homeMetadataAutoRefreshRevision;
    }

    final featuredSection = heroEnabled
        ? _resolveStableHeroSection(
            resolvedSections: resolvedSections,
            preferredModuleId: heroSourceModuleId,
            preferredModuleLoading: preferredHeroSectionLoading,
          )
        : null;

    final featuredItems = !heroEnabled
        ? const <_FeaturedHeroItem>[]
        : _buildFeaturedItems(
            featuredSection: featuredSection,
          );
    final activeHero = _resolveActiveHeroItem(featuredItems);
    final currentHeroIds =
        featuredItems.map((item) => item.id.trim()).toList(growable: false);
    final heroListChanged = !listEquals(currentHeroIds, _lastFeaturedHeroIds);
    _lastFeaturedHeroIds = currentHeroIds;
    final heroPrefetchDecision = resolveHomeHeroPrefetchDecision(
      isPageVisible: isPageVisible,
      featuredItemCount: featuredItems.length,
      heroListChanged: heroListChanged,
      scheduledMetadataRevision: _scheduledHeroMetadataAutoRefreshRevision,
      currentMetadataRevision: homeMetadataAutoRefreshRevision,
      scheduledExplicitRevision: _scheduledHeroExplicitRefreshRevision,
      currentExplicitRevision: homeExplicitRefreshRevision,
    );
    if (heroPrefetchDecision.shouldSchedule) {
      _heroPrefetchCoordinator.schedulePrefetch(
        ref: ref,
        targets: featuredItems.map((item) => item.detailTarget),
        isPageActive: () => mounted && isPageVisible,
        forceMetadataRefresh: heroPrefetchDecision.forceMetadataRefresh,
      );
      _scheduledHeroMetadataAutoRefreshRevision =
          homeMetadataAutoRefreshRevision;
      _scheduledHeroExplicitRefreshRevision = homeExplicitRefreshRevision;
    }
    if (heroListChanged) {
      _scheduleHeroSelectionSync(activeHero);
    }
    final visibleModules = featuredSection == null
        ? enabledModules
        : enabledModules
            .where((module) => module.id != featuredSection.id)
            .toList(growable: false);
    final firstFocusableSectionId = _resolveFirstFocusableSectionId(
      enabledModules: visibleModules,
    );
    final hasHeroListSlot =
        heroEnabled && (featuredItems.isNotEmpty || hasPendingSections);
    final moduleListOffset = hasHeroListSlot ? 1 : 0;
    final listItemCount = moduleListOffset + visibleModules.length + 2;

    final content = RefreshIndicator(
      color: Colors.white,
      backgroundColor: const Color(0xFF102033),
      onRefresh: () => refreshHomeModules(ref),
      child: ListView.builder(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: EdgeInsets.zero,
        itemCount: listItemCount,
        itemBuilder: (context, index) {
          if (hasHeroListSlot && index == 0) {
            if (featuredItems.isNotEmpty) {
              return RepaintBoundary(
                child: _HomeKeepAlive(
                  child: Padding(
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
                      focusScopePrefix: 'home:hero',
                      onFocusBelowControl: _focusBelowHeroContent,
                      onFocusedItemChanged: _handleFocusedHeroChanged,
                    ),
                  ),
                ),
              );
            }
            return RepaintBoundary(
              child: _HomeKeepAlive(
                child: Padding(
                  padding: heroDisplayMode.heroPadding(context),
                  child: _HomeHeroPlaceholder(displayMode: heroDisplayMode),
                ),
              ),
            );
          }

          final moduleIndex = index - moduleListOffset;
          if (moduleIndex >= 0 && moduleIndex < visibleModules.length) {
            final module = visibleModules[moduleIndex];
            return RepaintBoundary(
              child: Padding(
                padding: EdgeInsets.only(
                  top: !heroEnabled && moduleIndex == 0 ? 20 : 0,
                  bottom: 26,
                ),
                child: _HomeSectionSlot(
                  key: ValueKey<String>('home:section-slot:${module.id}'),
                  module: module,
                  isPageVisible: isPageVisible,
                  useHeroNextSectionFocusNode:
                      module.id == firstFocusableSectionId,
                  heroNextSectionFocusNode: _heroNextSectionFocusNode,
                  homeMetadataAutoRefreshRevision:
                      homeMetadataAutoRefreshRevision,
                ),
              ),
            );
          }

          final trailingIndex = moduleIndex - visibleModules.length;
          if (trailingIndex == 0) {
            return const SizedBox(height: 6);
          }
          return const RepaintBoundary(child: _HomeEditButton());
        },
      ),
    );

    return ValueListenableBuilder<_HomeHeroSelection>(
      valueListenable: _heroSelectionNotifier,
      child: content,
      builder: (context, selection, child) {
        return _HomeShell(
          backgroundImageUrl: heroBackgroundEnabled ? selection.imageUrl : '',
          backgroundImageHeaders:
              heroBackgroundEnabled ? selection.imageHeaders : const {},
          translucentEffectsEnabled: translucentEffectsEnabled,
          simplifyHeroBackdrop: simplifyHeroBackdrop,
          child: child!,
        );
      },
    );
  }

  String? _resolveFirstFocusableSectionId({
    required List<HomeModuleConfig> enabledModules,
  }) {
    for (final module in enabledModules) {
      return module.id;
    }
    return null;
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
    final selectedHeroId = _heroSelectionNotifier.value.heroId;
    for (final item in items) {
      if (item.id == selectedHeroId) {
        return item;
      }
    }
    return items.first;
  }

  void _scheduleHeroSelectionSync(_FeaturedHeroItem? activeHero) {
    final nextSelection = activeHero == null
        ? const _HomeHeroSelection.empty()
        : _HomeHeroSelection(
            heroId: activeHero.id,
            imageUrl: activeHero.backgroundImage.url,
            imageHeaders: activeHero.backgroundImage.headers,
          );
    final current = _heroSelectionNotifier.value;
    if (current.matches(nextSelection)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final latest = _heroSelectionNotifier.value;
      if (latest.matches(nextSelection)) {
        return;
      }
      _heroSelectionNotifier.value = nextSelection;
    });
  }

  void _handleFocusedHeroChanged(_FeaturedHeroItem item) {
    _scheduleHeroSelectionSync(item);
  }

  HomeSectionViewModel? _resolveStableHeroSection({
    required List<HomeSectionViewModel> resolvedSections,
    required String preferredModuleId,
    required bool preferredModuleLoading,
  }) {
    final normalizedPreferredModuleId = preferredModuleId.trim();
    if (_lastHeroSourceModuleId != normalizedPreferredModuleId) {
      _lastHeroSourceModuleId = normalizedPreferredModuleId;
      _pinnedHeroSectionId = '';
      _lastFeaturedHeroIds = const [];
      _heroPrefetchCoordinator.reset();
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

      if (preferredModuleLoading) {
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
