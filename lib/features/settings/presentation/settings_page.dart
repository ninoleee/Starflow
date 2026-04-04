import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/core/widgets/section_panel.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

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
                      subtitle: _buildMediaSourceSubtitle(source),
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
                      subtitle: _buildSearchProviderSubtitle(provider),
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
                ref.read(settingsControllerProvider.notifier).saveDoubanAccount(
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
    final passwordController = TextEditingController(
      text: existing?.password ?? '',
    );
    final tokenController = TextEditingController(
      text: existing?.accessToken ?? '',
    );
    var kind = existing?.kind ?? MediaSourceKind.emby;
    var enabled = existing?.enabled ?? true;
    var resolvedUserId = existing?.userId ?? '';
    var resolvedServerId = existing?.serverId ?? '';
    var resolvedDeviceId = existing?.deviceId ?? '';
    var selectedSectionIds = {
      ...existing?.featuredSectionIds ?? const <String>[]
    };
    var availableSections = <MediaCollection>[];
    var isAuthenticating = false;
    var isLoadingSections = false;
    var connectionMessage = existing == null
        ? '填写账号密码后可以直接验证 Emby 登录。'
        : _buildEmbyConnectionMessage(existing);

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
                      decoration: InputDecoration(
                        labelText: kind == MediaSourceKind.emby
                            ? 'Endpoint'
                            : 'WebDAV Endpoint',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: usernameController,
                      decoration: InputDecoration(
                        labelText:
                            kind == MediaSourceKind.emby ? 'Emby 用户名' : '用户名',
                      ),
                    ),
                    if (kind == MediaSourceKind.emby) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: 'Emby 密码'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: tokenController,
                        decoration: const InputDecoration(
                          labelText: 'Access Token / API Key',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5FF),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              connectionMessage,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            if (resolvedUserId.trim().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              SelectableText(
                                'User ID: $resolvedUserId',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (availableSections.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '首页展示分区',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...availableSections.map(
                          (section) => CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: selectedSectionIds.contains(section.id),
                            title: Text(section.title),
                            subtitle: section.subtitle.trim().isEmpty
                                ? null
                                : Text(section.subtitle),
                            onChanged: (value) {
                              setState(() {
                                if (value ?? false) {
                                  selectedSectionIds.add(section.id);
                                } else {
                                  selectedSectionIds.remove(section.id);
                                }
                              });
                            },
                          ),
                        ),
                      ],
                    ] else ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: passwordController,
                        obscureText: true,
                        decoration:
                            const InputDecoration(labelText: 'WebDAV 密码'),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '飞牛 NAS 可直接填写它的 WebDAV 地址、用户名和密码。',
                        ),
                      ),
                    ],
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
                if (kind == MediaSourceKind.emby)
                  OutlinedButton(
                    onPressed: isAuthenticating
                        ? null
                        : () async {
                            final draft = MediaSourceConfig(
                              id: existing?.id ??
                                  'media-source-${DateTime.now().millisecondsSinceEpoch}',
                              name: nameController.text.trim().isEmpty
                                  ? '未命名媒体源'
                                  : nameController.text.trim(),
                              kind: kind,
                              endpoint: endpointController.text.trim(),
                              enabled: enabled,
                              username: usernameController.text.trim(),
                              password: passwordController.text,
                              accessToken: tokenController.text.trim(),
                              userId: resolvedUserId,
                              serverId: resolvedServerId,
                              deviceId: resolvedDeviceId,
                              featuredSectionIds: selectedSectionIds.toList(),
                            );

                            setState(() {
                              isAuthenticating = true;
                              connectionMessage = '正在连接 Emby...';
                            });

                            try {
                              final authenticated = await ref
                                  .read(settingsControllerProvider.notifier)
                                  .authenticateEmby(
                                    source: draft,
                                    password: passwordController.text.trim(),
                                  );
                              if (!context.mounted) {
                                return;
                              }

                              usernameController.text = authenticated.username;
                              endpointController.text = authenticated.endpoint;
                              tokenController.text = authenticated.accessToken;
                              setState(() {
                                isAuthenticating = false;
                                resolvedUserId = authenticated.userId;
                                resolvedServerId = authenticated.serverId;
                                resolvedDeviceId = authenticated.deviceId;
                                connectionMessage = _buildEmbyConnectionMessage(
                                  authenticated,
                                );
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Emby 登录成功')),
                              );
                            } catch (error) {
                              if (!context.mounted) {
                                return;
                              }
                              setState(() {
                                isAuthenticating = false;
                                connectionMessage = '登录失败：$error';
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Emby 登录失败：$error')),
                              );
                            }
                          },
                    child: Text(isAuthenticating ? '登录中...' : '测试登录'),
                  ),
                if (kind == MediaSourceKind.emby)
                  OutlinedButton(
                    onPressed: isLoadingSections ||
                            endpointController.text.trim().isEmpty ||
                            tokenController.text.trim().isEmpty ||
                            resolvedUserId.trim().isEmpty
                        ? null
                        : () async {
                            setState(() {
                              isLoadingSections = true;
                              connectionMessage = '正在读取 Emby 分区...';
                            });

                            try {
                              final sections = await ref
                                  .read(embyApiClientProvider)
                                  .fetchCollections(
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
                                      password: passwordController.text,
                                      accessToken: tokenController.text.trim(),
                                      userId: resolvedUserId,
                                      serverId: resolvedServerId,
                                      deviceId: resolvedDeviceId,
                                      featuredSectionIds:
                                          selectedSectionIds.toList(),
                                    ),
                                  );
                              if (!context.mounted) {
                                return;
                              }
                              setState(() {
                                isLoadingSections = false;
                                availableSections = sections;
                                connectionMessage =
                                    '${_buildEmbyConnectionMessage(
                                  MediaSourceConfig(
                                    id: existing?.id ?? '',
                                    name: nameController.text.trim(),
                                    kind: kind,
                                    endpoint: endpointController.text.trim(),
                                    enabled: enabled,
                                    username: usernameController.text.trim(),
                                    password: passwordController.text,
                                    accessToken: tokenController.text.trim(),
                                    userId: resolvedUserId,
                                    serverId: resolvedServerId,
                                    deviceId: resolvedDeviceId,
                                    featuredSectionIds:
                                        selectedSectionIds.toList(),
                                  ),
                                )}\n已读取 ${sections.length} 个分区。';
                              });
                            } catch (error) {
                              if (!context.mounted) {
                                return;
                              }
                              setState(() {
                                isLoadingSections = false;
                                connectionMessage = '读取分区失败：$error';
                              });
                            }
                          },
                    child: Text(isLoadingSections ? '读取中...' : '读取分区'),
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
                            password: passwordController.text,
                            accessToken: kind == MediaSourceKind.emby
                                ? tokenController.text.trim()
                                : '',
                            userId: kind == MediaSourceKind.emby
                                ? resolvedUserId
                                : '',
                            serverId: kind == MediaSourceKind.emby
                                ? resolvedServerId
                                : '',
                            deviceId: kind == MediaSourceKind.emby
                                ? resolvedDeviceId
                                : '',
                            featuredSectionIds: kind == MediaSourceKind.emby
                                ? selectedSectionIds.toList()
                                : const [],
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
    final usernameController = TextEditingController(
      text: existing?.username ?? '',
    );
    final passwordController = TextEditingController(
      text: existing?.password ?? '',
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
                      decoration: const InputDecoration(
                        labelText: 'JWT Token / API Key',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: usernameController,
                      decoration: const InputDecoration(labelText: '登录用户名'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: '登录密码'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: parserHintController,
                      decoration: const InputDecoration(labelText: '解析器提示'),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'PanSou 兼容接口建议填 parserHint 为 pansou-api。'
                        ' 如果服务启用了认证，可以直接填 JWT Token，'
                        '或者填写用户名和密码让应用自动登录。',
                      ),
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
                            username: usernameController.text.trim(),
                            password: passwordController.text.trim(),
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
                      decoration:
                          const InputDecoration(labelText: 'Douban User ID'),
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

  String _buildEmbyConnectionMessage(MediaSourceConfig source) {
    if (source.hasActiveSession) {
      final serverPart = source.serverId.trim().isEmpty
          ? ''
          : '，Server ID: ${source.serverId}';
      return '当前会话可用，登录用户 ${source.username}$serverPart';
    }
    if (source.accessToken.trim().isNotEmpty) {
      return '已经保存 token，但还没有拿到 User ID，建议重新测试登录。';
    }
    return '填写账号密码后可以直接验证 Emby 登录。';
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
