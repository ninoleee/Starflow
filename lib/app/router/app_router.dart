import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/media_detail_page.dart';
import 'package:starflow/features/home/presentation/home_page.dart';
import 'package:starflow/features/library/presentation/library_page.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/presentation/player_page.dart';
import 'package:starflow/features/search/presentation/search_page.dart';
import 'package:starflow/features/settings/presentation/settings_page.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    routes: [
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
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.space_dashboard_outlined),
            selectedIcon: Icon(Icons.space_dashboard_rounded),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_rounded),
            label: '搜索',
          ),
          NavigationDestination(
            icon: Icon(Icons.video_library_outlined),
            selectedIcon: Icon(Icons.video_library_rounded),
            label: '媒体库',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune_rounded),
            label: '设置',
          ),
        ],
      ),
    );
  }
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
