import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/features/bootstrap/presentation/bootstrap_page.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/media_detail_page.dart';
import 'package:starflow/features/home/presentation/home_editor_page.dart';
import 'package:starflow/features/home/presentation/home_module_collection_page.dart';
import 'package:starflow/features/home/presentation/home_page.dart';
import 'package:starflow/features/library/domain/library_collection_models.dart';
import 'package:starflow/features/library/presentation/library_collection_page.dart';
import 'package:starflow/features/library/presentation/library_page.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/presentation/player_page.dart';
import 'package:starflow/features/search/presentation/search_page.dart';
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
        builder: (context, state) => const BootstrapPage(),
      ),
      StatefulShellRoute.indexedStack(
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

class _AppNavigationShell extends StatefulWidget {
  const _AppNavigationShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  State<_AppNavigationShell> createState() => _AppNavigationShellState();
}

class _AppNavigationShellState extends State<_AppNavigationShell> {
  bool _isBottomBarVisible = true;

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
    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: widget.navigationShell,
      ),
      bottomNavigationBar: IgnorePointer(
        ignoring: !_isBottomBarVisible,
        child: AnimatedSlide(
          offset: _isBottomBarVisible ? Offset.zero : const Offset(0, 1.2),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: _isBottomBarVisible ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: Material(
                color: Colors.transparent,
                elevation: 0,
                shadowColor: Colors.transparent,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_kBottomNavShellRadius),
                  child: BackdropFilter(
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
                        onDestinationSelected: (index) {
                          _setBottomBarVisible(true);
                          widget.navigationShell.goBranch(index);
                        },
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
  }
}

class _FloatingNavigationBar extends StatelessWidget {
  const _FloatingNavigationBar({
    required this.currentIndex,
    required this.onDestinationSelected,
  });

  final int currentIndex;
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
    required this.onTap,
  });

  final _NavigationItemData item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foregroundColor = selected ? Colors.white : const Color(0xA8FFFFFF);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_kBottomNavItemRadius),
        splashColor: Colors.white.withValues(alpha: 0.06),
        highlightColor: Colors.white.withValues(alpha: 0.02),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          child: AnimatedContainer(
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
