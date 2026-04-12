import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/app/router/app_router.dart';
import 'package:starflow/app/theme/app_theme.dart';
import 'package:starflow/core/widgets/touch_back_swipe_scope.dart';

class StarflowApp extends ConsumerWidget {
  const StarflowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Starflow',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      routerConfig: ref.watch(appRouterProvider),
      builder: (context, child) {
        if (child == null) {
          return const SizedBox.shrink();
        }
        return TouchBackSwipeScope(child: child);
      },
    );
  }
}
