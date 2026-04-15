import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/core/widgets/no_animation_page_route.dart';
import 'package:starflow/core/widgets/section_panel.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/home/application/home_controller.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/application/settings_slice_providers.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/media_source_editor_page.dart';
import 'package:starflow/features/settings/presentation/metadata_match_settings_page.dart';
import 'package:starflow/features/settings/presentation/local_storage_settings_page.dart';
import 'package:starflow/features/settings/presentation/network_storage_settings_page.dart';
import 'package:starflow/features/settings/presentation/performance_settings_page.dart';
import 'package:starflow/features/settings/presentation/playback_settings_page.dart';
import 'package:starflow/features/settings/presentation/search_provider_editor_page.dart';
import 'package:starflow/features/settings/presentation/settings_management_page.dart';
import 'package:starflow/features/settings/presentation/settings_version_label.dart';
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
    required TvFocusMemoryController tvFocusMemoryController,
  }) {
    final mediaSources = ref.watch(settingsMediaSourcesProvider);
    final searchProviders = ref.watch(settingsSearchProvidersProvider);
    final searchSourceIds = ref.watch(settingsSearchSourceIdsProvider);
    final libraryMatchSourceIds =
        ref.watch(settingsLibraryMatchSourceIdsProvider);
    final detailAutoLibraryMatchEnabled =
        ref.watch(settingsDetailAutoLibraryMatchEnabledProvider);
    final networkStorage = ref.watch(settingsNetworkStorageProvider);
    final heroSlice = ref.watch(settingsHeroSliceProvider);
    final playbackSlice = ref.watch(settingsPlaybackSliceProvider);
    final performanceSlice = ref.watch(settingsPerformanceSliceProvider);
    final loading = ref.watch(settingsControllerProvider).isLoading;
    final heroCandidates = ref.watch(homeHeroModuleCandidatesProvider);
    final heroModule = ref.watch(homeHeroModuleProvider);
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    final heroEnabled = heroModule?.enabled ?? false;

    return TvPageFocusScope(
      controller: tvFocusMemoryController,
      scopeId: 'settings',
      isTelevision: isTelevision,
      child: Scaffold(
        body: AppPageBackground(
          contentPadding: appPageContentPadding(
            context,
            includeBottomNavigationBar: true,
          ),
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
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
                  title: '媒体源',
                  child: Column(
                    children: [
                      ...mediaSources.map(
                        (source) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _SettingsTile(
                            title: source.name,
                            value: source.enabled,
                            onChanged: (value) {
                              ref
                                  .read(settingsControllerProvider.notifier)
                                  .toggleMediaSource(source.id, value);
                            },
                            onEdit: () => _openMediaSourceEditor(
                              context,
                              existing: source,
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: StarflowButton(
                          label: '新增媒体源',
                          icon: Icons.add_rounded,
                          onPressed: () => _openMediaSourceEditor(context),
                          variant: StarflowButtonVariant.secondary,
                          compact: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SectionPanel(
                  title: '搜索服务',
                  child: Column(
                    children: [
                      ...searchProviders.map(
                        (provider) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _SettingsTile(
                            title: provider.name,
                            value: provider.enabled,
                            onChanged: (value) {
                              ref
                                  .read(settingsControllerProvider.notifier)
                                  .toggleSearchProvider(provider.id, value);
                            },
                            onEdit: () => _openSearchProviderEditor(
                              context,
                              existing: provider,
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: StarflowButton(
                          label: '新增搜索服务',
                          icon: Icons.add_rounded,
                          onPressed: () => _openSearchProviderEditor(context),
                          variant: StarflowButtonVariant.secondary,
                          compact: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _SettingsNavigationTile(
                        title: '搜索来源',
                        subtitle: _searchSourceSummary(
                          mediaSources: mediaSources,
                          searchProviders: searchProviders,
                          searchSourceIds: searchSourceIds,
                        ),
                        onTap: () => _openSearchSourcePicker(
                          context,
                          ref,
                          mediaSources: mediaSources,
                          searchProviders: searchProviders,
                          searchSourceIds: searchSourceIds,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SectionPanel(
                  title: '元数据与评分',
                  child: Column(
                    children: [
                      _SettingsNavigationTile(
                        title: '打开匹配与评分设置',
                        subtitle: detailAutoLibraryMatchEnabled
                            ? '详情页自动匹配资源：已开启'
                            : '详情页自动匹配资源：已关闭',
                        onTap: () => _openMetadataMatchSettings(context),
                      ),
                      const SizedBox(height: 10),
                      _SettingsNavigationTile(
                        title: '匹配来源',
                        subtitle: _libraryMatchSourceSummary(
                          mediaSources: mediaSources,
                          selectedIds: libraryMatchSourceIds,
                        ),
                        onTap: () => _openLibraryMatchSourcePicker(
                          context,
                          ref,
                          mediaSources: mediaSources,
                          selectedIds: libraryMatchSourceIds,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SectionPanel(
                  title: '网络存储',
                  child: _SettingsNavigationTile(
                    title: '夸克与 STRM',
                    onTap: () => _openNetworkStorageSettings(
                      context,
                      networkStorage,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SectionPanel(
                  title: '本地存储',
                  child: _SettingsNavigationTile(
                    title: '查看分类与清理',
                    onTap: () => _openLocalStorageSettings(context),
                  ),
                ),
                const SizedBox(height: 18),
                SectionPanel(
                  title: '配置管理',
                  child: _SettingsNavigationTile(
                    title: '导入与导出配置',
                    onTap: () => _openSettingsManagement(context),
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
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SectionPanel(
                  title: '外观',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SettingsNavigationTile(
                        title: '高性能与轻量模式',
                        subtitle: performanceSettingsSummary(performanceSlice),
                        onTap: () => _openPerformanceSettings(context),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '首页 Hero',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Hero 展示方式',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final mode in HomeHeroDisplayMode.values)
                            StarflowChipButton(
                              label: mode.label,
                              selected: mode == heroSlice.displayMode,
                              onPressed: heroEnabled
                                  ? () {
                                      ref
                                          .read(settingsControllerProvider
                                              .notifier)
                                          .setHomeHeroDisplayMode(mode);
                                    }
                                  : null,
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      StarflowToggleTile(
                        title: '标题优先展示 Logo',
                        value: heroSlice.logoTitleEnabled,
                        onChanged: heroEnabled
                            ? (value) {
                                ref
                                    .read(settingsControllerProvider.notifier)
                                    .setHomeHeroLogoTitleEnabled(value);
                              }
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SectionPanel(
                  title: '首页模块',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hero 模块',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 10),
                      ...buildSettingsTileGroup([
                        StarflowToggleTile(
                          title: '启用 Hero',
                          value: heroEnabled,
                          onChanged: (value) {
                            ref
                                .read(settingsControllerProvider.notifier)
                                .setHomeHeroEnabled(value);
                          },
                        ),
                        StarflowSelectionTile(
                          title: 'Hero 数据来源',
                          value: _heroSourceLabel(
                            heroSlice: heroSlice,
                            heroCandidates: heroCandidates,
                          ),
                          onPressed: heroEnabled
                              ? () => _openHeroSourcePicker(
                                    context,
                                    ref,
                                    heroSlice: heroSlice,
                                    heroCandidates: heroCandidates,
                                  )
                              : null,
                        ),
                        _SettingsNavigationTile(
                          title: '打开首页编辑器',
                          onTap: () => context.pushNamed('home-editor'),
                        ),
                      ], spacing: 10),
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

  Future<void> _openMediaSourceEditor(
    BuildContext context, {
    MediaSourceConfig? existing,
  }) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      NoAnimationMaterialPageRoute<void>(
        builder: (context) => MediaSourceEditorPage(initial: existing),
      ),
    );
  }

  Future<void> _openSearchProviderEditor(
    BuildContext context, {
    SearchProviderConfig? existing,
  }) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      NoAnimationMaterialPageRoute<void>(
        builder: (context) => SearchProviderEditorPage(initial: existing),
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

  Future<void> _openSearchSourcePicker(
    BuildContext context,
    WidgetRef ref, {
    required List<MediaSourceConfig> mediaSources,
    required List<SearchProviderConfig> searchProviders,
    required List<String> searchSourceIds,
  }) async {
    final availableLocalSources = mediaSources
        .where(_isSelectableLocalMediaSource)
        .toList(growable: false);
    final availableProviders = searchProviders
        .where((provider) => provider.enabled)
        .toList(growable: false);
    if (availableLocalSources.isEmpty && availableProviders.isEmpty) {
      return;
    }

    final initialSelection = searchSourceIds.toSet();
    final selected = await showSettingsCheckboxSelectionDialog<String>(
      context: context,
      title: '选择搜索来源',
      initialSelection: initialSelection,
      allLabel: '全部已启用来源',
      allSubtitle: '清空单独选择，搜索时使用全部已启用本地源和搜索服务',
      sections: [
        if (availableLocalSources.isNotEmpty)
          SettingsCheckboxDialogSection<String>(
            title: '本地媒体源',
            options: availableLocalSources
                .map(
                  (source) => SettingsCheckboxDialogOption<String>(
                    value: searchSourceSettingIdForMediaSource(source.id),
                    title: source.name,
                    subtitle: source.kind.label,
                  ),
                )
                .toList(growable: false),
          ),
        if (availableProviders.isNotEmpty)
          SettingsCheckboxDialogSection<String>(
            title: '搜索服务',
            options: availableProviders
                .map(
                  (provider) => SettingsCheckboxDialogOption<String>(
                    value: searchSourceSettingIdForProvider(provider.id),
                    title: provider.name,
                    subtitle: provider.kind.label,
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
    if (selected == null) {
      return;
    }
    await ref
        .read(settingsControllerProvider.notifier)
        .setSearchSourceIds(selected.toList(growable: false));
  }

  Future<void> _openLibraryMatchSourcePicker(
    BuildContext context,
    WidgetRef ref, {
    required List<MediaSourceConfig> mediaSources,
    required List<String> selectedIds,
  }) async {
    final availableSources = mediaSources
        .where(_isSelectableLocalMediaSource)
        .toList(growable: false);
    if (availableSources.isEmpty) {
      return;
    }

    final initialSelection = selectedIds.toSet();
    final selected = await showSettingsCheckboxSelectionDialog<String>(
      context: context,
      title: '选择匹配来源',
      initialSelection: initialSelection,
      allLabel: '全部已启用来源',
      allSubtitle: '清空单独选择，匹配时扫描全部已启用媒体源',
      sections: [
        SettingsCheckboxDialogSection<String>(
          options: availableSources
              .map(
                (source) => SettingsCheckboxDialogOption<String>(
                  value: source.id,
                  title: source.name,
                  subtitle: source.kind.label,
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
    if (selected == null) {
      return;
    }
    await ref
        .read(settingsControllerProvider.notifier)
        .setLibraryMatchSourceIds(selected.toList(growable: false));
  }

  Future<void> _openNetworkStorageSettings(
    BuildContext context,
    NetworkStorageConfig initial,
  ) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      NoAnimationMaterialPageRoute<void>(
        builder: (context) => NetworkStorageSettingsPage(initial: initial),
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

  Future<void> _openPerformanceSettings(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      NoAnimationMaterialPageRoute<void>(
        builder: (context) => const PerformanceSettingsPage(),
      ),
    );
  }

  Future<void> _openLocalStorageSettings(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      NoAnimationMaterialPageRoute<void>(
        builder: (context) => const LocalStorageSettingsPage(),
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

  Future<void> _openHeroSourcePicker(
    BuildContext context,
    WidgetRef ref, {
    required SettingsHeroSlice heroSlice,
    required List<HomeModuleConfig> heroCandidates,
  }) async {
    final selection = await showDialog<String>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('选择 Hero 数据来源'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(''),
              child: Text(
                heroSlice.sourceModuleId.trim().isEmpty ? '自动选择  当前' : '自动选择',
              ),
            ),
            for (final module in heroCandidates)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(module.id),
                child: Text(
                  module.id == heroSlice.sourceModuleId
                      ? '${module.title}  当前'
                      : module.title,
                ),
              ),
          ],
        );
      },
    );
    if (selection == null) {
      return;
    }
    await ref
        .read(settingsControllerProvider.notifier)
        .setHomeHeroSourceModuleId(selection);
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
  final TvFocusMemoryController _tvFocusMemoryController =
      TvFocusMemoryController();

  @override
  void dispose() {
    _headerFocusNode.dispose();
    _scrollController.dispose();
    _tvFocusMemoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.buildPage(
      context,
      ref,
      scrollController: _scrollController,
      headerFocusNode: _headerFocusNode,
      tvFocusMemoryController: _tvFocusMemoryController,
    );
  }
}

String _resolveHeroModuleSelectionValue({
  required SettingsHeroSlice heroSlice,
  required List<HomeModuleConfig> heroCandidates,
}) {
  final selectedId = heroSlice.sourceModuleId.trim();
  if (selectedId.isEmpty) {
    return '';
  }
  for (final module in heroCandidates) {
    if (module.id == selectedId) {
      return selectedId;
    }
  }
  return '';
}

String _heroSourceLabel({
  required SettingsHeroSlice heroSlice,
  required List<HomeModuleConfig> heroCandidates,
}) {
  final selectedId = _resolveHeroModuleSelectionValue(
    heroSlice: heroSlice,
    heroCandidates: heroCandidates,
  );
  if (selectedId.isEmpty) {
    return '自动选择';
  }
  for (final module in heroCandidates) {
    if (module.id == selectedId) {
      return module.title;
    }
  }
  return '自动选择';
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
    playbackSlice.playbackSubtitleScale.label,
    isTelevision
        ? 'TV 端后台播放禁用'
        : playbackSlice.configuredBackgroundPlaybackEnabled
            ? '后台播放开'
            : '后台播放关',
  ].join(' · ');
}

String _searchSourceSummary({
  required List<MediaSourceConfig> mediaSources,
  required List<SearchProviderConfig> searchProviders,
  required List<String> searchSourceIds,
}) {
  final availableLocalSources =
      mediaSources.where(_isSelectableLocalMediaSource).toList(growable: false);
  final availableProviders = searchProviders
      .where((provider) => provider.enabled)
      .toList(growable: false);
  final totalCount = availableLocalSources.length + availableProviders.length;
  if (totalCount == 0) {
    return '暂无可选来源';
  }

  final selectedIds = searchSourceIds.toSet();
  if (selectedIds.isEmpty) {
    return '全部已启用来源';
  }

  final selectedLabels = <String>[
    ...availableLocalSources
        .where(
          (source) => selectedIds.contains(
            searchSourceSettingIdForMediaSource(source.id),
          ),
        )
        .map((source) => source.name),
    ...availableProviders
        .where(
          (provider) => selectedIds.contains(
            searchSourceSettingIdForProvider(provider.id),
          ),
        )
        .map((provider) => provider.name),
  ];
  if (selectedLabels.isEmpty || selectedLabels.length >= totalCount) {
    return '全部已启用来源';
  }
  if (selectedLabels.length <= 2) {
    return selectedLabels.join('、');
  }
  return '${selectedLabels.take(2).join('、')} 等 ${selectedLabels.length} 个来源';
}

String _libraryMatchSourceSummary({
  required List<MediaSourceConfig> mediaSources,
  required List<String> selectedIds,
}) {
  final availableSources =
      mediaSources.where(_isSelectableLocalMediaSource).toList(growable: false);
  if (availableSources.isEmpty) {
    return '暂无可选来源';
  }

  final selectedIdsSet = selectedIds.toSet();
  if (selectedIdsSet.isEmpty) {
    return '全部已启用来源';
  }

  final selectedNames = availableSources
      .where((source) => selectedIdsSet.contains(source.id))
      .map((source) => source.name)
      .toList(growable: false);
  if (selectedNames.isEmpty ||
      selectedNames.length >= availableSources.length) {
    return '全部已启用来源';
  }
  if (selectedNames.length <= 2) {
    return selectedNames.join('、');
  }
  return '${selectedNames.take(2).join('、')} 等 ${selectedNames.length} 个来源';
}

bool _isSelectableLocalMediaSource(MediaSourceConfig source) {
  if (!source.enabled) {
    return false;
  }
  if (source.kind == MediaSourceKind.quark) {
    return source.hasConfiguredQuarkFolder;
  }
  return source.kind == MediaSourceKind.emby ||
      source.kind == MediaSourceKind.nas;
}

String _formatPlaybackSpeedLabel(double speed) {
  if (speed == speed.roundToDouble()) {
    return '${speed.toStringAsFixed(0)}x';
  }
  return '${speed.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')}x';
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.title,
    required this.value,
    required this.onChanged,
    required this.onEdit,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final toggleLabel = value ? '已开启' : '已关闭';
        final toggleIcon =
            value ? Icons.toggle_on_rounded : Icons.toggle_off_rounded;
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: scheme.outlineVariant,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value ? '已开启' : '已关闭',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              compact
                  ? StarflowIconButton(
                      icon: Icons.edit_outlined,
                      onPressed: onEdit,
                      variant: StarflowButtonVariant.secondary,
                      tooltip: '编辑',
                    )
                  : StarflowButton(
                      label: '编辑',
                      icon: Icons.edit_outlined,
                      onPressed: onEdit,
                      variant: StarflowButtonVariant.secondary,
                      compact: true,
                    ),
              const SizedBox(width: 8),
              compact
                  ? StarflowIconButton(
                      icon: toggleIcon,
                      onPressed: () => onChanged(!value),
                      variant: value
                          ? StarflowButtonVariant.primary
                          : StarflowButtonVariant.secondary,
                      tooltip: toggleLabel,
                    )
                  : StarflowButton(
                      label: toggleLabel,
                      icon: toggleIcon,
                      onPressed: () => onChanged(!value),
                      variant: value
                          ? StarflowButtonVariant.primary
                          : StarflowButtonVariant.secondary,
                      compact: true,
                    ),
            ],
          ),
        );
      },
    );
  }
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
          const SizedBox(height: 8),
          Text(
            '集中管理媒体源、搜索服务、元数据、网络存储、播放与首页展示。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
