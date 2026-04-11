import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/app/router/app_navigation_shell.dart';
import 'package:starflow/app/router/app_routes.dart';
import 'package:starflow/core/utils/subtitle_search_trace.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
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
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/playback/presentation/player_page.dart';
import 'package:starflow/features/playback/presentation/subtitle_search_page.dart';
import 'package:starflow/features/search/presentation/search_page.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/settings_page.dart';

final _performanceReduceMotionEnabledProvider = Provider<bool>((ref) {
  return ref.watch(appSettingsProvider.select(
    (settings) => settings.effectiveReduceMotionEnabled,
  ));
});

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.boot.path,
    routes: [
      GoRoute(
        path: AppRoutes.boot.path,
        name: AppRoutes.boot.name,
        pageBuilder: (context, state) => _buildNoTransitionPage(
          state: state,
          child: const BootstrapPage(),
        ),
      ),
      StatefulShellRoute.indexedStack(
        pageBuilder: (context, state, navigationShell) {
          final performanceReduceMotionEnabled =
              ProviderScope.containerOf(context, listen: false)
                  .read(_performanceReduceMotionEnabledProvider);
          if (performanceReduceMotionEnabled) {
            return _buildNoTransitionPage(
              state: state,
              child: AppNavigationShell(navigationShell: navigationShell),
            );
          }
          return CustomTransitionPage<void>(
            key: state.pageKey,
            child: AppNavigationShell(navigationShell: navigationShell),
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
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home.path,
                name: AppRoutes.home.name,
                builder: (context, state) => const HomePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.search.path,
                name: AppRoutes.search.name,
                builder: (context, state) => SearchPage(
                  initialQuery: state.uri.queryParameters['q'],
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.library.path,
                name: AppRoutes.library.name,
                builder: (context, state) => const LibraryPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.settings.path,
                name: AppRoutes.settings.name,
                builder: (context, state) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.homeEditor.path,
        name: AppRoutes.homeEditor.name,
        builder: (context, state) => const HomeEditorPage(),
      ),
      GoRoute(
        path: AppRoutes.homeModuleList.path,
        name: AppRoutes.homeModuleList.name,
        builder: (context, state) {
          return _buildRequiredPage<HomeModuleConfig>(
            state: state,
            missingPage: const _MissingRouteTargetPage(
              message: '缺少首页模块目标',
              showBackButton: false,
            ),
            builder: (module) => HomeModuleCollectionPage(module: module),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.collection.path,
        name: AppRoutes.collection.name,
        builder: (context, state) {
          return _buildRequiredPage<LibraryCollectionTarget>(
            state: state,
            missingPage: const _MissingRouteTargetPage(
              message: '没有收到可展示的分区数据。',
            ),
            builder: (target) => LibraryCollectionPage(target: target),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.detail.path,
        name: AppRoutes.detail.name,
        builder: (context, state) {
          return _buildRequiredPage<MediaDetailTarget>(
            state: state,
            missingPage: const _MissingRouteTargetPage(
              message: '没有收到可展示的详情数据。',
            ),
            builder: (target) => MediaDetailPage(target: target),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.personCredits.path,
        name: AppRoutes.personCredits.name,
        builder: (context, state) {
          return _buildRequiredPage<PersonCreditsPageTarget>(
            state: state,
            missingPage: const _MissingRouteTargetPage(
              message: '没有收到可展示的详情数据。',
            ),
            builder: (target) => PersonCreditsPage(target: target),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.detailSearch.path,
        name: AppRoutes.detailSearch.name,
        pageBuilder: (context, state) {
          return _buildNoTransitionPage(
            state: state,
            child: SearchPage(
              initialQuery: state.uri.queryParameters['q'],
              showBackButton: true,
            ),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.metadataIndex.path,
        name: AppRoutes.metadataIndex.name,
        pageBuilder: (context, state) {
          return _buildRequiredFullscreenDialogPage<MediaDetailTarget>(
            context: context,
            state: state,
            missingPage: const _MissingRouteTargetPage(
              message: '没有收到可展示的详情数据。',
            ),
            builder: (target) => MetadataIndexManagementPage(target: target),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.subtitleSearch.path,
        name: AppRoutes.subtitleSearch.name,
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
          return _buildFullscreenDialogPage(
            context: context,
            state: state,
            child: SubtitleSearchPage(request: request),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.player.path,
        name: AppRoutes.player.name,
        pageBuilder: (context, state) {
          return _buildRequiredFullscreenDialogPage<PlaybackTarget>(
            context: context,
            state: state,
            missingPage: const _MissingRouteTargetPage(
              message: '没有收到可播放目标。',
            ),
            builder: (target) => PlayerPage(target: target),
          );
        },
      ),
    ],
  );
});

NoTransitionPage<void> _buildNoTransitionPage({
  required GoRouterState state,
  required Widget child,
}) {
  return NoTransitionPage<void>(
    key: state.pageKey,
    child: child,
  );
}

Page<void> _buildFullscreenDialogPage({
  required BuildContext context,
  required GoRouterState state,
  required Widget child,
}) {
  final performanceReduceMotionEnabled =
      ProviderScope.containerOf(context, listen: false)
          .read(_performanceReduceMotionEnabledProvider);
  if (performanceReduceMotionEnabled) {
    return _buildNoTransitionPage(
      state: state,
      child: child,
    );
  }
  return MaterialPage<void>(
    key: state.pageKey,
    fullscreenDialog: true,
    child: child,
  );
}

Widget _buildRequiredPage<T>({
  required GoRouterState state,
  required Widget missingPage,
  required Widget Function(T target) builder,
}) {
  final target = state.extra as T?;
  if (target == null) {
    return missingPage;
  }
  return builder(target);
}

Page<void> _buildRequiredFullscreenDialogPage<T>({
  required BuildContext context,
  required GoRouterState state,
  required Widget missingPage,
  required Widget Function(T target) builder,
}) {
  return _buildFullscreenDialogPage(
    context: context,
    state: state,
    child: _buildRequiredPage<T>(
      state: state,
      missingPage: missingPage,
      builder: builder,
    ),
  );
}

class _MissingRouteTargetPage extends StatelessWidget {
  const _MissingRouteTargetPage({
    required this.message,
    this.showBackButton = true,
  });

  final String message;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    final content = Center(child: Text(message));
    if (!showBackButton) {
      return Scaffold(body: content);
    }
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          content,
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
