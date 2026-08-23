import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/application/settings_slice_providers.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';

String performanceSettingsSummary(
  SettingsPerformanceSlice settings,
) {
  final enabledItems = <String>[
    if (!settings.translucentEffectsEnabled) '磨砂关闭',
    if (!settings.autoHideNavigationBarEnabled) '菜单常驻',
    if (!settings.homeHeroBackgroundEnabled) 'Hero 背景关闭',
    if (!settings.effectiveLiveItemHeroOverlayEnabled) '局部实时更新关闭',
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
    final detailAutoLibraryMatchEnabled =
        ref.watch(settingsDetailAutoLibraryMatchEnabledProvider);
    final homeNavigationSingleTapCleanupEnabled = ref.watch(
      appSettingsProvider.select(
        (settings) => settings.homeNavigationSingleTapCleanupEnabled,
      ),
    );
    final controller = ref.read(settingsControllerProvider.notifier);
    final theme = Theme.of(context);
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    final startupRefreshSettings = ref.watch(
      appSettingsProvider.select(
        (settings) => (
          enabled: settings.homeStartupAutoRefreshEnabled,
          embyEnabled: settings.homeStartupAutoRefreshEmbyEnabled,
        ),
      ),
    );
    final startupEmbyEnabled =
        startupRefreshSettings.embyEnabled ?? !isTelevision;

    return SettingsPageScaffold(
      onBack: () => Navigator.of(context).pop(),
      children: [
        Text(
          '这里集中放置你之前已经确认过的高性能与轻量模式选项。打开高性能模式会套用推荐轻量配置；关闭时会恢复富视觉默认值，下面这些项之后仍可单独调整。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SettingsSectionTitle(label: '预设'),
        SettingsToggleTile(
          title: '高性能模式',
          subtitle: '打开时会重新套用这一页的推荐轻量配置；关闭时会恢复透明磨砂、自动隐藏菜单栏、Hero 背景和其它轻量化子项。',
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
          SettingsToggleTile(
            title: '单击首页时清理后台任务',
            subtitle: '开启后，单击菜单栏首页会停止非播放后台任务并回到顶部；双击首页仍执行刷新。',
            value: homeNavigationSingleTapCleanupEnabled,
            onChanged: (value) {
              controller.setHomeNavigationSingleTapCleanupEnabled(value);
            },
          ),
        ]),
        const SettingsSectionTitle(label: '详情页'),
        ...buildSettingsTileGroup([
          SettingsToggleTile(
            title: '自动匹配本地资源',
            subtitle: '进入详情页时自动尝试匹配本地媒体源。此开关独立保存，不会被高性能模式开关改变。',
            value: detailAutoLibraryMatchEnabled,
            onChanged: (value) {
              controller.setDetailAutoLibraryMatchEnabled(value);
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
            title: '启动时自动刷新首页',
            subtitle: '冷启动应用后，首页模块会在后台重新拉取一次最新数据。',
            value: startupRefreshSettings.enabled,
            onChanged: controller.setHomeStartupAutoRefreshEnabled,
          ),
          SettingsToggleTile(
            title: '同时刷新 Emby 媒体源',
            subtitle: startupRefreshSettings.enabled
                ? (isTelevision
                    ? 'TV 端默认关闭以避免冷启动卡顿，需要时可手动开启。'
                    : '关闭后启动时仅刷新首页模块缓存，不触发 Emby 全量同步。')
                : '需先开启“启动时自动刷新首页”。',
            value: startupEmbyEnabled,
            onChanged: startupRefreshSettings.enabled
                ? controller.setHomeStartupAutoRefreshEmbyEnabled
                : null,
          ),
          SettingsToggleTile(
            title: '运行时卡片 / Hero 局部更新',
            subtitle: isTelevision
                ? 'TV 端为保证滚动和焦点稳定，已强制关闭这类运行时局部刷新；普通端仍可按需开启。'
                : '关闭后首页 Hero 和列表卡片不会跟随后台 metadata 缓存变化做局部刷新，只会在应用启动、保存设置或手动刷新后更新。',
            value: settings.effectiveLiveItemHeroOverlayEnabled,
            onChanged: isTelevision
                ? null
                : (value) {
                    controller.setPerformanceLiveItemHeroOverlayEnabled(value);
                  },
          ),
          SettingsStepperTile(
            title: '后台元数据最大并发数',
            subtitle: '同时执行的首页 Hero、评分和元数据补全任务数量。TV 或低性能设备建议设为 1–2；数值过高可能造成卡顿。',
            value: '${settings.metadataPrefetchMaxConcurrency}',
            onDecrease: settings.metadataPrefetchMaxConcurrency <=
                    kMetadataPrefetchMaxConcurrencyMin
                ? null
                : () {
                    controller.setMetadataPrefetchMaxConcurrency(
                      settings.metadataPrefetchMaxConcurrency - 1,
                    );
                  },
            onIncrease: settings.metadataPrefetchMaxConcurrency >=
                    kMetadataPrefetchMaxConcurrencyMax
                ? null
                : () {
                    controller.setMetadataPrefetchMaxConcurrency(
                      settings.metadataPrefetchMaxConcurrency + 1,
                    );
                  },
          ),
          SettingsStepperTile(
            title: '首批元数据预取数量',
            subtitle: 'Hero、评分和各首页分区合计先处理的数量；剩余内容会在后台分批补齐，不会丢弃。TV 推荐 12。',
            value: '${settings.metadataPrefetchInitialBatchSize}',
            onDecrease: settings.metadataPrefetchInitialBatchSize <=
                    kMetadataPrefetchInitialBatchSizeMin
                ? null
                : () {
                    controller.setMetadataPrefetchInitialBatchSize(
                      settings.metadataPrefetchInitialBatchSize -
                          kMetadataPrefetchInitialBatchSizeStep,
                    );
                  },
            onIncrease: settings.metadataPrefetchInitialBatchSize >=
                    kMetadataPrefetchInitialBatchSizeMax
                ? null
                : () {
                    controller.setMetadataPrefetchInitialBatchSize(
                      settings.metadataPrefetchInitialBatchSize +
                          kMetadataPrefetchInitialBatchSizeStep,
                    );
                  },
          ),
        ]),
      ],
    );
  }
}
