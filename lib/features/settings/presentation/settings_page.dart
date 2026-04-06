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
                      child: isTelevision
                          ? TvAdaptiveButton(
                              label: '新增媒体源',
                              icon: Icons.add_rounded,
                              onPressed: () => _openMediaSourceEditor(context),
                              variant: TvButtonVariant.outlined,
                            )
                          : OutlinedButton.icon(
                              onPressed: () => _openMediaSourceEditor(context),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('新增媒体源'),
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
                      child: isTelevision
                          ? TvAdaptiveButton(
                              label: '新增搜索服务',
                              icon: Icons.add_rounded,
                              onPressed: () =>
                                  _openSearchProviderEditor(context),
                              variant: TvButtonVariant.outlined,
                            )
                          : OutlinedButton.icon(
                              onPressed: () =>
                                  _openSearchProviderEditor(context),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('新增搜索服务'),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SectionPanel(
                title: '元数据与评分',
                child: _SettingsNavigationTile(
                  title: '打开匹配与评分设置',
                  subtitle: settings.detailAutoLibraryMatchEnabled
                      ? '详情页自动匹配资源：已开启'
                      : '详情页自动匹配资源：已关闭',
                  onTap: () => _openMetadataMatchSettings(context),
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
                  title: '查看与清理缓存',
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
                    const SizedBox(height: 10),
                    if (isTelevision)
                      TvSelectionTile(
                        title: '高性能模式',
                        value:
                            settings.highPerformanceModeEnabled ? '已开启' : '已关闭',
                        onPressed: () {
                          ref
                              .read(settingsControllerProvider.notifier)
                              .setHighPerformanceModeEnabled(
                                !settings.highPerformanceModeEnabled,
                              );
                        },
                      )
                    else
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('高性能模式'),
                        subtitle: const Text(
                          '降低 TV 端动画、模糊背景和播放页叠层，优先保证流畅度',
                        ),
                        value: settings.highPerformanceModeEnabled,
                        onChanged: (value) {
                          ref
                              .read(settingsControllerProvider.notifier)
                              .setHighPerformanceModeEnabled(value);
                        },
                      ),
                    const SizedBox(height: 10),
                    if (isTelevision)
                      TvSelectionTile(
                        title: '透明磨砂效果',
                        value:
                            settings.translucentEffectsEnabled ? '已开启' : '已关闭',
                        onPressed: () {
                          ref
                              .read(settingsControllerProvider.notifier)
                              .setTranslucentEffectsEnabled(
                                !settings.translucentEffectsEnabled,
                              );
                        },
                      )
                    else
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('透明磨砂效果'),
                        subtitle: Text(
                          settings.highPerformanceModeEnabled
                              ? '高性能模式开启时，会自动进一步压低 TV 端视觉效果'
                              : '关闭后减少模糊和毛玻璃效果，提高性能',
                        ),
                        value: settings.translucentEffectsEnabled,
                        onChanged: (value) {
                          ref
                              .read(settingsControllerProvider.notifier)
                              .setTranslucentEffectsEnabled(value);
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
                    if (isTelevision)
                      TvSelectionTile(
                        title: '启用 Hero',
                        value: heroEnabled ? '已开启' : '已关闭',
                        onPressed: () {
                          ref
                              .read(settingsControllerProvider.notifier)
                              .setHomeHeroEnabled(!heroEnabled);
                        },
                      )
                    else
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('启用 Hero'),
                        value: heroEnabled,
                        onChanged: (value) {
                          ref
                              .read(settingsControllerProvider.notifier)
                              .setHomeHeroEnabled(value);
                        },
                      ),
                    const SizedBox(height: 10),
                    if (isTelevision)
                      TvSelectionTile(
                        title: 'Hero 样式',
                        value: settings.homeHeroStyle.label,
                        onPressed: heroEnabled
                            ? () => _openHeroStylePicker(
                                  context,
                                  ref,
                                  settings.homeHeroStyle,
                                )
                            : null,
                      )
                    else
                      SegmentedButton<HomeHeroStyle>(
                        showSelectedIcon: false,
                        segments: [
                          for (final style in HomeHeroStyle.values)
                            ButtonSegment<HomeHeroStyle>(
                              value: style,
                              label: Text(style.label),
                            ),
                        ],
                        selected: {settings.homeHeroStyle},
                        onSelectionChanged: heroEnabled
                            ? (selection) {
                                if (selection.isEmpty) {
                                  return;
                                }
                                final style = selection.first;
                                ref
                                    .read(settingsControllerProvider.notifier)
                                    .setHomeHeroStyle(style);
                              }
                            : null,
                      ),
                    const SizedBox(height: 14),
                    if (isTelevision)
                      TvSelectionTile(
                        title: '标题使用 Logo',
                        value:
                            settings.homeHeroLogoTitleEnabled ? '已开启' : '已关闭',
                        onPressed: heroEnabled
                            ? () {
                                ref
                                    .read(settingsControllerProvider.notifier)
                                    .setHomeHeroLogoTitleEnabled(
                                      !settings.homeHeroLogoTitleEnabled,
                                    );
                              }
                            : null,
                      )
                    else
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('标题优先展示 Logo'),
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
                    if (isTelevision)
                      TvSelectionTile(
                        title: '全屏背景图',
                        value:
                            settings.homeHeroBackgroundEnabled ? '已开启' : '已关闭',
                        onPressed: () {
                          ref
                              .read(settingsControllerProvider.notifier)
                              .setHomeHeroBackgroundEnabled(
                                !settings.homeHeroBackgroundEnabled,
                              );
                        },
                      )
                    else
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('启用 Hero 全屏背景图'),
                        value: settings.homeHeroBackgroundEnabled,
                        onChanged: (value) {
                          ref
                              .read(settingsControllerProvider.notifier)
                              .setHomeHeroBackgroundEnabled(value);
                        },
                      ),
                    const SizedBox(height: 10),
                    if (isTelevision)
                      TvSelectionTile(
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
                      )
                    else
                      DropdownButtonFormField<String>(
                        initialValue: _resolveHeroModuleSelectionValue(
                          settings: settings,
                          heroCandidates: heroCandidates,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Hero 数据来源',
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: '',
                            child: Text('自动选择'),
                          ),
                          ...heroCandidates.map(
                            (module) => DropdownMenuItem<String>(
                              value: module.id,
                              child: Text(module.title),
                            ),
                          ),
                        ],
                        onChanged: heroEnabled
                            ? (value) {
                                ref
                                    .read(settingsControllerProvider.notifier)
                                    .setHomeHeroSourceModuleId(value ?? '');
                              }
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

  Future<void> _openHeroStylePicker(
    BuildContext context,
    WidgetRef ref,
    HomeHeroStyle current,
  ) async {
    final selection = await showDialog<HomeHeroStyle>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('选择 Hero 样式'),
          children: [
            for (final style in HomeHeroStyle.values)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(style),
                child:
                    Text(style == current ? '${style.label}  当前' : style.label),
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
        .setHomeHeroStyle(selection);
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

String _formatPlaybackSpeedLabel(double speed) {
  if (speed == speed.roundToDouble()) {
    return '${speed.toStringAsFixed(0)}x';
  }
  return '${speed.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')}x';
}

class _SettingsTile extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isTelevision = ref.watch(isTelevisionProvider).valueOrNull ?? false;
    if (isTelevision) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
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
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        value ? '已启用' : '已关闭',
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
                _SettingsTileActionButton(
                  icon: Icons.edit_outlined,
                  label: compact ? '' : '编辑',
                  onPressed: onEdit,
                  filled: false,
                ),
                const SizedBox(width: 8),
                _SettingsTileActionButton(
                  icon: value
                      ? Icons.toggle_off_rounded
                      : Icons.toggle_on_rounded,
                  label: value ? '关闭' : '开启',
                  onPressed: () => onChanged(!value),
                ),
              ],
            ),
          );
        },
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: scheme.outlineVariant,
        ),
      ),
      child: ListTile(
        title: Text(title),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _SettingsTileActionButton extends StatelessWidget {
  const _SettingsTileActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.filled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final foregroundColor = filled ? const Color(0xFF081120) : Colors.white;
    final backgroundColor =
        filled ? Colors.white : Colors.white.withValues(alpha: 0.08);
    final borderColor =
        filled ? Colors.white : Colors.white.withValues(alpha: 0.22);
    return TvFocusableAction(
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: label.isEmpty ? 12 : 14,
            vertical: 11,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: foregroundColor),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: foregroundColor,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
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

class _SettingsNavigationTile extends ConsumerWidget {
  const _SettingsNavigationTile({
    required this.title,
    required this.onTap,
    this.subtitle = '',
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTelevision = ref.watch(isTelevisionProvider).valueOrNull ?? false;
    if (isTelevision) {
      return TvSelectionTile(
        title: title,
        value: subtitle,
        onPressed: onTap,
      );
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: subtitle.trim().isEmpty ? null : Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
