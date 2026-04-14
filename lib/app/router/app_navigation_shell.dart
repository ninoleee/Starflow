import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/starflow_action_dialog.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/home/application/home_controller.dart';
import 'package:starflow/features/playback/application/playback_session.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

const _kBottomNavShellRadius = 34.0;
const _kBottomNavItemRadius = 24.0;

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

class AppNavigationShell extends ConsumerStatefulWidget {
  const AppNavigationShell({
    required this.navigationShell,
    super.key,
  });

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppNavigationShell> createState() => _AppNavigationShellState();
}

class _AppNavigationShellState extends ConsumerState<AppNavigationShell> {
  static const int _homeBranchIndex = 0;
  bool _isBottomBarVisible = true;
  ProviderSubscription<bool>? _autoHideNavigationBarSubscription;

  @override
  void initState() {
    super.initState();
    _autoHideNavigationBarSubscription = ref.listenManual<bool>(
      _navigationAutoHideProvider,
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

  void _handleDestinationSelected(int index) {
    final shouldRefreshHome = index == _homeBranchIndex &&
        widget.navigationShell.currentIndex == _homeBranchIndex;
    _setBottomBarVisible(true);
    widget.navigationShell.goBranch(index);
    if (shouldRefreshHome) {
      unawaited(refreshHomeModules(ref));
    }
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
                    color: const Color(0xE1141F30),
                  ),
                  child: _FloatingNavigationBar(
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
              currentIndex: widget.navigationShell.currentIndex,
              onDestinationSelected: _handleDestinationSelected,
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
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.child,
    required this.translucentEffectsEnabled,
    required this.autoHideNavigationBarEnabled,
    required this.staticNavigationEnabled,
    required this.navigationAnimationEnabled,
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
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
    _navigationItems.length,
    (index) => FocusNode(debugLabel: 'tv-nav-$index'),
  );
  bool _isExitDialogVisible = false;
  bool _isSidebarVisible = true;
  bool _sidebarVisibilitySyncScheduled = false;
  bool _sidebarFocusListenerAttached = false;

  @override
  void initState() {
    super.initState();
    _setSidebarFocusListenerEnabled(widget.autoHideNavigationBarEnabled);
  }

  @override
  void didUpdateWidget(covariant _TelevisionNavigationShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    _setSidebarFocusListenerEnabled(widget.autoHideNavigationBarEnabled);
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
    _setSidebarFocusListenerEnabled(false);
    for (final node in _destinationFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _setSidebarFocusListenerEnabled(bool enabled) {
    if (enabled == _sidebarFocusListenerAttached) {
      return;
    }
    if (enabled) {
      FocusManager.instance.addListener(_scheduleSidebarVisibilitySync);
      _sidebarFocusListenerAttached = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncSidebarVisibility();
      });
      return;
    }
    FocusManager.instance.removeListener(_scheduleSidebarVisibilitySync);
    _sidebarFocusListenerAttached = false;
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
    final shouldExit = await showStarflowActionDialog<bool>(
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
    _isExitDialogVisible = false;

    if (shouldExit) {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sidebarVisible =
        !widget.autoHideNavigationBarEnabled || _isSidebarVisible;
    final sidebarAnimationDuration =
        widget.navigationAnimationEnabled && !widget.staticNavigationEnabled
            ? const Duration(milliseconds: 180)
            : Duration.zero;
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
            widget.navigationAnimationEnabled
                ? TweenAnimationBuilder<double>(
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
                  )
                : (sidebarVisible
                    ? IgnorePointer(
                        ignoring: false,
                        child: sidebarSlot,
                      )
                    : const SizedBox.shrink()),
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
          for (var index = 0; index < _navigationItems.length; index++) ...[
            _TelevisionNavigationDestination(
              item: _navigationItems[index],
              selected: index == currentIndex,
              focusNode: focusNodes[index],
              autofocus: index == currentIndex,
              onPressed: () => onDestinationSelected(index),
            ),
            if (index != _navigationItems.length - 1)
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
    required this.staticNavigationEnabled,
    required this.onDestinationSelected,
  });

  final int currentIndex;
  final bool staticNavigationEnabled;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: List.generate(_navigationItems.length, (index) {
          final item = _navigationItems[index];
          final selected = index == currentIndex;
          return Expanded(
            child: _FloatingNavigationButton(
              item: item,
              selected: selected,
              staticNavigationEnabled: staticNavigationEnabled,
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
    required this.staticNavigationEnabled,
    required this.onTap,
  });

  final _NavigationItemData item;
  final bool selected;
  final bool staticNavigationEnabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foregroundColor = selected ? Colors.white : const Color(0xA8FFFFFF);
    final buttonChild = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      child: staticNavigationEnabled
          ? Container(
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
            )
          : AnimatedContainer(
              duration: const Duration(milliseconds: 220),
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
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
