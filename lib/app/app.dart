import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/app/lifecycle/app_runtime_recovery_boundary.dart';
import 'package:starflow/app/router/app_router.dart';
import 'package:starflow/app/theme/app_theme.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/playback/application/playback_runtime_priority_binding.dart';

final TvSafeDirectionalFocusAction _tvSafeDirectionalFocusAction =
    TvSafeDirectionalFocusAction();

class StarflowApp extends ConsumerWidget {
  const StarflowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(playbackRuntimePriorityBindingProvider);
    return AppRuntimeRecoveryBoundary(
      child: MaterialApp.router(
        title: 'Starflow',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        routerConfig: ref.watch(appRouterProvider),
        builder: (context, child) => Actions(
          actions: <Type, Action<Intent>>{
            DirectionalFocusIntent: _tvSafeDirectionalFocusAction,
          },
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
