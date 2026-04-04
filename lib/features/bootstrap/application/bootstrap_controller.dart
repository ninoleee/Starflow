import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/home/application/home_controller.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

class BootstrapState {
  const BootstrapState({
    required this.progress,
    required this.title,
    required this.subtitle,
    required this.currentStep,
    this.isComplete = false,
  });

  final double progress;
  final String title;
  final String subtitle;
  final int currentStep;
  final bool isComplete;

  BootstrapState copyWith({
    double? progress,
    String? title,
    String? subtitle,
    int? currentStep,
    bool? isComplete,
  }) {
    return BootstrapState(
      progress: progress ?? this.progress,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      currentStep: currentStep ?? this.currentStep,
      isComplete: isComplete ?? this.isComplete,
    );
  }
}

final bootstrapControllerProvider =
    NotifierProvider<BootstrapController, BootstrapState>(
  BootstrapController.new,
);

class BootstrapController extends Notifier<BootstrapState> {
  bool _started = false;

  @override
  BootstrapState build() {
    return const BootstrapState(
      progress: 0.08,
      title: '正在唤醒你的片库',
      subtitle: '先把应用外壳、路由和首页容器准备好。',
      currentStep: 0,
    );
  }

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;

    await _setStage(
      progress: 0.18,
      currentStep: 0,
      title: '正在唤醒你的片库',
      subtitle: '先把应用外壳、路由和首页容器准备好。',
      minDelay: const Duration(milliseconds: 180),
    );

    await _runStage(
      progress: 0.42,
      currentStep: 1,
      title: '正在读取配置',
      subtitle: '加载媒体源、搜索服务和首页模块顺序。',
      task: () async {
        await ref
            .read(settingsControllerProvider.future)
            .timeout(const Duration(seconds: 3));
      },
    );

    await _runStage(
      progress: 0.76,
      currentStep: 2,
      title: '正在同步首页内容',
      subtitle: '预热首页模块，把可展示的资源先准备出来。',
      task: () async {
        await ref.read(homeSectionsProvider.future).timeout(
              const Duration(seconds: 6),
            );
      },
      nonBlockingErrorSubtitle: '媒体源响应偏慢，先进入应用，资源会继续在后台补齐。',
    );

    await _setStage(
      progress: 0.94,
      currentStep: 3,
      title: '正在整理展示内容',
      subtitle: '马上进入首页。',
      minDelay: const Duration(milliseconds: 180),
    );

    state = state.copyWith(
      progress: 1,
      title: '准备完成',
      subtitle: '你的首页和片库已经就绪。',
      currentStep: 3,
      isComplete: true,
    );
  }

  Future<void> _runStage({
    required double progress,
    required int currentStep,
    required String title,
    required String subtitle,
    required Future<void> Function() task,
    String? nonBlockingErrorSubtitle,
  }) async {
    await _setStage(
      progress: progress,
      currentStep: currentStep,
      title: title,
      subtitle: subtitle,
      minDelay: const Duration(milliseconds: 140),
    );

    try {
      await task();
    } catch (_) {
      if (nonBlockingErrorSubtitle != null) {
        state = state.copyWith(subtitle: nonBlockingErrorSubtitle);
      }
    }
  }

  Future<void> _setStage({
    required double progress,
    required int currentStep,
    required String title,
    required String subtitle,
    Duration minDelay = Duration.zero,
  }) async {
    state = state.copyWith(
      progress: progress,
      currentStep: currentStep,
      title: title,
      subtitle: subtitle,
    );
    if (minDelay > Duration.zero) {
      await Future<void>.delayed(minDelay);
    }
  }
}
