import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';
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
    final action = await showSettingsCloseConfirmDialog(context);
    if (action == SettingsCloseAction.discard) {
      await _discardAndClose();
    } else if (action == SettingsCloseAction.save) {
      await _saveDraft();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _skipAutoSaveOnPop) {
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
        children: [
          const SettingsSectionTitle(label: '账号'),
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
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                '推荐与「想看」等模块会携带此会话访问豆瓣。请勿分享 Cookie。',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
          const SizedBox(height: 8),
          StarflowToggleTile(
            title: '启用豆瓣模块',
            value: _enabled,
            onChanged: (value) => setState(() => _enabled = value),
          ),
        ],
      ),
    );
  }
}
