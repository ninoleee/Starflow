import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class HomeEditorPage extends ConsumerWidget {
  const HomeEditorPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final collectionsAsync = ref.watch(homeEditorCollectionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('编辑首页')),
      floatingActionButton: FloatingActionButton.small(
        onPressed: () => _showAddModuleSheet(context, ref),
        child: const Icon(Icons.add_rounded),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
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
                          color: const Color(0xFFF8FAFE),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: ListTile(
                          title: Text(module.title),
                          subtitle: Text(module.description),
                          leading: ReorderableDragStartListener(
                            index: index,
                            child: const Icon(Icons.drag_indicator_rounded),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: () =>
                                    _showEditModuleDialog(context, ref, module),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                onPressed: () {
                                  ref
                                      .read(settingsControllerProvider.notifier)
                                      .removeHomeModule(module.id);
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                              Switch(
                                value: module.enabled,
                                onChanged: (value) {
                                  ref
                                      .read(settingsControllerProvider.notifier)
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
            subtitle: '当前已接入的来源分区会出现在这里',
            child: collectionsAsync.when(
              data: (collections) {
                if (collections.isEmpty) {
                  return const Text('还没有可用分区。先去设置里接入 Emby 或 NAS。');
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: collections
                      .map(
                        (collection) => ActionChip(
                          label: Text(
                              '${collection.sourceName} · ${collection.title}'),
                          onPressed: () {
                            ref
                                .read(settingsControllerProvider.notifier)
                                .saveHomeModule(
                                  HomeModuleConfig.libraryCollection(
                                      collection),
                                );
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
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => Text('读取分区失败：$error'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddModuleSheet(BuildContext context, WidgetRef ref) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '添加模块',
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
                _AddModuleTile(
                  title: '豆瓣我想看',
                  subtitle: '来自豆瓣我看列表',
                  onTap: () {
                    ref
                        .read(settingsControllerProvider.notifier)
                        .saveHomeModule(
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
                    ref
                        .read(settingsControllerProvider.notifier)
                        .saveHomeModule(
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
                    ref
                        .read(settingsControllerProvider.notifier)
                        .saveHomeModule(
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
                    ref
                        .read(settingsControllerProvider.notifier)
                        .saveHomeModule(
                          HomeModuleConfig.doubanSuggestion(
                            DoubanSuggestionMediaType.tv,
                          ),
                        );
                    Navigator.of(context).pop();
                  },
                ),
                _AddModuleTile(
                  title: '豆瓣片单',
                  subtitle: '支持 doulist 和 subject_collection 地址',
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _showCreateDoubanListDialog(context, ref);
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
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCreateDoubanListDialog(
    BuildContext context,
    WidgetRef ref,
  ) {
    final titleController = TextEditingController(text: '豆瓣片单');
    final urlController = TextEditingController();

    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('新增豆瓣片单'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
            ],
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
                ref.read(settingsControllerProvider.notifier).saveHomeModule(
                      HomeModuleConfig.doubanList(
                        title: titleController.text.trim().isEmpty
                            ? '豆瓣片单'
                            : titleController.text.trim(),
                        url: url,
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
  }

  Future<void> _showEditModuleDialog(
    BuildContext context,
    WidgetRef ref,
    HomeModuleConfig module,
  ) {
    final titleController = TextEditingController(text: module.title);
    final urlController = TextEditingController(text: module.doubanListUrl);
    var interestStatus = module.doubanInterestStatus;
    var suggestionType = module.doubanSuggestionType;

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
                    if (module.type == HomeModuleType.doubanList) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: urlController,
                        minLines: 2,
                        maxLines: 3,
                        decoration: const InputDecoration(labelText: '片单地址'),
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
                            doubanListUrl: urlController.text.trim(),
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
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.add_circle_outline_rounded),
      onTap: onTap,
    );
  }
}
