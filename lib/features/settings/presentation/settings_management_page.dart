import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/core/widgets/section_panel.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/data/settings_transfer_service.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

class SettingsManagementPage extends ConsumerStatefulWidget {
  const SettingsManagementPage({super.key});

  @override
  ConsumerState<SettingsManagementPage> createState() =>
      _SettingsManagementPageState();
}

class _SettingsManagementPageState
    extends ConsumerState<SettingsManagementPage> {
  late final TextEditingController _exportPathController;
  late final TextEditingController _importPathController;
  bool _isExporting = false;
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _exportPathController = TextEditingController();
    _importPathController = TextEditingController();
    unawaited(_prefillSuggestedExportPath());
  }

  @override
  void dispose() {
    _exportPathController.dispose();
    _importPathController.dispose();
    super.dispose();
  }

  Future<void> _prefillSuggestedExportPath() async {
    final service = ref.read(settingsTransferServiceProvider);
    if (!service.isSupported) {
      return;
    }
    final suggestedPath = await service.buildSuggestedExportPath();
    if (!mounted) {
      return;
    }
    _exportPathController.text = suggestedPath;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final service = ref.watch(settingsTransferServiceProvider);
    final isTelevision = ref.watch(isTelevisionProvider).valueOrNull ?? false;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppPageBackground(
        contentPadding: appPageContentPadding(context),
        child: Stack(
          children: [
            ListView(
              padding: EdgeInsets.zero,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                SizedBox(
                  height:
                      MediaQuery.paddingOf(context).top + kToolbarHeight + 12,
                ),
                SectionPanel(
                  title: '配置管理',
                  child: service.isSupported
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '可以把当前设置导出到本地 JSON 文件，也可以从本地 JSON 文件导入并覆盖当前配置。导出时会先选择目录，再自动生成文件名。',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 16),
                            _PathEditor(
                              label: '导出路径',
                              controller: _exportPathController,
                              hintText:
                                  '例如：D:\\Backups\\starflow-settings.json',
                              icon: Icons.upload_file_rounded,
                              actionLabel: '选择位置',
                              onActionPressed: _pickExportPath,
                            ),
                            const SizedBox(height: 12),
                            _ActionButton(
                              isTelevision: isTelevision,
                              icon: Icons.save_alt_rounded,
                              label: _isExporting ? '正在导出…' : '导出当前配置',
                              onPressed: _isExporting || _isImporting
                                  ? null
                                  : () => _exportSettings(settings),
                            ),
                            const SizedBox(height: 24),
                            _PathEditor(
                              label: '导入路径',
                              controller: _importPathController,
                              hintText: '填写要导入的 JSON 文件路径',
                              icon: Icons.download_rounded,
                              actionLabel: '选择文件',
                              onActionPressed: _pickImportPath,
                            ),
                            const SizedBox(height: 12),
                            _ActionButton(
                              isTelevision: isTelevision,
                              icon: Icons.restore_page_rounded,
                              label: _isImporting ? '正在导入…' : '导入并覆盖配置',
                              onPressed: _isExporting || _isImporting
                                  ? null
                                  : _confirmImport,
                            ),
                          ],
                        )
                      : Text(service.unsupportedReason),
                ),
                const SizedBox(height: kBottomReservedSpacing),
              ],
            ),
            OverlayToolbar(
              onBack: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportSettings(AppSettings settings) async {
    final targetPath = _exportPathController.text.trim();
    if (targetPath.isEmpty) {
      _showMessage('请先填写导出路径');
      return;
    }

    setState(() => _isExporting = true);
    try {
      final result =
          await ref.read(settingsTransferServiceProvider).exportSettings(
                settings: settings,
                targetPath: targetPath,
              );
      if (!mounted) {
        return;
      }
      _exportPathController.text = result.path;
      _showMessage('已导出到 ${result.path}');
    } catch (error) {
      _showMessage('导出失败：$error');
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _pickExportPath() async {
    final picked =
        await ref.read(settingsTransferServiceProvider).pickExportPath(
              suggestedName: _defaultExportFileName(),
            );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _exportPathController.text = picked;
    });
  }

  Future<void> _pickImportPath() async {
    final picked =
        await ref.read(settingsTransferServiceProvider).pickImportPath();
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _importPathController.text = picked;
    });
  }

  String _defaultExportFileName() {
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    return 'starflow-settings-$timestamp.json';
  }

  Future<void> _confirmImport() async {
    final sourcePath = _importPathController.text.trim();
    if (sourcePath.isEmpty) {
      _showMessage('请先填写导入路径');
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('导入配置'),
              content: const Text('导入后会覆盖当前设置，是否继续？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('继续导入'),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!confirmed) {
      return;
    }

    setState(() => _isImporting = true);
    try {
      final imported = await ref
          .read(settingsTransferServiceProvider)
          .importSettings(sourcePath);
      await ref
          .read(settingsControllerProvider.notifier)
          .replaceAllSettings(imported);
      if (!mounted) {
        return;
      }
      _showMessage('配置已导入并生效');
    } catch (error) {
      _showMessage('导入失败：$error');
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _PathEditor extends ConsumerWidget {
  const _PathEditor({
    required this.label,
    required this.controller,
    required this.hintText,
    required this.icon,
    required this.actionLabel,
    required this.onActionPressed,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final String actionLabel;
  final Future<void> Function() onActionPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTelevision = ref.watch(isTelevisionProvider).valueOrNull ?? false;
    if (isTelevision) {
      return TvSelectionTile(
        title: label,
        value: controller.text.trim().isEmpty ? '未填写' : controller.text.trim(),
        onPressed: () => _openActionDialog(context),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: label,
              hintText: hintText,
              prefixIcon: Icon(icon),
            ),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          onPressed: onActionPressed,
          child: Text(actionLabel),
        ),
      ],
    );
  }

  Future<void> _openActionDialog(BuildContext context) async {
    final selection = await showDialog<_PathEditorAction>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: Text(label),
          children: [
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.of(context).pop(_PathEditorAction.pick),
              child: Text(actionLabel),
            ),
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.of(context).pop(_PathEditorAction.manualEdit),
              child: const Text('手动填写'),
            ),
          ],
        );
      },
    );
    if (selection == null) {
      return;
    }
    if (selection == _PathEditorAction.pick) {
      await onActionPressed();
      return;
    }
    if (!context.mounted) {
      return;
    }
    await _openEditDialog(context);
  }

  Future<void> _openEditDialog(BuildContext context) async {
    final dialogController = TextEditingController(text: controller.text);
    try {
      final selection = await showDialog<String>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(label),
            content: TextField(
              controller: dialogController,
              maxLines: 3,
              decoration: InputDecoration(hintText: hintText),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(dialogController.text),
                child: const Text('确定'),
              ),
            ],
          );
        },
      );
      if (selection == null) {
        return;
      }
      controller.text = selection.trim();
    } finally {
      dialogController.dispose();
    }
  }
}

enum _PathEditorAction {
  pick,
  manualEdit,
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.isTelevision,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final bool isTelevision;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (isTelevision) {
      return TvAdaptiveButton(
        label: label,
        icon: icon,
        onPressed: onPressed,
      );
    }

    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}
