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
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 420),
                      curve: Curves.easeOutCubic,
                      scale: 0.94 + progress * 0.08,
                      child: const StarflowLogo(
                        iconSize: 124,
                        showWordmark: false,
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
