import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/app/router/app_navigator.dart';
import 'package:starflow/app/router/app_navigation_shell.dart';
import 'package:starflow/app/router/app_routes.dart';
import 'package:starflow/core/widgets/no_animation_page_route.dart';
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
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/settings_page.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: appNavigatorKey,
    initialLocation: AppRoutes.boot.path,
    routes: [
      GoRoute(
        path: AppRoutes.boot.path,
        name: AppRoutes.boot.name,
        pageBuilder: (context, state) => _buildAppPage(
          state: state,
          child: const BootstrapPage(),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppNavigationShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home.path,
                name: AppRoutes.home.name,
                pageBuilder: (context, state) => _buildAppPage(
                  state: state,
                  child: const HomePage(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.search.path,
                name: AppRoutes.search.name,
                pageBuilder: (context, state) => _buildAppPage(
                  state: state,
                  child: SearchPage(
                    initialQuery: state.uri.queryParameters['q'],
                  ),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.library.path,
                name: AppRoutes.library.name,
                pageBuilder: (context, state) => _buildAppPage(
                  state: state,
                  child: const LibraryPage(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.settings.path,
                name: AppRoutes.settings.name,
                pageBuilder: (context, state) => _buildAppPage(
                  state: state,
                  child: const SettingsPage(),
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.homeEditor.path,
        name: AppRoutes.homeEditor.name,
        pageBuilder: (context, state) => _buildAppPage(
          state: state,
          child: const HomeEditorPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.homeModuleList.path,
        name: AppRoutes.homeModuleList.name,
        pageBuilder: (context, state) {
          return _buildAppPage(
            state: state,
            child: _buildRequiredPage<HomeModuleConfig>(
              state: state,
              missingPage: const _MissingRouteTargetPage(
                message: '缺少首页模块目标',
                showBackButton: false,
              ),
              builder: (module) => HomeModuleCollectionPage(module: module),
            ),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.collection.path,
        name: AppRoutes.collection.name,
        pageBuilder: (context, state) {
          return _buildAppPage(
            state: state,
            child: _buildRequiredPage<LibraryCollectionTarget>(
              state: state,
              missingPage: const _MissingRouteTargetPage(
                message: '没有收到可展示的分区数据。',
              ),
              builder: (target) => LibraryCollectionPage(target: target),
            ),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.detail.path,
        name: AppRoutes.detail.name,
        pageBuilder: (context, state) {
          return _buildAppPage(
            state: state,
            child: _buildRequiredPage<MediaDetailTarget>(
              state: state,
              missingPage: const _MissingRouteTargetPage(
                message: '没有收到可展示的详情数据。',
              ),
              builder: (target) => MediaDetailPage(target: target),
            ),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.personCredits.path,
        name: AppRoutes.personCredits.name,
        pageBuilder: (context, state) {
          return _buildAppPage(
            state: state,
            child: _buildRequiredPage<PersonCreditsPageTarget>(
              state: state,
              missingPage: const _MissingRouteTargetPage(
                message: '没有收到可展示的详情数据。',
              ),
              builder: (target) => PersonCreditsPage(target: target),
            ),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.detailSearch.path,
        name: AppRoutes.detailSearch.name,
        pageBuilder: (context, state) {
          return _buildAppPage(
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

Page<void> _buildAppPage({
  required GoRouterState state,
  required Widget child,
}) {
  return NoAnimationMaterialPage<void>(
    key: state.pageKey,
    name: state.name ?? state.uri.toString(),
    arguments: state.extra,
    child: child,
  );
}

Page<void> _buildFullscreenDialogPage({
  required GoRouterState state,
  required Widget child,
}) {
  return NoAnimationMaterialPage<void>(
    key: state.pageKey,
    name: state.name ?? state.uri.toString(),
    arguments: state.extra,
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
  required GoRouterState state,
  required Widget missingPage,
  required Widget Function(T target) builder,
}) {
  return _buildFullscreenDialogPage(
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
