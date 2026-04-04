import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/core/widgets/section_panel.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

final homeEditorCollectionsProvider = FutureProvider<List<MediaCollection>>((
  ref,
) {
  return ref.read(mediaRepositoryProvider).fetchCollections();
});

const _kCustomDoubanListPresetValue = '__custom__';

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
    final settings = ref.watch(appSettingsProvider);
    final enabledSources =
        settings.mediaSources.where((item) => item.enabled).toList();

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
                  subtitle: '拖动排序，或在底部加一个新的模块',
                  child: settings.homeModules.isEmpty
                      ? const Text('还没有首页模块。')
                      : ReorderableListView.builder(
                          shrinkWrap: true,
                          buildDefaultDragHandles: false,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: settings.homeModules.length,
                          onReorder: (oldIndex, newIndex) {
                            ref
                                .read(settingsControllerProvider.notifier)
                                .reorderHomeModules(oldIndex, newIndex);
                          },
                          itemBuilder: (context, index) {
                            final module = settings.homeModules[index];
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
                              child: ListTile(
                                title: Text(module.title),
                                subtitle: Text(module.description),
                                leading: ReorderableDragStartListener(
                                  index: index,
                                  child:
                                      const Icon(Icons.drag_indicator_rounded),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      onPressed: () => _showEditModuleDialog(
                                          context, ref, module),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                    IconButton(
                                      onPressed: () {
                                        ref
                                            .read(settingsControllerProvider
                                                .notifier)
                                            .removeHomeModule(module.id);
                                      },
                                      icon: const Icon(Icons.close_rounded),
                                    ),
                                    Switch(
                                      value: module.enabled,
                                      onChanged: (value) {
                                        ref
                                            .read(settingsControllerProvider
                                                .notifier)
                                            .toggleHomeModule(module.id, value);
                                      },
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
                  subtitle: '先按来源分类，再进入具体模块或分区',
                  child: Column(
                    children: [
                      _SourceCategoryTile(
                        title: '内置',
                        subtitle: '最近新增等基础模块',
                        icon: Icons.auto_awesome_rounded,
                        onTap: () => _showBuiltinModuleSheet(context, ref),
                      ),
                      const SizedBox(height: 10),
                      _SourceCategoryTile(
                        title: '豆瓣',
                        subtitle: '我想看、推荐、片单和轮播',
                        icon: Icons.movie_filter_rounded,
                        onTap: () => _showDoubanModuleSheet(context, ref),
                      ),
                      if (enabledSources.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        ...enabledSources.map(
                          (source) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _SourceCategoryTile(
                              title: source.name,
                              subtitle: '${source.kind.label} · 点击后选择具体分区',
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
                            '还没有启用的 Emby 或 NAS 来源，先去设置里接入后，这里就会出现。',
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
        .read(appSettingsProvider)
        .mediaSources
        .where((item) => item.enabled)
        .toList();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '选择来源分类',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            _AddModuleTile(
              title: '内置',
              subtitle: '最近新增等基础模块',
              onTap: () async {
                Navigator.of(context).pop();
                await _showBuiltinModuleSheet(context, ref);
              },
            ),
            _AddModuleTile(
              title: '豆瓣',
              subtitle: '我想看、推荐、片单和轮播',
              onTap: () async {
                Navigator.of(context).pop();
                await _showDoubanModuleSheet(context, ref);
              },
            ),
            ...enabledSources.map(
              (source) => _AddModuleTile(
                title: source.name,
                subtitle: '${source.kind.label} · 点击后选择具体分区',
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
  }

  Future<void> _showBuiltinModuleSheet(BuildContext context, WidgetRef ref) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '内置模块',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            _AddModuleTile(
              title: '最近新增',
              subtitle: '把最近同步进来的资源放上首页',
              onTap: () {
                ref
                    .read(settingsControllerProvider.notifier)
                    .saveHomeModule(HomeModuleConfig.recentlyAdded());
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showDoubanModuleSheet(BuildContext context, WidgetRef ref) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '豆瓣模块',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            _AddModuleTile(
              title: '豆瓣我想看',
              subtitle: '来自豆瓣我看列表',
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
              subtitle: '从想看列表随机抽取 9 个条目',
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
              subtitle: '需要设置里配置 Cookie',
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
              subtitle: '需要设置里配置 Cookie',
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
              subtitle: '内置热门片单，也支持 doulist 和 subject_collection 自定义地址',
              onTap: () async {
                Navigator.of(context).pop();
                await _showDoubanListDialog(context, ref);
              },
            ),
            _AddModuleTile(
              title: '豆瓣首页轮播',
              subtitle: '使用 ForwardWidgets 同源轮播数据',
              onTap: () {
                ref
                    .read(settingsControllerProvider.notifier)
                    .saveHomeModule(HomeModuleConfig.doubanCarousel());
                Navigator.of(context).pop();
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
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              source.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            ...sourceCollections.map(
              (collection) => _AddModuleTile(
                title: collection.title,
                subtitle: collection.subtitle.trim().isEmpty
                    ? '${collection.sourceKind.label} 分区'
                    : collection.subtitle,
                onTap: () {
                  ref.read(settingsControllerProvider.notifier).saveHomeModule(
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
            ),
          ],
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

    return showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
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
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: '标题'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: urlController,
                      minLines: 2,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: '片单地址'),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '支持 `subject_collection` 和 `doulist` 地址，也可以先选默认片单再手动改。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
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
                    Navigator.of(context).pop();
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showEditModuleDialog(
    BuildContext context,
    WidgetRef ref,
    HomeModuleConfig module,
  ) {
    final titleController = TextEditingController(text: module.title);
    var interestStatus = module.doubanInterestStatus;
    var suggestionType = module.doubanSuggestionType;

    if (module.type == HomeModuleType.doubanList) {
      return _showDoubanListDialog(
        context,
        ref,
        existing: module,
      );
    }

    return showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('编辑模块'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: '标题'),
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
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
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
                    Navigator.of(context).pop();
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
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
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.add_circle_outline_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _SourceCategoryTile extends StatelessWidget {
  const _SourceCategoryTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: scheme.primary.withValues(alpha: 0.12),
              foregroundColor: scheme.primary,
              child: Icon(icon),
            ),
            title: Text(title),
            subtitle: Text(subtitle),
            trailing: const Icon(Icons.chevron_right_rounded),
          ),
        ),
      ),
    );
  }
}
