import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/application/settings_slice_providers.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';

class TaskSchedulingSettingsPage extends ConsumerWidget {
  const TaskSchedulingSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsPerformanceSliceProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
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
    final theme = Theme.of(context);

    return SettingsPageScaffold(
      onBack: () => Navigator.of(context).pop(),
      children: [
        Text('性能与后台', style: theme.textTheme.headlineSmall),
        const SettingsSectionTitle(label: '内容刷新'),
        ...buildSettingsTileGroup([
          SettingsToggleTile(
            title: '启动时自动刷新首页',
            subtitle: '冷启动应用后，首页模块会在后台重新拉取一次最新数据。',
            value: startupRefreshSettings.enabled,
            autofocus: true,
            focusId: 'performance-background:startup-refresh',
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
            focusId: 'performance-background:startup-emby',
            onChanged: startupRefreshSettings.enabled
                ? controller.setHomeStartupAutoRefreshEmbyEnabled
                : null,
          ),
          if (!isTelevision)
            SettingsToggleTile(
              title: '自动更新卡片信息',
              subtitle:
                  '开启后首页 Hero 和列表卡片会自动应用后台补全的标题、评分与图片；关闭后只在应用启动、保存设置或手动刷新时更新。',
              value: settings.configuredLiveItemHeroOverlayEnabled,
              focusId: 'performance-background:live-card-update',
              onChanged: controller.setPerformanceLiveItemHeroOverlayEnabled,
            ),
        ]),
        const SettingsSectionTitle(label: '并发控制'),
        ...buildSettingsTileGroup([
          SettingsStepperTile(
            title: '最大并发任务数',
            subtitle:
                '统一限制首页加载、搜索链接验证、后台元数据、Emby 刷新及 NAS / WebDAV 扫描补全的并发规模。TV 推荐 2，性能较好的设备可设为 3。',
            value: '${settings.taskMaxConcurrency}',
            onDecrease: settings.taskMaxConcurrency <= kTaskMaxConcurrencyMin
                ? null
                : () => controller.setTaskMaxConcurrency(
                      settings.taskMaxConcurrency - 1,
                    ),
            onIncrease: settings.taskMaxConcurrency >= kTaskMaxConcurrencyMax
                ? null
                : () => controller.setTaskMaxConcurrency(
                      settings.taskMaxConcurrency + 1,
                    ),
          ),
        ]),
        const SettingsSectionTitle(label: '元数据补全'),
        ...buildSettingsTileGroup([
          SettingsStepperTile(
            title: '首批元数据预取数量',
            subtitle: 'Hero、评分和各首页分区合计先处理的数量；剩余内容会在后台分批补齐，不会丢弃。TV 推荐 12。',
            value: '${settings.metadataPrefetchInitialBatchSize}',
            onDecrease: settings.metadataPrefetchInitialBatchSize <=
                    kMetadataPrefetchInitialBatchSizeMin
                ? null
                : () => controller.setMetadataPrefetchInitialBatchSize(
                      settings.metadataPrefetchInitialBatchSize -
                          kMetadataPrefetchInitialBatchSizeStep,
                    ),
            onIncrease: settings.metadataPrefetchInitialBatchSize >=
                    kMetadataPrefetchInitialBatchSizeMax
                ? null
                : () => controller.setMetadataPrefetchInitialBatchSize(
                      settings.metadataPrefetchInitialBatchSize +
                          kMetadataPrefetchInitialBatchSizeStep,
                    ),
          ),
          SettingsStepperTile(
            title: '元数据后台批次间隔',
            subtitle: '首批完成后继续释放后台补全任务的间隔。推荐 300 毫秒；调低会更快，调高会更省资源。',
            value: '${settings.metadataPrefetchBatchDelayMs} 毫秒',
            onDecrease: settings.metadataPrefetchBatchDelayMs <=
                    kMetadataPrefetchBatchDelayMsMin
                ? null
                : () => controller.setMetadataPrefetchBatchDelayMs(
                      settings.metadataPrefetchBatchDelayMs -
                          kMetadataPrefetchBatchDelayMsStep,
                    ),
            onIncrease: settings.metadataPrefetchBatchDelayMs >=
                    kMetadataPrefetchBatchDelayMsMax
                ? null
                : () => controller.setMetadataPrefetchBatchDelayMs(
                      settings.metadataPrefetchBatchDelayMs +
                          kMetadataPrefetchBatchDelayMsStep,
                    ),
          ),
          SettingsStepperTile(
            title: '交互结束后恢复时间',
            subtitle: '滚动、焦点移动或页面切换停止后，等待多久再继续后台补全。TV 推荐 400 毫秒。',
            value: '${settings.metadataPrefetchForegroundResumeDelayMs} 毫秒',
            onDecrease: settings.metadataPrefetchForegroundResumeDelayMs <=
                    kMetadataPrefetchForegroundResumeDelayMsMin
                ? null
                : () => controller.setMetadataPrefetchForegroundResumeDelayMs(
                      settings.metadataPrefetchForegroundResumeDelayMs -
                          kMetadataPrefetchForegroundResumeDelayMsStep,
                    ),
            onIncrease: settings.metadataPrefetchForegroundResumeDelayMs >=
                    kMetadataPrefetchForegroundResumeDelayMsMax
                ? null
                : () => controller.setMetadataPrefetchForegroundResumeDelayMs(
                      settings.metadataPrefetchForegroundResumeDelayMs +
                          kMetadataPrefetchForegroundResumeDelayMsStep,
                    ),
          ),
        ]),
        const SettingsSectionTitle(label: '首页模块'),
        ...buildSettingsTileGroup([
          SettingsStepperTile(
            title: '首页首批优先模块数',
            subtitle: '进入首页后优先启动的前几个模块；其余模块会自动错峰加载，不会遗漏。TV 推荐 1–2。',
            value: '${settings.homeFeedInitialBatchSize}',
            onDecrease: settings.homeFeedInitialBatchSize <=
                    kHomeFeedInitialBatchSizeMin
                ? null
                : () => controller.setHomeFeedInitialBatchSize(
                      settings.homeFeedInitialBatchSize - 1,
                    ),
            onIncrease: settings.homeFeedInitialBatchSize >=
                    kHomeFeedInitialBatchSizeMax
                ? null
                : () => controller.setHomeFeedInitialBatchSize(
                      settings.homeFeedInitialBatchSize + 1,
                    ),
          ),
          SettingsStepperTile(
            title: '首页后台批次间隔',
            subtitle: '首批首页模块之后继续加载其余模块的间隔。推荐 350 毫秒。',
            value: '${settings.homeFeedBatchDelayMs} 毫秒',
            onDecrease: settings.homeFeedBatchDelayMs <=
                    kHomeFeedBatchDelayMsMin
                ? null
                : () => controller.setHomeFeedBatchDelayMs(
                      settings.homeFeedBatchDelayMs - kHomeFeedBatchDelayMsStep,
                    ),
            onIncrease: settings.homeFeedBatchDelayMs >=
                    kHomeFeedBatchDelayMsMax
                ? null
                : () => controller.setHomeFeedBatchDelayMs(
                      settings.homeFeedBatchDelayMs + kHomeFeedBatchDelayMsStep,
                    ),
          ),
        ]),
      ],
    );
  }
}
