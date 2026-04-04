import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/widgets/section_panel.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final loading = ref.watch(settingsControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          if (loading) const LinearProgressIndicator(),
          SectionPanel(
            title: '媒体源',
            subtitle: '把 Emby 或 NAS 网关都挂进来，首页和媒体库都会共用这里的配置',
            child: Column(
              children: [
                ...settings.mediaSources.map(
                  (source) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _SettingsTile(
                      title: source.name,
                      subtitle: '${source.kind.label} · ${source.endpoint}',
                      value: source.enabled,
                      onChanged: (value) {
                        ref
                            .read(settingsControllerProvider.notifier)
                            .toggleMediaSource(source.id, value);
                      },
                      onEdit: () => _showMediaSourceDialog(
                        context,
                        ref,
                        existing: source,
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => _showMediaSourceDialog(context, ref),
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
            subtitle: '可以挂自己的索引服务、聚合接口或站点模板',
            child: Column(
              children: [
                ...settings.searchProviders.map(
                  (provider) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _SettingsTile(
                      title: provider.name,
                      subtitle: '${provider.kind.label} · ${provider.endpoint}',
                      value: provider.enabled,
                      onChanged: (value) {
                        ref
                            .read(settingsControllerProvider.notifier)
                            .toggleSearchProvider(provider.id, value);
                      },
                      onEdit: () => _showSearchProviderDialog(
                        context,
                        ref,
                        existing: provider,
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => _showSearchProviderDialog(context, ref),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('新增搜索服务'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SectionPanel(
            title: '豆瓣',
            subtitle: '推荐与想看模块会读取这里的账号配置',
            child: _SettingsTile(
              title: settings.doubanAccount.enabled ? '豆瓣已启用' : '豆瓣未启用',
              subtitle: settings.doubanAccount.userId.isEmpty
                  ? '还没有填写 userId'
                  : '当前账号：${settings.doubanAccount.userId}',
              value: settings.doubanAccount.enabled,
              onChanged: (value) {
                ref
                    .read(settingsControllerProvider.notifier)
                    .saveDoubanAccount(
                      settings.doubanAccount.copyWith(enabled: value),
                    );
              },
              onEdit: () =>
                  _showDoubanDialog(context, ref, settings.doubanAccount),
            ),
          ),
          const SizedBox(height: 18),
          SectionPanel(
            title: '首页模块',
            subtitle: '拖动排序，控制首页展示顺序；后续加新模块时这里无需重构',
            child: ReorderableListView.builder(
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
                    subtitle: Text(module.type.description),
                    leading: ReorderableDragStartListener(
                      index: index,
                      child: const Icon(Icons.drag_indicator_rounded),
                    ),
                    trailing: Switch(
                      value: module.enabled,
                      onChanged: (value) {
                        ref
                            .read(settingsControllerProvider.notifier)
                            .toggleHomeModule(module.id, value);
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showMediaSourceDialog(
    BuildContext context,
    WidgetRef ref, {
    MediaSourceConfig? existing,
  }) {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final endpointController = TextEditingController(
      text: existing?.endpoint ?? '',
    );
    final usernameController = TextEditingController(
      text: existing?.username ?? '',
    );
    final tokenController = TextEditingController(
      text: existing?.accessToken ?? '',
    );
    var kind = existing?.kind ?? MediaSourceKind.emby;
    var enabled = existing?.enabled ?? true;

    return showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(existing == null ? '新增媒体源' : '编辑媒体源'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: '名称'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<MediaSourceKind>(
                      initialValue: kind,
                      decoration: const InputDecoration(labelText: '类型'),
                      items: MediaSourceKind.values
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
                            kind = value;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: endpointController,
                      decoration: const InputDecoration(labelText: 'Endpoint'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: usernameController,
                      decoration: const InputDecoration(labelText: '用户名'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: tokenController,
                      decoration: const InputDecoration(labelText: 'Token / API Key'),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('启用'),
                      value: enabled,
                      onChanged: (value) {
                        setState(() {
                          enabled = value;
                        });
                      },
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
                    ref
                        .read(settingsControllerProvider.notifier)
                        .saveMediaSource(
                          MediaSourceConfig(
                            id: existing?.id ??
                                'media-source-${DateTime.now().millisecondsSinceEpoch}',
                            name: nameController.text.trim().isEmpty
                                ? '未命名媒体源'
                                : nameController.text.trim(),
                            kind: kind,
                            endpoint: endpointController.text.trim(),
                            enabled: enabled,
                            username: usernameController.text.trim(),
                            accessToken: tokenController.text.trim(),
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

  Future<void> _showSearchProviderDialog(
    BuildContext context,
    WidgetRef ref, {
    SearchProviderConfig? existing,
  }) {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final endpointController = TextEditingController(
      text: existing?.endpoint ?? '',
    );
    final apiKeyController = TextEditingController(
      text: existing?.apiKey ?? '',
    );
    final parserHintController = TextEditingController(
      text: existing?.parserHint ?? '',
    );
    var kind = existing?.kind ?? SearchProviderKind.indexer;
    var enabled = existing?.enabled ?? true;

    return showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(existing == null ? '新增搜索服务' : '编辑搜索服务'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: '名称'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<SearchProviderKind>(
                      initialValue: kind,
                      decoration: const InputDecoration(labelText: '类型'),
                      items: SearchProviderKind.values
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
                            kind = value;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: endpointController,
                      decoration: const InputDecoration(labelText: 'Endpoint'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: apiKeyController,
                      decoration: const InputDecoration(labelText: 'API Key'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: parserHintController,
                      decoration: const InputDecoration(labelText: '解析器提示'),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('启用'),
                      value: enabled,
                      onChanged: (value) {
                        setState(() {
                          enabled = value;
                        });
                      },
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
                    ref
                        .read(settingsControllerProvider.notifier)
                        .saveSearchProvider(
                          SearchProviderConfig(
                            id: existing?.id ??
                                'search-provider-${DateTime.now().millisecondsSinceEpoch}',
                            name: nameController.text.trim().isEmpty
                                ? '未命名搜索服务'
                                : nameController.text.trim(),
                            kind: kind,
                            endpoint: endpointController.text.trim(),
                            enabled: enabled,
                            apiKey: apiKeyController.text.trim(),
                            parserHint: parserHintController.text.trim(),
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

  Future<void> _showDoubanDialog(
    BuildContext context,
    WidgetRef ref,
    DoubanAccountConfig config,
  ) {
    final userIdController = TextEditingController(text: config.userId);
    final sessionController = TextEditingController(text: config.sessionCookie);
    var enabled = config.enabled;

    return showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('豆瓣配置'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: userIdController,
                      decoration: const InputDecoration(labelText: 'Douban User ID'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: sessionController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Cookie / Session',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('启用豆瓣模块'),
                      value: enabled,
                      onChanged: (value) {
                        setState(() {
                          enabled = value;
                        });
                      },
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
                    ref
                        .read(settingsControllerProvider.notifier)
                        .saveDoubanAccount(
                          DoubanAccountConfig(
                            enabled: enabled,
                            userId: userIdController.text.trim(),
                            sessionCookie: sessionController.text.trim(),
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

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.onEdit,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFE),
        borderRadius: BorderRadius.circular(22),
      ),
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
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
