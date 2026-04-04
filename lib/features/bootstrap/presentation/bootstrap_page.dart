import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/features/bootstrap/application/bootstrap_controller.dart';

class BootstrapPage extends ConsumerStatefulWidget {
  const BootstrapPage({super.key});

  @override
  ConsumerState<BootstrapPage> createState() => _BootstrapPageState();
}

class _BootstrapPageState extends ConsumerState<BootstrapPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(bootstrapControllerProvider.notifier).start();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(bootstrapControllerProvider, (previous, next) {
      if (next.isComplete && previous?.isComplete != true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            context.goNamed('home');
          }
        });
      }
    });

    final state = ref.watch(bootstrapControllerProvider);
    final progress = state.progress.clamp(0.0, 1.0).toDouble();

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF050816),
              Color(0xFF10265E),
              Color(0xFF1A58D6),
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
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedScale(
                            duration: const Duration(milliseconds: 420),
                            curve: Curves.easeOutCubic,
                            scale: 0.94 + progress * 0.08,
                            child: Container(
                              width: 156,
                              height: 156,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFFFFFFF),
                                    Color(0xFFB7D0FF),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF7DB1FF,
                                    ).withValues(alpha: 0.42),
                                    blurRadius: 42,
                                    spreadRadius: 10,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Transform.rotate(
                                  angle: progress * 0.18,
                                  child: const Icon(
                                    Icons.play_circle_fill_rounded,
                                    size: 84,
                                    color: Color(0xFF1141A7),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                          const Text(
                            'Starflow',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 38,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1.2,
                            ),
                          ),
                          const SizedBox(height: 24),
                          _ProgressBar(progress: progress),
                        ],
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

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            math.max(24.0, constraints.maxWidth * progress).toDouble();
        return ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 12,
            color: Colors.white.withValues(alpha: 0.16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 340),
                curve: Curves.easeOutCubic,
                width: width,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF93C5FD),
                      Color(0xFFFFFFFF),
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
