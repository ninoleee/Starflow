import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_text_input_field.dart';

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

  bool _hasUnsavedChanges() {
    final draft = DoubanAccountConfig(
      enabled: _enabled,
      userId: _userIdController.text.trim(),
      sessionCookie: _sessionController.text.trim(),
    );
    return jsonEncode(draft.toJson()) != jsonEncode(widget.initial.toJson());
  }

  Future<void> _discardAndClose() async {
    _skipAutoSaveOnPop = true;
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleCloseRequest() async {
    if (_skipAutoSaveOnPop) {
      return;
    }
    if (!_hasUnsavedChanges()) {
      await _discardAndClose();
      return;
    }
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('保存修改？'),
        content: const Text('当前页面有未保存的修改，返回前要怎么处理？'),
        actions: [
          StarflowButton(
            label: '取消',
            onPressed: () => Navigator.of(dialogContext).pop('cancel'),
            variant: StarflowButtonVariant.ghost,
            compact: true,
          ),
          StarflowButton(
            label: '不保存',
            onPressed: () => Navigator.of(dialogContext).pop('discard'),
            variant: StarflowButtonVariant.secondary,
            compact: true,
          ),
          StarflowButton(
            label: '保存',
            onPressed: () => Navigator.of(dialogContext).pop('save'),
            compact: true,
          ),
        ],
      ),
    );
    if (action == 'discard') {
      await _discardAndClose();
    } else if (action == 'save') {
      await _saveDraft();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTelevision = ref.watch(isTelevisionProvider).valueOrNull ?? false;

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _skipAutoSaveOnPop) {
          return;
        }
        _handleCloseRequest();
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
                SettingsTextInputField(
                  controller: _userIdController,
                  labelText: 'Douban User ID',
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                SettingsTextInputField(
                  controller: _sessionController,
                  labelText: 'Cookie / Session',
                  minLines: 3,
                  maxLines: 8,
                  alignLabelWithHint: true,
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
                if (isTelevision)
                  TvSelectionTile(
                    title: '启用豆瓣模块',
                    value: _enabled ? '已开启' : '已关闭',
                    onPressed: () => setState(() => _enabled = !_enabled),
                  )
                else
                  StarflowToggleTile(
                    title: '启用豆瓣模块',
                    value: _enabled,
                    onChanged: (value) => setState(() => _enabled = value),
                  ),
                const SizedBox(height: kBottomReservedSpacing),
              ],
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: OverlayToolbar(
                onBack: _handleCloseRequest,
                trailing: isTelevision
                    ? Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: TvAdaptiveButton(
                          label: '保存',
                          icon: Icons.save_rounded,
                          onPressed: _saveDraft,
                          variant: TvButtonVariant.text,
                        ),
                      )
                    : StarflowButton(
                        label: '保存',
                        onPressed: _saveDraft,
                        variant: StarflowButtonVariant.ghost,
                        compact: true,
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
