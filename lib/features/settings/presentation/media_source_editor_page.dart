import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_text_input_field.dart';

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
  late final TextEditingController _webDavExcludedKeywordsController;

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
  late String _boundWebDavEndpoint;
  late bool _webDavStructureInferenceEnabled;
  late bool _webDavSidecarScrapingEnabled;
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
    _webDavExcludedKeywordsController = TextEditingController(
      text: (e?.webDavExcludedPathKeywords ?? const []).join('\n'),
    );
    _kind = e?.kind ?? MediaSourceKind.emby;
    _enabled = e?.enabled ?? true;
    _resolvedUserId = e?.userId ?? '';
    _resolvedServerId = e?.serverId ?? '';
    _resolvedDeviceId = e?.deviceId ?? '';
    _savedFeaturedSectionIds = e == null ? const [] : [...e.featuredSectionIds];
    _selectedSectionIds = e?.selectedSectionIds.toSet() ?? <String>{};
    _connectionMessage = _initialConnectionMessage(e);
    _advancedTokenExpanded = _tokenController.text.trim().isNotEmpty;
    _selectedNasPath = e?.libraryPath ?? '';
    _boundWebDavEndpoint =
        (e?.kind == MediaSourceKind.nas ? (e?.endpoint ?? '') : '').trim();
    _webDavStructureInferenceEnabled =
        e?.webDavStructureInferenceEnabled ?? false;
    _webDavSidecarScrapingEnabled = e?.webDavSidecarScrapingEnabled ?? true;
    _endpointController.addListener(_handleEndpointChanged);
  }

  @override
  void dispose() {
    _endpointController.removeListener(_handleEndpointChanged);
    _nameController.dispose();
    _endpointController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _tokenController.dispose();
    _webDavExcludedKeywordsController.dispose();
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
      webDavSidecarScrapingEnabled:
          _kind == MediaSourceKind.nas && _webDavSidecarScrapingEnabled,
      webDavExcludedPathKeywords: _kind == MediaSourceKind.nas
          ? _parsedWebDavExcludedPathKeywords()
          : const [],
    );
  }

  List<String> _parsedWebDavExcludedPathKeywords() {
    final seen = <String>{};
    final values = <String>[];
    for (final chunk
        in _webDavExcludedKeywordsController.text.split(RegExp(r'[\n,，;；]+'))) {
      final normalized = chunk.trim();
      if (normalized.isEmpty || !seen.add(normalized.toLowerCase())) {
        continue;
      }
      values.add(normalized);
    }
    return values;
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
        _webDavExcludedKeywordsController.text.trim().isNotEmpty ||
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
      webDavSidecarScrapingEnabled:
          _kind == MediaSourceKind.nas && _webDavSidecarScrapingEnabled,
      webDavExcludedPathKeywords: _kind == MediaSourceKind.nas
          ? _parsedWebDavExcludedPathKeywords()
          : const [],
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

  void _handleEndpointChanged() {
    if (_kind != MediaSourceKind.nas) {
      return;
    }
    final normalizedEndpoint = _endpointController.text.trim();
    if (normalizedEndpoint == _boundWebDavEndpoint) {
      return;
    }

    final hadBoundWebDavState = _selectedNasPath.trim().isNotEmpty ||
        _availableSections.isNotEmpty ||
        _didHydrateSectionSelection;

    setState(() {
      _boundWebDavEndpoint = normalizedEndpoint;
      if (!hadBoundWebDavState) {
        return;
      }
      _selectedNasPath = '';
      _savedFeaturedSectionIds = const [];
      _availableSections = const [];
      _selectedSectionIds.clear();
      _didHydrateSectionSelection = false;
      _connectionMessage = normalizedEndpoint.isEmpty
          ? _defaultConnectionMessage(MediaSourceKind.nas)
          : 'WebDAV 地址已变更，请重新选择路径并测试连接。';
    });
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
      _boundWebDavEndpoint = endpoint;
      _savedFeaturedSectionIds = const [];
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

  void _applyKindSelection(MediaSourceKind value) {
    setState(() {
      _kind = value;
      _savedFeaturedSectionIds = const [];
      _didHydrateSectionSelection = false;
      _availableSections = const [];
      _selectedSectionIds.clear();
      _selectedNasPath = '';
      _boundWebDavEndpoint =
          value == MediaSourceKind.nas ? _endpointController.text.trim() : '';
      _webDavStructureInferenceEnabled = false;
      _webDavSidecarScrapingEnabled = true;
      _webDavExcludedKeywordsController.clear();
      _connectionMessage = _defaultConnectionMessage(value);
    });
  }

  Future<void> _openKindPicker() async {
    final selected = await showSettingsOptionDialog<MediaSourceKind>(
      context: context,
      title: '选择类型',
      options: MediaSourceKind.values,
      currentValue: _kind,
      labelBuilder: (item) => item.label,
    );
    if (selected == null) {
      return;
    }
    _applyKindSelection(selected);
  }

  Future<void> _onSave() => _saveDraft();

  bool _hasUnsavedChanges() {
    if (_didDelete) {
      return false;
    }
    final initial = widget.initial;
    if (initial == null) {
      return _hasMeaningfulDraft();
    }
    return jsonEncode(_draftConfig().toJson()) != jsonEncode(initial.toJson());
  }

  Future<void> _discardAndClose() async {
    _skipAutoSaveOnPop = true;
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleCloseRequest() async {
    if (_skipAutoSaveOnPop || _didDelete) {
      return;
    }
    if (!_hasUnsavedChanges()) {
      await _discardAndClose();
      return;
    }
    final action = await showSettingsCloseConfirmDialog(context);
    if (action == SettingsCloseAction.discard) {
      await _discardAndClose();
    } else if (action == SettingsCloseAction.save) {
      await _saveDraft();
    }
  }

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
          StarflowButton(
            label: '取消',
            onPressed: () => Navigator.of(ctx).pop(false),
            variant: StarflowButtonVariant.ghost,
            compact: true,
          ),
          StarflowButton(
            label: '删除',
            onPressed: () => Navigator.of(ctx).pop(true),
            variant: StarflowButtonVariant.danger,
            compact: true,
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
    final isEmby = _kind == MediaSourceKind.emby;

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _skipAutoSaveOnPop || _didDelete) {
          return;
        }
        _handleCloseRequest();
      },
      child: SettingsPageScaffold(
        onBack: _handleCloseRequest,
        trailing: SettingsToolbarButton(
          label: '保存',
          icon: Icons.save_rounded,
          onPressed: _onSave,
        ),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          const SettingsSectionTitle(label: '基本信息'),
          SettingsTextInputField(
            controller: _nameController,
            labelText: '名称',
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          SettingsSelectionTile(
            title: '类型',
            value: _kind.label,
            onPressed: _openKindPicker,
          ),
          const SettingsSectionTitle(label: '连接'),
          SettingsTextInputField(
            controller: _endpointController,
            labelText: isEmby ? 'Endpoint' : 'WebDAV Endpoint',
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            hintText: isEmby
                ? 'https://emby.example.com'
                : 'https://nas.example.com/dav',
          ),
          if (!isEmby) ...[
            const SizedBox(height: 12),
            StarflowSelectionTile(
              title: '当前路径',
              subtitle:
                  _selectedNasPath.trim().isEmpty ? '根目录' : _selectedNasPath,
              onPressed: _endpointController.text.trim().isEmpty
                  ? null
                  : _pickWebDavPath,
            ),
          ],
          const SizedBox(height: 12),
          AutofillGroup(
            child: Column(
              children: [
                SettingsTextInputField(
                  controller: _usernameController,
                  labelText: isEmby ? 'Emby 用户名' : '用户名',
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                ),
                const SizedBox(height: 12),
                SettingsTextInputField(
                  controller: _passwordController,
                  labelText: isEmby ? 'Emby 密码' : 'WebDAV 密码',
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  summaryBuilder: (value) => value.isEmpty ? '未填写' : '已填写',
                ),
              ],
            ),
          ),
          if (isEmby) ...[
            const SizedBox(height: 8),
            SettingsExpandableSection(
              title: '高级（可选）',
              subtitle: '手动粘贴 Access Token / API Key',
              expanded: _advancedTokenExpanded,
              onChanged: (expanded) {
                setState(() => _advancedTokenExpanded = expanded);
              },
              children: [
                SettingsTextInputField(
                  controller: _tokenController,
                  labelText: 'Access Token / API Key',
                  minLines: 1,
                  maxLines: 4,
                  alignLabelWithHint: true,
                  summaryBuilder: (value) => value.isEmpty ? '未填写' : '已填写',
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 12),
            Text(
              '可直接填写 WebDAV 地址、用户名和密码。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
          const SettingsSectionTitle(label: '选择分区'),
          if (_availableSections.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SettingsActionButton(
                    label: '全选',
                    icon: Icons.select_all_rounded,
                    onPressed: _selectAllSections,
                    variant: StarflowButtonVariant.ghost,
                  ),
                  SettingsActionButton(
                    label: '清空',
                    icon: Icons.clear_all_rounded,
                    onPressed: _clearAllSections,
                    variant: StarflowButtonVariant.ghost,
                  ),
                ],
              ),
            ),
          if (_availableSections.isNotEmpty)
            ..._availableSections.map(
              (section) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: StarflowCheckboxTile(
                  title: section.title,
                  value: _selectedSectionIds.contains(section.id),
                  onChanged: (checked) {
                    setState(() {
                      _didHydrateSectionSelection = true;
                      final nextSelection = {..._selectedSectionIds};
                      if (checked) {
                        nextSelection.add(section.id);
                      } else {
                        nextSelection.remove(section.id);
                      }
                      _selectedSectionIds = nextSelection;
                    });
                  },
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '未选择分区',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _connectionMessage,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (isEmby && _resolvedUserId.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    SelectableText(
                      'User ID: $_resolvedUserId',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SettingsToggleTile(
            title: '启用此媒体源',
            value: _enabled,
            onChanged: (value) => setState(() => _enabled = value),
          ),
          if (!isEmby) ...[
            const SizedBox(height: 12),
            SettingsToggleTile(
              title: '目录结构推断',
              value: _webDavStructureInferenceEnabled,
              onChanged: (value) {
                setState(() {
                  _webDavStructureInferenceEnabled = value;
                });
              },
            ),
            SettingsToggleTile(
              title: '本地刮削/NFO',
              value: _webDavSidecarScrapingEnabled,
              onChanged: (value) {
                setState(() {
                  _webDavSidecarScrapingEnabled = value;
                });
              },
            ),
            const SizedBox(height: 8),
            SettingsTextInputField(
              controller: _webDavExcludedKeywordsController,
              labelText: '过滤关键字',
              minLines: 2,
              maxLines: 5,
              hintText: '比如：sample、预告片',
              alignLabelWithHint: true,
              summaryBuilder: (value) {
                if (value.isEmpty) {
                  return '未填写';
                }
                final keywords = value
                    .split(RegExp(r'[\n,，;；]+'))
                    .map((item) => item.trim())
                    .where((item) => item.isNotEmpty)
                    .toList(growable: false);
                if (keywords.isEmpty) {
                  return '未填写';
                }
                return '已填写 ${keywords.length} 项';
              },
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '支持填写多个。每行一个，或用逗号分隔；命中任意关键字的路径都会被过滤。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
          if (isEmby) ...[
            const SizedBox(height: 28),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.start,
              children: [
                SettingsActionButton(
                  label: _isAuthenticating ? '登录中…' : '测试登录',
                  icon: Icons.login_rounded,
                  onPressed: _isAuthenticating ? null : _onTestEmbyLogin,
                ),
                SettingsActionButton(
                  label: _isLoadingSections ? '读取中…' : '选择分区',
                  icon: Icons.folder_open_rounded,
                  onPressed: _isLoadingSections ||
                          _endpointController.text.trim().isEmpty ||
                          _tokenController.text.trim().isEmpty ||
                          _resolvedUserId.trim().isEmpty
                      ? null
                      : _onFetchEmbySections,
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
                  SettingsActionButton(
                    label: _isTestingWebDav ? '测试中…' : '测试连接',
                    icon: Icons.cloud_done_outlined,
                    onPressed: _isTestingWebDav ||
                            _endpointController.text.trim().isEmpty
                        ? null
                        : _onTestWebDavConnection,
                  ),
                  SettingsActionButton(
                    label: '选择路径',
                    icon: Icons.folder_open_rounded,
                    onPressed: _endpointController.text.trim().isEmpty
                        ? null
                        : _pickWebDavPath,
                  ),
                  SettingsActionButton(
                    label: _isLoadingSections ? '读取中…' : '选择分区',
                    icon: Icons.view_list_rounded,
                    onPressed: _isLoadingSections ||
                            _endpointController.text.trim().isEmpty
                        ? null
                        : _onFetchNasSections,
                  ),
                ],
              ),
            ),
          ],
          if (widget.initial != null) ...[
            const SizedBox(height: 28),
            Align(
              alignment: Alignment.centerLeft,
              child: SettingsActionButton(
                label: '删除此媒体源',
                icon: Icons.delete_outline_rounded,
                onPressed: _confirmDeleteMediaSource,
                variant: StarflowButtonVariant.danger,
              ),
            ),
          ],
        ],
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
      child: SettingsPageScaffold(
        onBack: () {
          _skipAutoSaveOnPop = true;
          Navigator.of(context).pop(_currentPath);
        },
        trailing: SettingsToolbarButton(
          label: '选这里',
          icon: Icons.check_rounded,
          onPressed: () {
            _skipAutoSaveOnPop = true;
            Navigator.of(context).pop(_currentPath);
          },
        ),
        children: [
          const SettingsSectionTitle(label: '当前路径'),
          SelectableText(
            _pathLabel(_currentPath),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (parentPath != null) ...[
            const SizedBox(height: 16),
            SettingsActionButton(
              label: '返回上一级目录',
              icon: Icons.arrow_upward_rounded,
              onPressed: () {
                setState(() {
                  _currentPath = parentPath;
                });
              },
            ),
          ],
          const SettingsSectionTitle(label: '子文件夹'),
          FutureBuilder<List<MediaCollection>>(
            future: _loadFolders(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('读取路径失败：${snapshot.error}'),
                );
              }
              final folders = snapshot.data ?? const <MediaCollection>[];
              if (folders.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('当前路径下没有子文件夹，可以直接选择这里作为根路径。'),
                );
              }
              return Column(
                children: [
                  for (final folder in folders)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SettingsSelectionTile(
                        title: folder.title,
                        subtitle: folder.id,
                        value: '进入',
                        leading: const Icon(Icons.folder_open_rounded),
                        onPressed: () {
                          setState(() {
                            _currentPath = folder.id;
                          });
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
