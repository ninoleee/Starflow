import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/core/navigation/page_activity_mixin.dart';
import 'package:starflow/core/navigation/retained_async_value.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/utils/media_rating_labels.dart';
import 'package:starflow/core/utils/metadata_text.dart';
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
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/metadata/application/metadata_prefetch_concurrency_limiter.dart';
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

String _homeSectionItemFocusKey(
  HomeSectionViewModel section,
  HomeCardViewModel item,
) {
  return 'item:${section.id}:${_homeCardResourceIdentity(item)}';
}

String _homeCarouselItemFocusKey(
  HomeSectionViewModel section,
  HomeCarouselItemViewModel item,
) {
  return 'carousel:${section.id}:${_homeCarouselResourceIdentity(item)}';
}

String _homeCardResourceIdentity(HomeCardViewModel item) {
  return _homeResourceIdentity(
    id: item.id,
    target: item.detailTarget,
    fallbackTitle: item.title,
  );
}

String _homeCarouselResourceIdentity(HomeCarouselItemViewModel item) {
  return _homeResourceIdentity(
    id: item.id,
    target: item.detailTarget,
    fallbackTitle: item.title,
  );
}

String _homeResourceIdentity({
  required String id,
  required MediaDetailTarget target,
  required String fallbackTitle,
}) {
  final normalizedId = id.trim();
  if (normalizedId.isNotEmpty) {
    return normalizedId;
  }
  final itemId = target.itemId.trim();
  if (itemId.isNotEmpty) {
    final sourceId = target.sourceId.trim();
    return sourceId.isEmpty ? itemId : '$sourceId:$itemId';
  }
  for (final externalId in <String>[
    target.doubanId,
    target.tmdbId,
    target.imdbId,
    target.tvdbId,
    target.resourcePath,
    target.playbackTarget?.itemId ?? '',
    target.playbackTarget?.streamUrl ?? '',
  ]) {
    final normalizedExternalId = externalId.trim();
    if (normalizedExternalId.isNotEmpty) {
      return normalizedExternalId;
    }
  }
  return fallbackTitle.trim();
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
  final ValueNotifier<_HomeHeroSelection> _heroSelectionNotifier =
      ValueNotifier<_HomeHeroSelection>(const _HomeHeroSelection.empty());
  final HomeHeroPrefetchCoordinator _heroPrefetchCoordinator =
      HomeHeroPrefetchCoordinator();
  final GlobalKey<_FeaturedHeroState> _featuredHeroKey =
      GlobalKey<_FeaturedHeroState>();
  final Map<String, FocusNode> _contentFocusNodes = <String, FocusNode>{};
  final FocusNode _homeEditFocusNode =
      FocusNode(debugLabel: 'home-edit-action');
  String _firstFocusableContentKey = '';
  bool _contentFocusNodePruneScheduled = false;
  Set<String> _pendingContentFocusNodeKeys = const <String>{};
  int _heroFocusBelowRequestVersion = 0;
  List<String> _lastFeaturedHeroIds = const [];
  String _lastFeaturedHeroSectionId = '';
  int _observedHomeMetadataAutoRefreshRevision = 0;
  int _observedHomeNavigationResetRevision = 0;
  int _scheduledHeroMetadataAutoRefreshRevision = 0;
  int _scheduledHeroExplicitRefreshRevision = 0;
  bool _contentLoadingDeferralActive = false;
  bool _missingFocusRecoveryScheduled = false;
  int _missingFocusRecoveryVersion = 0;
  bool _hasPendingSections = false;
  List<String> _observedEnabledModuleIds = const <String>[];
  bool _didObserveEnabledModuleIds = false;
  List<String> _observedFocusableSectionIds = const <String>[];
  bool _didObserveFocusableSectionIds = false;
  List<String> _observedFocusTopology = const <String>[];
  bool _didObserveFocusTopology = false;

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
  void initState() {
    super.initState();
    _scrollController.addListener(_deferPrefetchForForegroundInteraction);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (final focusNode in _contentFocusNodes.values) {
      focusNode.dispose();
    }
    _contentFocusNodes.clear();
    _homeEditFocusNode.dispose();
    _heroSelectionNotifier.dispose();
    super.dispose();
  }

  @override
  void onPageBecameActive() {
    _deferPrefetchForForegroundInteraction(reason: 'home.page-active');
    _scheduleMissingFocusRecovery(reason: 'page-active');
    // Keep stable cached sections when returning to home, and only warm data
    // sources opportunistically.
    primeHomeModulesFromWidget(ref);
  }

  void _deferPrefetchForForegroundInteraction({
    String reason = 'home.scroll',
  }) {
    if (!mounted || !isPageVisible) {
      return;
    }
    ref
        .read(metadataPrefetchConcurrencyLimiterProvider)
        .deferForForegroundInteraction(
          reason: reason,
          resumeDelay: Duration(
            milliseconds: ref
                .read(appSettingsProvider)
                .metadataPrefetchForegroundResumeDelayMs,
          ),
        );
  }

  void _deferPrefetchWhileContentLoading(bool isLoading) {
    if (!isLoading) {
      _contentLoadingDeferralActive = false;
      return;
    }
    if (_contentLoadingDeferralActive) {
      return;
    }
    _contentLoadingDeferralActive = true;
    _deferPrefetchForForegroundInteraction(reason: 'home.content-loading');
  }

  void _scheduleMissingFocusRecovery({required String reason}) {
    if (!(ref.read(isTelevisionProvider).value ?? false)) {
      return;
    }
    if (_missingFocusRecoveryScheduled) {
      return;
    }
    _missingFocusRecoveryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _missingFocusRecoveryScheduled = false;
      if (!mounted || !_isHomeRouteVisible) {
        return;
      }
      unawaited(_recoverMissingHomeFocus(reason: reason));
    });
  }

  Future<void> _recoverMissingHomeFocus({required String reason}) async {
    final requestVersion = ++_missingFocusRecoveryVersion;
    if (!mounted || !_isHomeRouteVisible) {
      return;
    }
    var primaryFocus = FocusManager.instance.primaryFocus;
    if (_isFirstHomeTarget(primaryFocus)) {
      _ensureFocusNodeVisible(primaryFocus!);
      return;
    }
    if (_hasActionableHomeFocus(primaryFocus)) {
      return;
    }
    if (_requestFirstHomeContentFocus()) {
      return;
    }

    final hasKnownOffscreenTarget = _firstFocusableContentKey.isNotEmpty ||
        (!_hasPendingSections && _homeEditFocusNode.context == null);
    if (hasKnownOffscreenTarget &&
        await _revealAndRequestFirstHomeContentFocus(requestVersion)) {
      return;
    }

    if (!mounted ||
        requestVersion != _missingFocusRecoveryVersion ||
        !_isHomeRouteVisible) {
      return;
    }
    primaryFocus = FocusManager.instance.primaryFocus;
    if (_isFirstHomeTarget(primaryFocus)) {
      _ensureFocusNodeVisible(primaryFocus!);
      return;
    }
    if (_hasActionableHomeFocus(primaryFocus) ||
        _requestFirstHomeContentFocus()) {
      return;
    }
    final menuScope = TvMenuButtonScope.maybeOf(context);
    if (menuScope == null) {
      return;
    }
    appLogInfo(
      'tv.focus-recovery',
      'Home focus recovery requested',
      fields: <String, Object?>{
        'reason': reason,
        'previousFocus': describeTvFocusNode(primaryFocus),
        'previousFocusType': primaryFocus?.runtimeType.toString() ?? 'none',
        'contextAttached': primaryFocus?.context != null,
        'canRequestFocus': primaryFocus?.canRequestFocus ?? false,
      },
    );
    menuScope.onMenuButtonPressed();
  }

  Future<bool> _revealAndRequestFirstHomeContentFocus(
    int requestVersion,
  ) {
    return _scrollUntilFirstHomeTargetCanFocus(
      isRequestActive: () =>
          mounted &&
          requestVersion == _missingFocusRecoveryVersion &&
          _isHomeRouteVisible,
      shouldStopForFocus: _hasActionableHomeFocus,
    );
  }

  Future<bool> _scrollUntilFirstHomeTargetCanFocus({
    required bool Function() isRequestActive,
    required bool Function(FocusNode? focus) shouldStopForFocus,
  }) async {
    if (!_scrollController.hasClients) {
      await _waitForNextFrame();
    }
    if (!isRequestActive() || !_scrollController.hasClients) {
      return false;
    }

    final initialOffset = _scrollController.offset;
    var lastOffset = initialOffset;
    var stalledFrames = 0;
    for (var attempt = 0; attempt < 40; attempt += 1) {
      if (!isRequestActive()) {
        return false;
      }
      final primaryFocus = FocusManager.instance.primaryFocus;
      if (_isFirstHomeTarget(primaryFocus)) {
        _ensureFocusNodeVisible(primaryFocus!);
        return true;
      }
      if (shouldStopForFocus(primaryFocus)) {
        return true;
      }
      if (_requestFirstHomeContentFocus()) {
        return true;
      }
      if (!_scrollController.hasClients) {
        break;
      }

      final position = _scrollController.position;
      final viewportStep = position.viewportDimension.isFinite
          ? position.viewportDimension * 0.72
          : 360.0;
      final nextOffset = (position.pixels + viewportStep)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if ((nextOffset - lastOffset).abs() < 1) {
        stalledFrames += 1;
        if (stalledFrames >= 2) {
          break;
        }
      } else {
        stalledFrames = 0;
        lastOffset = nextOffset;
        position.jumpTo(nextOffset);
      }
      await _waitForNextFrame();
    }

    if (isRequestActive() &&
        _scrollController.hasClients &&
        !shouldStopForFocus(FocusManager.instance.primaryFocus)) {
      final position = _scrollController.position;
      position.jumpTo(
        initialOffset
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble(),
      );
    }
    return false;
  }

  bool _isFirstHomeTarget(FocusNode? focus) {
    if (focus == null) {
      return false;
    }
    final contentTarget = _contentFocusNodes[_firstFocusableContentKey];
    if (contentTarget != null &&
        contentTarget.context != null &&
        contentTarget.canRequestFocus) {
      return identical(focus, contentTarget);
    }
    return _firstFocusableContentKey.isEmpty &&
        _homeEditFocusNode.context != null &&
        _homeEditFocusNode.canRequestFocus &&
        identical(focus, _homeEditFocusNode);
  }

  void _ensureFocusNodeVisible(FocusNode focusNode) {
    final focusContext = focusNode.context;
    if (focusContext == null) {
      return;
    }
    unawaited(
      Scrollable.ensureVisible(
        focusContext,
        alignment: 0.52,
        duration: Duration.zero,
      ),
    );
  }

  bool get _isHomeRouteVisible {
    final route = ModalRoute.of(context);
    return isPageVisible &&
        TickerMode.valuesOf(context).enabled &&
        (route?.isCurrent ?? true);
  }

  bool _hasActionableHomeFocus(FocusNode? focus) {
    final focusContext = focus?.context;
    if (focus == null ||
        focus is FocusScopeNode ||
        focusContext == null ||
        !focus.canRequestFocus) {
      return false;
    }
    final focusRoute = ModalRoute.of(focusContext);
    if (focusRoute == null) {
      // The TV sidebar lives outside the branch route and remains actionable.
      return true;
    }
    final homeRoute = ModalRoute.of(context);
    return focusRoute == homeRoute && (homeRoute?.isCurrent ?? true);
  }

  @override
  void onPageBecameInactive() {
    // Inactive should cancel in-flight home-only work, but avoid invalidating
    // section providers to prevent unnecessary re-fetch/rebuild on resume.
    _heroFocusBelowRequestVersion += 1;
    _missingFocusRecoveryVersion += 1;
    _heroPrefetchCoordinator.reset();
  }

  @override
  Widget build(BuildContext context) {
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    ref.listen<bool>(
      homeResolvedSectionsProvider.select(
        (state) => state.hasPendingSections,
      ),
      (previous, next) {
        if (isTelevision && previous == true && !next) {
          _scheduleMissingFocusRecovery(reason: 'content-loaded');
        }
      },
    );
    final heroModule = ref.watch(homeHeroModuleProvider);
    final enabledModules = ref.watch(homeEnabledModulesProvider);
    final enabledModuleIds =
        enabledModules.map((module) => module.id).toList(growable: false);
    if (!listEquals(enabledModuleIds, _observedEnabledModuleIds)) {
      final shouldRecoverFocus = _didObserveEnabledModuleIds;
      _didObserveEnabledModuleIds = true;
      _observedEnabledModuleIds = enabledModuleIds;
      _heroFocusBelowRequestVersion += 1;
      if (shouldRecoverFocus) {
        _scheduleMissingFocusRecovery(reason: 'modules-changed');
      }
    }
    final resolvedSectionsState = ref.watch(homeResolvedSectionsProvider);
    final heroDisplayMode = ref.watch(
      appSettingsProvider.select((settings) => settings.homeHeroDisplayMode),
    );
    final heroSourceModuleId = ref.watch(
      appSettingsProvider.select((settings) => settings.homeHeroSourceModuleId),
    );
    final preferredHeroModuleId = heroSourceModuleId.trim();
    final preferredHeroSectionLoading = preferredHeroModuleId.isNotEmpty &&
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
    final lightweightHomeHeroEnabled = ref.watch(
      appSettingsProvider.select(
        (settings) => settings.effectiveLightweightHomeHeroEnabled(
          isTelevision: isTelevision,
        ),
      ),
    );
    final homeMetadataAutoRefreshRevision = ref.watch(
      homeMetadataAutoRefreshRevisionProvider,
    );
    final homeExplicitRefreshRevision = ref.watch(
      homeExplicitRefreshRevisionProvider,
    );
    final homeNavigationResetRevision = ref.watch(
      homeNavigationResetRevisionProvider,
    );
    if (homeNavigationResetRevision != _observedHomeNavigationResetRevision) {
      _observedHomeNavigationResetRevision = homeNavigationResetRevision;
      _heroFocusBelowRequestVersion += 1;
      _heroPrefetchCoordinator.reset();
      _scheduleMissingFocusRecovery(reason: 'navigation-reset');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _jumpToHeroTop();
        }
      });
    }
    final effectiveTranslucentEffectsEnabled =
        translucentEffectsEnabled && !lightweightHomeHeroEnabled;
    final effectiveHeroBackgroundEnabled = heroBackgroundEnabled;
    final simplifyHeroBackdrop = lightweightHomeHeroEnabled;
    final resolvedSections = resolvedSectionsState.sections;
    final hasPendingSections = resolvedSectionsState.hasPendingSections;
    _hasPendingSections = hasPendingSections;
    final focusTopology = _resolveHomeFocusTopology(resolvedSections);
    if (!hasPendingSections) {
      _scheduleContentFocusNodePrune(focusTopology.toSet());
    }
    if (!listEquals(focusTopology, _observedFocusTopology)) {
      final shouldRecoverFocus = _didObserveFocusTopology;
      _didObserveFocusTopology = true;
      _observedFocusTopology = focusTopology;
      if (shouldRecoverFocus) {
        _scheduleMissingFocusRecovery(reason: 'focus-content-changed');
      }
    }
    final shouldAutofocusHomeTarget = isTelevision &&
        _isHomeRouteVisible &&
        !_hasActionableHomeFocus(FocusManager.instance.primaryFocus);
    _deferPrefetchWhileContentLoading(hasPendingSections);

    return AppPrimaryScrollController(
      controller: _scrollController,
      child: TvPageFocusScope(
        isTelevision: isTelevision,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: enabledModules.isEmpty
              ? _HomeShell(
                  backgroundImageUrl: '',
                  backgroundImageHeaders: {},
                  child: _EmptyHomeState(
                    editFocusNode: isTelevision ? _homeEditFocusNode : null,
                    autofocusEdit: shouldAutofocusHomeTarget,
                  ),
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
                  lightweightHomeHeroEnabled: lightweightHomeHeroEnabled,
                  simplifyHeroBackdrop: simplifyHeroBackdrop,
                  homeMetadataAutoRefreshRevision:
                      homeMetadataAutoRefreshRevision,
                  homeExplicitRefreshRevision: homeExplicitRefreshRevision,
                  homeNavigationResetRevision: homeNavigationResetRevision,
                  isTelevision: isTelevision,
                  shouldAutofocusHomeTarget: shouldAutofocusHomeTarget,
                  heroDisplayMode: heroDisplayMode,
                ),
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
    required int homeNavigationResetRevision,
    required bool isTelevision,
    required bool shouldAutofocusHomeTarget,
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
    final featuredHeroSectionId = featuredSection?.id ?? '';
    final heroSectionChanged =
        featuredHeroSectionId != _lastFeaturedHeroSectionId;
    _lastFeaturedHeroSectionId = featuredHeroSectionId;
    final activeHero = heroSectionChanged
        ? featuredItems.firstOrNull
        : _resolveActiveHeroItem(featuredItems);
    final currentHeroIds =
        featuredItems.map((item) => item.id.trim()).toList(growable: false);
    final heroListChanged =
        heroSectionChanged || !listEquals(currentHeroIds, _lastFeaturedHeroIds);
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
      _scheduleMissingFocusRecovery(reason: 'hero-content-changed');
    }
    // Hero references a section; it does not consume that module's normal
    // slot. Keeping both avoids a first module (often Recent Playback)
    // disappearing whenever automatic Hero selection pins it.
    final visibleModules = enabledModules;
    final focusableSectionIds = _resolveFocusableSectionIds(
      enabledModules: visibleModules,
      resolvedSections: resolvedSections,
    );
    if (!listEquals(focusableSectionIds, _observedFocusableSectionIds)) {
      final shouldRecoverFocus = _didObserveFocusableSectionIds;
      _didObserveFocusableSectionIds = true;
      _observedFocusableSectionIds = focusableSectionIds;
      if (shouldRecoverFocus) {
        _scheduleMissingFocusRecovery(reason: 'focusable-sections-changed');
      }
    }
    final firstFocusableSectionId = focusableSectionIds.firstOrNull;
    _firstFocusableContentKey = _resolveFirstFocusableContentKey(
          enabledModules: visibleModules,
          resolvedSections: resolvedSections,
        ) ??
        '';
    final hasHeroListSlot =
        heroEnabled && (featuredItems.isNotEmpty || hasPendingSections);
    final moduleListOffset = hasHeroListSlot ? 1 : 0;
    final listItemCount = moduleListOffset + visibleModules.length + 2;
    const heroListKey = ValueKey<String>('home:list:hero');
    const spacerListKey = ValueKey<String>('home:list:spacer');
    const editListKey = ValueKey<String>('home:list:edit');
    final moduleListKeys = <String, Key>{
      for (final module in visibleModules)
        module.id: ValueKey<String>('home:list:module:${module.id}'),
    };
    final listIndicesByKey = <Key, int>{
      if (hasHeroListSlot) heroListKey: 0,
      for (var index = 0; index < visibleModules.length; index += 1)
        moduleListKeys[visibleModules[index].id]!: moduleListOffset + index,
      spacerListKey: moduleListOffset + visibleModules.length,
      editListKey: moduleListOffset + visibleModules.length + 1,
    };

    final content = RefreshIndicator(
      color: Colors.white,
      backgroundColor: const Color(0xFF102033),
      onRefresh: () => refreshHomeModules(ref, allowNetworkProbe: true),
      child: ListView.builder(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: EdgeInsets.zero,
        itemCount: listItemCount,
        findChildIndexCallback: (key) => listIndicesByKey[key],
        itemBuilder: (context, index) {
          if (hasHeroListSlot && index == 0) {
            if (featuredItems.isNotEmpty) {
              return RepaintBoundary(
                key: heroListKey,
                child: _HomeKeepAlive(
                  child: Padding(
                    padding: heroDisplayMode.heroPadding(context),
                    child: _FeaturedHero(
                      key: _featuredHeroKey,
                      items: featuredItems,
                      contentScopeId: featuredHeroSectionId,
                      isTelevision: isTelevision,
                      staticModeEnabled: staticHomeHeroEnabled,
                      lightweightVisualEnabled: lightweightHomeHeroEnabled,
                      showPagerButtons: _showHeroPagerButtons || isTelevision,
                      logoTitleEnabled: heroLogoTitleEnabled,
                      translucentEffectsEnabled: translucentEffectsEnabled,
                      displayMode: heroDisplayMode,
                      focusScopePrefix: 'home:hero',
                      autofocusCurrentItem: shouldAutofocusHomeTarget,
                      onFocusBelowControl: _focusBelowHeroContent,
                      onHeroFocusGained: _jumpToHeroTop,
                      onFocusedItemChanged: _handleFocusedHeroChanged,
                    ),
                  ),
                ),
              );
            }
            return RepaintBoundary(
              key: heroListKey,
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
              key: moduleListKeys[module.id],
              child: Padding(
                padding: EdgeInsets.only(
                  top: !heroEnabled && moduleIndex == 0 ? 20 : 0,
                  bottom: 26,
                ),
                child: _HomeSectionSlot(
                  key: ValueKey<String>('home:section-slot:${module.id}'),
                  module: module,
                  isPageVisible: isPageVisible,
                  focusNodeForContent: _focusNodeForContent,
                  autofocusFirstItem: shouldAutofocusHomeTarget &&
                      !hasHeroListSlot &&
                      module.id == firstFocusableSectionId,
                  homeMetadataAutoRefreshRevision:
                      homeMetadataAutoRefreshRevision,
                  homeNavigationResetRevision: homeNavigationResetRevision,
                ),
              ),
            );
          }

          final trailingIndex = moduleIndex - visibleModules.length;
          if (trailingIndex == 0) {
            return const SizedBox(key: spacerListKey, height: 6);
          }
          return RepaintBoundary(
            key: editListKey,
            child: _HomeEditButton(
              focusNode:
                  firstFocusableSectionId == null ? _homeEditFocusNode : null,
              autofocus: shouldAutofocusHomeTarget &&
                  !hasHeroListSlot &&
                  firstFocusableSectionId == null,
            ),
          );
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

  List<String> _resolveFocusableSectionIds({
    required List<HomeModuleConfig> enabledModules,
    required List<HomeSectionViewModel> resolvedSections,
  }) {
    final focusableSectionIds = <String>{
      for (final section in resolvedSections)
        if (section.items.isNotEmpty || section.carouselItems.isNotEmpty)
          section.id,
    };
    return enabledModules
        .map((module) => module.id)
        .where(focusableSectionIds.contains)
        .toList(growable: false);
  }

  String? _resolveFirstFocusableContentKey({
    required List<HomeModuleConfig> enabledModules,
    required List<HomeSectionViewModel> resolvedSections,
  }) {
    final sectionsById = <String, HomeSectionViewModel>{
      for (final section in resolvedSections) section.id: section,
    };
    for (final module in enabledModules) {
      final section = sectionsById[module.id];
      if (section == null) {
        continue;
      }
      if (section.items.isNotEmpty) {
        return _homeSectionItemFocusKey(section, section.items.first);
      }
      if (section.carouselItems.isNotEmpty) {
        return _homeCarouselItemFocusKey(
          section,
          section.carouselItems.first,
        );
      }
    }
    return null;
  }

  FocusNode _focusNodeForContent(String focusKey) {
    return _contentFocusNodes.putIfAbsent(
      focusKey,
      () => FocusNode(debugLabel: 'home-content:$focusKey'),
    );
  }

  void _scheduleContentFocusNodePrune(Set<String> validFocusKeys) {
    _pendingContentFocusNodeKeys = Set<String>.from(validFocusKeys);
    if (_contentFocusNodePruneScheduled) {
      return;
    }
    _contentFocusNodePruneScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _contentFocusNodePruneScheduled = false;
      if (!mounted) {
        return;
      }
      final retainedKeys = _pendingContentFocusNodeKeys;
      final obsoleteKeys = _contentFocusNodes.keys
          .where((focusKey) => !retainedKeys.contains(focusKey))
          .toList(growable: false);
      for (final focusKey in obsoleteKeys) {
        _contentFocusNodes.remove(focusKey)?.dispose();
      }
    });
  }

  List<String> _resolveHomeFocusTopology(
    List<HomeSectionViewModel> sections,
  ) {
    return <String>[
      for (final section in sections) ...<String>[
        'section:${section.id}:${section.layout.name}',
        for (final item in section.items)
          _homeSectionItemFocusKey(section, item),
        for (final item in section.carouselItems)
          _homeCarouselItemFocusKey(section, item),
        if (section.viewAllTarget != null) _homeSectionViewAllFocusKey(section),
      ],
    ];
  }

  void _focusBelowHeroContent() {
    unawaited(_focusBelowHeroContentAsync());
  }

  void _jumpToHeroTop() {
    if (!_scrollController.hasClients) {
      return;
    }
    final targetOffset = _scrollController.position.minScrollExtent;
    if ((_scrollController.offset - targetOffset).abs() < 1) {
      return;
    }
    _scrollController.jumpTo(targetOffset);
  }

  Future<void> _focusBelowHeroContentAsync() async {
    final requestVersion = ++_heroFocusBelowRequestVersion;
    final sourceFocus = FocusManager.instance.primaryFocus;
    if (_requestFirstHomeContentFocus()) {
      return;
    }
    final focusedTarget = await _scrollUntilFirstHomeTargetCanFocus(
      isRequestActive: () =>
          mounted &&
          requestVersion == _heroFocusBelowRequestVersion &&
          _isHomeRouteVisible &&
          (sourceFocus?.hasFocus ?? false),
      shouldStopForFocus: (focus) =>
          !identical(focus, sourceFocus) && _hasActionableHomeFocus(focus),
    );
    if (focusedTarget ||
        !mounted ||
        requestVersion != _heroFocusBelowRequestVersion ||
        !(sourceFocus?.hasFocus ?? false)) {
      return;
    }

    handleTvDirectionalFocusBoundary(
      context,
      TraversalDirection.down,
    );
  }

  bool _requestHeroNextSectionFocus() {
    final targetNode = _contentFocusNodes[_firstFocusableContentKey];
    final targetContext = targetNode?.context;
    if (targetNode == null ||
        targetContext == null ||
        !targetNode.canRequestFocus) {
      return false;
    }
    requestTvFocus(
      targetNode,
      scope: FocusScope.of(targetContext),
    );
    unawaited(
      Scrollable.ensureVisible(
        targetContext,
        alignment: 0.52,
        duration: Duration.zero,
      ),
    );
    return true;
  }

  bool _requestFirstHomeContentFocus() {
    if (_requestHeroNextSectionFocus()) {
      return true;
    }
    if (_firstFocusableContentKey.isNotEmpty) {
      return false;
    }
    final editContext = _homeEditFocusNode.context;
    if (editContext == null || !_homeEditFocusNode.canRequestFocus) {
      return false;
    }
    requestTvFocus(
      _homeEditFocusNode,
      scope: FocusScope.of(editContext),
    );
    unawaited(
      Scrollable.ensureVisible(
        editContext,
        alignment: 0.52,
        duration: Duration.zero,
      ),
    );
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
