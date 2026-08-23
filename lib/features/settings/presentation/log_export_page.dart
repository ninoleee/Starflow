import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/section_panel.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/settings/data/log_export_service.dart';
import 'package:starflow/features/settings/presentation/widgets/lan_transfer_qr_address_card.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';

class LogExportPage extends ConsumerStatefulWidget {
  const LogExportPage({super.key});

  @override
  ConsumerState<LogExportPage> createState() => _LogExportPageState();
}

class _LogExportPageState extends ConsumerState<LogExportPage> {
  late final TextEditingController _pathController;
  bool _isExporting = false;
  bool _isStartingTelevisionExport = false;

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController();
    unawaited(_prefillSuggestedPath());
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _prefillSuggestedPath() async {
    final service = ref.read(logExportServiceProvider);
    if (!service.isSupported || service.supportsSystemExport) {
      return;
    }
    try {
      final path = await service.buildSuggestedExportPath();
      if (mounted) {
        _pathController.text = path;
      }
    } catch (_) {
      // The export action will surface the platform-specific error if needed.
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(logExportServiceProvider);
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;

    return SettingsPageScaffold(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        SectionPanel(
          title: '导出日志',
          subtitle: '导出的文件会合并当前与上一份轮转日志，内容仍保持敏感信息脱敏。',
          child: service.isSupported
              ? isTelevision
                  ? _buildTelevisionContent()
                  : _buildStandardContent(service)
              : Text(service.unsupportedReason),
        ),
      ],
    );
  }

  Widget _buildStandardContent(LogExportService service) {
    final usesSystemExport = service.supportsSystemExport;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          usesSystemExport
              ? '点击导出后会打开系统文件导出器，可保存到“文件”、iCloud 或本机其他位置。'
              : '选择保存目录后会自动生成带时间的 .log 文件，也可以直接编辑完整导出路径。',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (!usesSystemExport) ...[
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _pathController,
                  decoration: const InputDecoration(
                    labelText: '导出路径',
                    hintText: '填写完整的 .log 文件路径',
                    prefixIcon: Icon(Icons.description_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              StarflowButton(
                label: '选择位置',
                icon: Icons.folder_open_rounded,
                onPressed: _isExporting ? null : _pickExportPath,
                variant: StarflowButtonVariant.secondary,
                compact: true,
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        SettingsActionButton(
          label: _isExporting
              ? usesSystemExport
                  ? '正在打开导出器…'
                  : '正在导出…'
              : '导出日志文件',
          icon: Icons.save_alt_rounded,
          onPressed: _isExporting ? null : _exportLogs,
          loading: _isExporting,
          focusId: 'settings:logging:export-file',
          compact: false,
        ),
      ],
    );
  }

  Widget _buildTelevisionContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '电视模式不会调用系统目录选择器。启动后会显示局域网地址，手机与电视连接同一网络，在手机浏览器中打开地址即可下载日志。',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        SettingsActionButton(
          label: _isStartingTelevisionExport ? '正在启动手机导出…' : '手机导出日志',
          icon: Icons.devices_rounded,
          onPressed: _isStartingTelevisionExport ? null : _openTelevisionExport,
          loading: _isStartingTelevisionExport,
          focusId: 'settings:logging:export-tv',
          compact: false,
        ),
      ],
    );
  }

  Future<void> _pickExportPath() async {
    try {
      final picked = await ref.read(logExportServiceProvider).pickExportPath(
            suggestedName: _defaultExportFileName(),
          );
      if (picked != null && mounted) {
        _pathController.text = picked;
      }
    } catch (error) {
      _showMessage('选择导出位置失败：$error');
    }
  }

  Future<void> _exportLogs() async {
    final service = ref.read(logExportServiceProvider);
    final targetPath = _pathController.text.trim();
    if (!service.supportsSystemExport && targetPath.isEmpty) {
      _showMessage('请先填写导出路径');
      return;
    }
    setState(() => _isExporting = true);
    try {
      final result = service.supportsSystemExport
          ? await service.exportLogsWithSystemPicker(
              suggestedName: _defaultExportFileName(),
            )
          : await service.exportLogs(targetPath: targetPath);
      if (!mounted) {
        return;
      }
      if (result == null) {
        _showMessage('已取消导出');
      } else if (service.supportsSystemExport) {
        _showMessage('日志已导出，可在“文件”中查看。');
      } else {
        _pathController.text = result.path;
        _showMessage('日志已导出到 ${result.path}');
      }
    } catch (error) {
      _showMessage('导出失败：$error');
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _openTelevisionExport() async {
    if (_isStartingTelevisionExport) {
      return;
    }
    setState(() => _isStartingTelevisionExport = true);
    LogLanExportSession? session;
    try {
      session =
          await ref.read(logExportServiceProvider).startTelevisionExport();
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => _LogLanExportDialog(session: session!),
      );
    } catch (error) {
      _showMessage('启动手机导出失败：$error');
    } finally {
      await session?.close();
      if (mounted) {
        setState(() => _isStartingTelevisionExport = false);
      }
    }
  }

  String _defaultExportFileName() {
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    return 'starflow-logs-$timestamp.log';
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

class _LogLanExportDialog extends StatefulWidget {
  const _LogLanExportDialog({required this.session});

  final LogLanExportSession session;

  @override
  State<_LogLanExportDialog> createState() => _LogLanExportDialogState();
}

class _LogLanExportDialogState extends State<_LogLanExportDialog> {
  late final StreamSubscription<LogLanExportEvent> _subscription;
  late final List<FocusNode> _urlFocusNodes;
  late final FocusNode _closeFocusNode;
  String _statusMessage = '服务已启动，等待手机下载日志。';
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    _urlFocusNodes = List<FocusNode>.generate(
      widget.session.urls.length,
      (index) => FocusNode(debugLabel: 'logging-lan-url-$index'),
    );
    _closeFocusNode = FocusNode(debugLabel: 'logging-lan-close');
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
    for (final focusNode in _urlFocusNodes) {
      focusNode.dispose();
    }
    _closeFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dialog = AlertDialog(
      title: const Text('手机导出日志'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          primary: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '请让手机和电视连接同一个局域网，然后扫描下面任意二维码；也可以在手机浏览器中输入对应地址。',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              Text(
                '访问码：${widget.session.accessCode}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '端口：${widget.session.port}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              for (var index = 0;
                  index < widget.session.urls.length;
                  index++) ...[
                LanTransferQrAddressCard(
                  url: widget.session.urls[index],
                  focusNode: _urlFocusNodes[index],
                  focusId: 'settings:logging:lan-url:$index',
                ),
                const SizedBox(height: 12),
              ],
              Text(
                '打开手机页面后点击“下载日志”。关闭此窗口会同时停止局域网服务。',
                style: theme.textTheme.bodyMedium?.copyWith(
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
                  style: theme.textTheme.bodyMedium?.copyWith(
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
      inputFocusNodes: const <FocusNode>[],
      contentFocusNodes: _urlFocusNodes,
      actionFocusNodes: <FocusNode>[_closeFocusNode],
      child: dialog,
    );
  }
}
