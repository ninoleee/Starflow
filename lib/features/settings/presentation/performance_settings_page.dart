import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/application/settings_slice_providers.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';

String performanceSettingsSummary(
  SettingsPerformanceSlice settings, {
  bool isTelevision = false,
}) {
  final enabledItems = <String>[
    if (!settings.translucentEffectsEnabled) '磨砂关闭',
    if (!settings.autoHideNavigationBarEnabled) '菜单常驻',
    if (!settings.homeHeroBackgroundEnabled) 'Hero 背景关闭',
    if (isTelevision || !settings.performanceLiveItemHeroOverlayEnabled)
      '局部实时更新关闭',
  ];

  if (enabledItems.isEmpty) {
    return settings.highPerformanceModeEnabled
        ? '预设已开，当前轻量项已手动调回'
        : '按需管理界面、Hero 与局部更新策略';
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
    final settings = ref.watch(settingsPerformanceSliceProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final theme = Theme.of(context);
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    final effectiveLiveOverlayEnabled =
        !isTelevision && settings.performanceLiveItemHeroOverlayEnabled;

    return SettingsPageScaffold(
      onBack: () => Navigator.of(context).pop(),
      children: [
        Text(
          '这里集中放置你之前已经确认过的高性能与轻量模式选项。高性能模式本身只是一次性套用推荐值，下面这些项之后仍可单独改回；未单独列出的其他轻量化处理会继续跟随高性能模式预设。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SettingsSectionTitle(label: '预设'),
        SettingsToggleTile(
          title: '高性能模式',
          subtitle:
              '打开时会默认关闭透明磨砂、关闭菜单栏自动隐藏、关闭 Hero 背景图、关闭运行时卡片与 Hero 局部更新，并套用这页中的推荐值；未单独列出的其他轻量化处理也会一起生效。',
          value: settings.highPerformanceModeEnabled,
          onChanged: (value) {
            controller.setHighPerformanceModeEnabled(value);
          },
        ),
        const SettingsSectionTitle(label: '界面'),
        ...buildSettingsTileGroup([
          SettingsToggleTile(
            title: '透明磨砂效果',
            subtitle: '关闭后可减少模糊和毛玻璃效果。',
            value: settings.translucentEffectsEnabled,
            onChanged: (value) {
              controller.setTranslucentEffectsEnabled(value);
            },
          ),
          SettingsToggleTile(
            title: '自动隐藏菜单栏',
            subtitle: '普通端会按页面交互自动隐藏；TV 端会在焦点离开左侧菜单后收起。',
            value: settings.autoHideNavigationBarEnabled,
            onChanged: (value) {
              controller.setAutoHideNavigationBarEnabled(value);
            },
          ),
        ]),
        const SettingsSectionTitle(label: '首页 Hero'),
        ...buildSettingsTileGroup([
          SettingsToggleTile(
            title: 'Hero 全屏背景图',
            subtitle: '关闭后首页 Hero 不再加载全屏背景图。',
            value: settings.homeHeroBackgroundEnabled,
            onChanged: (value) {
              controller.setHomeHeroBackgroundEnabled(value);
            },
          ),
        ]),
        const SettingsSectionTitle(label: '内容刷新'),
        ...buildSettingsTileGroup([
          SettingsToggleTile(
            title: '运行时卡片 / Hero 局部更新',
            subtitle: isTelevision
                ? 'TV 端为保证滚动和焦点稳定，已强制关闭这类运行时局部刷新；普通端仍可按需开启。'
                : '关闭后首页 Hero 和列表卡片不会跟随后台 metadata 缓存变化做局部刷新，只会在应用启动、保存设置或手动刷新后更新。',
            value: effectiveLiveOverlayEnabled,
            onChanged: isTelevision
                ? null
                : (value) {
                    controller.setPerformanceLiveItemHeroOverlayEnabled(value);
                  },
          ),
        ]),
      ],
    );
  }
}
