import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/utils/subtitle_search_trace.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/bootstrap/presentation/bootstrap_page.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/media_detail_page.dart';
import 'package:starflow/features/details/presentation/metadata_index_management_page.dart';
import 'package:starflow/features/details/presentation/person_credits_page.dart';
import 'package:starflow/features/home/presentation/home_editor_page.dart';
import 'package:starflow/features/home/presentation/home_module_collection_page.dart';
import 'package:starflow/features/home/presentation/home_page.dart';
import 'package:starflow/features/library/domain/library_collection_models.dart';
import 'package:starflow/features/library/presentation/library_collection_page.dart';
import 'package:starflow/features/library/presentation/library_page.dart';
import 'package:starflow/features/playback/application/playback_session.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/playback/presentation/player_page.dart';
import 'package:starflow/features/playback/presentation/subtitle_search_page.dart';
import 'package:starflow/features/search/presentation/search_page.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/settings_page.dart';

const _kBottomNavShellRadius = 34.0;
const _kBottomNavItemRadius = 24.0;

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/boot',
    routes: [
      GoRoute(
        path: '/boot',
        name: 'boot',
        pageBuilder: (context, state) => const NoTransitionPage<void>(
          child: BootstrapPage(),
        ),
      ),
      StatefulShellRoute.indexedStack(
        pageBuilder: (context, state, navigationShell) {
          final highPerformanceModeEnabled =
              ProviderScope.containerOf(context, listen: false)
                  .read(appSettingsProvider)
                  .highPerformanceModeEnabled;
          if (highPerformanceModeEnabled) {
            return NoTransitionPage<void>(
              key: state.pageKey,
              child: _AppNavigationShell(navigationShell: navigationShell),
            );
          }
          return CustomTransitionPage<void>(
            key: state.pageKey,
            child: _AppNavigationShell(navigationShell: navigationShell),
            transitionDuration: const Duration(milliseconds: 260),
            reverseTransitionDuration: const Duration(milliseconds: 200),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              );
              return FadeTransition(
                opacity: Tween<double>(begin: 0.2, end: 1).animate(curved),
                child: child,
              );
            },
          );
        },
        builder: (context, state, navigationShell) {
          return _AppNavigationShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                name: 'home',
                builder: (context, state) => const HomePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/search',
                name: 'search',
                builder: (context, state) => SearchPage(
                  initialQuery: state.uri.queryParameters['q'],
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/library',
                name: 'library',
                builder: (context, state) => const LibraryPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                name: 'settings',
                builder: (context, state) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/home-editor',
        name: 'home-editor',
        builder: (context, state) => const HomeEditorPage(),
      ),
      GoRoute(
        path: '/home-module-list',
        name: 'home-module-list',
        builder: (context, state) {
          final module = state.extra as HomeModuleConfig?;
          if (module == null) {
            return const _MissingHomeModuleTargetPage();
          }
          return HomeModuleCollectionPage(module: module);
        },
      ),
      GoRoute(
        path: '/collection',
        name: 'collection',
        builder: (context, state) {
          final target = state.extra as LibraryCollectionTarget?;
          if (target == null) {
            return const _MissingCollectionTargetPage();
          }
          return LibraryCollectionPage(target: target);
        },
      ),
      GoRoute(
        path: '/detail',
        name: 'detail',
        builder: (context, state) {
          final target = state.extra as MediaDetailTarget?;
          if (target == null) {
            return const _MissingDetailTargetPage();
          }
          return MediaDetailPage(target: target);
        },
      ),
      GoRoute(
        path: '/person-credits',
        name: 'person-credits',
        builder: (context, state) {
          final target = state.extra as PersonCreditsPageTarget?;
          if (target == null) {
            return const _MissingDetailTargetPage();
          }
          return PersonCreditsPage(target: target);
        },
      ),
      GoRoute(
        path: '/detail-search',
        name: 'detail-search',
        pageBuilder: (context, state) {
          return NoTransitionPage<void>(
            key: state.pageKey,
            child: SearchPage(
              initialQuery: state.uri.queryParameters['q'],
              showBackButton: true,
            ),
          );
        },
      ),
      GoRoute(
        path: '/metadata-index',
        name: 'metadata-index',
        pageBuilder: (context, state) {
          final target = state.extra as MediaDetailTarget?;
          if (target == null) {
            return MaterialPage<void>(
              key: state.pageKey,
              fullscreenDialog: true,
              child: const _MissingDetailTargetPage(),
            );
          }
          return MaterialPage<void>(
            key: state.pageKey,
            fullscreenDialog: true,
            child: MetadataIndexManagementPage(target: target),
          );
        },
      ),
      GoRoute(
        path: '/subtitle-search',
        name: 'subtitle-search',
        pageBuilder: (context, state) {
          subtitleSearchTrace(
            'router.subtitle-search.route',
            fields: {
              'uri': state.uri.toString(),
              'queryParameters': state.uri.queryParameters.toString(),
            },
          );
          final request = SubtitleSearchRequest.fromQueryParameters(
            state.uri.queryParameters,
          );
          subtitleSearchTrace(
            'router.subtitle-search.request',
            fields: {
              'query': request.query,
              'title': request.title,
              'initialInput': request.initialInput,
              'applyMode': request.applyMode.name,
              'standalone': request.standalone,
            },
          );
          return MaterialPage<void>(
            key: state.pageKey,
            fullscreenDialog: true,
            child: SubtitleSearchPage(request: request),
          );
        },
      ),
      GoRoute(
        path: '/player',
        name: 'player',
        pageBuilder: (context, state) {
          final target = state.extra as PlaybackTarget?;
          if (target == null) {
            return MaterialPage<void>(
              key: state.pageKey,
              fullscreenDialog: true,
              child: const _MissingPlayerTargetPage(),
            );
          }
          return MaterialPage<void>(
            key: state.pageKey,
            fullscreenDialog: true,
            child: PlayerPage(target: target),
          );
        },
      ),
    ],
  );
});

class _AppNavigationShell extends ConsumerStatefulWidget {
  const _AppNavigationShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<_AppNavigationShell> createState() =>
      _AppNavigationShellState();
}

class _AppNavigationShellState extends ConsumerState<_AppNavigationShell> {
  bool _isBottomBarVisible = true;
  ProviderSubscription<bool>? _autoHideNavigationBarSubscription;

  @override
  void initState() {
    super.initState();
    _autoHideNavigationBarSubscription = ref.listenManual<bool>(
      appSettingsProvider.select(
        (settings) => settings.autoHideNavigationBarEnabled,
      ),
      (previous, next) {
        if (!next) {
          _setBottomBarVisible(true);
        }
      },
    );
  }

  @override
  void dispose() {
    _autoHideNavigationBarSubscription?.close();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final isTelevision = ref.watch(isTelevisionProvider).valueOrNull ?? false;
    final backgroundWorkSuspended = ref.watch(backgroundWorkSuspendedProvider);
    final translucentEffectsEnabled = ref.watch(
      appSettingsProvider.select(
        (settings) => settings.translucentEffectsEnabled,
      ),
    );
    final autoHideNavigationBarEnabled = ref.watch(
      appSettingsProvider.select(
        (settings) => settings.autoHideNavigationBarEnabled,
      ),
    );
    final highPerformanceModeEnabled = ref.watch(
      appSettingsProvider
          .select((settings) => settings.highPerformanceModeEnabled),
    );
    final effectiveTranslucentEffectsEnabled =
        translucentEffectsEnabled && !highPerformanceModeEnabled;
    final effectiveAutoHideNavigationBarEnabled =
        autoHideNavigationBarEnabled && !highPerformanceModeEnabled;
    final navigationAnimationDuration = highPerformanceModeEnabled
        ? Duration.zero
        : const Duration(milliseconds: 220);
    final navigationOpacityDuration = highPerformanceModeEnabled
        ? Duration.zero
        : const Duration(milliseconds: 180);
    final bottomBarVisible =
        !effectiveAutoHideNavigationBarEnabled || _isBottomBarVisible;
    final shellChild = HeroMode(
      enabled: !backgroundWorkSuspended,
      child: TickerMode(
        enabled: !backgroundWorkSuspended,
        child: IgnorePointer(
          ignoring: backgroundWorkSuspended,
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
          child: effectiveTranslucentEffectsEnabled
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
                      currentIndex: widget.navigationShell.currentIndex,
                      highPerformanceModeEnabled: highPerformanceModeEnabled,
                      onDestinationSelected: (index) {
                        _setBottomBarVisible(true);
                        widget.navigationShell.goBranch(index);
                      },
                    ),
                  ),
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(_kBottomNavShellRadius),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                    color: const Color(0xE1141F30),
                  ),
                  child: _FloatingNavigationBar(
                    currentIndex: widget.navigationShell.currentIndex,
                    highPerformanceModeEnabled: highPerformanceModeEnabled,
                    onDestinationSelected: (index) {
                      _setBottomBarVisible(true);
                      widget.navigationShell.goBranch(index);
                    },
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
              currentIndex: widget.navigationShell.currentIndex,
              onDestinationSelected: widget.navigationShell.goBranch,
              translucentEffectsEnabled: effectiveTranslucentEffectsEnabled,
              autoHideNavigationBarEnabled:
                  effectiveAutoHideNavigationBarEnabled,
              highPerformanceModeEnabled: highPerformanceModeEnabled,
              child: shellChild,
            )
          : NotificationListener<ScrollNotification>(
              onNotification: effectiveAutoHideNavigationBarEnabled
                  ? _handleScrollNotification
                  : (_) => false,
              child: shellChild,
            ),
      bottomNavigationBar: isTelevision
          ? null
          : highPerformanceModeEnabled
              ? bottomNavigationBarChild
              : IgnorePointer(
              ignoring: !bottomBarVisible,
              child: AnimatedSlide(
                offset: bottomBarVisible ? Offset.zero : const Offset(0, 1.2),
                duration: navigationAnimationDuration,
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: bottomBarVisible ? 1 : 0,
                  duration: navigationOpacityDuration,
                  curve: Curves.easeOutCubic,
                  child: bottomNavigationBarChild,
                ),
              ),
            ),
    );
  }
}

class _TelevisionNavigationShell extends StatefulWidget {
  const _TelevisionNavigationShell({
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.child,
    required this.translucentEffectsEnabled,
    required this.autoHideNavigationBarEnabled,
    required this.highPerformanceModeEnabled,
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;
  final bool translucentEffectsEnabled;
  final bool autoHideNavigationBarEnabled;
  final bool highPerformanceModeEnabled;

  static const _items = [
    _NavigationItemData(
      label: '首页',
      icon: Icons.space_dashboard_outlined,
      selectedIcon: Icons.space_dashboard_rounded,
    ),
    _NavigationItemData(
      label: '搜索',
      icon: Icons.search_rounded,
      selectedIcon: Icons.search_rounded,
    ),
    _NavigationItemData(
      label: '媒体库',
      icon: Icons.video_library_outlined,
      selectedIcon: Icons.video_library_rounded,
    ),
    _NavigationItemData(
      label: '设置',
      icon: Icons.tune_outlined,
      selectedIcon: Icons.tune_rounded,
    ),
  ];

  @override
  State<_TelevisionNavigationShell> createState() =>
      _TelevisionNavigationShellState();
}

class _TelevisionNavigationShellState
    extends State<_TelevisionNavigationShell> {
  late final List<FocusNode> _destinationFocusNodes = List.generate(
    _TelevisionNavigationShell._items.length,
    (index) => FocusNode(debugLabel: 'tv-nav-$index'),
  );
  bool _isExitDialogVisible = false;
  bool _isSidebarVisible = true;
  bool _sidebarVisibilitySyncScheduled = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_scheduleSidebarVisibilitySync);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncSidebarVisibility();
    });
  }

  @override
  void didUpdateWidget(covariant _TelevisionNavigationShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.autoHideNavigationBarEnabled) {
      _setSidebarVisible(true);
      return;
    }
    if (oldWidget.autoHideNavigationBarEnabled !=
        widget.autoHideNavigationBarEnabled) {
      _scheduleSidebarVisibilitySync();
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_scheduleSidebarVisibilitySync);
    for (final node in _destinationFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _focusCurrentDestination() {
    _setSidebarVisible(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _destinationFocusNodes.isEmpty) {
        return;
      }
      final index = widget.currentIndex.clamp(
        0,
        _destinationFocusNodes.length - 1,
      );
      final node = _destinationFocusNodes[index];
      if (!node.canRequestFocus) {
        return;
      }
      node.requestFocus();
    });
  }

  bool get _isSidebarFocused => _destinationFocusNodes.any(
        (node) => node.hasFocus || node.hasPrimaryFocus,
      );

  void _scheduleSidebarVisibilitySync() {
    if (_sidebarVisibilitySyncScheduled) {
      return;
    }
    _sidebarVisibilitySyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sidebarVisibilitySyncScheduled = false;
      _syncSidebarVisibility();
    });
  }

  void _syncSidebarVisibility() {
    if (!mounted) {
      return;
    }
    if (!widget.autoHideNavigationBarEnabled) {
      _setSidebarVisible(true);
      return;
    }
    if (FocusManager.instance.primaryFocus == null) {
      return;
    }
    _setSidebarVisible(_isSidebarFocused);
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
    if (!_isSidebarFocused) {
      _focusCurrentDestination();
      return;
    }
    if (_isExitDialogVisible) {
      return;
    }

    _isExitDialogVisible = true;
    final shouldExit = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('退出 Starflow？'),
              content: const Text('再次确认后将关闭当前应用。'),
              actions: [
                TvAdaptiveButton(
                  label: '取消',
                  icon: Icons.close_rounded,
                  autofocus: true,
                  variant: TvButtonVariant.text,
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                ),
                TvAdaptiveButton(
                  label: '退出',
                  icon: Icons.logout_rounded,
                  variant: TvButtonVariant.outlined,
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                ),
              ],
            );
          },
        ) ??
        false;
    _isExitDialogVisible = false;

    if (shouldExit) {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sidebarVisible =
        !widget.autoHideNavigationBarEnabled || _isSidebarVisible;
    final sidebarAnimationDuration = widget.highPerformanceModeEnabled
        ? Duration.zero
        : const Duration(milliseconds: 180);
    final sidebar = ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: widget.translucentEffectsEnabled
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  color: const Color(0x160F1724),
                ),
                child: _TelevisionSidebarContent(
                  currentIndex: widget.currentIndex,
                  focusNodes: _destinationFocusNodes,
                  onDestinationSelected: widget.onDestinationSelected,
                ),
              ),
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                color: const Color(0xCC101926),
              ),
              child: _TelevisionSidebarContent(
                currentIndex: widget.currentIndex,
                focusNodes: _destinationFocusNodes,
                onDestinationSelected: widget.onDestinationSelected,
              ),
            ),
    );
    final sidebarSlot = SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
        child: sidebar,
      ),
    );

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
        child: Row(
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: sidebarVisible ? 1 : 0,
                end: sidebarVisible ? 1 : 0,
              ),
              duration: sidebarAnimationDuration,
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: value,
                    child: Opacity(
                      opacity: value <= 0.001 ? 0 : value,
                      child: child,
                    ),
                  ),
                );
              },
              child: IgnorePointer(
                ignoring: !sidebarVisible,
                child: sidebarSlot,
              ),
            ),
            Expanded(
              child: _TelevisionContentFocusBoundary(
                focusSidebar: _focusCurrentDestination,
                isSidebarFocused: () => _isSidebarFocused,
                child: widget.child,
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

class _TelevisionSidebarContent extends StatelessWidget {
  const _TelevisionSidebarContent({
    required this.currentIndex,
    required this.focusNodes,
    required this.onDestinationSelected,
  });

  final int currentIndex;
  final List<FocusNode> focusNodes;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 82,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 10),
          for (var index = 0;
              index < _TelevisionNavigationShell._items.length;
              index++) ...[
            _TelevisionNavigationDestination(
              item: _TelevisionNavigationShell._items[index],
              selected: index == currentIndex,
              focusNode: focusNodes[index],
              autofocus: index == currentIndex,
              onPressed: () => onDestinationSelected(index),
            ),
            if (index != _TelevisionNavigationShell._items.length - 1)
              const SizedBox(height: 10),
          ],
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _TelevisionNavigationDestination extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final foregroundColor = selected ? Colors.white : const Color(0xD9E8F7FF);
    final backgroundColor =
        selected ? Colors.white.withValues(alpha: 0.10) : Colors.transparent;

    return TvFocusableAction(
      focusNode: focusNode,
      autofocus: autofocus,
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: SizedBox(
          width: 56,
          height: 56,
          child: Center(
            child: Icon(
              selected ? item.selectedIcon : item.icon,
              color: foregroundColor,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingNavigationBar extends StatelessWidget {
  const _FloatingNavigationBar({
    required this.currentIndex,
    required this.highPerformanceModeEnabled,
    required this.onDestinationSelected,
  });

  final int currentIndex;
  final bool highPerformanceModeEnabled;
  final ValueChanged<int> onDestinationSelected;

  static const _items = [
    _NavigationItemData(
      label: '首页',
      icon: Icons.space_dashboard_outlined,
      selectedIcon: Icons.space_dashboard_rounded,
    ),
    _NavigationItemData(
      label: '搜索',
      icon: Icons.search_rounded,
      selectedIcon: Icons.search_rounded,
    ),
    _NavigationItemData(
      label: '媒体库',
      icon: Icons.video_library_outlined,
      selectedIcon: Icons.video_library_rounded,
    ),
    _NavigationItemData(
      label: '设置',
      icon: Icons.tune_outlined,
      selectedIcon: Icons.tune_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: List.generate(_items.length, (index) {
          final item = _items[index];
          final selected = index == currentIndex;
          return Expanded(
            child: _FloatingNavigationButton(
              item: item,
              selected: selected,
              highPerformanceModeEnabled: highPerformanceModeEnabled,
              onTap: () => onDestinationSelected(index),
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
    required this.highPerformanceModeEnabled,
    required this.onTap,
  });

  final _NavigationItemData item;
  final bool selected;
  final bool highPerformanceModeEnabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foregroundColor = selected ? Colors.white : const Color(0xA8FFFFFF);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_kBottomNavItemRadius),
        splashColor: highPerformanceModeEnabled
            ? Colors.transparent
            : Colors.white.withValues(alpha: 0.06),
        highlightColor: highPerformanceModeEnabled
            ? Colors.transparent
            : Colors.white.withValues(alpha: 0.02),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          child: AnimatedContainer(
            duration: highPerformanceModeEnabled
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: selected
                  ? Colors.white.withValues(alpha: 0.05)
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
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavigationItemData {
  const _NavigationItemData({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _MissingDetailTargetPage extends StatelessWidget {
  const _MissingDetailTargetPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Center(child: Text('没有收到可展示的详情数据。')),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: OverlayToolbar(
              onBack: () => context.pop(),
            ),
          ),
        ],
      ),
    );
  }
}

class _MissingCollectionTargetPage extends StatelessWidget {
  const _MissingCollectionTargetPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Center(child: Text('没有收到可展示的分区数据。')),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: OverlayToolbar(
              onBack: () => context.pop(),
            ),
          ),
        ],
      ),
    );
  }
}

class _MissingHomeModuleTargetPage extends StatelessWidget {
  const _MissingHomeModuleTargetPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text('缺少首页模块目标'),
      ),
    );
  }
}

class _MissingPlayerTargetPage extends StatelessWidget {
  const _MissingPlayerTargetPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Center(child: Text('没有收到可播放目标。')),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: OverlayToolbar(
              onBack: () => context.pop(),
            ),
          ),
        ],
      ),
    );
  }
}
