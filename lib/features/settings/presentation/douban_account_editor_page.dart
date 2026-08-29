import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/presentation/settings_auto_save_coordinator.dart';
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
  final SettingsAutoSaveCoordinator _autoSave = SettingsAutoSaveCoordinator();

  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    _userIdController = TextEditingController(text: c.userId);
    _sessionController = TextEditingController(text: c.sessionCookie);
    _enabled = c.enabled;
    _userIdController.addListener(_scheduleAutoSave);
    _sessionController.addListener(_scheduleAutoSave);
    _autoSave.markCurrentAsSaved(_draftFingerprint(c));
  }

  @override
  void dispose() {
    _userIdController.removeListener(_scheduleAutoSave);
    _sessionController.removeListener(_scheduleAutoSave);
    _autoSave.dispose();
    _userIdController.dispose();
    _sessionController.dispose();
    super.dispose();
  }

  DoubanAccountConfig _buildDraft() {
    return DoubanAccountConfig(
      enabled: _enabled,
      userId: _userIdController.text.trim(),
      sessionCookie: _sessionController.text.trim(),
    );
  }

  String _draftFingerprint(DoubanAccountConfig draft) =>
      jsonEncode(draft.toJson());

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _scheduleAutoSave();
  }

  void _scheduleAutoSave() {
    if (!mounted) {
      return;
    }
    final draft = _buildDraft();
    final controller = ref.read(settingsControllerProvider.notifier);
    _autoSave.schedule(
      fingerprint: _draftFingerprint(draft),
      save: () => controller.saveDoubanAccount(draft),
    );
  }

  void _flushAutoSave() {
    if (!mounted) {
      return;
    }
    final draft = _buildDraft();
    final controller = ref.read(settingsControllerProvider.notifier);
    _autoSave.flush(
      fingerprint: _draftFingerprint(draft),
      save: () => controller.saveDoubanAccount(draft),
    );
  }

  void _closePage() {
    _flushAutoSave();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _flushAutoSave();
        }
      },
      child: SettingsPageScaffold(
        onBack: _closePage,
        children: [
          Text('豆瓣账号', style: Theme.of(context).textTheme.headlineSmall),
          const SettingsSectionTitle(label: '账号'),
          SettingsTextInputField(
            controller: _userIdController,
            labelText: 'Douban User ID',
            autofocus: true,
            focusId: 'douban-account:user-id',
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
