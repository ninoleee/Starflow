import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/widgets/no_animation_page_route.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/application/settings_slice_providers.dart';
import 'package:starflow/features/settings/presentation/media_source_editor_page.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_management_item.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';

class MediaSourceSettingsPage extends ConsumerWidget {
  const MediaSourceSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(settingsMediaSourcesProvider);
    final libraryMatchSourceIds =
        ref.watch(settingsLibraryMatchSourceIdsProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final theme = Theme.of(context);

    return SettingsPageScaffold(
      onBack: () => Navigator.of(context).pop(),
      trailing: SettingsToolbarButton(
        label: '新增',
        icon: Icons.add_rounded,
        onPressed: () => _openEditor(context),
      ),
      children: [
        Text('媒体源管理', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          '管理 Emby、NAS / WebDAV 和夸克媒体源。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SettingsSectionTitle(label: '匹配范围'),
        SettingsSelectionTile(
          title: '详情页匹配来源',
          subtitle: _libraryMatchSourceSummary(
            mediaSources: sources,
            selectedIds: libraryMatchSourceIds,
          ),
          value: '',
          autofocus: true,
          focusId: 'media-sources:match-sources',
          onPressed: () => _openLibraryMatchSourcePicker(
            context,
            ref,
            mediaSources: sources,
            selectedIds: libraryMatchSourceIds,
          ),
        ),
        const SettingsSectionTitle(label: '媒体源'),
        if (sources.isEmpty)
          SettingsActionButton(
            label: '新增媒体源',
            icon: Icons.add_rounded,
            focusId: 'media-sources:add-empty',
            onPressed: () => _openEditor(context),
          )
        else
          for (var index = 0; index < sources.length; index++) ...[
            SettingsManagementItem(
              title: sources[index].name,
              enabled: sources[index].enabled,
              autofocus: false,
              focusIdPrefix: 'media-sources:${sources[index].id}',
              onChanged: (enabled) =>
                  controller.toggleMediaSource(sources[index].id, enabled),
              onEdit: () => _openEditor(context, existing: sources[index]),
            ),
            if (index < sources.length - 1) const SizedBox(height: 10),
          ],
      ],
    );
  }

  Future<void> _openEditor(
    BuildContext context, {
    MediaSourceConfig? existing,
  }) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      NoAnimationMaterialPageRoute<void>(
        builder: (context) => MediaSourceEditorPage(initial: existing),
      ),
    );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先添加 NAS / WebDAV 或夸克媒体源')),
      );
      return;
    }
    final selected = await showSettingsCheckboxSelectionDialog<String>(
      context: context,
      title: '选择匹配来源',
      initialSelection: selectedIds.toSet(),
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
}

String _libraryMatchSourceSummary({
  required List<MediaSourceConfig> mediaSources,
  required List<String> selectedIds,
}) {
  final available =
      mediaSources.where(_isSelectableLocalMediaSource).toList(growable: false);
  if (available.isEmpty) {
    return '暂无可匹配来源';
  }
  if (selectedIds.isEmpty) {
    return '全部已启用来源';
  }
  final selectedNames = available
      .where((source) => selectedIds.contains(source.id))
      .map((source) => source.name)
      .toList(growable: false);
  if (selectedNames.isEmpty) {
    return '全部已启用来源';
  }
  return selectedNames.length <= 2
      ? selectedNames.join('、')
      : '${selectedNames.take(2).join('、')} 等 ${selectedNames.length} 个';
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
