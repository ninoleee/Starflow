import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/app/theme/app_colors.dart';
import 'package:starflow/app/router/home_navigation_tap_coordinator.dart';
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/core/platform/application_exit.dart';
import 'package:starflow/core/platform/android_picture_in_picture.dart';
import 'package:starflow/core/platform/background_playback.dart';
import 'package:starflow/core/platform/playback_system_session.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/starflow_action_dialog.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/bootstrap/application/startup_crash_recovery.dart';
import 'package:starflow/features/home/application/home_controller.dart';
import 'package:starflow/features/home/application/home_feed_load_scheduler.dart';
import 'package:starflow/features/home/application/home_metadata_auto_refresh.dart';
import 'package:starflow/features/library/application/media_refresh_coordinator.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/metadata/application/metadata_prefetch_concurrency_limiter.dart';
import 'package:starflow/features/playback/application/active_playback_cleanup.dart';
import 'package:starflow/features/playback/application/playback_session.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

const _kBottomNavShellRadius = 34.0;
const _kBottomNavItemRadius = AppRadii.pill;

final _navigationTranslucentEffectsProvider = Provider<bool>((ref) {
  return ref.watch(appSettingsProvider.select(
    (settings) => settings.effectiveTranslucentEffectsEnabled,
  ));
});

final _navigationAutoHideProvider = Provider<bool>((ref) {
  return ref.watch(appSettingsProvider.select(
    (settings) => settings.effectiveNavigationAutoHideEnabled,
  ));
});

final _navigationStaticNavigationProvider = Provider<bool>((ref) {
  return ref.watch(appSettingsProvider.select(
    (settings) => settings.effectiveStaticNavigationEnabled,
  ));
});

final _navigationAnimationEnabledProvider = Provider<bool>((ref) {
  return ref.watch(appSettingsProvider.select(
    (settings) => settings.effectiveNavigationAnimationEnabled,
  ));
});
const _navigationItems = <_NavigationItemData>[
  _NavigationItemData(
    id: kNavigationDestinationHome,
    branchIndex: 0,
    label: '首页',
    icon: Icons.space_dashboard_outlined,
    selectedIcon: Icons.space_dashboard_rounded,
  ),
  _NavigationItemData(
    id: kNavigationDestinationSearch,
    branchIndex: 1,
    label: '搜索',
    icon: Icons.search_rounded,
    selectedIcon: Icons.search_rounded,
  ),
  _NavigationItemData(
    id: kNavigationDestinationFavorites,
    branchIndex: 2,
    label: '收藏',
    icon: Icons.favorite_border_rounded,
    selectedIcon: Icons.favorite_rounded,
  ),
  _NavigationItemData(
    id: kNavigationDestinationLibrary,
    branchIndex: 3,
    label: '媒体库',
    icon: Icons.video_library_outlined,
    selectedIcon: Icons.video_library_rounded,
  ),
  _NavigationItemData(
    id: kNavigationDestinationSettings,
    branchIndex: 4,
    label: '设置',
    icon: Icons.tune_outlined,
    selectedIcon: Icons.tune_rounded,
  ),
];

class AppNavigationShell extends ConsumerStatefulWidget {
  const AppNavigationShell({
    required this.navigationShell,
    super.key,
  });

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppNavigationShell> createState() => _AppNavigationShellState();
}

class _AppNavigationShellState extends ConsumerState<AppNavigationShell>
    with WidgetsBindingObserver {
  static const int _homeBranchIndex = 0;
  bool _isBottomBarVisible = true;
  bool _coldStartHomeRefreshScheduled = false;
  int _tvFocusRecoveryRevision = 0;
  final HomeNavigationTapCoordinator _homeNavigationTapCoordinator =
      HomeNavigationTapCoordinator();
  MetadataPrefetchForegroundLease? _exitDialogPrefetchLease;
  ProviderSubscription<bool>? _autoHideNavigationBarSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _autoHideNavigationBarSubscription = ref.listenManual<bool>(
      _navigationAutoHideProvider,
      (previous, next) {
        if (!next) {
          _setBottomBarVisible(true);
        }
      },
    );
    _scheduleColdStartHomeRefresh();
  }

  void _scheduleColdStartHomeRefresh() {
    if (_coldStartHomeRefreshScheduled) {
      return;
    }
    _coldStartHomeRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runColdStartHomeRefresh());
    });
  }

  Future<void> _runColdStartHomeRefresh() async {
    if (!mounted) {
      return;
    }
    try {
      if (ref.read(startupCrashRecoveryActiveProvider)) {
        appLogTrace(
          'home.refresh',
          'Cold start home refresh skipped',
          fields: const <String, Object?>{
            'reason': 'temporary-startup-recovery',
            'savedSettingsChanged': false,
          },
        );
        return;
      }
      final settings = ref.read(appSettingsProvider);
      if (!settings.homeStartupAutoRefreshEnabled) {
        return;
      }
      final startupRefreshCompleted =
          ref.read(homeExplicitRefreshRevisionProvider) > 0;
      if (startupRefreshCompleted) {
        appLogTrace(
          'home.refresh',
          'Cold start home refresh skipped',
          fields: const <String, Object?>{
            'reason': 'already-refreshed-during-bootstrap',
          },
        );
      } else {
        await refreshHomeModules(ref);
      }
      final isTelevision =
          await ref.read(isTelevisionProvider.future).catchError((_) => false);
      if (!mounted) {
        return;
      }
      final embyEffective = settings.effectiveHomeStartupAutoRefreshEmbyEnabled(
        isTelevision: isTelevision,
      );
      if (embyEffective) {
        unawaited(_refreshHomeEmbySources());
      }
    } finally {
      unawaited(
        startupCrashRecovery.completeStartup().catchError((_) {}),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _exitDialogPrefetchLease?.release(resumeDelay: Duration.zero);
    _exitDialogPrefetchLease = null;
    _homeNavigationTapCoordinator.dispose();
    _autoHideNavigationBarSubscription?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _requestTvFocusRecovery();
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }

    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.reverse) {
        _setBottomBarVisible(false);
      } else if (notification.direction == ScrollDirection.forward) {
        _setBottomBarVisible(true);
      }
    }

    return false;
  }

  void _setBottomBarVisible(bool visible) {
    if (_isBottomBarVisible == visible || !mounted) {
      return;
    }
    setState(() {
      _isBottomBarVisible = visible;
    });
  }

  void _handleDestinationSelected(int index) {
    _setBottomBarVisible(true);
    if (index != _homeBranchIndex) {
      _homeNavigationTapCoordinator.cancel();
      widget.navigationShell.goBranch(index);
      _requestTvFocusRecovery();
      return;
    }

    final wasAlreadyOnHome =
        widget.navigationShell.currentIndex == _homeBranchIndex;
    widget.navigationShell.goBranch(index);
    _requestTvFocusRecovery();
    final singleTapCleanupEnabled =
        ref.read(appSettingsProvider).homeNavigationSingleTapCleanupEnabled;
    if (!singleTapCleanupEnabled) {
      _homeNavigationTapCoordinator.cancel();
      if (wasAlreadyOnHome) {
        _refreshHomeFromNavigation();
      }
      return;
    }
    _homeNavigationTapCoordinator.registerTap(
      onSingleTap: () {
        if (mounted) {
          unawaited(_handleHomeSingleTap());
        }
      },
      onDoubleTap: _refreshHomeFromNavigation,
    );
  }

  Future<void> _handleHomeSingleTap() async {
    ref.read(homeNavigationResetRevisionProvider.notifier).state += 1;
    ref.read(homeFeedLoadSchedulerProvider).recoverAfterUserNavigation();
    ref
        .read(metadataPrefetchConcurrencyLimiterProvider)
        .recoverAfterUserNavigation();
    await ref.read(mediaRefreshCoordinatorProvider).cancelBackgroundTasks();
  }

  void _handleExitDialogVisibilityChanged(bool visible) {
    if (visible) {
      _exitDialogPrefetchLease ??= ref
          .read(metadataPrefetchConcurrencyLimiterProvider)
          .beginForegroundWork(
            reason: 'app-exit-confirmation',
            resumeDelay: Duration.zero,
          );
      return;
    }
    _exitDialogPrefetchLease?.release(resumeDelay: Duration.zero);
    _exitDialogPrefetchLease = null;
    _requestTvFocusRecovery();
  }

  void _requestTvFocusRecovery() {
    if (!mounted || !(ref.read(isTelevisionProvider).value ?? false)) {
      return;
    }
    setState(() {
      _tvFocusRecoveryRevision += 1;
    });
  }

  void _refreshHomeFromNavigation() {
    unawaited(refreshHomeModules(ref, allowNetworkProbe: true));
    unawaited(_refreshHomeEmbySources());
  }

  Future<void> _refreshHomeEmbySources() async {
    final sourceIds = ref
        .read(appSettingsProvider)
        .mediaSources
        .where(
          (source) =>
              source.enabled &&
              source.kind == MediaSourceKind.emby &&
              source.hasActiveSession,
        )
        .map((source) => source.id.trim())
        .where((sourceId) => sourceId.isNotEmpty)
        .toList(growable: false);
    if (sourceIds.isEmpty) {
      return;
    }
    await ref
        .read(mediaRefreshCoordinatorProvider)
        .startBackgroundEmbyRefresh(sourceIds: sourceIds);
  }

  @override
  Widget build(BuildContext context) {
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    final backgroundAnimationsSuspended =
        ref.watch(backgroundAnimationsSuspendedProvider);
    final translucentEffectsEnabled =
        ref.watch(_navigationTranslucentEffectsProvider);
    final autoHideNavigationBarEnabled = ref.watch(_navigationAutoHideProvider);
    final performanceStaticNavigationEnabled =
        ref.watch(_navigationStaticNavigationProvider);
    final navigationAnimationEnabled =
        ref.watch(_navigationAnimationEnabledProvider);
    final visibleNavigationIds = ref.watch(
      appSettingsProvider
          .select((settings) => settings.navigationDestinationIds),
    );
    final visibleNavigationItems = _navigationItems
        .where((item) => visibleNavigationIds.contains(item.id))
        .toList(growable: false);
    final navigationAnimationDuration = navigationAnimationEnabled
        ? const Duration(milliseconds: 220)
        : Duration.zero;
    final navigationOpacityDuration = navigationAnimationEnabled
        ? const Duration(milliseconds: 180)
        : Duration.zero;
    final bottomBarVisible =
        !autoHideNavigationBarEnabled || _isBottomBarVisible;
    final shellChild = HeroMode(
      enabled: !backgroundAnimationsSuspended,
      child: TickerMode(
        enabled: !backgroundAnimationsSuspended,
        child: IgnorePointer(
          ignoring: backgroundAnimationsSuspended,
          child: widget.navigationShell,
        ),
      ),
    );
    final bottomNavigationBarChild = Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: Material(
        color: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_kBottomNavShellRadius),
          child: translucentEffectsEnabled
              ? BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(_kBottomNavShellRadius),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                      color: const Color(0x1A0F1622),
                    ),
                    child: _FloatingNavigationBar(
                      items: visibleNavigationItems,
                      currentIndex: widget.navigationShell.currentIndex,
                      staticNavigationEnabled:
                          performanceStaticNavigationEnabled,
                      onDestinationSelected: _handleDestinationSelected,
                    ),
                  ),
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_kBottomNavShellRadius),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                    color: AppColors.neutral3.withValues(alpha: 0.95),
                  ),
                  child: _FloatingNavigationBar(
                    items: visibleNavigationItems,
                    currentIndex: widget.navigationShell.currentIndex,
                    staticNavigationEnabled: performanceStaticNavigationEnabled,
                    onDestinationSelected: _handleDestinationSelected,
                  ),
                ),
        ),
      ),
    );

    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: isTelevision
          ? _TelevisionNavigationShell(
              key: ValueKey(
                visibleNavigationItems.map((item) => item.id).join(','),
              ),
              items: visibleNavigationItems,
              currentIndex: widget.navigationShell.currentIndex,
              onDestinationSelected: _handleDestinationSelected,
              onExitDialogVisibilityChanged: _handleExitDialogVisibilityChanged,
              focusRecoveryRevision: _tvFocusRecoveryRevision,
              translucentEffectsEnabled: translucentEffectsEnabled,
              autoHideNavigationBarEnabled: autoHideNavigationBarEnabled,
              staticNavigationEnabled: performanceStaticNavigationEnabled,
              navigationAnimationEnabled: navigationAnimationEnabled,
              child: shellChild,
            )
          : NotificationListener<ScrollNotification>(
              onNotification: autoHideNavigationBarEnabled
                  ? _handleScrollNotification
                  : (_) => false,
              child: shellChild,
            ),
      bottomNavigationBar: isTelevision
          ? null
          : navigationAnimationEnabled
              ? IgnorePointer(
                  ignoring: !bottomBarVisible,
                  child: AnimatedSlide(
                    offset:
                        bottomBarVisible ? Offset.zero : const Offset(0, 1.2),
                    duration: navigationAnimationDuration,
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      opacity: bottomBarVisible ? 1 : 0,
                      duration: navigationOpacityDuration,
                      curve: Curves.easeOutCubic,
                      child: bottomNavigationBarChild,
                    ),
                  ),
                )
              : Offstage(
                  offstage: !bottomBarVisible,
                  child: bottomNavigationBarChild,
                ),
    );
  }
}

class _TelevisionNavigationShell extends StatefulWidget {
  const _TelevisionNavigationShell({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.onExitDialogVisibilityChanged,
    required this.focusRecoveryRevision,
    required this.child,
    required this.translucentEffectsEnabled,
    required this.autoHideNavigationBarEnabled,
    required this.staticNavigationEnabled,
    required this.navigationAnimationEnabled,
  });

  final int currentIndex;
  final List<_NavigationItemData> items;
  final ValueChanged<int> onDestinationSelected;
  final ValueChanged<bool> onExitDialogVisibilityChanged;
  final int focusRecoveryRevision;
  final Widget child;
  final bool translucentEffectsEnabled;
  final bool autoHideNavigationBarEnabled;
  final bool staticNavigationEnabled;
  final bool navigationAnimationEnabled;

  @override
  State<_TelevisionNavigationShell> createState() =>
      _TelevisionNavigationShellState();
}

class _TelevisionNavigationShellState
    extends State<_TelevisionNavigationShell> {
  late final List<FocusNode> _destinationFocusNodes = List.generate(
    widget.items.length,
    (index) => FocusNode(debugLabel: 'tv-nav-$index'),
  );
  bool _isExitDialogVisible = false;
  late bool _isSidebarVisible;

  @override
  void initState() {
    super.initState();
    _isSidebarVisible = !widget.autoHideNavigationBarEnabled;
  }

  @override
  void didUpdateWidget(covariant _TelevisionNavigationShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusRecoveryRevision != widget.focusRecoveryRevision) {
      _scheduleFocusRecoveryIfMissing();
    }
    if (oldWidget.currentIndex != widget.currentIndex &&
        widget.autoHideNavigationBarEnabled) {
      _setSidebarVisible(false);
    }
    if (!widget.autoHideNavigationBarEnabled) {
      _setSidebarVisible(true);
      return;
    }
    if (oldWidget.autoHideNavigationBarEnabled !=
        widget.autoHideNavigationBarEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _setSidebarVisible(_isSidebarFocused);
        }
      });
    }
  }

  void _scheduleFocusRecoveryIfMissing() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isExitDialogVisible || _hasActionablePrimaryFocus()) {
        return;
      }
      _focusCurrentDestination(onlyIfStillMissing: true);
    });
  }

  bool _hasActionablePrimaryFocus() {
    final primaryFocus = FocusManager.instance.primaryFocus;
    return primaryFocus != null &&
        primaryFocus is! FocusScopeNode &&
        primaryFocus.context != null &&
        primaryFocus.canRequestFocus;
  }

  @override
  void dispose() {
    for (final node in _destinationFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _focusCurrentDestination({bool onlyIfStillMissing = false}) {
    _setSidebarVisible(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _destinationFocusNodes.isEmpty ||
          (onlyIfStillMissing && _hasActionablePrimaryFocus())) {
        return;
      }
      final currentDisplayIndex = widget.items.indexWhere(
        (item) => item.branchIndex == widget.currentIndex,
      );
      final index = (currentDisplayIndex < 0 ? 0 : currentDisplayIndex).clamp(
        0,
        _destinationFocusNodes.length - 1,
      );
      final node = _destinationFocusNodes[index];
      if (!node.canRequestFocus) {
        return;
      }
      requestTvFocus(
        node,
      );
    });
  }

  bool get _isSidebarFocused => _destinationFocusNodes.any(
        (node) => node.hasFocus || node.hasPrimaryFocus,
      );

  int get _currentDestinationDisplayIndex {
    final currentDisplayIndex = widget.items.indexWhere(
      (item) => item.branchIndex == widget.currentIndex,
    );
    return (currentDisplayIndex < 0 ? 0 : currentDisplayIndex).clamp(
      0,
      _destinationFocusNodes.length - 1,
    );
  }

  bool get _isCurrentDestinationFocused =>
      _destinationFocusNodes.isNotEmpty &&
      _destinationFocusNodes[_currentDestinationDisplayIndex].hasPrimaryFocus;

  void _clearFocusAndFocusCurrentDestination() {
    final previousFocus = FocusManager.instance.primaryFocus;
    previousFocus?.unfocus(
      disposition: UnfocusDisposition.scope,
    );
    _setSidebarVisible(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _destinationFocusNodes.isEmpty) {
        return;
      }
      final currentNode =
          _destinationFocusNodes[_currentDestinationDisplayIndex];
      if (currentNode.canRequestFocus) {
        requestTvFocus(currentNode);
        final destination = widget.items[_currentDestinationDisplayIndex];
        appLogTrace(
          'tv.focus-recovery',
          'Focus cleared and moved to current sidebar destination',
          fields: <String, Object?>{
            'branch': destination.id,
            'branchIndex': destination.branchIndex,
            'previousFocus': describeTvFocusNode(previousFocus),
            'previousFocusType':
                previousFocus?.runtimeType.toString() ?? 'none',
            'targetFocus': describeTvFocusNode(currentNode),
          },
        );
      }
    });
  }

  void _handleSidebarFocusChanged(bool focused) {
    if (!widget.autoHideNavigationBarEnabled) {
      return;
    }
    _setSidebarVisible(focused);
  }

  void _setSidebarVisible(bool visible) {
    if (!mounted || _isSidebarVisible == visible) {
      return;
    }
    setState(() {
      _isSidebarVisible = visible;
    });
  }

  Future<void> _handleRootBackNavigation() async {
    if (!mounted) {
      return;
    }
    if (!_isCurrentDestinationFocused) {
      _clearFocusAndFocusCurrentDestination();
      return;
    }
    if (_isExitDialogVisible) {
      return;
    }

    _isExitDialogVisible = true;
    widget.onExitDialogVisibilityChanged(true);
    var shouldExit = false;
    try {
      shouldExit = await showStarflowActionDialog<bool>(
            context: context,
            title: '退出 Starflow？',
            message: '再次确认后将关闭当前应用。',
            actions: const [
              StarflowDialogAction<bool>(
                label: '取消',
                value: false,
                icon: Icons.close_rounded,
                variant: StarflowButtonVariant.ghost,
                autofocus: true,
              ),
              StarflowDialogAction<bool>(
                label: '退出',
                value: true,
                icon: Icons.logout_rounded,
                variant: StarflowButtonVariant.secondary,
              ),
            ],
          ) ??
          false;
    } finally {
      _isExitDialogVisible = false;
      if (!shouldExit) {
        widget.onExitDialogVisibilityChanged(false);
      }
    }

    if (shouldExit) {
      try {
        await _exitApplication();
      } finally {
        widget.onExitDialogVisibilityChanged(false);
      }
    }
  }

  Future<void> _exitApplication() async {
    await ActivePlaybackCleanupCoordinator.cleanupAll(reason: 'app-exit');
    await PlaybackSystemSessionController.setActive(false);
    await PlaybackSystemSessionController.detach();
    if (AndroidPictureInPictureController.isSupportedPlatform) {
      await AndroidPictureInPictureController.setPlaybackEnabled(
        enabled: false,
        aspectRatioWidth: 16,
        aspectRatioHeight: 9,
      );
      await AndroidPictureInPictureController.detach();
    }
    await BackgroundPlaybackController.setEnabled(false);
    if (await ApplicationExitController.exitNativeTask()) {
      return;
    }
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    // A focused navigation destination must never be laid out at zero width.
    // Keeping this invariant in the build itself also repairs a stale
    // visibility state left by a focus transition during an animation.
    final sidebarVisible =
        !widget.autoHideNavigationBarEnabled || _isSidebarVisible;
    final sidebarAnimationDuration =
        widget.navigationAnimationEnabled && !widget.staticNavigationEnabled
            ? const Duration(milliseconds: 180)
            : Duration.zero;
    final sidebarRadius =
        widget.autoHideNavigationBarEnabled ? AppRadii.lg : 0.0;
    final sidebarColor = widget.autoHideNavigationBarEnabled
        ? AppColors.neutral3.withValues(
            alpha: widget.translucentEffectsEnabled ? 0.46 : 0.78,
          )
        : Theme.of(context).colorScheme.surface;
    final sidebar = ClipRRect(
      borderRadius: BorderRadius.circular(sidebarRadius),
      child: widget.autoHideNavigationBarEnabled &&
              widget.translucentEffectsEnabled
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(sidebarRadius),
                  color: sidebarColor,
                ),
                child: _TelevisionSidebarContent(
                  items: widget.items,
                  currentIndex: widget.currentIndex,
                  focusNodes: _destinationFocusNodes,
                  onDestinationSelected: widget.onDestinationSelected,
                ),
              ),
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(sidebarRadius),
                color: sidebarColor,
              ),
              child: _TelevisionSidebarContent(
                items: widget.items,
                currentIndex: widget.currentIndex,
                focusNodes: _destinationFocusNodes,
                onDestinationSelected: widget.onDestinationSelected,
              ),
            ),
    );
    final sidebarSlot = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: _handleSidebarFocusChanged,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.zero,
          child: sidebar,
        ),
      ),
    );
    final sidebarWithBoundary = widget.autoHideNavigationBarEnabled
        ? _TelevisionSidebarFocusBoundary(
            focusNodes: _destinationFocusNodes,
            child: sidebarSlot,
          )
        : sidebarSlot;

    return TvMenuButtonScope(
      onMenuButtonPressed: _focusCurrentDestination,
      child: PopScope<void>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) {
            return;
          }
          unawaited(_handleRootBackNavigation());
        },
        child: !widget.autoHideNavigationBarEnabled
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ColoredBox(
                    color: Theme.of(context).colorScheme.surface,
                    child: sidebarSlot,
                  ),
                  Expanded(
                    child: _TelevisionContentFocusBoundary(
                      focusSidebar: _focusCurrentDestination,
                      isSidebarFocused: () => _isSidebarFocused,
                      child: widget.child,
                    ),
                  ),
                ],
              )
            : Stack(
                children: [
                  Positioned.fill(
                    child: _TelevisionContentFocusBoundary(
                      focusSidebar: _focusCurrentDestination,
                      isSidebarFocused: () => _isSidebarFocused,
                      child: widget.child,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: AnimatedSlide(
                      offset: sidebarVisible ? Offset.zero : const Offset(-1, 0),
                      duration: sidebarAnimationDuration,
                      curve: Curves.easeOutCubic,
                      child: AnimatedOpacity(
                        opacity: sidebarVisible ? 1 : 0,
                        duration: sidebarAnimationDuration,
                        curve: Curves.easeOutCubic,
                        child: ExcludeFocus(
                          excluding: !sidebarVisible,
                          child: IgnorePointer(
                            ignoring: !sidebarVisible,
                            child: sidebarWithBoundary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _TelevisionContentFocusBoundary extends StatelessWidget {
  const _TelevisionContentFocusBoundary({
    required this.focusSidebar,
    required this.isSidebarFocused,
    required this.child,
  });

  final VoidCallback focusSidebar;
  final bool Function() isSidebarFocused;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
          onInvoke: (intent) {
            final primaryFocus = FocusManager.instance.primaryFocus;
            if (primaryFocus == null || isSidebarFocused()) {
              return null;
            }

            handleTvDirectionalFocusBoundary(
              context,
              intent.direction,
              onMoveLeftOut: focusSidebar,
            );
            return null;
          },
        ),
      },
      child: child,
    );
  }
}

class _TelevisionSidebarFocusBoundary extends StatelessWidget {
  const _TelevisionSidebarFocusBoundary({
    required this.focusNodes,
    required this.child,
  });

  final List<FocusNode> focusNodes;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
          onInvoke: (intent) {
            final primaryFocus = FocusManager.instance.primaryFocus;
            if (primaryFocus == null) {
              return null;
            }

            if (intent.direction == TraversalDirection.up ||
                intent.direction == TraversalDirection.down) {
              final currentIndex = focusNodes.indexWhere(
                (node) => node.hasFocus || node.hasPrimaryFocus,
              );
              if (currentIndex < 0) {
                return null;
              }
              final nextIndex =
                  intent.direction == TraversalDirection.up
                      ? currentIndex - 1
                      : currentIndex + 1;
              if (nextIndex < 0 || nextIndex >= focusNodes.length) {
                return null;
              }
              requestTvFocus(focusNodes[nextIndex]);
              return null;
            }

            // Horizontal movement is intentionally left to the shell's normal
            // traversal so right can enter the content page and left stays
            // bounded by the edge fallback.
            handleTvDirectionalFocusBoundary(
              context,
              intent.direction,
              onMoveLeftOut: () {},
            );
            return null;
          },
        ),
      },
      child: child,
    );
  }
}

class _TelevisionSidebarContent extends StatelessWidget {
  const _TelevisionSidebarContent({
    required this.items,
    required this.currentIndex,
    required this.focusNodes,
    required this.onDestinationSelected,
  });

  final List<_NavigationItemData> items;
  final int currentIndex;
  final List<FocusNode> focusNodes;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 10),
          for (var index = 0; index < items.length; index++) ...[
            _TelevisionNavigationDestination(
              item: items[index],
              selected: items[index].branchIndex == currentIndex,
              focusNode: focusNodes[index],
              autofocus: items[index].branchIndex == currentIndex,
              onPressed: () => onDestinationSelected(items[index].branchIndex),
            ),
            if (index != items.length - 1) const SizedBox(height: 10),
          ],
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _TelevisionNavigationDestination extends StatefulWidget {
  const _TelevisionNavigationDestination({
    required this.item,
    required this.selected,
    required this.focusNode,
    required this.autofocus,
    required this.onPressed,
  });

  final _NavigationItemData item;
  final bool selected;
  final FocusNode focusNode;
  final bool autofocus;
  final VoidCallback onPressed;

  @override
  State<_TelevisionNavigationDestination> createState() =>
      _TelevisionNavigationDestinationState();
}

class _TelevisionNavigationDestinationState
    extends State<_TelevisionNavigationDestination> {
  final LayerLink _layerLink = LayerLink();
  final OverlayPortalController _overlayController = OverlayPortalController();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focused = widget.focusNode.hasFocus;
    widget.focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _TelevisionNavigationDestination oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_handleFocusChange);
      widget.focusNode.addListener(_handleFocusChange);
      _focused = widget.focusNode.hasFocus;
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocusChange);
    if (_overlayController.isShowing) {
      _overlayController.hide();
    }
    super.dispose();
  }

  void _handleFocusChange() {
    final focused = widget.focusNode.hasFocus;
    if (_focused == focused) {
      return;
    }
    setState(() {
      _focused = focused;
    });
    if (focused) {
      _overlayController.show();
    } else if (_overlayController.isShowing) {
      _overlayController.hide();
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColors = AppActionColors.of(Theme.of(context));
    final accent = accentColors.primary;
    final foregroundColor = widget.selected
        ? accent
        : AppColors.foregroundMuted.withValues(alpha: 0.76);
    final backgroundColor =
        widget.selected ? accent.withValues(alpha: 0.08) : Colors.transparent;

    final button = TvFocusableAction(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onPressed: widget.onPressed,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      visualStyle: TvFocusVisualStyle.subtle,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Icon(
              widget.selected ? widget.item.selectedIcon : widget.item.icon,
              color: foregroundColor,
              size: 24,
            ),
          ),
        ),
      ),
    );

    return OverlayPortal(
      controller: _overlayController,
      overlayChildBuilder: (context) {
        if (!_focused) {
          return const SizedBox.shrink();
        }
        // Non-positioned overlay children receive full-screen tight constraints.
        // Let the follower measure the label so its anchor is the text's center.
        return Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.centerRight,
            followerAnchor: Alignment.centerLeft,
            offset: const Offset(2, 0),
            child: IgnorePointer(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.scale(
                      scale: 0.92 + (0.08 * value),
                      alignment: Alignment.centerLeft,
                      child: child,
                    ),
                  );
                },
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.18),
                        blurRadius: 9,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                    ),
                    child: SizedBox(
                      height: 42,
                      child: Center(
                        child: Text(
                          widget.item.label,
                          style: TextStyle(
                            color: accentColors.onPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: CompositedTransformTarget(
        link: _layerLink,
        child: button,
      ),
    );
  }
}

class _FloatingNavigationBar extends StatelessWidget {
  const _FloatingNavigationBar({
    required this.items,
    required this.currentIndex,
    required this.staticNavigationEnabled,
    required this.onDestinationSelected,
  });

  final List<_NavigationItemData> items;
  final int currentIndex;
  final bool staticNavigationEnabled;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: List.generate(items.length, (index) {
          final item = items[index];
          final selected = item.branchIndex == currentIndex;
          return Expanded(
            child: _FloatingNavigationButton(
              item: item,
              selected: selected,
              staticNavigationEnabled: staticNavigationEnabled,
              onTap: () => onDestinationSelected(item.branchIndex),
            ),
          );
        }),
      ),
    );
  }
}

class _FloatingNavigationButton extends StatelessWidget {
  const _FloatingNavigationButton({
    required this.item,
    required this.selected,
    required this.staticNavigationEnabled,
    required this.onTap,
  });

  final _NavigationItemData item;
  final bool selected;
  final bool staticNavigationEnabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppActionColors.of(Theme.of(context)).primary;
    final foregroundColor = selected ? accent : AppColors.foregroundMuted;
    final buttonChild = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      child: staticNavigationEnabled
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? accent.withValues(alpha: 0.14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(_kBottomNavItemRadius),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selected ? item.selectedIcon : item.icon,
                    color: foregroundColor,
                    size: 20,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foregroundColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            )
          : AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? accent.withValues(alpha: 0.14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(_kBottomNavItemRadius),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selected ? item.selectedIcon : item.icon,
                    color: foregroundColor,
                    size: 20,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foregroundColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_kBottomNavItemRadius),
        splashColor: staticNavigationEnabled
            ? Colors.transparent
            : Colors.white.withValues(alpha: 0.06),
        highlightColor: staticNavigationEnabled
            ? Colors.transparent
            : Colors.white.withValues(alpha: 0.02),
        child: buttonChild,
      ),
    );
  }
}

class _NavigationItemData {
  const _NavigationItemData({
    required this.id,
    required this.branchIndex,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String id;
  final int branchIndex;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
