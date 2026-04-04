import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/core/widgets/section_panel.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/media_source_editor_page.dart';
import 'package:starflow/features/settings/presentation/metadata_match_settings_page.dart';
import 'package:starflow/features/settings/presentation/search_provider_editor_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final loading = ref.watch(settingsControllerProvider).isLoading;

    return Scaffold(
      body: AppPageBackground(
        contentPadding: appPageContentPadding(
          context,
          includeBottomNavigationBar: true,
        ),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            if (loading) const LinearProgressIndicator(),
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
                    child: OutlinedButton.icon(
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
                    child: OutlinedButton.icon(
                      onPressed: () => _openSearchProviderEditor(context),
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
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('打开匹配与评分设置'),
                subtitle: Text(_buildMetadataMatchSubtitle(settings)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _openMetadataMatchSettings(context),
              ),
            ),
            const SizedBox(height: 18),
            SectionPanel(
              title: '首页模块',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hero 样式',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 10),
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
                    onSelectionChanged: (selection) {
                      if (selection.isEmpty) {
                        return;
                      }
                      final style = selection.first;
                      ref
                          .read(settingsControllerProvider.notifier)
                          .setHomeHeroStyle(style);
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    settings.homeHeroStyle == HomeHeroStyle.normal
                        ? '正常模式保留顶部安全区和原来的卡片感。'
                        : '无边模式会把 Hero 放大，并让封面左右贴到屏幕边缘。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF7F8FAE),
                          height: 1.45,
                        ),
                  ),
                  const SizedBox(height: 14),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('打开首页编辑器'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.pushNamed('home-editor'),
                  ),
                ],
              ),
            ),
          ],
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

  String _buildMetadataMatchSubtitle(AppSettings settings) {
    final tmdbStatus = settings.tmdbMetadataMatchEnabled ? 'TMDB 开' : 'TMDB 关';
    final wmdbStatus = settings.wmdbMetadataMatchEnabled ? 'WMDB 开' : 'WMDB 关';
    final imdbStatus =
        settings.imdbRatingMatchEnabled ? 'IMDb 评分开' : 'IMDb 评分关';
    return '${settings.metadataMatchPriority.label} 优先 · $tmdbStatus · $wmdbStatus · $imdbStatus';
  }
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
