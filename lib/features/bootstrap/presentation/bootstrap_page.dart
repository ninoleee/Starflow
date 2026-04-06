import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
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
                    constraints: const BoxConstraints(maxWidth: 320),
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
                              width: 280,
                              height: 280,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    const Color(0xFF4F8FFF)
                                        .withValues(alpha: 0.12),
                                    const Color(0xFF4F8FFF)
                                        .withValues(alpha: 0.03),
                                    Colors.transparent,
                                  ],
                                  stops: const [0, 0.42, 1],
                                ),
                              ),
                            ),
                          ),
                          IgnorePointer(
                            child: Container(
                              width: 168,
                              height: 168,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    Colors.white.withValues(alpha: 0.04),
                                    Colors.transparent,
                                  ],
                                  stops: const [0, 1],
                                ),
                              ),
                            ),
                          ),
                          const _BootstrapLogoMark(
                            iconSize: 108,
                            wordmarkSize: 34,
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

class _BootstrapLogoMark extends StatefulWidget {
  const _BootstrapLogoMark({
    required this.iconSize,
    required this.wordmarkSize,
  });

  final double iconSize;
  final double wordmarkSize;

  @override
  State<_BootstrapLogoMark> createState() => _BootstrapLogoMarkState();
}

class _BootstrapLogoMarkState extends State<_BootstrapLogoMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final glowScale = 1.0 + (_controller.value * 0.06);
        final glowOpacity = 0.6 + (_controller.value * 0.4);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: widget.iconSize,
              height: widget.iconSize,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Transform.scale(
                    scale: glowScale,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          center: const Alignment(0, 0.2),
                          radius: 0.76,
                          colors: [
                            const Color(0xFF64A0FF)
                                .withValues(alpha: 0.14 * glowOpacity),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: SizedBox(
                        width: widget.iconSize,
                        height: widget.iconSize,
                      ),
                    ),
                  ),
                  SvgPicture.asset(
                    'assets/branding/starflow_logo_primary.svg',
                    width: widget.iconSize,
                    height: widget.iconSize,
                  ),
                ],
              ),
            ),
            SizedBox(height: widget.iconSize * 0.21),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Star',
                  style: TextStyle(
                    fontSize: widget.wordmarkSize,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -widget.wordmarkSize * 0.03,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'flow',
                  style: TextStyle(
                    fontSize: widget.wordmarkSize,
                    fontWeight: FontWeight.w400,
                    letterSpacing: -widget.wordmarkSize * 0.04,
                    color: Colors.white.withValues(alpha: 0.48),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
