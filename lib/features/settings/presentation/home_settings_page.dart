import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/home/application/home_controller.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/application/settings_slice_providers.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';

class HomeSettingsPage extends ConsumerWidget {
  const HomeSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heroSlice = ref.watch(settingsHeroSliceProvider);
    final heroCandidates = ref.watch(homeHeroModuleCandidatesProvider);
    final heroModule = ref.watch(homeHeroModuleProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final heroEnabled = heroModule?.enabled ?? false;

    return SettingsPageScaffold(
      onBack: () => Navigator.of(context).pop(),
      children: [
        const SettingsSectionTitle(label: '首页 Hero'),
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
                    ? () => controller.setHomeHeroDisplayMode(mode)
                    : null,
              ),
          ],
        ),
        const SizedBox(height: 14),
        ...buildSettingsTileGroup([
          StarflowToggleTile(
            title: '标题优先展示 Logo',
            value: heroSlice.logoTitleEnabled,
            onChanged:
                heroEnabled ? controller.setHomeHeroLogoTitleEnabled : null,
          ),
          StarflowToggleTile(
            title: '启用 Hero',
            value: heroEnabled,
            onChanged: controller.setHomeHeroEnabled,
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
                      controller: controller,
                      heroSlice: heroSlice,
                      heroCandidates: heroCandidates,
                    )
                : null,
          ),
        ]),
        const SettingsSectionTitle(label: '首页模块'),
        StarflowSelectionTile(
          title: '打开首页编辑器',
          value: '模块显示、顺序与豆瓣内容',
          onPressed: () => context.pushNamed('home-editor'),
        ),
      ],
    );
  }
}

String _heroSourceLabel({
  required SettingsHeroSlice heroSlice,
  required List<HomeModuleConfig> heroCandidates,
}) {
  final selectedId = heroSlice.sourceModuleId.trim();
  for (final module in heroCandidates) {
    if (module.id == selectedId) {
      return module.title;
    }
  }
  return '自动选择';
}

Future<void> _openHeroSourcePicker(
  BuildContext context, {
  required SettingsController controller,
  required SettingsHeroSlice heroSlice,
  required List<HomeModuleConfig> heroCandidates,
}) async {
  final selection = await showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
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
    ),
  );
  if (selection != null) {
    await controller.setHomeHeroSourceModuleId(selection);
  }
}
