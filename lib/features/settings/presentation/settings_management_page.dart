import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/section_panel.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/data/settings_lan_transfer_service.dart';
import 'package:starflow/features/settings/data/settings_transfer_service.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';

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
  bool _isStartingLanTransfer = false;

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
    if (!service.isSupported || service.supportsSystemExport) {
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
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    final isIos = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final usesWebTransfer = kIsWeb && service.isSupported;
    final usesSystemExport =
        (usesWebTransfer || isIos) && service.supportsSystemExport;

    return SettingsPageScaffold(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        SectionPanel(
          title: '配置管理',
          child: service.isSupported
              ? isTelevision
                  ? _buildTelevisionTransferContent()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          usesWebTransfer
                              ? '浏览器会直接下载当前配置为 JSON，也可以选择本地 JSON 文件导入并覆盖当前配置。'
                              : usesSystemExport
                                  ? '可以把当前设置导出到本地 JSON 文件，也可以从本地 JSON 文件导入并覆盖当前配置。iOS 上导出会直接打开系统文件导出器，可保存到“文件 / iCloud / 本机其他位置”。'
                                  : '可以把当前设置导出到本地 JSON 文件，也可以从本地 JSON 文件导入并覆盖当前配置。导出时会先选择目录，再自动生成文件名。',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        if (!usesSystemExport) ...[
                          _PathEditor(
                            label: '导出路径',
                            controller: _exportPathController,
                            hintText: '例如：D:\\Backups\\starflow-settings.json',
                            icon: Icons.upload_file_rounded,
                            actionLabel: '选择位置',
                            onActionPressed: _pickExportPath,
                          ),
                          const SizedBox(height: 12),
                        ],
                        _ActionButton(
                          icon: Icons.save_alt_rounded,
                          label: _isExporting
                              ? usesWebTransfer
                                  ? '正在准备下载…'
                                  : usesSystemExport
                                      ? '正在打开导出器…'
                                      : '正在导出…'
                              : '导出当前配置',
                          onPressed: _isExporting || _isImporting
                              ? null
                              : () => _exportSettings(settings),
                        ),
                        const SizedBox(height: 24),
                        if (usesWebTransfer)
                          _ActionButton(
                            icon: Icons.restore_page_rounded,
                            label: _isImporting ? '正在导入…' : '选择 JSON 并导入',
                            onPressed: _isExporting || _isImporting
                                ? null
                                : _importSettingsFromPicker,
                          )
                        else ...[
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
                            icon: Icons.restore_page_rounded,
                            label: _isImporting ? '正在导入…' : '导入并覆盖配置',
                            onPressed: _isExporting || _isImporting
                                ? null
                                : _confirmImport,
                          ),
                        ],
                      ],
                    )
              : Text(service.unsupportedReason),
        ),
      ],
    );
  }

  Future<void> _exportSettings(AppSettings settings) async {
    final service = ref.read(settingsTransferServiceProvider);
    final isIos = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final usesWebTransfer = kIsWeb && service.isSupported;
    final usesSystemExport =
        (usesWebTransfer || isIos) && service.supportsSystemExport;
    final targetPath = _exportPathController.text.trim();
    if (!usesSystemExport && targetPath.isEmpty) {
      _showMessage('请先填写导出路径');
      return;
    }

    setState(() => _isExporting = true);
    try {
      final result = usesSystemExport
          ? await service.exportSettingsWithSystemPicker(
              settings: settings,
              suggestedName: _defaultExportFileName(),
            )
          : await service.exportSettings(
              settings: settings,
              targetPath: targetPath,
            );
      if (!mounted) {
        return;
      }
      if (result == null) {
        _showMessage('已取消导出');
        return;
      }
      if (!usesSystemExport) {
        _exportPathController.text = result.path;
        _showMessage('已导出到 ${result.path}');
        return;
      }
      if (kIsWeb) {
        _showMessage('浏览器已开始下载配置文件。');
      } else {
        _showMessage('配置已导出，可在“文件”中查看。');
      }
    } catch (error) {
      _showMessage('导出失败：$error');
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Widget _buildTelevisionTransferContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '电视模式下不再调用系统目录或文件选择器。点击下方按钮后，会在电视上弹出局域网地址；手机连接同一网络后，打开该地址即可下载当前配置，或上传新的 JSON 配置并直接覆盖本机设置。',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        _ActionButton(
          icon: Icons.devices_rounded,
          label: _isStartingLanTransfer ? '正在启动手机传输…' : '手机传输配置',
          onPressed: _isStartingLanTransfer ? null : _openTelevisionLanTransfer,
        ),
      ],
    );
  }

  Future<void> _openTelevisionLanTransfer() async {
    if (_isStartingLanTransfer) {
      return;
    }

    setState(() => _isStartingLanTransfer = true);
    SettingsLanTransferSession? session;
    StreamSubscription<SettingsLanTransferEvent>? eventsSubscription;
    try {
      session = await SettingsLanTransferService.start(
        loadSettings: () => ref.read(appSettingsProvider),
        importSettings: (settings) async {
          await ref
              .read(settingsControllerProvider.notifier)
              .replaceAllSettings(settings);
        },
      );
      eventsSubscription = session.events.listen((event) {
        if (!mounted) {
          return;
        }
        _showMessage(event.message);
      });

      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (context) {
          return _SettingsLanTransferDialog(session: session!);
        },
      );
    } catch (error) {
      _showMessage('启动手机传输失败：$error');
    } finally {
      await eventsSubscription?.cancel();
      await session?.close();
      if (mounted) {
        setState(() => _isStartingLanTransfer = false);
      }
    }
  }

  Future<void> _pickExportPath() async {
    final isTelevision = ref.read(isTelevisionProvider).value ?? false;
    if (isTelevision) {
      if (_exportPathController.text.trim().isEmpty) {
        final suggestedPath = await ref
            .read(settingsTransferServiceProvider)
            .buildSuggestedExportPath();
        if (mounted) {
          _exportPathController.text = suggestedPath;
        }
      }
      _showMessage('电视模式暂不打开系统目录选择器，请直接编辑导出路径。');
      return;
    }
    String? picked;
    try {
      picked = await ref.read(settingsTransferServiceProvider).pickExportPath(
            suggestedName: _defaultExportFileName(),
          );
    } catch (error) {
      _showMessage('选择导出位置失败：$error');
      return;
    }
    if (picked == null || !mounted) {
      return;
    }
    final pickedPath = picked;
    setState(() {
      _exportPathController.text = pickedPath;
    });
  }

  Future<void> _pickImportPath() async {
    final isTelevision = ref.read(isTelevisionProvider).value ?? false;
    if (isTelevision) {
      _showMessage('电视模式暂不打开系统文件选择器，请直接填写要导入的 JSON 文件路径。');
      return;
    }
    String? picked;
    try {
      picked = await ref.read(settingsTransferServiceProvider).pickImportPath();
    } catch (error) {
      _showMessage('选择导入文件失败：$error');
      return;
    }
    if (picked == null || !mounted) {
      return;
    }
    final pickedPath = picked;
    setState(() {
      _importPathController.text = pickedPath;
    });
  }

  Future<void> _importSettingsFromPicker() async {
    String? picked;
    try {
      picked = await ref.read(settingsTransferServiceProvider).pickImportPath();
    } catch (error) {
      _showMessage('选择导入文件失败：$error');
      return;
    }
    if (picked == null || !mounted) {
      return;
    }
    await _confirmImportWithPath(picked);
  }

  String _defaultExportFileName() {
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    return 'starflow-settings-$timestamp.json';
  }

  Future<void> _confirmImport() async {
    await _confirmImportWithPath(_importPathController.text.trim());
  }

  Future<void> _confirmImportWithPath(String sourcePath) async {
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
                StarflowButton(
                  label: '取消',
                  onPressed: () => Navigator.of(context).pop(false),
                  variant: StarflowButtonVariant.ghost,
                  compact: true,
                ),
                StarflowButton(
                  label: '继续导入',
                  onPressed: () => Navigator.of(context).pop(true),
                  compact: true,
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

class _SettingsLanTransferDialog extends StatefulWidget {
  const _SettingsLanTransferDialog({
    required this.session,
  });

  final SettingsLanTransferSession session;

  @override
  State<_SettingsLanTransferDialog> createState() =>
      _SettingsLanTransferDialogState();
}

class _SettingsLanTransferDialogState
    extends State<_SettingsLanTransferDialog> {
  late final StreamSubscription<SettingsLanTransferEvent> _subscription;
  late final FocusNode _closeFocusNode;
  String _statusMessage = '服务已启动，手机访问下方地址后即可上传或下载配置。';
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    _closeFocusNode = FocusNode(debugLabel: 'settings-lan-transfer-close');
    _subscription = widget.session.events.listen((event) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = event.message;
        _statusIsError = event.isError;
      });
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    _closeFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dialog = AlertDialog(
      title: const Text('手机传输配置'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '请让手机和电视连接同一个局域网，然后在手机浏览器中打开下面任意地址。',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              Text(
                '访问码：${widget.session.accessCode}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                '端口：${widget.session.port}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 14),
              for (final url in widget.session.urls) ...[
                SelectableText(
                  url,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 8),
              Text(
                '手机页面里可以直接下载当前配置，或上传新的 JSON 配置。上传成功后，电视端会立即替换并生效。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _statusIsError
                      ? colorScheme.errorContainer
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _statusMessage,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _statusIsError
                            ? colorScheme.onErrorContainer
                            : colorScheme.onSurface,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        StarflowButton(
          label: '关闭服务',
          focusNode: _closeFocusNode,
          onPressed: () => Navigator.of(context).pop(),
          compact: true,
        ),
      ],
    );

    return wrapTelevisionDialogBackHandling(
      enabled: true,
      dialogContext: context,
      inputFocusNodes: const [],
      contentFocusNodes: const [],
      actionFocusNodes: [_closeFocusNode],
      child: dialog,
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
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    if (isTelevision) {
      return SettingsSelectionTile(
        title: label,
        value: controller.text.trim().isEmpty ? '未填写' : controller.text.trim(),
        onPressed: () => _openActionDialog(context, isTelevision),
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
        StarflowButton(
          label: actionLabel,
          icon: icon,
          onPressed: onActionPressed,
          variant: StarflowButtonVariant.secondary,
          compact: true,
        ),
      ],
    );
  }

  Future<void> _openActionDialog(
    BuildContext context,
    bool isTelevision,
  ) async {
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
    await _openEditDialog(context, isTelevision);
  }

  Future<void> _openEditDialog(
    BuildContext context,
    bool isTelevision,
  ) async {
    final dialogController = TextEditingController(text: controller.text);
    final inputFocusNode = FocusNode(debugLabel: 'settings-path-dialog-field');
    final cancelFocusNode =
        FocusNode(debugLabel: 'settings-path-dialog-cancel');
    final confirmFocusNode =
        FocusNode(debugLabel: 'settings-path-dialog-confirm');
    try {
      final selection = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          final dialog = AlertDialog(
            title: Text(label),
            content: wrapTelevisionDialogFieldTraversal(
              enabled: isTelevision,
              child: TextField(
                controller: dialogController,
                focusNode: inputFocusNode,
                autofocus: true,
                maxLines: 3,
                decoration: InputDecoration(hintText: hintText),
              ),
            ),
            actions: [
              StarflowButton(
                label: '取消',
                focusNode: cancelFocusNode,
                onPressed: () => Navigator.of(dialogContext).pop(),
                variant: StarflowButtonVariant.ghost,
                compact: true,
              ),
              StarflowButton(
                label: '确定',
                focusNode: confirmFocusNode,
                onPressed: () =>
                    Navigator.of(dialogContext).pop(dialogController.text),
                compact: true,
              ),
            ],
          );
          return wrapTelevisionDialogBackHandling(
            enabled: isTelevision,
            dialogContext: dialogContext,
            inputFocusNodes: [inputFocusNode],
            contentFocusNodes: [inputFocusNode],
            actionFocusNodes: [confirmFocusNode, cancelFocusNode],
            child: dialog,
          );
        },
      );
      if (selection == null) {
        return;
      }
      controller.text = selection.trim();
    } finally {
      dialogController.dispose();
      inputFocusNode.dispose();
      cancelFocusNode.dispose();
      confirmFocusNode.dispose();
    }
  }
}

enum _PathEditorAction {
  pick,
  manualEdit,
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SettingsActionButton(
      label: label,
      icon: icon,
      onPressed: onPressed,
    );
  }
}
