import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

/// 全屏编辑媒体源（替代原先窄对话框，便于长表单与键盘避让）。
class MediaSourceEditorPage extends ConsumerStatefulWidget {
  const MediaSourceEditorPage({super.key, this.initial});

  final MediaSourceConfig? initial;

  @override
  ConsumerState<MediaSourceEditorPage> createState() =>
      _MediaSourceEditorPageState();
}

class _MediaSourceEditorPageState extends ConsumerState<MediaSourceEditorPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _endpointController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _tokenController;

  late MediaSourceKind _kind;
  late bool _enabled;
  String _resolvedUserId = '';
  String _resolvedServerId = '';
  String _resolvedDeviceId = '';
  late Set<String> _selectedSectionIds;
  List<MediaCollection> _availableSections = [];
  bool _isAuthenticating = false;
  bool _isLoadingSections = false;
  late String _connectionMessage;
  late bool _advancedTokenExpanded;
  late final String _sourceId;

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _sourceId =
        e?.id ?? 'media-source-${DateTime.now().millisecondsSinceEpoch}';
    _nameController = TextEditingController(text: e?.name ?? '');
    _endpointController = TextEditingController(text: e?.endpoint ?? '');
    _usernameController = TextEditingController(text: e?.username ?? '');
    _passwordController = TextEditingController(text: e?.password ?? '');
    _tokenController = TextEditingController(text: e?.accessToken ?? '');
    _kind = e?.kind ?? MediaSourceKind.emby;
    _enabled = e?.enabled ?? true;
    _resolvedUserId = e?.userId ?? '';
    _resolvedServerId = e?.serverId ?? '';
    _resolvedDeviceId = e?.deviceId ?? '';
    _selectedSectionIds = {...?e?.featuredSectionIds};
    _connectionMessage =
        e == null ? '填写账号密码后可以直接验证 Emby 登录。' : e.embyEditorStatusMessage;
    _advancedTokenExpanded = _tokenController.text.trim().isNotEmpty;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _endpointController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  MediaSourceConfig _draftConfig() {
    return MediaSourceConfig(
      id: _sourceId,
      name: _nameController.text.trim().isEmpty
          ? '未命名媒体源'
          : _nameController.text.trim(),
      kind: _kind,
      endpoint: _endpointController.text.trim(),
      enabled: _enabled,
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      accessToken: _tokenController.text.trim(),
      userId: _resolvedUserId,
      serverId: _resolvedServerId,
      deviceId: _resolvedDeviceId,
      featuredSectionIds: _selectedSectionIds.toList(),
    );
  }

  Future<void> _onTestEmbyLogin() async {
    final draft = _draftConfig();
    setState(() {
      _isAuthenticating = true;
      _connectionMessage = '正在连接 Emby...';
    });
    try {
      final authenticated =
          await ref.read(settingsControllerProvider.notifier).authenticateEmby(
                source: draft,
                password: _passwordController.text.trim(),
              );
      if (!mounted) {
        return;
      }
      _usernameController.text = authenticated.username;
      _endpointController.text = authenticated.endpoint;
      _tokenController.text = authenticated.accessToken;
      setState(() {
        _isAuthenticating = false;
        _resolvedUserId = authenticated.userId;
        _resolvedServerId = authenticated.serverId;
        _resolvedDeviceId = authenticated.deviceId;
        _connectionMessage = authenticated.embyEditorStatusMessage;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Emby 登录成功')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isAuthenticating = false;
        _connectionMessage = '登录失败：$error';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Emby 登录失败：$error')),
      );
    }
  }

  Future<void> _onFetchEmbySections() async {
    setState(() {
      _isLoadingSections = true;
      _connectionMessage = '正在读取 Emby 分区...';
    });
    try {
      final sections = await ref.read(embyApiClientProvider).fetchCollections(
            _draftConfig(),
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingSections = false;
        _availableSections = sections;
        _connectionMessage =
            '${_draftConfig().embyEditorStatusMessage}\n已读取 ${sections.length} 个分区。';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingSections = false;
        _connectionMessage = '读取分区失败：$error';
      });
    }
  }

  void _onSave() {
    ref.read(settingsControllerProvider.notifier).saveMediaSource(
          MediaSourceConfig(
            id: _sourceId,
            name: _nameController.text.trim().isEmpty
                ? '未命名媒体源'
                : _nameController.text.trim(),
            kind: _kind,
            endpoint: _endpointController.text.trim(),
            enabled: _enabled,
            username: _usernameController.text.trim(),
            password: _passwordController.text,
            accessToken: _kind == MediaSourceKind.emby
                ? _tokenController.text.trim()
                : '',
            userId: _kind == MediaSourceKind.emby ? _resolvedUserId : '',
            serverId: _kind == MediaSourceKind.emby ? _resolvedServerId : '',
            deviceId: _kind == MediaSourceKind.emby ? _resolvedDeviceId : '',
            featuredSectionIds: _kind == MediaSourceKind.emby
                ? _selectedSectionIds.toList()
                : const [],
          ),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEmby = _kind == MediaSourceKind.emby;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? '新增媒体源' : '编辑媒体源'),
        actions: [
          TextButton(
            onPressed: _onSave,
            child: const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          _SectionTitle(theme: theme, label: '基本信息'),
          TextField(
            controller: _nameController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: '名称'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<MediaSourceKind>(
            key: ValueKey(_kind),
            initialValue: _kind,
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
                setState(() => _kind = value);
              }
            },
          ),
          _SectionTitle(theme: theme, label: '连接'),
          TextField(
            controller: _endpointController,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: isEmby ? 'Endpoint' : 'WebDAV Endpoint',
              hintText: isEmby
                  ? 'https://emby.example.com'
                  : 'https://nas.example.com/dav',
            ),
          ),
          const SizedBox(height: 12),
          AutofillGroup(
            child: Column(
              children: [
                TextField(
                  controller: _usernameController,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                  decoration: InputDecoration(
                    labelText: isEmby ? 'Emby 用户名' : '用户名',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: isEmby ? 'Emby 密码' : 'WebDAV 密码',
                  ),
                ),
              ],
            ),
          ),
          if (isEmby) ...[
            const SizedBox(height: 8),
            ExpansionTile(
              initiallyExpanded: _advancedTokenExpanded,
              onExpansionChanged: (expanded) {
                setState(() => _advancedTokenExpanded = expanded);
              },
              title: Text(
                '高级（可选）',
                style: theme.textTheme.titleSmall,
              ),
              subtitle: Text(
                '手动粘贴 Access Token / API Key',
                style: theme.textTheme.bodySmall,
              ),
              children: [
                TextField(
                  controller: _tokenController,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Access Token / API Key',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _connectionMessage,
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (_resolvedUserId.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      SelectableText(
                        'User ID: $_resolvedUserId',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_availableSections.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                '首页展示分区',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              ..._availableSections.map(
                (section) => CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _selectedSectionIds.contains(section.id),
                  title: Text(section.title),
                  subtitle: section.subtitle.trim().isEmpty
                      ? null
                      : Text(section.subtitle),
                  onChanged: (value) {
                    setState(() {
                      if (value ?? false) {
                        _selectedSectionIds.add(section.id);
                      } else {
                        _selectedSectionIds.remove(section.id);
                      }
                    });
                  },
                ),
              ),
            ],
          ] else ...[
            const SizedBox(height: 12),
            Text(
              '飞牛 NAS 可直接填写 WebDAV 地址、用户名和密码。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('启用此媒体源'),
            value: _enabled,
            onChanged: (value) => setState(() => _enabled = value),
          ),
          if (isEmby) ...[
            const SizedBox(height: 28),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.start,
              children: [
                OutlinedButton(
                  onPressed: _isAuthenticating ? null : _onTestEmbyLogin,
                  child: Text(
                    _isAuthenticating ? '登录中…' : '测试登录',
                  ),
                ),
                OutlinedButton(
                  onPressed: _isLoadingSections ||
                          _endpointController.text.trim().isEmpty ||
                          _tokenController.text.trim().isEmpty ||
                          _resolvedUserId.trim().isEmpty
                      ? null
                      : _onFetchEmbySections,
                  child: Text(
                    _isLoadingSections ? '读取中…' : '读取分区',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.theme, required this.label});

  final ThemeData theme;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
