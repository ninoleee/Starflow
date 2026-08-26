import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/core/widgets/no_animation_page_route.dart';
import 'package:starflow/core/widgets/section_panel.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/application/settings_slice_providers.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/home_settings_page.dart';
import 'package:starflow/features/settings/presentation/interface_settings_page.dart';
import 'package:starflow/features/settings/presentation/media_source_settings_page.dart';
import 'package:starflow/features/settings/presentation/metadata_match_settings_page.dart';
import 'package:starflow/features/settings/presentation/local_storage_settings_page.dart';
import 'package:starflow/features/settings/presentation/logging_settings_page.dart';
import 'package:starflow/features/settings/presentation/network_storage_settings_page.dart';
import 'package:starflow/features/settings/presentation/playback_settings_page.dart';
import 'package:starflow/features/settings/presentation/playback_tuning_settings_page.dart';
import 'package:starflow/features/settings/presentation/search_service_settings_page.dart';
import 'package:starflow/features/settings/presentation/settings_management_page.dart';
import 'package:starflow/features/settings/presentation/settings_version_label.dart';
import 'package:starflow/features/settings/presentation/task_scheduling_settings_page.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';

final Future<PackageInfo> _settingsPagePackageInfoFuture =
    PackageInfo.fromPlatform();

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();

  Widget buildPage(
    BuildContext context,
    WidgetRef ref, {
    required ScrollController scrollController,
    required FocusNode headerFocusNode,
  }) {
    final mediaSources = ref.watch(settingsMediaSourcesProvider);
    final playbackSlice = ref.watch(settingsPlaybackSliceProvider);
    final performanceSlice = ref.watch(settingsPerformanceSliceProvider);
    final loading = ref.watch(settingsControllerProvider).isLoading;
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    final navigationDestinationIds = ref.watch(
      appSettingsProvider
          .select((settings) => settings.navigationDestinationIds),
    );

    return AppPrimaryScrollController(
      controller: scrollController,
      child: TvPageFocusScope(
        isTelevision: isTelevision,
        child: Scaffold(
          body: AppPageBackground(
            contentPadding: appPageContentPadding(
              context,
              includeBottomNavigationBar: true,
            ),
            child: ListView(
              controller: scrollController,
              padding: EdgeInsets.zero,
              children: [
                if (loading) const LinearProgressIndicator(),
                _SettingsPageHeader(
                  isTelevision: isTelevision,
                  focusNode: headerFocusNode,
                ),
                const SizedBox(height: 18),
                SectionPanel(
                  title: '内容与来源',
                  child: Column(
                    children: [
                      _SettingsNavigationTile(
                        title: '媒体源管理',
                        subtitle: _enabledCountSummary(mediaSources),
                        onTap: () => _openMediaSourceSettings(context),
                      ),
                      const SizedBox(height: 10),
                      _SettingsNavigationTile(
                        title: '搜索服务管理',
                        subtitle: '在线服务与搜索来源',
                        onTap: () => _openSearchServiceSettings(context),
                      ),
                      const SizedBox(height: 10),
                      _SettingsNavigationTile(
                        title: '网络存储',
                        subtitle: '夸克、SmartStrm、同步与索引刷新',
                        onTap: () => _openNetworkStorageSettings(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SectionPanel(
                  title: '元数据',
                  child: _SettingsNavigationTile(
                    title: '元数据匹配',
                    subtitle: 'TMDB、WMDB、自动匹配与匹配优先级',
                    onTap: () => _openMetadataMatchSettings(context),
                  ),
                ),
                const SizedBox(height: 18),
                SectionPanel(
                  title: '播放',
                  child: Column(
                    children: [
                      _SettingsNavigationTile(
                        title: '播放器与字幕',
                        subtitle: _playbackSettingsSummary(
                          playbackSlice,
                          isTelevision: isTelevision,
                        ),
                        onTap: () => _openPlaybackSettings(
                          context,
                          playbackSlice,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _SettingsNavigationTile(
                        title: 'MPV 调优',
                        subtitle:
                            performanceSlice.aggressivePlaybackTuningEnabled
                                ? '激进性能调优已开启'
                                : '使用标准播放参数',
                        onTap: () => _openPlaybackTuningSettings(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SectionPanel(
                  title: '界面',
                  child: Column(
                    children: [
                      _SettingsNavigationTile(
                        title: '首页设置',
                        subtitle: 'Hero、首页模块与数据来源',
                        onTap: () => _openHomeSettings(context),
                      ),
                      const SizedBox(height: 10),
                      _SettingsNavigationTile(
                        title: '界面效果',
                        subtitle: '特效、动画、Hero 与导航交互',
                        onTap: () => _openInterfaceSettings(context),
                      ),
                      const SizedBox(height: 10),
                      _SettingsNavigationTile(
                        title: '菜单栏按钮',
                        subtitle: _navigationDestinationSummary(
                          navigationDestinationIds,
                        ),
                        onTap: () => _openNavigationDestinationPicker(
                          context,
                          ref,
                          selectedIds: navigationDestinationIds,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SectionPanel(
                  title: '性能与后台',
                  child: _SettingsNavigationTile(
                    title: '任务调度',
                    subtitle: '最大并发 ${performanceSlice.taskMaxConcurrency}',
                    onTap: () => _openBackgroundTaskSettings(context),
                  ),
                ),
                const SizedBox(height: 18),
                SectionPanel(
                  title: '数据与维护',
                  child: Column(
                    children: [
                      _SettingsNavigationTile(
                        title: '本地存储',
                        subtitle: '查看分类占用并安全清理缓存',
                        onTap: () => _openLocalStorageSettings(context),
                      ),
                      const SizedBox(height: 10),
                      _SettingsNavigationTile(
                        title: '日志',
                        subtitle: '记录、预览、筛选、导出与清理',
                        onTap: () => _openLoggingSettings(context),
                      ),
                      const SizedBox(height: 10),
                      _SettingsNavigationTile(
                        title: '配置管理',
                        subtitle: '导入、导出与 TV 二维码传输',
                        onTap: () => _openSettingsManagement(context),
                      ),
                    ],
                  ),
                ),
                const _SettingsPageVersionFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openMediaSourceSettings(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      NoAnimationMaterialPageRoute<void>(
        builder: (context) => const MediaSourceSettingsPage(),
      ),
    );
  }

  Future<void> _openSearchServiceSettings(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      NoAnimationMaterialPageRoute<void>(
        builder: (context) => const SearchServiceSettingsPage(),
      ),
    );
  }

  Future<void> _openMetadataMatchSettings(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      NoAnimationMaterialPageRoute<void>(
        builder: (context) => const MetadataMatchSettingsPage(),
      ),
    );
  }

  Future<void> _openNetworkStorageSettings(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      NoAnimationMaterialPageRoute<void>(
        builder: (context) => const NetworkStorageSettingsPage(),
      ),
    );
  }

  Future<void> _openPlaybackSettings(
    BuildContext context,
    SettingsPlaybackSlice playbackSlice,
  ) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      NoAnimationMaterialPageRoute<void>(
        builder: (context) => PlaybackSettingsPage(
          initialTimeoutSeconds: playbackSlice.playbackOpenTimeoutSeconds,
          initialDefaultSpeed: playbackSlice.playbackDefaultSpeed,
          initialSubtitlePreference: playbackSlice.playbackSubtitlePreference,
          initialSubtitleScale: playbackSlice.playbackSubtitleScale,
          initialOnlineSubtitleSources: playbackSlice.onlineSubtitleSources,
          initialAssrtToken: playbackSlice.assrtToken,
          initialOpensubtitlesEnabled: playbackSlice.opensubtitlesEnabled,
          initialOpensubtitlesUsername: playbackSlice.opensubtitlesUsername,
          initialOpensubtitlesPassword: playbackSlice.opensubtitlesPassword,
          initialSubdlEnabled: playbackSlice.subdlEnabled,
          initialSubdlApiKey: playbackSlice.subdlApiKey,
          initialSubtitlePreferredLanguages:
              playbackSlice.subtitlePreferredLanguages,
          initialSubtitleSearchMaxValidatedCandidates:
              playbackSlice.subtitleSearchMaxValidatedCandidates,
          initialBackgroundPlaybackEnabled:
              playbackSlice.configuredBackgroundPlaybackEnabled,
          initialPlaybackEngine: playbackSlice.playbackEngine,
          initialPlaybackDecodeMode: playbackSlice.playbackDecodeMode,
          initialPlaybackMpvDoubleTapToSeekEnabled:
              playbackSlice.playbackMpvDoubleTapToSeekEnabled,
          initialPlaybackMpvSwipeToSeekEnabled:
              playbackSlice.playbackMpvSwipeToSeekEnabled,
          initialPlaybackMpvLongPressSpeedBoostEnabled:
              playbackSlice.playbackMpvLongPressSpeedBoostEnabled,
          initialPlaybackMpvStallAutoRecoveryEnabled:
              playbackSlice.playbackMpvStallAutoRecoveryEnabled,
        ),
      ),
    );
  }

  Future<void> _openPlaybackTuningSettings(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      NoAnimationMaterialPageRoute<void>(
        builder: (context) => const PlaybackTuningSettingsPage(),
      ),
    );
  }

  Future<void> _openInterfaceSettings(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      NoAnimationMaterialPageRoute<void>(
        builder: (context) => const InterfaceSettingsPage(),
      ),
    );
  }

  Future<void> _openBackgroundTaskSettings(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      NoAnimationMaterialPageRoute<void>(
        builder: (context) => const TaskSchedulingSettingsPage(),
      ),
    );
  }

  Future<void> _openHomeSettings(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      NoAnimationMaterialPageRoute<void>(
        builder: (context) => const HomeSettingsPage(),
      ),
    );
  }

  Future<void> _openNavigationDestinationPicker(
    BuildContext context,
    WidgetRef ref, {
    required List<String> selectedIds,
  }) async {
    final selected = await showSettingsCheckboxSelectionDialog<String>(
      context: context,
      title: '选择菜单栏按钮',
      initialSelection: selectedIds.toSet(),
      showAllOption: false,
      showClearAction: false,
      sections: const [
        SettingsCheckboxDialogSection<String>(
          options: [
            SettingsCheckboxDialogOption(
                value: kNavigationDestinationHome, title: '首页'),
            SettingsCheckboxDialogOption(
                value: kNavigationDestinationSearch, title: '搜索'),
            SettingsCheckboxDialogOption(
                value: kNavigationDestinationFavorites, title: '收藏'),
            SettingsCheckboxDialogOption(
                value: kNavigationDestinationLibrary, title: '媒体库'),
            SettingsCheckboxDialogOption(
                value: kNavigationDestinationSettings, title: '设置'),
          ],
        ),
      ],
    );
    if (selected == null) {
      return;
    }
    await ref
        .read(settingsControllerProvider.notifier)
        .setNavigationDestinationIds(selected);
  }

  Future<void> _openLocalStorageSettings(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      NoAnimationMaterialPageRoute<void>(
        builder: (context) => const LocalStorageSettingsPage(),
      ),
    );
  }

  Future<void> _openLoggingSettings(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      NoAnimationMaterialPageRoute<void>(
        builder: (context) => const LoggingSettingsPage(),
      ),
    );
  }

  Future<void> _openSettingsManagement(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      NoAnimationMaterialPageRoute<void>(
        builder: (context) => const SettingsManagementPage(),
      ),
    );
  }
}

class _SettingsPageVersionFooter extends StatelessWidget {
  const _SettingsPageVersionFooter();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<PackageInfo>(
      future: _settingsPagePackageInfoFuture,
      builder: (context, snapshot) {
        final info = snapshot.data;
        if (info == null) {
          return const SizedBox(height: kBottomReservedSpacing);
        }
        final footerInfo = resolveSettingsVersionFooterInfo(info);
        if (footerInfo == null) {
          return const SizedBox(height: kBottomReservedSpacing);
        }
        return Padding(
          padding: const EdgeInsets.only(
            top: 18,
            bottom: kBottomReservedSpacing,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  footerInfo.author,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.72,
                    ),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                TvFocusableAction(
                  focusId: 'settings-root-footer:version',
                  onPressed: () {},
                  visualStyle: TvFocusVisualStyle.subtle,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: Text(
                      footerInfo.version,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.82,
                        ),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (footerInfo.buildDate.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    footerInfo.buildDate,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.72,
                      ),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final ScrollController _scrollController = ScrollController();
  final FocusNode _headerFocusNode = FocusNode(debugLabel: 'settings-header');

  @override
  void dispose() {
    _headerFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.buildPage(
      context,
      ref,
      scrollController: _scrollController,
      headerFocusNode: _headerFocusNode,
    );
  }
}

String _playbackSettingsSummary(
  SettingsPlaybackSlice playbackSlice, {
  bool isTelevision = false,
}) {
  return [
    playbackSlice.playbackEngine.label,
    playbackSlice.playbackDecodeMode.label,
    if (playbackSlice.playbackEngine == PlaybackEngine.embeddedMpv)
      playbackSlice.playbackMpvDoubleTapToSeekEnabled ||
              playbackSlice.playbackMpvSwipeToSeekEnabled ||
              playbackSlice.playbackMpvLongPressSpeedBoostEnabled
          ? 'MPV 触控增强'
          : 'MPV 触控精简',
    if (playbackSlice.playbackEngine == PlaybackEngine.embeddedMpv)
      playbackSlice.playbackMpvStallAutoRecoveryEnabled ? '自动恢复开' : '自动恢复关',
    '${playbackSlice.playbackOpenTimeoutSeconds}s 超时',
    '${_formatPlaybackSpeedLabel(playbackSlice.playbackDefaultSpeed)} 默认倍速',
    '字幕 ${playbackSlice.playbackSubtitlePreference.label}',
    formatPlaybackSubtitleScaleLabel(playbackSlice.playbackSubtitleScale),
    if ((playbackSlice.onlineSubtitleSources.contains(
              OnlineSubtitleSource.assrt,
            ) &&
            playbackSlice.assrtToken.trim().isNotEmpty) ||
        playbackSlice.opensubtitlesEnabled ||
        playbackSlice.subdlEnabled)
      [
        if (playbackSlice.onlineSubtitleSources.contains(
              OnlineSubtitleSource.assrt,
            ) &&
            playbackSlice.assrtToken.trim().isNotEmpty)
          'ASSRT API',
        if (playbackSlice.opensubtitlesEnabled) 'OpenSubtitles',
        if (playbackSlice.subdlEnabled) 'SubDL',
      ].join('/'),
    isTelevision
        ? 'TV 端后台播放禁用'
        : playbackSlice.configuredBackgroundPlaybackEnabled
            ? '后台播放开'
            : '后台播放关',
  ].join(' · ');
}

String _navigationDestinationSummary(List<String> selectedIds) {
  const labels = <String, String>{
    kNavigationDestinationHome: '首页',
    kNavigationDestinationSearch: '搜索',
    kNavigationDestinationFavorites: '收藏',
    kNavigationDestinationLibrary: '媒体库',
    kNavigationDestinationSettings: '设置',
  };
  final selected = normalizeNavigationDestinationIds(selectedIds);
  return selected.map((id) => labels[id]).whereType<String>().join('、');
}

String _enabledCountSummary(List<MediaSourceConfig> sources) {
  if (sources.isEmpty) {
    return '尚未添加';
  }
  final enabledCount = sources.where((source) => source.enabled).length;
  return '已启用 $enabledCount / ${sources.length}';
}

String _formatPlaybackSpeedLabel(double speed) {
  if (speed == speed.roundToDouble()) {
    return '${speed.toStringAsFixed(0)}x';
  }
  return '${speed.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')}x';
}

class _SettingsPageHeader extends StatelessWidget {
  const _SettingsPageHeader({
    required this.isTelevision,
    this.focusNode,
  });

  final bool isTelevision;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '设置',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
    if (!isTelevision) {
      return content;
    }
    return TvFocusableAction(
      onPressed: () => FocusScope.of(context).nextFocus(),
      focusNode: focusNode,
      focusId: 'settings:header',
      borderRadius: BorderRadius.circular(28),
      child: content,
    );
  }
}

class _SettingsNavigationTile extends StatelessWidget {
  const _SettingsNavigationTile({
    required this.title,
    required this.onTap,
    this.subtitle = '',
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return StarflowSelectionTile(
      title: title,
      subtitle: subtitle,
      onPressed: onTap,
    );
  }
}
