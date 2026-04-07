import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/core/widgets/section_panel.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/home/application/home_controller.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/media_source_editor_page.dart';
import 'package:starflow/features/settings/presentation/metadata_match_settings_page.dart';
import 'package:starflow/features/settings/presentation/local_storage_settings_page.dart';
import 'package:starflow/features/settings/presentation/network_storage_settings_page.dart';
import 'package:starflow/features/settings/presentation/playback_settings_page.dart';
import 'package:starflow/features/settings/presentation/search_provider_editor_page.dart';
import 'package:starflow/features/settings/presentation/settings_management_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final loading = ref.watch(settingsControllerProvider).isLoading;
    final heroCandidates = ref.watch(homeHeroModuleCandidatesProvider);
    final heroModule = ref.watch(homeHeroModuleProvider);
    final isTelevision = ref.watch(isTelevisionProvider).valueOrNull ?? false;
    final heroEnabled = heroModule?.enabled ?? false;

    return Scaffold(
      body: AppPageBackground(
        contentPadding: appPageContentPadding(
          context,
          includeBottomNavigationBar: true,
        ),
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              if (loading) const LinearProgressIndicator(),
              _SettingsPageHeader(isTelevision: isTelevision),
              const SizedBox(height: 18),
              SectionPanel(
                title: '媒体源',
                child: Column(
                  children: [
                    ...settings.mediaSources.map(
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
                    ...settings.searchProviders.map(
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
                      subtitle: _searchSourceSummary(settings),
                      onTap: () =>
                          _openSearchSourcePicker(context, ref, settings),
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
                      subtitle: settings.detailAutoLibraryMatchEnabled
                          ? '详情页自动匹配资源：已开启'
                          : '详情页自动匹配资源：已关闭',
                      onTap: () => _openMetadataMatchSettings(context),
                    ),
                    const SizedBox(height: 10),
                    _SettingsNavigationTile(
                      title: '匹配来源',
                      subtitle: _libraryMatchSourceSummary(settings),
                      onTap: () =>
                          _openLibraryMatchSourcePicker(context, ref, settings),
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
                    settings.networkStorage,
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
                      subtitle: _playbackSettingsSummary(settings),
                      onTap: () => _openPlaybackSettings(
                        context,
                        settings,
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
                    Text(
                      '应用界面',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 10),
                    StarflowToggleTile(
                      title: '高性能模式',
                      subtitle: _highPerformanceModeSummary(),
                      value: settings.highPerformanceModeEnabled,
                      onChanged: (value) {
                        ref
                            .read(settingsControllerProvider.notifier)
                            .setHighPerformanceModeEnabled(value);
                      },
                    ),
                    const SizedBox(height: 10),
                    StarflowToggleTile(
                      title: '透明磨砂效果',
                      subtitle: _translucentEffectsSummary(settings),
                      value: _effectiveTranslucentEffectsEnabled(settings),
                      onChanged: settings.highPerformanceModeEnabled
                          ? null
                          : (value) {
                              ref
                                  .read(settingsControllerProvider.notifier)
                                  .setTranslucentEffectsEnabled(value);
                            },
                    ),
                    const SizedBox(height: 10),
                    StarflowToggleTile(
                      title: '自动隐藏菜单栏',
                      subtitle: _autoHideNavigationBarSummary(settings),
                      value: settings.autoHideNavigationBarEnabled,
                      onChanged: (value) {
                        ref
                            .read(settingsControllerProvider.notifier)
                            .setAutoHideNavigationBarEnabled(value);
                      },
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
                            selected: mode == settings.homeHeroDisplayMode,
                            onPressed: heroEnabled
                                ? () {
                                    ref
                                        .read(
                                            settingsControllerProvider.notifier)
                                        .setHomeHeroDisplayMode(mode);
                                  }
                                : null,
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Hero 样式',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final style in HomeHeroStyle.values)
                          StarflowChipButton(
                            label: style.label,
                            selected: style == settings.homeHeroStyle,
                            onPressed: heroEnabled
                                ? () {
                                    ref
                                        .read(
                                            settingsControllerProvider.notifier)
                                        .setHomeHeroStyle(style);
                                  }
                                : null,
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    StarflowToggleTile(
                      title: '标题优先展示 Logo',
                      value: settings.homeHeroLogoTitleEnabled,
                      onChanged: heroEnabled
                          ? (value) {
                              ref
                                  .read(settingsControllerProvider.notifier)
                                  .setHomeHeroLogoTitleEnabled(value);
                            }
                          : null,
                    ),
                    const SizedBox(height: 14),
                    StarflowToggleTile(
                      title: '启用 Hero 全屏背景图',
                      value: settings.homeHeroBackgroundEnabled,
                      onChanged: (value) {
                        ref
                            .read(settingsControllerProvider.notifier)
                            .setHomeHeroBackgroundEnabled(value);
                      },
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
                    StarflowToggleTile(
                      title: '启用 Hero',
                      value: heroEnabled,
                      onChanged: (value) {
                        ref
                            .read(settingsControllerProvider.notifier)
                            .setHomeHeroEnabled(value);
                      },
                    ),
                    const SizedBox(height: 10),
                    StarflowSelectionTile(
                      title: 'Hero 数据来源',
                      value: _heroSourceLabel(
                        settings: settings,
                        heroCandidates: heroCandidates,
                      ),
                      onPressed: heroEnabled
                          ? () => _openHeroSourcePicker(
                                context,
                                ref,
                                settings,
                                heroCandidates,
                              )
                          : null,
                    ),
                    const SizedBox(height: 14),
                    _SettingsNavigationTile(
                      title: '打开首页编辑器',
                      onTap: () => context.pushNamed('home-editor'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: kBottomReservedSpacing),
            ],
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
      MaterialPageRoute<void>(
        builder: (context) => MediaSourceEditorPage(initial: existing),
      ),
    );
  }

  Future<void> _openSearchProviderEditor(
    BuildContext context, {
    SearchProviderConfig? existing,
  }) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => SearchProviderEditorPage(initial: existing),
      ),
    );
  }

  Future<void> _openMetadataMatchSettings(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => const MetadataMatchSettingsPage(),
      ),
    );
  }

  Future<void> _openSearchSourcePicker(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) async {
    final availableLocalSources = settings.mediaSources
        .where(
          (source) =>
              source.enabled &&
              (source.kind == MediaSourceKind.emby ||
                  source.kind == MediaSourceKind.nas),
        )
        .toList(growable: false);
    final availableProviders = settings.searchProviders
        .where((provider) => provider.enabled)
        .toList(growable: false);
    if (availableLocalSources.isEmpty && availableProviders.isEmpty) {
      return;
    }

    final initialSelection = settings.searchSourceIds.toSet();
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) {
        var draft = <String>{...initialSelection};
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('选择搜索来源'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StarflowCheckboxTile(
                        title: '全部已启用来源',
                        subtitle: '清空单独选择，搜索时使用全部已启用本地源和搜索服务',
                        value: draft.isEmpty,
                        onChanged: (_) {
                          setState(() {
                            draft = <String>{};
                          });
                        },
                      ),
                      if (availableLocalSources.isNotEmpty) ...[
                        const Divider(height: 16),
                        Text(
                          '本地媒体源',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        for (final source in availableLocalSources)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: StarflowCheckboxTile(
                              title: source.name,
                              subtitle: source.kind.label,
                              value: draft.contains(
                                searchSourceSettingIdForMediaSource(source.id),
                              ),
                              onChanged: (checked) {
                                setState(() {
                                  final id =
                                      searchSourceSettingIdForMediaSource(
                                    source.id,
                                  );
                                  if (checked) {
                                    draft.add(id);
                                  } else {
                                    draft.remove(id);
                                  }
                                });
                              },
                            ),
                          ),
                      ],
                      if (availableProviders.isNotEmpty) ...[
                        const Divider(height: 16),
                        Text(
                          '搜索服务',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        for (final provider in availableProviders)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: StarflowCheckboxTile(
                              title: provider.name,
                              subtitle: provider.kind.label,
                              value: draft.contains(
                                searchSourceSettingIdForProvider(provider.id),
                              ),
                              onChanged: (checked) {
                                setState(() {
                                  final id = searchSourceSettingIdForProvider(
                                    provider.id,
                                  );
                                  if (checked) {
                                    draft.add(id);
                                  } else {
                                    draft.remove(id);
                                  }
                                });
                              },
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                StarflowButton(
                  label: '取消',
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  variant: StarflowButtonVariant.ghost,
                  compact: true,
                ),
                StarflowButton(
                  label: '全部来源',
                  onPressed: () => Navigator.of(dialogContext).pop(<String>{}),
                  variant: StarflowButtonVariant.secondary,
                  compact: true,
                ),
                StarflowButton(
                  label: '保存',
                  onPressed: () => Navigator.of(dialogContext).pop(draft),
                  compact: true,
                ),
              ],
            );
          },
        );
      },
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
    WidgetRef ref,
    AppSettings settings,
  ) async {
    final availableSources = settings.mediaSources
        .where(
          (source) =>
              source.enabled &&
              (source.kind == MediaSourceKind.emby ||
                  source.kind == MediaSourceKind.nas),
        )
        .toList(growable: false);
    if (availableSources.isEmpty) {
      return;
    }

    final initialSelection = settings.libraryMatchSourceIds.toSet();
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) {
        var draft = <String>{...initialSelection};
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('选择匹配来源'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StarflowCheckboxTile(
                        title: '全部已启用来源',
                        subtitle: '清空单独选择，匹配时扫描全部已启用媒体源',
                        value: draft.isEmpty,
                        onChanged: (_) {
                          setState(() {
                            draft = <String>{};
                          });
                        },
                      ),
                      const Divider(height: 16),
                      for (final source in availableSources)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: StarflowCheckboxTile(
                            title: source.name,
                            subtitle: source.kind.label,
                            value: draft.contains(source.id),
                            onChanged: (checked) {
                              setState(() {
                                if (checked) {
                                  draft.add(source.id);
                                } else {
                                  draft.remove(source.id);
                                }
                              });
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                StarflowButton(
                  label: '取消',
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  variant: StarflowButtonVariant.ghost,
                  compact: true,
                ),
                StarflowButton(
                  label: '全部来源',
                  onPressed: () => Navigator.of(dialogContext).pop(<String>{}),
                  variant: StarflowButtonVariant.secondary,
                  compact: true,
                ),
                StarflowButton(
                  label: '保存',
                  onPressed: () => Navigator.of(dialogContext).pop(draft),
                  compact: true,
                ),
              ],
            );
          },
        );
      },
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
      MaterialPageRoute<void>(
        builder: (context) => NetworkStorageSettingsPage(initial: initial),
      ),
    );
  }

  Future<void> _openPlaybackSettings(
    BuildContext context,
    AppSettings settings,
  ) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => PlaybackSettingsPage(
          initialTimeoutSeconds: settings.playbackOpenTimeoutSeconds,
          initialDefaultSpeed: settings.playbackDefaultSpeed,
          initialSubtitlePreference: settings.playbackSubtitlePreference,
          initialSubtitleScale: settings.playbackSubtitleScale,
          initialOnlineSubtitleSources: settings.onlineSubtitleSources,
          initialBackgroundPlaybackEnabled:
              settings.playbackBackgroundPlaybackEnabled,
          initialPlaybackEngine: settings.playbackEngine,
          initialPlaybackDecodeMode: settings.playbackDecodeMode,
        ),
      ),
    );
  }

  Future<void> _openLocalStorageSettings(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => const LocalStorageSettingsPage(),
      ),
    );
  }

  Future<void> _openSettingsManagement(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => const SettingsManagementPage(),
      ),
    );
  }

  Future<void> _openHeroSourcePicker(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
    List<HomeModuleConfig> heroCandidates,
  ) async {
    final selection = await showDialog<String>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('选择 Hero 数据来源'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(''),
              child: Text(
                settings.homeHeroSourceModuleId.trim().isEmpty
                    ? '自动选择  当前'
                    : '自动选择',
              ),
            ),
            for (final module in heroCandidates)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(module.id),
                child: Text(
                  module.id == settings.homeHeroSourceModuleId
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

String _resolveHeroModuleSelectionValue({
  required AppSettings settings,
  required List<HomeModuleConfig> heroCandidates,
}) {
  final selectedId = settings.homeHeroSourceModuleId.trim();
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
  required AppSettings settings,
  required List<HomeModuleConfig> heroCandidates,
}) {
  final selectedId = _resolveHeroModuleSelectionValue(
    settings: settings,
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

String _playbackSettingsSummary(AppSettings settings) {
  return [
    settings.playbackEngine.label,
    settings.playbackDecodeMode.label,
    '${settings.playbackOpenTimeoutSeconds}s 超时',
    '${_formatPlaybackSpeedLabel(settings.playbackDefaultSpeed)} 默认倍速',
    '字幕 ${settings.playbackSubtitlePreference.label}',
    settings.playbackSubtitleScale.label,
    settings.playbackBackgroundPlaybackEnabled ? '后台播放开' : '后台播放关',
  ].join(' · ');
}

String _highPerformanceModeSummary() {
  return '所有客户端都会关闭磨砂/模糊背景和通用面板阴影，并压低启动页、导航切换、首页 Hero 与 TV 焦点动画；进入播放器时，还会简化叠层，暂停首页 Hero 补数、详情自动补元数据/本地资源匹配、后台图片加载，并取消或跳过索引刷新。';
}

bool _effectiveTranslucentEffectsEnabled(AppSettings settings) {
  return !settings.highPerformanceModeEnabled &&
      settings.translucentEffectsEnabled;
}

String _translucentEffectsSummary(AppSettings settings) {
  if (settings.highPerformanceModeEnabled) {
    return '高性能模式开启时，此项会被强制关闭；如需单独设置，请先关闭高性能模式。';
  }
  return '关闭后可减少模糊和毛玻璃效果，提高性能。';
}

String _autoHideNavigationBarSummary(AppSettings settings) {
  if (!settings.autoHideNavigationBarEnabled) {
    return '关闭后菜单栏会保持常驻显示，不再自动隐藏。';
  }
  return '普通端会按页面交互自动隐藏；TV 端在焦点离开左侧菜单栏后自动收起。';
}

String _searchSourceSummary(AppSettings settings) {
  final availableLocalSources = settings.mediaSources
      .where(
        (source) =>
            source.enabled &&
            (source.kind == MediaSourceKind.emby ||
                source.kind == MediaSourceKind.nas),
      )
      .toList(growable: false);
  final availableProviders = settings.searchProviders
      .where((provider) => provider.enabled)
      .toList(growable: false);
  final totalCount = availableLocalSources.length + availableProviders.length;
  if (totalCount == 0) {
    return '暂无可选来源';
  }

  final selectedIds = settings.searchSourceIds.toSet();
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

String _libraryMatchSourceSummary(AppSettings settings) {
  final availableSources = settings.mediaSources
      .where(
        (source) =>
            source.enabled &&
            (source.kind == MediaSourceKind.emby ||
                source.kind == MediaSourceKind.nas),
      )
      .toList(growable: false);
  if (availableSources.isEmpty) {
    return '暂无可选来源';
  }

  final selectedIds = settings.libraryMatchSourceIds.toSet();
  if (selectedIds.isEmpty) {
    return '全部已启用来源';
  }

  final selectedNames = availableSources
      .where((source) => selectedIds.contains(source.id))
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
  const _SettingsPageHeader({required this.isTelevision});

  final bool isTelevision;

  @override
  Widget build(BuildContext context) {
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
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
      ),
    );
    if (!isTelevision) {
      return content;
    }
    return TvFocusableAction(
      onPressed: () => FocusScope.of(context).nextFocus(),
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
