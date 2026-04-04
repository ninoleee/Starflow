import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/features/bootstrap/presentation/bootstrap_page.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/media_detail_page.dart';
import 'package:starflow/features/home/presentation/home_editor_page.dart';
import 'package:starflow/features/home/presentation/home_page.dart';
import 'package:starflow/features/library/domain/library_collection_models.dart';
import 'package:starflow/features/library/presentation/library_collection_page.dart';
import 'package:starflow/features/library/presentation/library_page.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/presentation/player_page.dart';
import 'package:starflow/features/search/presentation/search_page.dart';
import 'package:starflow/features/settings/presentation/settings_page.dart';

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
        builder: (context, state) {
          final target = state.extra as PlaybackTarget?;
          if (target == null) {
            return const _MissingPlayerTargetPage();
          }
          return PlayerPage(target: target);
        },
      ),
    ],
  );
});

class _AppNavigationShell extends StatelessWidget {
  const _AppNavigationShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: navigationShell,
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0x28101927),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 30,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: _FloatingNavigationBar(
                currentIndex: navigationShell.currentIndex,
                onDestinationSelected: (index) =>
                    navigationShell.goBranch(index),
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
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
    final foregroundColor = selected ? Colors.white : const Color(0xCCFFFFFF);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        splashColor: Colors.white.withValues(alpha: 0.12),
        highlightColor: Colors.white.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? item.selectedIcon : item.icon,
                  color: foregroundColor,
                  size: 22,
                ),
                const SizedBox(height: 4),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foregroundColor,
                    fontSize: 12,
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
      appBar: AppBar(title: const Text('详情')),
      body: const Center(child: Text('没有收到可展示的详情数据。')),
    );
  }
}

class _MissingCollectionTargetPage extends StatelessWidget {
  const _MissingCollectionTargetPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('分区')),
      body: const Center(child: Text('没有收到可展示的分区数据。')),
    );
  }
}

class _MissingPlayerTargetPage extends StatelessWidget {
  const _MissingPlayerTargetPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('播放器')),
      body: const Center(child: Text('没有收到可播放目标。')),
    );
  }
}
