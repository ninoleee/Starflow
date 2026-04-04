import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/core/widgets/section_panel.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/presentation/media_source_editor_page.dart';
import 'package:starflow/features/settings/presentation/douban_account_editor_page.dart';
import 'package:starflow/features/settings/presentation/search_provider_editor_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final loading = ref.watch(settingsControllerProvider).isLoading;

    return Scaffold(
      body: AppPageBackground(
        child: ListView(
          padding: EdgeInsets.zero,
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
                        subtitle: _buildMediaSourceSubtitle(source),
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
              subtitle: '可以挂自己的索引服务、聚合接口或站点模板',
              child: Column(
                children: [
                  ...settings.searchProviders.map(
                    (provider) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _SettingsTile(
                        title: provider.name,
                        subtitle: _buildSearchProviderSubtitle(provider),
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
                onEdit: () => _openDoubanAccountEditor(
                  context,
                  settings.doubanAccount,
                ),
              ),
            ),
            const SizedBox(height: 18),
            SectionPanel(
              title: '元数据与评分',
              subtitle: 'TMDB 补影片信息，IMDb 补评分；都只在详情页按需触发，不拖慢首页和媒体库',
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用 TMDB 自动补全影片信息'),
                    subtitle: Text(
                      settings.tmdbReadAccessToken.trim().isEmpty
                          ? '当前未配置 TMDB Read Access Token，打开开关后也不会触发。'
                          : '缺少海报、简介、导演、演员等信息时自动补全。',
                    ),
                    value: settings.tmdbMetadataMatchEnabled,
                    onChanged: (value) {
                      ref
                          .read(settingsControllerProvider.notifier)
                          .setTmdbMetadataMatchEnabled(value);
                    },
                  ),
                  const SizedBox(height: 6),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('TMDB Read Access Token'),
                    subtitle: Text(
                      settings.tmdbReadAccessToken.trim().isEmpty
                          ? '未配置'
                          : '已配置',
                    ),
                    trailing: OutlinedButton(
                      onPressed: () => _openTmdbTokenEditor(
                        context,
                        ref,
                        settings.tmdbReadAccessToken,
                      ),
                      child: Text(
                        settings.tmdbReadAccessToken.trim().isEmpty
                            ? '填写'
                            : '编辑',
                      ),
                    ),
                  ),
                  const Divider(height: 20),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用 IMDb 自动补评分'),
                    subtitle: const Text('会先匹配 IMDb 条目，再补一个 IMDb 评分标签。'),
                    value: settings.imdbRatingMatchEnabled,
                    onChanged: (value) {
                      ref
                          .read(settingsControllerProvider.notifier)
                          .setImdbRatingMatchEnabled(value);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SectionPanel(
              title: '首页模块',
              subtitle: '首页最底部有一个低调的“编辑首页”入口，用它来选择显示哪些模块',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('当前已配置 ${settings.homeModules.length} 个首页模块。'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => context.pushNamed('home-editor'),
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('去首页编辑器'),
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
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => MediaSourceEditorPage(initial: existing),
      ),
    );
  }

  Future<void> _openSearchProviderEditor(
    BuildContext context, {
    SearchProviderConfig? existing,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => SearchProviderEditorPage(initial: existing),
      ),
    );
  }

  Future<void> _openDoubanAccountEditor(
    BuildContext context,
    DoubanAccountConfig config,
  ) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => DoubanAccountEditorPage(initial: config),
      ),
    );
  }

  Future<void> _openTmdbTokenEditor(
    BuildContext context,
    WidgetRef ref,
    String currentToken,
  ) async {
    final controller = TextEditingController(text: currentToken);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('TMDB Read Access Token'),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: '粘贴 TMDB 的 Read Access Token',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                controller.clear();
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('清空'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    if (saved == true) {
      await ref
          .read(settingsControllerProvider.notifier)
          .setTmdbReadAccessToken(controller.text);
    }
    controller.dispose();
  }

  String _buildMediaSourceSubtitle(MediaSourceConfig source) {
    if (source.kind != MediaSourceKind.emby) {
      final authLine = source.username.trim().isEmpty
          ? '匿名 WebDAV'
          : 'WebDAV · ${source.username}';
      return '${source.kind.label} · ${source.endpoint}\n$authLine';
    }

    final authLine = source.hasActiveSession
        ? '状态：已登录 ${source.username.isEmpty ? '' : '· ${source.username}'}'
        : '状态：${source.connectionStatusLabel}';
    final sectionLine = source.featuredSectionIds.isEmpty
        ? '首页分区：未选择'
        : '首页分区：已选 ${source.featuredSectionIds.length} 个';
    return 'Emby · ${source.endpoint}\n$authLine\n$sectionLine';
  }

  String _buildSearchProviderSubtitle(SearchProviderConfig provider) {
    final adapter = provider.parserHint.trim().isEmpty
        ? provider.kind.label
        : '${provider.kind.label} · ${provider.parserHint}';
    final authStatus = provider.apiKey.trim().isNotEmpty
        ? '已填 Token'
        : provider.username.trim().isNotEmpty
            ? '自动登录 ${provider.username}'
            : '匿名请求';
    return '$adapter · ${provider.endpoint}\n$authStatus';
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
