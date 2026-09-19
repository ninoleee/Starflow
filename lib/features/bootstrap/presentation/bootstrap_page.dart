import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/app/router/app_routes.dart';
import 'package:starflow/features/bootstrap/application/bootstrap_controller.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

final _bootstrapReduceMotionProvider = Provider<bool>((ref) {
  return ref.watch(appSettingsProvider.select(
    (settings) => settings.performanceReduceMotionEnabled,
  ));
});

class BootstrapPage extends ConsumerStatefulWidget {
  const BootstrapPage({super.key});

  @override
  ConsumerState<BootstrapPage> createState() => _BootstrapPageState();
}

class _BootstrapPageState extends ConsumerState<BootstrapPage> {
  ProviderSubscription<BootstrapState>? _bootstrapSubscription;

  @override
  void initState() {
    super.initState();
    _bootstrapSubscription = ref.listenManual<BootstrapState>(
      bootstrapControllerProvider,
      (previous, next) {
        if (next.isComplete && previous?.isComplete != true) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              context.goNamed(AppRoutes.home.name);
            }
          });
        }
      },
    );
    Future<void>.microtask(() {
      ref.read(bootstrapControllerProvider.notifier).start();
    });
  }

  @override
  void dispose() {
    _bootstrapSubscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotionEnabled = ref.watch(_bootstrapReduceMotionProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFF121212),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: reduceMotionEnabled
                        ? const _BootstrapLogoMark(
                            iconSize: 108,
                            wordmarkSize: 34,
                          )
                        : TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: 1),
                            duration: const Duration(milliseconds: 820),
                            curve: Curves.easeOutCubic,
                            builder: (context, entrance, child) {
                              return Opacity(
                                opacity: 0.58 + entrance * 0.42,
                                child: child,
                              );
                            },
                            child: const _BootstrapLogoMark(
                              iconSize: 108,
                              wordmarkSize: 34,
                            ),
                          ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BootstrapLogoMark extends StatelessWidget {
  const _BootstrapLogoMark({
    required this.iconSize,
    required this.wordmarkSize,
  });

  final double iconSize;
  final double wordmarkSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: iconSize,
          height: iconSize,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(iconSize * 0.22),
            child: Image.asset(
              'assets/branding/starflow_launch_logo.png',
              width: iconSize,
              height: iconSize,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
        SizedBox(height: iconSize * 0.16),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Star',
              style: TextStyle(
                fontSize: wordmarkSize,
                fontWeight: FontWeight.w800,
                letterSpacing: -wordmarkSize * 0.03,
                color: Colors.white,
              ),
            ),
            Text(
              'flow',
              style: TextStyle(
                fontSize: wordmarkSize,
                fontWeight: FontWeight.w400,
                letterSpacing: -wordmarkSize * 0.04,
                color: Colors.white.withValues(alpha: 0.64),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
