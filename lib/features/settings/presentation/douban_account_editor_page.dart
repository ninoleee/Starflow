import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

/// 全屏编辑豆瓣账号（与媒体源 / 搜索服务编辑页一致）。
class DoubanAccountEditorPage extends ConsumerStatefulWidget {
  const DoubanAccountEditorPage({super.key, required this.initial});

  final DoubanAccountConfig initial;

  @override
  ConsumerState<DoubanAccountEditorPage> createState() =>
      _DoubanAccountEditorPageState();
}

class _DoubanAccountEditorPageState
    extends ConsumerState<DoubanAccountEditorPage> {
  late final TextEditingController _userIdController;
  late final TextEditingController _sessionController;
  late bool _enabled;
  bool _skipAutoSaveOnPop = false;

  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    _userIdController = TextEditingController(text: c.userId);
    _sessionController = TextEditingController(text: c.sessionCookie);
    _enabled = c.enabled;
  }

  @override
  void dispose() {
    _userIdController.dispose();
    _sessionController.dispose();
    super.dispose();
  }

  Future<void> _saveDraft({bool popAfterSave = true}) async {
    await ref.read(settingsControllerProvider.notifier).saveDoubanAccount(
          DoubanAccountConfig(
            enabled: _enabled,
            userId: _userIdController.text.trim(),
            sessionCookie: _sessionController.text.trim(),
          ),
        );
    if (popAfterSave && mounted) {
      _skipAutoSaveOnPop = true;
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope<void>(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop || _skipAutoSaveOnPop) {
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
                _SectionTitle(theme: theme, label: '账号'),
                TextField(
                  controller: _userIdController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Douban User ID',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _sessionController,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Cookie / Session',
                    alignLabelWithHint: true,
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
                      '推荐与「想看」等模块会携带此会话访问豆瓣。请勿分享 Cookie。',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用豆瓣模块'),
                  value: _enabled,
                  onChanged: (value) => setState(() => _enabled = value),
                ),
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
