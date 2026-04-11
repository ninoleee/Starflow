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
    final state = ref.watch(bootstrapControllerProvider);
    final progress = state.progress.clamp(0.0, 1.0).toDouble();
    final reduceMotionEnabled = ref.watch(_bootstrapReduceMotionProvider);

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
                    child: reduceMotionEnabled
                        ? Stack(
                            alignment: Alignment.center,
                            clipBehavior: Clip.none,
                            children: const [
                              _BootstrapLogoMark(
                                iconSize: 108,
                                wordmarkSize: 34,
                                animate: false,
                              ),
                            ],
                          )
                        : TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: 1),
                            duration: const Duration(milliseconds: 820),
                            curve: Curves.easeOutCubic,
                            builder: (context, entrance, child) {
                              final scale = (0.92 + entrance * 0.08) *
                                  (0.97 + progress * 0.04);
                              final translateY = 18 * (1 - entrance) - 18;
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
                              children: const [
                                _BootstrapLogoMark(
                                  iconSize: 108,
                                  wordmarkSize: 34,
                                  animate: true,
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
    required this.animate,
  });

  final double iconSize;
  final double wordmarkSize;
  final bool animate;

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
    );
    if (widget.animate) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _BootstrapLogoMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate == oldWidget.animate) {
      return;
    }
    if (widget.animate) {
      _controller
        ..reset()
        ..repeat(reverse: true);
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) {
      return _buildContent();
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => child ?? const SizedBox.shrink(),
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: widget.iconSize,
          height: widget.iconSize,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.iconSize * 0.22),
            child: Image.asset(
              'assets/branding/starflow_launch_logo.png',
              width: widget.iconSize,
              height: widget.iconSize,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
        SizedBox(height: widget.iconSize * 0.16),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Star',
              style: TextStyle(
                fontSize: widget.wordmarkSize,
                fontWeight: FontWeight.w800,
                letterSpacing: -widget.wordmarkSize * 0.03,
                color: Color(0xFF101A2C),
              ),
            ),
            Text(
              'flow',
              style: TextStyle(
                fontSize: widget.wordmarkSize,
                fontWeight: FontWeight.w400,
                letterSpacing: -widget.wordmarkSize * 0.04,
                color: Color(0xFF101A2C).withValues(alpha: 0.54),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
