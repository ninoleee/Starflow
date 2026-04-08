import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';

String performanceSettingsSummary(AppSettings settings) {
  final enabledItems = <String>[
    if (!settings.translucentEffectsEnabled) '磨砂关闭',
    if (settings.performanceReduceDecorationsEnabled) '装饰简化',
    if (settings.performanceReduceMotionEnabled) '动画简化',
    if (settings.performanceStaticNavigationEnabled) '导航静态',
    if (!settings.autoHideNavigationBarEnabled) '菜单常驻',
    if (settings.performanceLightweightTvFocusEnabled) 'TV 焦点轻量',
    if (!settings.homeHeroBackgroundEnabled) 'Hero 背景关闭',
    if (settings.performanceStaticHomeHeroEnabled) 'Hero 静态',
    if (settings.performanceLightweightHomeHeroEnabled) 'Hero 轻量卡面',
    if (settings.performanceSlimDetailHeroEnabled) '详情轻量',
    if (settings.performanceLeanPlaybackUiEnabled) '播放轻量',
    if (settings.performanceAggressivePlaybackTuningEnabled) '解码调优',
    if (settings.performanceAutoDowngradeHeavyPlaybackEnabled) '片源自动降级',
  ];

  if (enabledItems.isEmpty) {
    return settings.highPerformanceModeEnabled
        ? '预设已开，当前轻量项已手动调回'
        : '按需管理界面、Hero 和播放轻量模式';
  }

  final itemsLabel = enabledItems.length <= 2
      ? enabledItems.join('、')
      : '${enabledItems.take(2).join('、')} 等 ${enabledItems.length} 项';
  if (!settings.highPerformanceModeEnabled) {
    return itemsLabel;
  }
  return '预设已开 · $itemsLabel';
}

class PerformanceSettingsPage extends ConsumerWidget {
  const PerformanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final theme = Theme.of(context);

    return SettingsPageScaffold(
      onBack: () => Navigator.of(context).pop(),
      children: [
        Text(
          '这里集中放置高性能与轻量模式相关选项。高性能模式本身只是一次性套用推荐值，下面每一项之后仍可单独改回。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SettingsSectionTitle(label: '预设'),
        SettingsToggleTile(
          title: '高性能模式',
          subtitle:
              '打开时会默认关闭透明磨砂、关闭菜单栏自动隐藏、关闭 Hero 背景图，并开启界面、导航、Hero、详情和播放的轻量开关；之后你仍可逐项改回。',
          value: settings.highPerformanceModeEnabled,
          onChanged: (value) {
            controller.setHighPerformanceModeEnabled(value);
          },
        ),
        const SettingsSectionTitle(label: '界面'),
        SettingsToggleTile(
          title: '透明磨砂效果',
          subtitle: '关闭后可减少模糊和毛玻璃效果。',
          value: settings.translucentEffectsEnabled,
          onChanged: (value) {
            controller.setTranslucentEffectsEnabled(value);
          },
        ),
        const SizedBox(height: 18),
        SettingsToggleTile(
          title: '界面装饰简化',
          subtitle: '减少背景光效、面板阴影和部分额外装饰。',
          value: settings.performanceReduceDecorationsEnabled,
          onChanged: (value) {
            controller.setPerformanceReduceDecorationsEnabled(value);
          },
        ),
        const SizedBox(height: 18),
        SettingsToggleTile(
          title: '页面过渡动画简化',
          subtitle: '让启动页和页面切换尽量少动效。',
          value: settings.performanceReduceMotionEnabled,
          onChanged: (value) {
            controller.setPerformanceReduceMotionEnabled(value);
          },
        ),
        const SizedBox(height: 18),
        SettingsToggleTile(
          title: '导航静态化',
          subtitle: '导航栏显隐、按钮反馈和 TV 侧栏切换尽量使用静态表现。',
          value: settings.performanceStaticNavigationEnabled,
          onChanged: (value) {
            controller.setPerformanceStaticNavigationEnabled(value);
          },
        ),
        const SizedBox(height: 18),
        SettingsToggleTile(
          title: '自动隐藏菜单栏',
          subtitle: '普通端会按页面交互自动隐藏；TV 端会在焦点离开左侧菜单后收起。',
          value: settings.autoHideNavigationBarEnabled,
          onChanged: (value) {
            controller.setAutoHideNavigationBarEnabled(value);
          },
        ),
        const SizedBox(height: 18),
        SettingsToggleTile(
          title: 'TV 焦点轻量高亮',
          subtitle: 'TV 端使用更轻的焦点描边和发光效果。',
          value: settings.performanceLightweightTvFocusEnabled,
          onChanged: (value) {
            controller.setPerformanceLightweightTvFocusEnabled(value);
          },
        ),
        const SettingsSectionTitle(label: '首页 Hero'),
        SettingsToggleTile(
          title: 'Hero 全屏背景图',
          subtitle: '关闭后首页 Hero 不再加载全屏背景图。',
          value: settings.homeHeroBackgroundEnabled,
          onChanged: (value) {
            controller.setHomeHeroBackgroundEnabled(value);
          },
        ),
        const SizedBox(height: 18),
        SettingsToggleTile(
          title: 'Hero 静态单卡',
          subtitle: 'Hero 翻页与指示器改为静态切换，减少动画。',
          value: settings.performanceStaticHomeHeroEnabled,
          onChanged: (value) {
            controller.setPerformanceStaticHomeHeroEnabled(value);
          },
        ),
        const SizedBox(height: 18),
        SettingsToggleTile(
          title: 'Hero 轻量卡面（海报/无阴影）',
          subtitle: '强制使用海报卡面，并关闭阴影、模糊等额外效果。',
          value: settings.performanceLightweightHomeHeroEnabled,
          onChanged: (value) {
            controller.setPerformanceLightweightHomeHeroEnabled(value);
          },
        ),
        const SettingsSectionTitle(label: '详情'),
        SettingsToggleTile(
          title: '详情页顶部轻量模式',
          subtitle: '收紧顶部大图区高度、信息宽度和视觉层次。',
          value: settings.performanceSlimDetailHeroEnabled,
          onChanged: (value) {
            controller.setPerformanceSlimDetailHeroEnabled(value);
          },
        ),
        const SettingsSectionTitle(label: '播放'),
        SettingsToggleTile(
          title: '播放页轻量叠层与字幕',
          subtitle: '简化启动叠层、缓冲遮罩与字幕样式。',
          value: settings.performanceLeanPlaybackUiEnabled,
          onChanged: (value) {
            controller.setPerformanceLeanPlaybackUiEnabled(value);
          },
        ),
        const SizedBox(height: 18),
        SettingsToggleTile(
          title: '更积极的解码与 MPV 调优',
          subtitle: '自动模式下会更积极优先硬解，并应用更激进的 MPV 缓冲调优。',
          value: settings.performanceAggressivePlaybackTuningEnabled,
          onChanged: (value) {
            controller.setPerformanceAggressivePlaybackTuningEnabled(value);
          },
        ),
        const SizedBox(height: 18),
        SettingsToggleTile(
          title: '高压力片源自动切换原生/系统播放器',
          subtitle: 'TV 端遇到高码率 4K / HEVC 等重负载片源时，优先切到更稳的播放器。',
          value: settings.performanceAutoDowngradeHeavyPlaybackEnabled,
          onChanged: (value) {
            controller.setPerformanceAutoDowngradeHeavyPlaybackEnabled(value);
          },
        ),
      ],
    );
  }
}
