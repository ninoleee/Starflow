import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/widgets/no_animation_page_route.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/application/settings_slice_providers.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/search_provider_editor_page.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_management_item.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';

class SearchServiceSettingsPage extends ConsumerWidget {
  const SearchServiceSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providers = ref.watch(settingsSearchProvidersProvider);
    final mediaSources = ref.watch(settingsMediaSourcesProvider);
    final searchSourceIds = ref.watch(settingsSearchSourceIdsProvider);
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
        Text('搜索服务管理', style: theme.textTheme.headlineSmall),
        const SettingsSectionTitle(label: '搜索来源'),
        SettingsSelectionTile(
          title: '搜索页来源标签',
          subtitle: _sourceSummary(
            mediaSources: mediaSources,
            providers: providers,
            selectedIds: searchSourceIds,
          ),
          value: '',
          autofocus: providers.isEmpty,
          focusId: 'search-services:sources',
          onPressed: () => _openSourcePicker(
            context,
            ref,
            mediaSources: mediaSources,
            providers: providers,
            selectedIds: searchSourceIds,
          ),
        ),
        const SettingsSectionTitle(label: '在线服务'),
        if (providers.isEmpty)
          SettingsActionButton(
            label: '新增搜索服务',
            icon: Icons.add_rounded,
            focusId: 'search-services:add-empty',
            onPressed: () => _openEditor(context),
          )
        else
          for (var index = 0; index < providers.length; index++) ...[
            SettingsManagementItem(
              title: providers[index].name,
              enabled: providers[index].enabled,
              autofocus: index == 0,
              focusIdPrefix: 'search-services:${providers[index].id}',
              onChanged: (enabled) => controller.toggleSearchProvider(
                providers[index].id,
                enabled,
              ),
              onEdit: () => _openEditor(
                context,
                existing: providers[index],
              ),
            ),
            if (index < providers.length - 1) const SizedBox(height: 10),
          ],
      ],
    );
  }

  Future<void> _openEditor(
    BuildContext context, {
    SearchProviderConfig? existing,
  }) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      SettingsMaterialPageRoute<void>(
        builder: (context) => SearchProviderEditorPage(initial: existing),
      ),
    );
  }

  Future<void> _openSourcePicker(
    BuildContext context,
    WidgetRef ref, {
    required List<MediaSourceConfig> mediaSources,
    required List<SearchProviderConfig> providers,
    required List<String> selectedIds,
  }) async {
    final localSources =
        mediaSources.where(_isSelectableLocalSource).toList(growable: false);
    final enabledProviders =
        providers.where((provider) => provider.enabled).toList(growable: false);
    if (localSources.isEmpty && enabledProviders.isEmpty) {
      return;
    }
    final selected = await showSettingsCheckboxSelectionDialog<String>(
      context: context,
      title: '选择搜索页来源标签',
      initialSelection: selectedIds.toSet(),
      allLabel: '展示全部已启用来源',
      allSubtitle: '清空单独选择，在搜索页展示全部已启用来源标签',
      sections: [
        if (localSources.isNotEmpty)
          SettingsCheckboxDialogSection<String>(
            title: '本地媒体源',
            options: [
              for (final source in localSources)
                SettingsCheckboxDialogOption<String>(
                  value: searchSourceSettingIdForMediaSource(source.id),
                  title: source.name,
                  subtitle: source.kind.label,
                ),
            ],
          ),
        if (enabledProviders.isNotEmpty)
          SettingsCheckboxDialogSection<String>(
            title: '搜索服务',
            options: [
              for (final provider in enabledProviders)
                SettingsCheckboxDialogOption<String>(
                  value: searchSourceSettingIdForProvider(provider.id),
                  title: provider.name,
                  subtitle: provider.kind.label,
                ),
            ],
          ),
      ],
    );
    if (selected != null) {
      await ref
          .read(settingsControllerProvider.notifier)
          .setSearchSourceIds(selected.toList(growable: false));
    }
  }

  String _sourceSummary({
    required List<MediaSourceConfig> mediaSources,
    required List<SearchProviderConfig> providers,
    required List<String> selectedIds,
  }) {
    if (selectedIds.isEmpty) {
      return '展示全部已启用来源';
    }
    final availableIds = <String>{
      for (final source in mediaSources.where(_isSelectableLocalSource))
        searchSourceSettingIdForMediaSource(source.id),
      for (final provider in providers.where((item) => item.enabled))
        searchSourceSettingIdForProvider(provider.id),
    };
    final count = selectedIds.where(availableIds.contains).length;
    return count == 0 ? '展示全部已启用来源' : '展示 $count 个来源标签';
  }
}

bool _isSelectableLocalSource(MediaSourceConfig source) {
  if (!source.enabled) {
    return false;
  }
  if (source.kind == MediaSourceKind.quark) {
    return source.hasConfiguredQuarkFolder;
  }
  return source.kind == MediaSourceKind.emby ||
      source.kind == MediaSourceKind.nas;
}
