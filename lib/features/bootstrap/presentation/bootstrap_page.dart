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
    final theme = Theme.of(context);
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
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 12),
                          Center(
                            child: AnimatedScale(
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
                          ),
                          const SizedBox(height: 32),
                          Center(
                            child: Text(
                              'Starflow',
                              style: theme.textTheme.displaySmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 280),
                            child: Text(
                              state.title,
                              key: ValueKey(state.title),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 280),
                            child: Text(
                              state.subtitle,
                              key: ValueKey(state.subtitle),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: const Color(0xFFD8E6FF),
                                height: 1.55,
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                          _ProgressBar(progress: progress),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              '${(progress * 100).round()}%',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          _BootstrapSteps(currentStep: state.currentStep),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: Text(
                          '启动时先把配置和首页内容预热，避免你看到空白等待。',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFFBED4FF),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
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

class _BootstrapSteps extends StatelessWidget {
  const _BootstrapSteps({required this.currentStep});

  final int currentStep;

  @override
  Widget build(BuildContext context) {
    const steps = [
      ('唤醒界面', '先让应用壳和导航结构就位'),
      ('读取配置', '加载媒体源、搜索服务和首页模块'),
      ('同步首页', '预热首页推荐和片库摘要'),
      ('完成进入', '整理展示内容并切到首页'),
    ];

    final theme = Theme.of(context);

    return Column(
      children: List.generate(steps.length, (index) {
        final item = steps[index];
        final isDone = index < currentStep;
        final isActive = index == currentStep;
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          opacity: isDone || isActive ? 1 : 0.6,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDone
                        ? const Color(0xFFBFE0FF)
                        : isActive
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.14),
                  ),
                  child: Icon(
                    isDone ? Icons.check_rounded : Icons.circle,
                    size: isDone ? 16 : 10,
                    color: isDone
                        ? const Color(0xFF0E3D99)
                        : isActive
                            ? const Color(0xFF0E3D99)
                            : Colors.white54,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.$1,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight:
                              isActive ? FontWeight.w800 : FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.$2,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFD8E6FF),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
