import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
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
  late final TextEditingController _parserHintController;

  late SearchProviderKind _kind;
  late bool _enabled;
  late final String _providerId;
  late bool _advancedAuthExpanded;

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
    _parserHintController = TextEditingController(text: e?.parserHint ?? '');
    _kind = e?.kind ?? SearchProviderKind.indexer;
    _enabled = e?.enabled ?? true;
    _advancedAuthExpanded = _apiKeyController.text.trim().isNotEmpty ||
        _usernameController.text.trim().isNotEmpty;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _endpointController.dispose();
    _apiKeyController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _parserHintController.dispose();
    super.dispose();
  }

  void _onSave() {
    ref.read(settingsControllerProvider.notifier).saveSearchProvider(
          SearchProviderConfig(
            id: _providerId,
            name: _nameController.text.trim().isEmpty
                ? '未命名搜索服务'
                : _nameController.text.trim(),
            kind: _kind,
            endpoint: _endpointController.text.trim(),
            enabled: _enabled,
            apiKey: _apiKeyController.text.trim(),
            parserHint: _parserHintController.text.trim(),
            username: _usernameController.text.trim(),
            password: _passwordController.text.trim(),
          ),
        );
    Navigator.of(context).pop();
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

    return Scaffold(
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
                decoration: const InputDecoration(
                  labelText: 'Endpoint',
                  hintText: 'https://search.example.com',
                ),
              ),
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
              _SectionTitle(theme: theme, label: '其他'),
              TextField(
                controller: _parserHintController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '解析器提示',
                  hintText: '例如 pansou-api',
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
                  child: Text(
                    'PanSou 兼容接口建议将解析器提示填为 pansou-api。'
                    '若服务启用认证，可直接填写 JWT Token，'
                    '或填写用户名与密码由应用自动登录。',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
              const SizedBox(height: 8),
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
                onPressed: _onSave,
                child: const Text('保存'),
              ),
            ),
          ),
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
