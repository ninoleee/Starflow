import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/search/data/cloud_saver_api_client.dart';
import 'package:starflow/features/search/data/pansou_api_client.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_text_input_field.dart';

/// 全屏编辑搜索服务（与 [MediaSourceEditorPage] 同一交互模式）。
class SearchProviderEditorPage extends ConsumerStatefulWidget {
  const SearchProviderEditorPage({super.key, this.initial});

  final SearchProviderConfig? initial;

  @override
  ConsumerState<SearchProviderEditorPage> createState() =>
      _SearchProviderEditorPageState();
}

class _SearchProviderEditorPageState
    extends ConsumerState<SearchProviderEditorPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _endpointController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _blockedKeywordsController;
  late final TextEditingController _maxTitleLengthController;

  late SearchProviderKind _kind;
  late bool _enabled;
  late bool _strongMatchEnabled;
  late final String _providerId;
  late bool _advancedAuthExpanded;
  late bool _cloudTypesExpanded;
  late Set<SearchCloudType> _selectedCloudTypes;
  bool _didDelete = false;
  bool _skipAutoSaveOnPop = false;
  bool _isTestingConnection = false;
  bool? _connectionTestSucceeded;
  String _connectionTestMessage = '';

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _providerId =
        e?.id ?? 'search-provider-${DateTime.now().millisecondsSinceEpoch}';
    _nameController = TextEditingController(text: e?.name ?? '');
    _endpointController = TextEditingController(text: e?.endpoint ?? '');
    _apiKeyController = TextEditingController(text: e?.apiKey ?? '');
    _usernameController = TextEditingController(text: e?.username ?? '');
    _passwordController = TextEditingController(text: e?.password ?? '');
    _blockedKeywordsController = TextEditingController(
      text: (e?.blockedKeywords ?? const []).join(', '),
    );
    _maxTitleLengthController = TextEditingController(
      text: '${(e?.maxTitleLength ?? 50).clamp(1, 500)}',
    );
    _kind = e?.kind ?? SearchProviderKind.panSou;
    _enabled = e?.enabled ?? true;
    _strongMatchEnabled = e?.strongMatchEnabled ?? false;
    final configuredCloudTypes = (e?.allowedCloudTypes ?? const [])
        .map(SearchCloudTypeX.fromCode)
        .whereType<SearchCloudType>()
        .toSet();
    _selectedCloudTypes = configuredCloudTypes.isEmpty
        ? SearchCloudType.values.toSet()
        : configuredCloudTypes;
    _advancedAuthExpanded = _apiKeyController.text.trim().isNotEmpty ||
        _usernameController.text.trim().isNotEmpty;
    _cloudTypesExpanded = false;
    if (e == null) {
      _applyDefaultsForKind(_kind);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _endpointController.dispose();
    _apiKeyController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _blockedKeywordsController.dispose();
    _maxTitleLengthController.dispose();
    super.dispose();
  }

  bool _hasMeaningfulDraft() {
    return _nameController.text.trim().isNotEmpty ||
        _endpointController.text.trim().isNotEmpty ||
        _apiKeyController.text.trim().isNotEmpty ||
        _usernameController.text.trim().isNotEmpty ||
        _passwordController.text.trim().isNotEmpty ||
        _blockedKeywordsController.text.trim().isNotEmpty ||
        _strongMatchEnabled ||
        _maxTitleLengthController.text.trim() != '50' ||
        widget.initial != null;
  }

  int _resolveMaxTitleLength() {
    final parsed = int.tryParse(_maxTitleLengthController.text.trim()) ?? 50;
    return parsed.clamp(1, 500);
  }

  SearchProviderConfig _buildDraftConfig() {
    return SearchProviderConfig(
      id: _providerId,
      name: _nameController.text.trim().isEmpty
          ? _kind.defaultName
          : _nameController.text.trim(),
      kind: _kind,
      endpoint: _endpointController.text.trim(),
      enabled: _enabled,
      apiKey: _apiKeyController.text.trim(),
      parserHint: _kind.defaultParserHint,
      username: _usernameController.text.trim(),
      password: _passwordController.text.trim(),
      allowedCloudTypes:
          _selectedCloudTypes.length == SearchCloudType.values.length
              ? const []
              : _selectedCloudTypes
                  .map((item) => item.code)
                  .toList(growable: false),
      blockedKeywords: parseSearchBlockedKeywords(
        _blockedKeywordsController.text,
      ),
      strongMatchEnabled: _strongMatchEnabled,
      maxTitleLength: _resolveMaxTitleLength(),
    );
  }

  void _applyDefaultsForKind(SearchProviderKind kind) {
    _kind = kind;
    _nameController.text = kind.defaultName;
    _endpointController.text = kind.defaultEndpoint;
    _selectedCloudTypes = SearchCloudType.values.toSet();
    _blockedKeywordsController.clear();
    _strongMatchEnabled = false;
    _maxTitleLengthController.text = '50';
    _connectionTestSucceeded = null;
    _connectionTestMessage = '';
  }

  String _selectedCloudTypesLabel() {
    if (_selectedCloudTypes.isEmpty) {
      return '未选择';
    }
    if (_selectedCloudTypes.length == SearchCloudType.values.length) {
      return '全部网盘';
    }
    if (_selectedCloudTypes.length <= 2) {
      final ordered = SearchCloudType.values
          .where(_selectedCloudTypes.contains)
          .map((item) => item.label)
          .toList(growable: false);
      return ordered.join('、');
    }
    return '已选 ${_selectedCloudTypes.length} 个网盘';
  }

  Future<void> _openKindPicker() async {
    final selected = await showSettingsOptionDialog<SearchProviderKind>(
      context: context,
      title: '选择类型',
      options: SearchProviderKind.values,
      currentValue: _kind,
      labelBuilder: (item) => item.label,
    );
    if (selected == null) {
      return;
    }
    setState(() => _applyDefaultsForKind(selected));
  }

  Future<void> _saveDraft({bool popAfterSave = true}) async {
    if (_didDelete || !_hasMeaningfulDraft()) {
      if (popAfterSave && mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    await ref.read(settingsControllerProvider.notifier).saveSearchProvider(
          _buildDraftConfig(),
        );
    if (popAfterSave && mounted) {
      _skipAutoSaveOnPop = true;
      Navigator.of(context).pop();
    }
  }

  bool _hasUnsavedChanges() {
    if (_didDelete) {
      return false;
    }
    final initial = widget.initial;
    if (initial == null) {
      return _hasMeaningfulDraft();
    }
    return jsonEncode(_buildDraftConfig().toJson()) !=
        jsonEncode(initial.toJson());
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

  Future<void> _testConnection() async {
    FocusScope.of(context).unfocus();
    final draft = _buildDraftConfig();
    if (draft.endpoint.trim().isEmpty) {
      setState(() {
        _connectionTestSucceeded = false;
        _connectionTestMessage = '请先填写搜索服务地址';
      });
      return;
    }

    setState(() {
      _isTestingConnection = true;
      _connectionTestSucceeded = null;
      _connectionTestMessage = '';
    });

    try {
      late final String summary;
      if (draft.kind == SearchProviderKind.panSou) {
        final status = await ref
            .read(panSouApiClientProvider)
            .testConnection(provider: draft);
        summary = status.summary;
      } else {
        final status = await ref
            .read(cloudSaverApiClientProvider)
            .testConnection(provider: draft);
        summary = status.summary;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _connectionTestSucceeded = true;
        _connectionTestMessage = summary;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('连接成功 · $summary')),
      );
    } on PanSouApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _connectionTestSucceeded = false;
        _connectionTestMessage = error.message;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('连接失败 · ${error.message}')),
      );
    } on CloudSaverApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _connectionTestSucceeded = false;
        _connectionTestMessage = error.message;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('连接失败 · ${error.message}')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = '$error';
      setState(() {
        _connectionTestSucceeded = false;
        _connectionTestMessage = message;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('连接失败 · $message')),
      );
    } finally {
      if (mounted) {
        setState(() => _isTestingConnection = false);
      }
    }
  }

  Future<void> _confirmDeleteSearchProvider() async {
    final name = _nameController.text.trim().isEmpty
        ? '此搜索服务'
        : _nameController.text.trim();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除搜索服务'),
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
    await ref.read(settingsControllerProvider.notifier).removeSearchProvider(
          _providerId,
        );
    _didDelete = true;
    _skipAutoSaveOnPop = true;
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已删除搜索服务')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
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
          onPressed: _saveDraft,
        ),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          const SettingsSectionTitle(label: '基本信息'),
          ...buildSettingsTileGroup([
            SettingsTextInputField(
              controller: _nameController,
              labelText: '名称',
              textInputAction: TextInputAction.next,
            ),
            SettingsSelectionTile(
              title: '类型',
              value: _kind.label,
              onPressed: _openKindPicker,
            ),
          ], spacing: 12),
          const SettingsSectionTitle(label: '连接'),
          SettingsTextInputField(
            controller: _endpointController,
            labelText: 'Endpoint',
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            hintText: _kind.defaultEndpoint,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: SettingsActionButton(
              label: _isTestingConnection ? '测试中...' : '测试连接',
              icon: Icons.network_check_rounded,
              onPressed: _isTestingConnection ? null : _testConnection,
            ),
          ),
          if (_connectionTestMessage.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _connectionTestMessage,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _connectionTestSucceeded == false
                        ? Theme.of(context).colorScheme.error
                        : const Color(0xFF7F8FAE),
                  ),
            ),
          ],
          const SettingsSectionTitle(label: '认证（可选）'),
          SettingsExpandableSection(
            title: 'Token / 账号',
            subtitle: 'JWT、API Key，或用户名密码自动登录',
            expanded: _advancedAuthExpanded,
            onChanged: (expanded) {
              setState(() => _advancedAuthExpanded = expanded);
            },
            children: [
              SettingsTextInputField(
                controller: _apiKeyController,
                labelText: 'JWT Token / API Key',
                minLines: 1,
                maxLines: 4,
                alignLabelWithHint: true,
                summaryBuilder: (value) => value.isEmpty ? '未填写' : '已填写',
              ),
              const SizedBox(height: 12),
              AutofillGroup(
                child: Column(
                  children: [
                    SettingsTextInputField(
                      controller: _usernameController,
                      labelText: '登录用户名',
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                    ),
                    const SizedBox(height: 12),
                    SettingsTextInputField(
                      controller: _passwordController,
                      labelText: '登录密码',
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      summaryBuilder: (value) => value.isEmpty ? '未填写' : '已填写',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SettingsSectionTitle(label: '结果筛选'),
          SettingsExpandableSection(
            title: '网盘类型',
            subtitle: _selectedCloudTypesLabel(),
            expanded: _cloudTypesExpanded,
            onChanged: (expanded) {
              setState(() => _cloudTypesExpanded = expanded);
            },
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SettingsActionButton(
                    label: '全选',
                    icon: Icons.select_all_rounded,
                    onPressed: () {
                      setState(() {
                        _selectedCloudTypes = SearchCloudType.values.toSet();
                      });
                    },
                    variant: StarflowButtonVariant.ghost,
                  ),
                  SettingsActionButton(
                    label: '清空',
                    icon: Icons.clear_all_rounded,
                    onPressed: () {
                      setState(() {
                        _selectedCloudTypes = <SearchCloudType>{};
                      });
                    },
                    variant: StarflowButtonVariant.ghost,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...SearchCloudType.values.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: StarflowCheckboxTile(
                    title: item.label,
                    value: _selectedCloudTypes.contains(item),
                    onChanged: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedCloudTypes.add(item);
                        } else {
                          _selectedCloudTypes.remove(item);
                        }
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
          ...buildSettingsTileGroup([
            SettingsTextInputField(
              controller: _blockedKeywordsController,
              labelText: '过滤词',
              minLines: 1,
              maxLines: 3,
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SettingsToggleTile(
                  title: '强匹配',
                  value: _strongMatchEnabled,
                  onChanged: (value) {
                    setState(() => _strongMatchEnabled = value);
                  },
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '开启后，标题只要包含搜索词拆分后的词组，或中文搜索词中这些字的任意组合，就会保留。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                    ),
                  ),
                ),
              ],
            ),
            SettingsTextInputField(
              controller: _maxTitleLengthController,
              labelText: '标题长度上限',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              hintText: '50',
            ),
            SettingsToggleTile(
              title: '启用此搜索服务',
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
          ], spacing: 12),
          if (widget.initial != null) ...[
            const SizedBox(height: 28),
            Align(
              alignment: Alignment.centerLeft,
              child: SettingsActionButton(
                label: '删除此搜索服务',
                icon: Icons.delete_outline_rounded,
                onPressed: _confirmDeleteSearchProvider,
                variant: StarflowButtonVariant.danger,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
