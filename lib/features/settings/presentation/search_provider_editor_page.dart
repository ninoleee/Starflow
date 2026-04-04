import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/features/search/data/cloud_saver_api_client.dart';
import 'package:starflow/features/search/data/pansou_api_client.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

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

  late SearchProviderKind _kind;
  late bool _enabled;
  late final String _providerId;
  late bool _advancedAuthExpanded;
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
    _kind = e?.kind ?? SearchProviderKind.panSou;
    _enabled = e?.enabled ?? true;
    final configuredCloudTypes = (e?.allowedCloudTypes ?? const [])
        .map(SearchCloudTypeX.fromCode)
        .whereType<SearchCloudType>()
        .toSet();
    _selectedCloudTypes = configuredCloudTypes.isEmpty
        ? SearchCloudType.values.toSet()
        : configuredCloudTypes;
    _advancedAuthExpanded = _apiKeyController.text.trim().isNotEmpty ||
        _usernameController.text.trim().isNotEmpty;
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
    super.dispose();
  }

  bool _hasMeaningfulDraft() {
    return _nameController.text.trim().isNotEmpty ||
        _endpointController.text.trim().isNotEmpty ||
        _apiKeyController.text.trim().isNotEmpty ||
        _usernameController.text.trim().isNotEmpty ||
        _passwordController.text.trim().isNotEmpty ||
        _blockedKeywordsController.text.trim().isNotEmpty ||
        widget.initial != null;
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
    );
  }

  void _applyDefaultsForKind(SearchProviderKind kind) {
    _kind = kind;
    _nameController.text = kind.defaultName;
    _endpointController.text = kind.defaultEndpoint;
    _selectedCloudTypes = SearchCloudType.values.toSet();
    _blockedKeywordsController.clear();
    _connectionTestSucceeded = null;
    _connectionTestMessage = '';
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
    final theme = Theme.of(context);

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
                DropdownButtonFormField<SearchProviderKind>(
                  key: ValueKey(_kind),
                  initialValue: _kind,
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
                      setState(() => _applyDefaultsForKind(value));
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
                    labelText: 'Endpoint',
                    hintText: _kind.defaultEndpoint,
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _isTestingConnection ? null : _testConnection,
                    icon: _isTestingConnection
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check_rounded),
                    label: Text(
                      _isTestingConnection ? '测试中...' : '测试连接',
                    ),
                  ),
                ),
                if (_connectionTestMessage.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _connectionTestMessage,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _connectionTestSucceeded == false
                          ? theme.colorScheme.error
                          : const Color(0xFF7F8FAE),
                    ),
                  ),
                ],
                _SectionTitle(theme: theme, label: '认证（可选）'),
                ExpansionTile(
                  initiallyExpanded: _advancedAuthExpanded,
                  onExpansionChanged: (expanded) {
                    setState(() => _advancedAuthExpanded = expanded);
                  },
                  title: Text(
                    'Token / 账号',
                    style: theme.textTheme.titleSmall,
                  ),
                  subtitle: Text(
                    'JWT、API Key，或用户名密码自动登录',
                    style: theme.textTheme.bodySmall,
                  ),
                  children: [
                    TextField(
                      controller: _apiKeyController,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'JWT Token / API Key',
                        alignLabelWithHint: true,
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
                            decoration: const InputDecoration(
                              labelText: '登录用户名',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _passwordController,
                            obscureText: true,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            decoration: const InputDecoration(
                              labelText: '登录密码',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
                _SectionTitle(theme: theme, label: '结果筛选'),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: SearchCloudType.values
                      .map(
                        (item) => FilterChip(
                          label: Text(item.label),
                          selected: _selectedCloudTypes.contains(item),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedCloudTypes.add(item);
                              } else {
                                _selectedCloudTypes.remove(item);
                              }
                            });
                          },
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _blockedKeywordsController,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '过滤词',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用此搜索服务'),
                  value: _enabled,
                  onChanged: (value) => setState(() => _enabled = value),
                ),
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
                        '删除此搜索服务',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      onPressed: _confirmDeleteSearchProvider,
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
                  onPressed: _saveDraft,
                  child: const Text('保存'),
                ),
              ),
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
