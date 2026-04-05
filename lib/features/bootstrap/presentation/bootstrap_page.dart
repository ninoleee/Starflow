import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/core/widgets/starflow_logo.dart';
import 'package:starflow/features/bootstrap/application/bootstrap_controller.dart';

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
              context.goNamed('home');
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
    final state = ref.watch(bootstrapControllerProvider);
    final progress = state.progress.clamp(0.0, 1.0).toDouble();

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF010206),
              Color(0xFF071327),
              Color(0xFF0D2856),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 820),
                      curve: Curves.easeOutCubic,
                      builder: (context, entrance, child) {
                        final scale =
                            (0.92 + entrance * 0.08) * (0.97 + progress * 0.04);
                        final translateY = 18 * (1 - entrance);
                        return Transform.translate(
                          offset: Offset(0, translateY),
                          child: Transform.scale(
                            scale: scale,
                            child: Opacity(
                              opacity: 0.58 + entrance * 0.42,
                              child: child,
                            ),
                          ),
                        );
                      },
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          IgnorePointer(
                            child: Container(
                              width: 244,
                              height: 244,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    const Color(0xFF4F8FFF)
                                        .withValues(alpha: 0.18),
                                    const Color(0xFF4F8FFF)
                                        .withValues(alpha: 0.06),
                                    Colors.transparent,
                                  ],
                                  stops: const [0, 0.38, 1],
                                ),
                              ),
                            ),
                          ),
                          IgnorePointer(
                            child: Container(
                              width: 176,
                              height: 176,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    Colors.white.withValues(alpha: 0.06),
                                    Colors.transparent,
                                  ],
                                  stops: const [0, 1],
                                ),
                              ),
                            ),
                          ),
                          const StarflowLogo(
                            iconSize: 132,
                            showWordmark: false,
                          ),
                        ],
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
