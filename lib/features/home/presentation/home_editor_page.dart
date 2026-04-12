import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/core/widgets/no_animation_page_route.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/core/widgets/section_panel.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/douban_account_editor_page.dart';
import 'package:starflow/features/home/application/home_settings_slices.dart';

final homeEditorCollectionsProvider = FutureProvider<List<MediaCollection>>((
  ref,
) {
  ref.watch(homeMediaSourcesProvider);
  return ref.read(mediaRepositoryProvider).fetchCollections();
});

const _kCustomDoubanListPresetValue = '__custom__';

/// 二级选择底部弹层：四周留白 + 列表过长时可滚动。
class _HomeEditorSecondarySheetBody extends StatelessWidget {
  const _HomeEditorSecondarySheetBody({
    required this.title,
    required this.tiles,
  });

  final String title;
  final List<Widget> tiles;

  static const _edgePadding = 20.0;

  @override
  Widget build(BuildContext context) {
    final maxListHeight = MediaQuery.sizeOf(context).height * 0.72;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(_edgePadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxListHeight),
              child: ListView(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                children: tiles,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _defaultDoubanListPresets = <_DoubanListPreset>[
  _DoubanListPreset(
    title: '豆瓣热门电影',
    url: 'https://m.douban.com/subject_collection/movie_hot_gaia',
  ),
  _DoubanListPreset(
    title: '热播新剧',
    url: 'https://m.douban.com/subject_collection/tv_hot',
  ),
  _DoubanListPreset(
    title: '热播综艺',
    url: 'https://m.douban.com/subject_collection/show_hot',
  ),
  _DoubanListPreset(
    title: '热播动漫',
    url: 'https://m.douban.com/subject_collection/tv_animation',
  ),
  _DoubanListPreset(
    title: '影院热映',
    url: 'https://m.douban.com/subject_collection/movie_showing',
  ),
  _DoubanListPreset(
    title: '实时热门电影',
    url: 'https://m.douban.com/subject_collection/movie_real_time_hotest',
  ),
  _DoubanListPreset(
    title: '实时热门电视',
    url: 'https://m.douban.com/subject_collection/tv_real_time_hotest',
  ),
  _DoubanListPreset(
    title: '豆瓣 Top 250',
    url: 'https://m.douban.com/subject_collection/movie_top250',
  ),
  _DoubanListPreset(
    title: '一周电影口碑榜',
    url: 'https://m.douban.com/subject_collection/movie_weekly_best',
  ),
  _DoubanListPreset(
    title: '华语口碑剧集榜',
    url: 'https://m.douban.com/subject_collection/tv_chinese_best_weekly',
  ),
  _DoubanListPreset(
    title: '全球口碑剧集榜',
    url: 'https://m.douban.com/subject_collection/tv_global_best_weekly',
  ),
  _DoubanListPreset(
    title: '国内综艺口碑榜',
    url: 'https://m.douban.com/subject_collection/show_chinese_best_weekly',
  ),
  _DoubanListPreset(
    title: '全球综艺口碑榜',
    url: 'https://m.douban.com/subject_collection/show_global_best_weekly',
  ),
  _DoubanListPreset(
    title: '第97届奥斯卡',
    url: 'https://m.douban.com/subject_collection/EC7I7ZDRA?type=rank',
  ),
  _DoubanListPreset(
    title: 'IMDB MOVIE TOP 250',
    url: 'https://m.douban.com/doulist/1518184',
  ),
  _DoubanListPreset(
    title: 'IMDB TV TOP 250',
    url: 'https://m.douban.com/doulist/41573512',
  ),
];

class HomeEditorPage extends ConsumerWidget {
  const HomeEditorPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<HomeModuleConfig> modules = ref.watch(homeModulesProvider);
    final List<MediaSourceConfig> mediaSources =
        ref.watch(homeMediaSourcesProvider);
    final collectionsAsync = ref.watch(homeEditorCollectionsProvider);
    final Set<String> visibleSourceIds =
        (collectionsAsync.value ?? const <MediaCollection>[])
            .map((item) => item.sourceId)
            .toSet();
    final enabledSources = mediaSources.where((item) => item.enabled).toList();
    final scopedSources = enabledSources
        .where((item) => visibleSourceIds.contains(item.id))
        .toList();

    return Scaffold(
      floatingActionButton: FloatingActionButton.small(
        onPressed: () => _showAddModuleSheet(context, ref),
        child: const Icon(Icons.add_rounded),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          AppPageBackground(
            child: ListView(
              padding: overlayToolbarPagePadding(context),
              children: [
                SectionPanel(
                  title: '当前模块',
                  child: modules.isEmpty
                      ? const Text('还没有首页模块。')
                      : ReorderableListView.builder(
                          shrinkWrap: true,
                          buildDefaultDragHandles: false,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: modules.length,
                          onReorder: (oldIndex, newIndex) {
                            ref
                                .read(settingsControllerProvider.notifier)
                                .reorderHomeModules(oldIndex, newIndex);
                          },
                          itemBuilder: (context, index) {
                            final module = modules[index];
                            return Container(
                              key: ValueKey(module.id),
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: const Icon(
                                        Icons.drag_indicator_rounded,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(child: Text(module.title)),
                                    StarflowIconButton(
                                      icon: Icons.edit_outlined,
                                      tooltip: '编辑',
                                      variant: StarflowButtonVariant.secondary,
                                      onPressed: () => _showEditModuleDialog(
                                        context,
                                        ref,
                                        module,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    StarflowIconButton(
                                      icon: Icons.close_rounded,
                                      tooltip: '删除',
                                      variant: StarflowButtonVariant.danger,
                                      onPressed: () {
                                        ref
                                            .read(settingsControllerProvider
                                                .notifier)
                                            .removeHomeModule(module.id);
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    StarflowButton(
                                      label: module.enabled ? '开启' : '关闭',
                                      icon: module.enabled
                                          ? Icons.toggle_on_rounded
                                          : Icons.toggle_off_rounded,
                                      onPressed: () {
                                        ref
                                            .read(settingsControllerProvider
                                                .notifier)
                                            .toggleHomeModule(
                                              module.id,
                                              !module.enabled,
                                            );
                                      },
                                      variant: module.enabled
                                          ? StarflowButtonVariant.primary
                                          : StarflowButtonVariant.secondary,
                                      compact: true,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 18),
                SectionPanel(
                  title: '可添加来源',
                  child: Column(
                    children: [
                      _SourceCategoryTile(
                        title: '内置',
                        icon: Icons.auto_awesome_rounded,
                        onTap: () => _showBuiltinModuleSheet(context, ref),
                      ),
                      const SizedBox(height: 10),
                      _SourceCategoryTile(
                        title: '豆瓣',
                        icon: Icons.movie_filter_rounded,
                        onTap: () => _showDoubanModuleSheet(context, ref),
                      ),
                      if (scopedSources.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        ...scopedSources.map(
                          (source) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _SourceCategoryTile(
                              title: source.name,
                              icon: source.kind == MediaSourceKind.emby
                                  ? Icons.video_library_rounded
                                  : Icons.storage_rounded,
                              onTap: () => _showMediaSourceModuleSheet(
                                context,
                                ref,
                                source,
                              ),
                            ),
                          ),
                        ),
                      ] else
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            '还没有启用的 Emby 或 WebDAV 来源，先去设置里接入后，这里就会出现。',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: OverlayToolbar(
              onBack: () => context.pop(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddModuleSheet(BuildContext context, WidgetRef ref) {
    final enabledSources = ref
        .read(homeMediaSourcesProvider)
        .where((item) => item.enabled)
        .toList();
    return ref.read(homeEditorCollectionsProvider.future).then((collections) {
      if (!context.mounted) {
        return Future<void>.value();
      }
      final visibleSourceIds = collections.map((item) => item.sourceId).toSet();
      final scopedSources = enabledSources
          .where((item) => visibleSourceIds.contains(item.id))
          .toList();
      return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          return _HomeEditorSecondarySheetBody(
            title: '选择来源分类',
            tiles: [
              _AddModuleTile(
                title: '内置',
                onTap: () async {
                  Navigator.of(context).pop();
                  await _showBuiltinModuleSheet(context, ref);
                },
              ),
              _AddModuleTile(
                title: '豆瓣',
                onTap: () async {
                  Navigator.of(context).pop();
                  await _showDoubanModuleSheet(context, ref);
                },
              ),
              ...scopedSources.map(
                (source) => _AddModuleTile(
                  title: source.name,
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _showMediaSourceModuleSheet(
                      context,
                      ref,
                      source,
                    );
                  },
                ),
              ),
            ],
          );
        },
      );
    });
  }

  Future<void> _showBuiltinModuleSheet(BuildContext context, WidgetRef ref) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return _HomeEditorSecondarySheetBody(
          title: '内置模块',
          tiles: [
            _AddModuleTile(
              title: 'Hero',
              onTap: () {
                ref
                    .read(settingsControllerProvider.notifier)
                    .saveHomeModule(HomeModuleConfig.hero());
                Navigator.of(context).pop();
              },
            ),
            _AddModuleTile(
              title: '最近新增',
              onTap: () {
                ref
                    .read(settingsControllerProvider.notifier)
                    .saveHomeModule(HomeModuleConfig.recentlyAdded());
                Navigator.of(context).pop();
              },
            ),
            _AddModuleTile(
              title: '最近播放',
              onTap: () {
                ref
                    .read(settingsControllerProvider.notifier)
                    .saveHomeModule(HomeModuleConfig.recentPlayback());
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showDoubanModuleSheet(BuildContext context, WidgetRef ref) {
    final doubanAccount = ref.read(homeDoubanAccountProvider);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return _HomeEditorSecondarySheetBody(
          title: '豆瓣模块',
          tiles: [
            _AddModuleTile(
              title: '豆瓣账号设置',
              onTap: () async {
                Navigator.of(context).pop();
                await Navigator.of(context, rootNavigator: true).push<void>(
                  NoAnimationMaterialPageRoute<void>(
                    builder: (context) => DoubanAccountEditorPage(
                      initial: doubanAccount,
                    ),
                  ),
                );
              },
            ),
            _AddModuleTile(
              title: '豆瓣我想看',
              onTap: () {
                ref.read(settingsControllerProvider.notifier).saveHomeModule(
                      HomeModuleConfig.doubanInterest(
                        DoubanInterestStatus.mark,
                      ),
                    );
                Navigator.of(context).pop();
              },
            ),
            _AddModuleTile(
              title: '豆瓣随机想看',
              onTap: () {
                ref.read(settingsControllerProvider.notifier).saveHomeModule(
                      HomeModuleConfig.doubanInterest(
                        DoubanInterestStatus.randomMark,
                      ),
                    );
                Navigator.of(context).pop();
              },
            ),
            _AddModuleTile(
              title: '豆瓣个性化推荐 · 电影',
              onTap: () {
                ref.read(settingsControllerProvider.notifier).saveHomeModule(
                      HomeModuleConfig.doubanSuggestion(
                        DoubanSuggestionMediaType.movie,
                      ),
                    );
                Navigator.of(context).pop();
              },
            ),
            _AddModuleTile(
              title: '豆瓣个性化推荐 · 电视',
              onTap: () {
                ref.read(settingsControllerProvider.notifier).saveHomeModule(
                      HomeModuleConfig.doubanSuggestion(
                        DoubanSuggestionMediaType.tv,
                      ),
                    );
                Navigator.of(context).pop();
              },
            ),
            _AddModuleTile(
              title: '豆瓣片单',
              onTap: () async {
                Navigator.of(context).pop();
                await _showDoubanListDialog(context, ref);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showMediaSourceModuleSheet(
    BuildContext context,
    WidgetRef ref,
    MediaSourceConfig source,
  ) async {
    final collections = await ref.read(homeEditorCollectionsProvider.future);
    if (!context.mounted) {
      return;
    }

    final sourceCollections = collections
        .where((collection) => collection.sourceId == source.id)
        .toList();
    if (sourceCollections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${source.name} 还没有可用分区'),
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return _HomeEditorSecondarySheetBody(
          title: source.name,
          tiles: sourceCollections
              .map(
                (collection) => _AddModuleTile(
                  title: collection.title,
                  onTap: () {
                    ref
                        .read(settingsControllerProvider.notifier)
                        .saveHomeModule(
                          HomeModuleConfig.libraryCollection(collection),
                        );
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('已添加 ${collection.title}'),
                      ),
                    );
                  },
                ),
              )
              .toList(),
        );
      },
    );
  }

  Future<void> _showDoubanListDialog(
    BuildContext context,
    WidgetRef ref, {
    HomeModuleConfig? existing,
  }) {
    final initialPreset = _findDoubanListPreset(existing?.doubanListUrl ?? '');
    final titleController = TextEditingController(
      text: existing?.title ?? initialPreset?.title ?? '豆瓣片单',
    );
    final urlController = TextEditingController(
      text: existing?.doubanListUrl ?? initialPreset?.url ?? '',
    );
    var selectedPresetUrl = initialPreset?.url ?? _kCustomDoubanListPresetValue;
    final isTelevision = ref.read(isTelevisionProvider).value ?? false;
    final titleFocusNode = FocusNode(debugLabel: 'home-douban-title');
    final urlFocusNode = FocusNode(debugLabel: 'home-douban-url');
    final cancelFocusNode = FocusNode(debugLabel: 'home-douban-cancel');
    final saveFocusNode = FocusNode(debugLabel: 'home-douban-save');

    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final dialog = AlertDialog(
              title: Text(existing == null ? '新增豆瓣片单' : '编辑豆瓣片单'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedPresetUrl,
                      decoration: const InputDecoration(labelText: '默认片单'),
                      items: [
                        for (final preset in _defaultDoubanListPresets)
                          DropdownMenuItem<String>(
                            value: preset.url,
                            child: Text(preset.title),
                          ),
                        const DropdownMenuItem<String>(
                          value: _kCustomDoubanListPresetValue,
                          child: Text('自定义输入'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          selectedPresetUrl = value;
                          if (value == _kCustomDoubanListPresetValue) {
                            return;
                          }
                          final preset = _findDoubanListPreset(value);
                          if (preset == null) {
                            return;
                          }
                          titleController.text = preset.title;
                          urlController.text = preset.url;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    wrapTelevisionDialogFieldTraversal(
                      enabled: isTelevision,
                      child: TextField(
                        controller: titleController,
                        focusNode: titleFocusNode,
                        autofocus: true,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: '标题'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    wrapTelevisionDialogFieldTraversal(
                      enabled: isTelevision,
                      child: TextField(
                        controller: urlController,
                        focusNode: urlFocusNode,
                        minLines: 2,
                        maxLines: 3,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(labelText: '片单地址'),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                StarflowButton(
                  label: '取消',
                  focusNode: cancelFocusNode,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  variant: StarflowButtonVariant.ghost,
                  compact: true,
                ),
                StarflowButton(
                  label: '保存',
                  focusNode: saveFocusNode,
                  onPressed: () {
                    final url = urlController.text.trim();
                    if (url.isEmpty) {
                      return;
                    }
                    ref
                        .read(settingsControllerProvider.notifier)
                        .saveHomeModule(
                          existing == null
                              ? HomeModuleConfig.doubanList(
                                  title: titleController.text.trim().isEmpty
                                      ? '豆瓣片单'
                                      : titleController.text.trim(),
                                  url: url,
                                )
                              : existing.copyWith(
                                  title: titleController.text.trim().isEmpty
                                      ? existing.title
                                      : titleController.text.trim(),
                                  doubanListUrl: url,
                                ),
                        );
                    Navigator.of(dialogContext).pop();
                  },
                  compact: true,
                ),
              ],
            );
            return wrapTelevisionDialogBackHandling(
              enabled: isTelevision,
              dialogContext: dialogContext,
              inputFocusNodes: [titleFocusNode, urlFocusNode],
              contentFocusNodes: [titleFocusNode, urlFocusNode],
              actionFocusNodes: [saveFocusNode, cancelFocusNode],
              child: dialog,
            );
          },
        );
      },
    ).whenComplete(() {
      titleController.dispose();
      urlController.dispose();
      titleFocusNode.dispose();
      urlFocusNode.dispose();
      cancelFocusNode.dispose();
      saveFocusNode.dispose();
    });
  }

  Future<void> _showEditModuleDialog(
    BuildContext context,
    WidgetRef ref,
    HomeModuleConfig module,
  ) {
    final titleController = TextEditingController(text: module.title);
    var interestStatus = module.doubanInterestStatus;
    var suggestionType = module.doubanSuggestionType;
    final isTelevision = ref.read(isTelevisionProvider).value ?? false;
    final titleFocusNode = FocusNode(debugLabel: 'home-module-title');
    final cancelFocusNode = FocusNode(debugLabel: 'home-module-cancel');
    final saveFocusNode = FocusNode(debugLabel: 'home-module-save');

    if (module.type == HomeModuleType.doubanList) {
      return _showDoubanListDialog(
        context,
        ref,
        existing: module,
      );
    }

    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final dialog = AlertDialog(
              title: const Text('编辑模块'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    wrapTelevisionDialogFieldTraversal(
                      enabled: isTelevision,
                      child: TextField(
                        controller: titleController,
                        focusNode: titleFocusNode,
                        autofocus: true,
                        decoration: const InputDecoration(labelText: '标题'),
                      ),
                    ),
                    if (module.type == HomeModuleType.doubanInterest) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<DoubanInterestStatus>(
                        initialValue: interestStatus,
                        decoration: const InputDecoration(labelText: '豆瓣状态'),
                        items: DoubanInterestStatus.values
                            .map(
                              (item) => DropdownMenuItem(
                                value: item,
                                child: Text(item.label),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              interestStatus = value;
                            });
                          }
                        },
                      ),
                    ],
                    if (module.type == HomeModuleType.doubanSuggestion) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<DoubanSuggestionMediaType>(
                        initialValue: suggestionType,
                        decoration: const InputDecoration(labelText: '推荐类型'),
                        items: DoubanSuggestionMediaType.values
                            .map(
                              (item) => DropdownMenuItem(
                                value: item,
                                child: Text(item.label),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              suggestionType = value;
                            });
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                StarflowButton(
                  label: '取消',
                  focusNode: cancelFocusNode,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  variant: StarflowButtonVariant.ghost,
                  compact: true,
                ),
                StarflowButton(
                  label: '保存',
                  focusNode: saveFocusNode,
                  onPressed: () {
                    ref
                        .read(settingsControllerProvider.notifier)
                        .saveHomeModule(
                          module.copyWith(
                            title: titleController.text.trim().isEmpty
                                ? module.title
                                : titleController.text.trim(),
                            doubanInterestStatus: interestStatus,
                            doubanSuggestionType: suggestionType,
                          ),
                        );
                    Navigator.of(dialogContext).pop();
                  },
                  compact: true,
                ),
              ],
            );
            return wrapTelevisionDialogBackHandling(
              enabled: isTelevision,
              dialogContext: dialogContext,
              inputFocusNodes: [titleFocusNode],
              contentFocusNodes: [titleFocusNode],
              actionFocusNodes: [saveFocusNode, cancelFocusNode],
              child: dialog,
            );
          },
        );
      },
    ).whenComplete(() {
      titleController.dispose();
      titleFocusNode.dispose();
      cancelFocusNode.dispose();
      saveFocusNode.dispose();
    });
  }
}

_DoubanListPreset? _findDoubanListPreset(String url) {
  final normalizedUrl = url.trim();
  if (normalizedUrl.isEmpty) {
    return null;
  }

  for (final preset in _defaultDoubanListPresets) {
    if (preset.url == normalizedUrl) {
      return preset;
    }
  }
  return null;
}

class _DoubanListPreset {
  const _DoubanListPreset({
    required this.title,
    required this.url,
  });

  final String title;
  final String url;
}

class _AddModuleTile extends StatelessWidget {
  const _AddModuleTile({
    required this.title,
    required this.onTap,
  });

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: StarflowSelectionTile(
        title: title,
        onPressed: onTap,
        trailing: const Icon(Icons.add_circle_outline_rounded),
      ),
    );
  }
}

class _SourceCategoryTile extends StatelessWidget {
  const _SourceCategoryTile({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StarflowSelectionTile(
      leading: CircleAvatar(
        backgroundColor: scheme.primary.withValues(alpha: 0.12),
        foregroundColor: scheme.primary,
        child: Icon(icon),
      ),
      title: title,
      onPressed: onTap,
    );
  }
}
