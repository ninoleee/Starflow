import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/application/settings_slice_providers.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';

class InterfaceSettingsPage extends ConsumerWidget {
  const InterfaceSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsPerformanceSliceProvider);
    final homeNavigationSingleTapCleanupEnabled = ref.watch(
      appSettingsProvider.select(
        (settings) => settings.homeNavigationSingleTapCleanupEnabled,
      ),
    );
    final controller = ref.read(settingsControllerProvider.notifier);
    final theme = Theme.of(context);

    return SettingsPageScaffold(
      onBack: () => Navigator.of(context).pop(),
      children: [
        Text('界面效果', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          '调整页面合成、动画、菜单栏与首页 Hero。相同用途的底层选项会一起保存。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SettingsSectionTitle(label: '界面'),
        ...buildSettingsTileGroup([
          SettingsToggleTile(
            title: '简化界面特效',
            subtitle: '同时关闭透明磨砂，并减少背景、渐变和阴影层级。',
            value: !settings.translucentEffectsEnabled ||
                settings.reduceDecorationsEnabled,
            autofocus: true,
            focusId: 'performance-interface:simplified-effects',
            onChanged: controller.setSimplifiedVisualEffectsEnabled,
          ),
          SettingsToggleTile(
            title: '减少界面动画',
            subtitle: '同时减少页面、全屏和导航切换动画。',
            value: settings.reduceMotionEnabled ||
                settings.staticNavigationEnabled,
            focusId: 'performance-interface:reduced-motion',
            onChanged: controller.setReducedInterfaceMotionEnabled,
          ),
          SettingsToggleTile(
            title: '自动隐藏菜单栏',
            subtitle: '普通端会按页面交互自动隐藏；TV 端会在焦点离开左侧菜单后收起。',
            value: settings.autoHideNavigationBarEnabled,
            focusId: 'performance-interface:auto-hide-navigation',
            onChanged: controller.setAutoHideNavigationBarEnabled,
          ),
        ]),
        const SettingsSectionTitle(label: '首页 Hero'),
        ...buildSettingsTileGroup([
          SettingsToggleTile(
            title: 'Hero 全屏背景图',
            subtitle: '关闭后首页 Hero 不再加载全屏背景图。',
            value: settings.homeHeroBackgroundEnabled,
            focusId: 'performance-interface:hero-background',
            onChanged: controller.setHomeHeroBackgroundEnabled,
          ),
          SettingsToggleTile(
            title: '简化首页 Hero',
            subtitle: '关闭自动轮播与动态切换，并减少 Hero 的过渡和装饰效果。',
            value: settings.staticHomeHeroEnabled ||
                settings.lightweightHomeHeroEnabled,
            focusId: 'performance-interface:simplified-hero',
            onChanged: controller.setSimplifiedHomeHeroEnabled,
          ),
        ]),
        const SettingsSectionTitle(label: '导航交互'),
        SettingsToggleTile(
          title: '单击首页时清理后台任务',
          subtitle: '开启后，单击菜单栏首页会停止非播放后台任务并回到顶部；双击首页仍执行刷新。',
          value: homeNavigationSingleTapCleanupEnabled,
          focusId: 'performance-interface:home-cleanup',
          onChanged: controller.setHomeNavigationSingleTapCleanupEnabled,
        ),
      ],
    );
  }
}
