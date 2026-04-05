import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
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
  late List<String> _savedFeaturedSectionIds;
  List<MediaCollection> _availableSections = [];
  bool _isAuthenticating = false;
  bool _isTestingWebDav = false;
  bool _isLoadingSections = false;
  bool _didHydrateSectionSelection = false;
  late String _connectionMessage;
  late bool _advancedTokenExpanded;
  late final String _sourceId;
  late String _selectedNasPath;
  late bool _webDavStructureInferenceEnabled;
  bool _didDelete = false;
  bool _skipAutoSaveOnPop = false;

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
    _savedFeaturedSectionIds = e == null
        ? const [kNoSectionsSelectedSentinel]
        : [...e.featuredSectionIds];
    _selectedSectionIds = e?.selectedSectionIds.toSet() ?? <String>{};
    _connectionMessage = _initialConnectionMessage(e);
    _advancedTokenExpanded = _tokenController.text.trim().isNotEmpty;
    _selectedNasPath = e?.libraryPath ?? '';
    _webDavStructureInferenceEnabled =
        e?.webDavStructureInferenceEnabled ?? false;
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
      libraryPath: _kind == MediaSourceKind.nas ? _selectedNasPath.trim() : '',
      featuredSectionIds: _selectedSectionIdsForSave(),
      webDavStructureInferenceEnabled:
          _kind == MediaSourceKind.nas && _webDavStructureInferenceEnabled,
    );
  }

  List<String> _selectedSectionIdsForSave() {
    if (!_didHydrateSectionSelection && _availableSections.isEmpty) {
      return _savedFeaturedSectionIds;
    }
    if (_selectedSectionIds.isNotEmpty) {
      return _selectedSectionIds.toList(growable: false);
    }
    return const [kNoSectionsSelectedSentinel];
  }

  bool _hasMeaningfulDraft() {
    return _nameController.text.trim().isNotEmpty ||
        _endpointController.text.trim().isNotEmpty ||
        _usernameController.text.trim().isNotEmpty ||
        _passwordController.text.trim().isNotEmpty ||
        _tokenController.text.trim().isNotEmpty ||
        _selectedNasPath.trim().isNotEmpty ||
        widget.initial != null;
  }

  Future<void> _saveDraft({bool popAfterSave = true}) async {
    if (_didDelete || !_hasMeaningfulDraft()) {
      if (popAfterSave && mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    final config = MediaSourceConfig(
      id: _sourceId,
      name: _nameController.text.trim().isEmpty
          ? '未命名媒体源'
          : _nameController.text.trim(),
      kind: _kind,
      endpoint: _endpointController.text.trim(),
      enabled: _enabled,
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      accessToken:
          _kind == MediaSourceKind.emby ? _tokenController.text.trim() : '',
      userId: _kind == MediaSourceKind.emby ? _resolvedUserId : '',
      serverId: _kind == MediaSourceKind.emby ? _resolvedServerId : '',
      deviceId: _kind == MediaSourceKind.emby ? _resolvedDeviceId : '',
      libraryPath: _kind == MediaSourceKind.nas ? _selectedNasPath : '',
      featuredSectionIds: _selectedSectionIdsForSave(),
      webDavStructureInferenceEnabled:
          _kind == MediaSourceKind.nas && _webDavStructureInferenceEnabled,
    );
    await ref.read(settingsControllerProvider.notifier).saveMediaSource(config);
    _savedFeaturedSectionIds = [...config.featuredSectionIds];

    if (popAfterSave && mounted) {
      _skipAutoSaveOnPop = true;
      Navigator.of(context).pop();
    }
  }

  String _defaultConnectionMessage(MediaSourceKind kind) {
    switch (kind) {
      case MediaSourceKind.emby:
        return '填写账号密码后可以直接验证 Emby 登录。';
      case MediaSourceKind.nas:
        return '填写 WebDAV 地址、用户名和密码后可以直接验证连接。';
    }
  }

  String _initialConnectionMessage(MediaSourceConfig? source) {
    if (source == null) {
      return _defaultConnectionMessage(_kind);
    }
    if (source.kind == MediaSourceKind.emby) {
      return source.embyEditorStatusMessage;
    }
    return _defaultConnectionMessage(source.kind);
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

  Future<void> _onTestWebDavConnection() async {
    final draft = _draftConfig();
    setState(() {
      _isTestingWebDav = true;
      _connectionMessage = '正在连接 WebDAV...';
    });
    try {
      final collections =
          await ref.read(webDavNasClientProvider).fetchCollections(draft);
      if (!mounted) {
        return;
      }
      setState(() {
        _isTestingWebDav = false;
        _connectionMessage = collections.isEmpty
            ? 'WebDAV 连接成功，已连通服务器，但顶层目录为空或当前账号没有列出权限。'
            : 'WebDAV 连接成功，读取到 ${collections.length} 个顶层目录。';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WebDAV 连接成功')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isTestingWebDav = false;
        _connectionMessage = '连接失败：$error';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('WebDAV 连接失败：$error')),
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
        _applyFetchedSections(sections);
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

  Future<void> _onFetchNasSections() async {
    setState(() {
      _isLoadingSections = true;
      _connectionMessage = '正在读取 WebDAV 分区...';
    });
    try {
      final sections = await ref.read(webDavNasClientProvider).fetchCollections(
            _draftConfig(),
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingSections = false;
        _applyFetchedSections(sections);
        _connectionMessage = sections.isEmpty
            ? '当前路径下没有可直接展示的子目录。'
            : '已读取 ${sections.length} 个 WebDAV 分区。';
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

  Future<void> _pickWebDavPath() async {
    final endpoint = _endpointController.text.trim();
    if (endpoint.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写 WebDAV Endpoint')),
      );
      return;
    }

    final pickedPath = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (context) => _WebDavPathPickerPage(source: _draftConfig()),
      ),
    );

    if (!mounted || pickedPath == null || pickedPath.trim().isEmpty) {
      return;
    }

    _selectedNasPath = pickedPath;
    setState(() {
      _savedFeaturedSectionIds = const [kNoSectionsSelectedSentinel];
      _availableSections = const [];
      _selectedSectionIds.clear();
      _didHydrateSectionSelection = false;
      _connectionMessage = '已选择路径，可继续测试连接。';
    });
  }

  void _applyFetchedSections(List<MediaCollection> sections) {
    _availableSections = sections;
    final availableIds = sections.map((section) => section.id).toSet();
    if (!_didHydrateSectionSelection) {
      final persistedSelection = _savedFeaturedSectionIds
          .map((item) => item.trim())
          .where(
            (item) => item.isNotEmpty && item != kNoSectionsSelectedSentinel,
          )
          .toSet()
          .intersection(availableIds);
      if (_savedFeaturedSectionIds.any(
        (item) => item.trim() == kNoSectionsSelectedSentinel,
      )) {
        _selectedSectionIds = <String>{};
      } else if (_savedFeaturedSectionIds.isNotEmpty) {
        _selectedSectionIds = persistedSelection;
      } else {
        _selectedSectionIds = availableIds;
      }
      _didHydrateSectionSelection = true;
      return;
    }

    _selectedSectionIds = _selectedSectionIds.intersection(availableIds);
  }

  void _selectAllSections() {
    setState(() {
      _didHydrateSectionSelection = true;
      _selectedSectionIds =
          _availableSections.map((section) => section.id).toSet();
    });
  }

  void _clearAllSections() {
    setState(() {
      _didHydrateSectionSelection = true;
      _selectedSectionIds = <String>{};
    });
  }

  Future<void> _onSave() => _saveDraft();

  Future<void> _confirmDeleteMediaSource() async {
    final name = _nameController.text.trim().isEmpty
        ? '此媒体源'
        : _nameController.text.trim();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除媒体源'),
        content: Text('确定删除「$name」？该操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      return;
    }
    await ref.read(settingsControllerProvider.notifier).removeMediaSource(
          _sourceId,
        );
    _didDelete = true;
    _skipAutoSaveOnPop = true;
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已删除媒体源')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEmby = _kind == MediaSourceKind.emby;

    return PopScope<void>(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop || _skipAutoSaveOnPop || _didDelete) {
          return;
        }
        _saveDraft(popAfterSave: false);
      },
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            ListView(
              padding: overlayToolbarPagePadding(context),
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
                      setState(() {
                        _kind = value;
                        _savedFeaturedSectionIds = const [
                          kNoSectionsSelectedSentinel,
                        ];
                        _didHydrateSectionSelection = false;
                        _availableSections = const [];
                        _selectedSectionIds.clear();
                        _selectedNasPath = '';
                        _webDavStructureInferenceEnabled = false;
                        _connectionMessage = _defaultConnectionMessage(value);
                      });
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
                if (!isEmby) ...[
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('当前路径'),
                    subtitle: Text(
                      _selectedNasPath.trim().isEmpty
                          ? '根目录'
                          : _selectedNasPath,
                    ),
                  ),
                ],
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
                ] else ...[
                  const SizedBox(height: 12),
                  Text(
                    '可直接填写 WebDAV 地址、用户名和密码。',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                _SectionTitle(theme: theme, label: '内容范围'),
                if (_availableSections.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: _selectAllSections,
                          child: const Text('全选'),
                        ),
                        TextButton(
                          onPressed: _clearAllSections,
                          child: const Text('清空'),
                        ),
                      ],
                    ),
                  ),
                if (_availableSections.isNotEmpty)
                  ..._availableSections.map(
                    (section) => CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _selectedSectionIds.contains(section.id),
                      title: Text(section.title),
                      onChanged: (value) {
                        setState(() {
                          _didHydrateSectionSelection = true;
                          final nextSelection = {..._selectedSectionIds};
                          if (value ?? false) {
                            nextSelection.add(section.id);
                          } else {
                            nextSelection.remove(section.id);
                          }
                          _selectedSectionIds = nextSelection;
                        });
                      },
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '未读取分区',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
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
                        if (isEmby && _resolvedUserId.trim().isNotEmpty) ...[
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
                ] else ...[
                  const SizedBox(height: 28),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton(
                          onPressed: _isTestingWebDav ||
                                  _endpointController.text.trim().isEmpty
                              ? null
                              : _onTestWebDavConnection,
                          child: Text(_isTestingWebDav ? '测试中…' : '测试连接'),
                        ),
                        OutlinedButton(
                          onPressed: _endpointController.text.trim().isEmpty
                              ? null
                              : _pickWebDavPath,
                          child: const Text('选择路径'),
                        ),
                        OutlinedButton(
                          onPressed: _isLoadingSections ||
                                  _endpointController.text.trim().isEmpty
                              ? null
                              : _onFetchNasSections,
                          child: Text(_isLoadingSections ? '读取中…' : '读取分区'),
                        ),
                      ],
                    ),
                  ),
                ],
                if (widget.initial != null) ...[
                  const SizedBox(height: 28),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: theme.colorScheme.error,
                      ),
                      label: Text(
                        '删除此媒体源',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      onPressed: _confirmDeleteMediaSource,
                    ),
                  ),
                ],
              ],
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: OverlayToolbar(
                trailing: TextButton(
                  onPressed: _onSave,
                  child: const Text('保存'),
                ),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('目录结构推断'),
              value: _webDavStructureInferenceEnabled,
              onChanged: (value) {
                setState(() {
                  _webDavStructureInferenceEnabled = value;
                });
              },
            ),
          ],
        ),
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

class _WebDavPathPickerPage extends ConsumerStatefulWidget {
  const _WebDavPathPickerPage({required this.source});

  final MediaSourceConfig source;

  @override
  ConsumerState<_WebDavPathPickerPage> createState() =>
      _WebDavPathPickerPageState();
}

class _WebDavPathPickerPageState extends ConsumerState<_WebDavPathPickerPage> {
  late String _currentPath;
  late String _rootPath;
  bool _skipAutoSaveOnPop = false;

  @override
  void initState() {
    super.initState();
    _rootPath = widget.source.endpoint.trim();
    _currentPath = widget.source.libraryPath.trim().isNotEmpty
        ? widget.source.libraryPath.trim()
        : _rootPath;
  }

  Future<List<MediaCollection>> _loadFolders() {
    return ref.read(webDavNasClientProvider).fetchCollections(
          widget.source,
          directoryId: _currentPath,
        );
  }

  String _pathLabel(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null) {
      return raw;
    }
    final path = uri.path.isEmpty ? '/' : uri.path;
    return '${uri.host}$path';
  }

  String? _parentPath(String raw) {
    final uri = Uri.tryParse(raw);
    final rootUri = Uri.tryParse(_rootPath);
    if (uri == null) {
      return null;
    }
    if (rootUri != null &&
        _normalizeDirectoryUri(uri) == _normalizeDirectoryUri(rootUri)) {
      return null;
    }
    final segments =
        uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
    if (segments.isEmpty) {
      return null;
    }
    final parentSegments = segments.take(segments.length - 1).toList();
    final parentPath =
        parentSegments.isEmpty ? '/' : '/${parentSegments.join('/')}/';
    final parent =
        uri.replace(path: parentPath, query: null, fragment: null).toString();
    if (rootUri == null) {
      return parent;
    }
    final normalizedParent = _normalizeDirectoryUri(Uri.parse(parent));
    final normalizedRoot = _normalizeDirectoryUri(rootUri);
    if (!normalizedParent.path.startsWith(normalizedRoot.path)) {
      return null;
    }
    return parent;
  }

  Uri _normalizeDirectoryUri(Uri uri) {
    final normalizedPath = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
    return uri.replace(path: normalizedPath, query: null, fragment: null);
  }

  @override
  Widget build(BuildContext context) {
    final parentPath = _parentPath(_currentPath);
    return PopScope<String>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _skipAutoSaveOnPop) {
          return;
        }
        _skipAutoSaveOnPop = true;
        Navigator.of(context).pop(_currentPath);
      },
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<List<MediaCollection>>(
              future: _loadFolders(),
              builder: (context, snapshot) {
                return ListView(
                  padding: overlayToolbarPagePadding(context),
                  children: [
                    Text(
                      '当前路径',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      _pathLabel(_currentPath),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (parentPath != null) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _currentPath = parentPath;
                            });
                          },
                          icon:
                              const Icon(Icons.arrow_upward_rounded, size: 18),
                          label: const Text('返回上一级目录'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.only(top: 48),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (snapshot.hasError)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text('读取路径失败：${snapshot.error}'),
                      )
                    else if ((snapshot.data ?? const []).isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text('当前路径下没有子文件夹，可以直接选择这里作为根路径。'),
                      )
                    else ...[
                      Text(
                        '子文件夹',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 8),
                      for (final folder in snapshot.data!)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.folder_open_rounded),
                          title: Text(folder.title),
                          subtitle: Text(folder.id),
                          onTap: () {
                            setState(() {
                              _currentPath = folder.id;
                            });
                          },
                        ),
                    ],
                  ],
                );
              },
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                type: MaterialType.transparency,
                child: Padding(
                  padding:
                      EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
                  child: SizedBox(
                    height: kToolbarHeight,
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () {
                            _skipAutoSaveOnPop = true;
                            Navigator.of(context).pop(_currentPath);
                          },
                          icon: const Icon(Icons.arrow_back_ios_new_rounded),
                        ),
                        Expanded(
                          child: Text(
                            '选择 WebDAV 路径',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            _skipAutoSaveOnPop = true;
                            Navigator.of(context).pop(_currentPath);
                          },
                          child: const Text('选这里'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
