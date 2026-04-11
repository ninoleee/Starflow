import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';

class QuarkDirectoryManagerPage extends ConsumerStatefulWidget {
  const QuarkDirectoryManagerPage({
    super.key,
    required this.cookie,
    this.initialFid = '0',
    this.initialPath = '/',
  });

  final String cookie;
  final String initialFid;
  final String initialPath;

  @override
  ConsumerState<QuarkDirectoryManagerPage> createState() =>
      _QuarkDirectoryManagerPageState();
}

class _QuarkDirectoryManagerPageState
    extends ConsumerState<QuarkDirectoryManagerPage> {
  late List<QuarkDirectoryEntry> _breadcrumbs;
  bool _isLoading = true;
  bool _isDeleting = false;
  String? _errorMessage;
  List<QuarkFileEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    _breadcrumbs = [
      QuarkDirectoryEntry(
        fid: widget.initialFid.trim().isEmpty ? '0' : widget.initialFid.trim(),
        name: '当前目录',
        path:
            widget.initialPath.trim().isEmpty ? '/' : widget.initialPath.trim(),
      ),
    ];
    _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final current = _breadcrumbs.last;
      final entries = await ref.read(quarkSaveClientProvider).listEntries(
            cookie: widget.cookie,
            parentFid: current.fid,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _entries = entries;
      });
    } on QuarkSaveException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.message;
        _entries = const [];
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '$error';
        _entries = const [];
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _goToEntry(QuarkFileEntry entry) {
    final directory = QuarkDirectoryEntry.fromFileEntry(entry);
    if (directory == null) {
      return;
    }
    setState(() {
      _breadcrumbs = [..._breadcrumbs, directory];
    });
    _loadCurrent();
  }

  void _goBackTo(int index) {
    setState(() {
      _breadcrumbs = _breadcrumbs.take(index + 1).toList(growable: false);
    });
    _loadCurrent();
  }

  Future<void> _deleteEntry(QuarkFileEntry entry) async {
    final label = entry.isDirectory ? '文件夹' : '文件';
    final confirmed = await _confirmDelete(
      title: '删除$label',
      content: '将把“${entry.name}”移动到夸克回收站，是否继续？',
      confirmLabel: '确认删除',
    );
    if (!confirmed) {
      return;
    }
    await _performDelete(
      entries: [entry],
      successMessage: '已将$label移到夸克回收站',
    );
  }

  Future<void> _clearCurrentDirectory() async {
    if (_entries.isEmpty) {
      return;
    }
    final confirmed = await _confirmDelete(
      title: '清空当前目录',
      content:
          '将把当前目录下的 ${_entries.length} 个项目移动到夸克回收站，是否继续？',
      confirmLabel: '确认清空',
    );
    if (!confirmed) {
      return;
    }
    await _performDelete(
      entries: _entries,
      successMessage: '已将当前目录内容移到夸克回收站',
    );
  }

  Future<void> _performDelete({
    required List<QuarkFileEntry> entries,
    required String successMessage,
  }) async {
    setState(() => _isDeleting = true);
    try {
      await ref.read(quarkSaveClientProvider).deleteEntries(
            cookie: widget.cookie,
            fids: entries.map((item) => item.fid).toList(growable: false),
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
      await _loadCurrent();
    } on QuarkSaveException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：${error.message}')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }
  }

  Future<bool> _confirmDelete({
    required String title,
    required String content,
    required String confirmLabel,
  }) async {
    final isTelevision = ref.read(isTelevisionProvider).value ?? false;
    final cancelFocusNode =
        FocusNode(debugLabel: 'quark-delete-dialog-cancel');
    final confirmFocusNode =
        FocusNode(debugLabel: 'quark-delete-dialog-confirm');
    try {
      final result = await showDialog<bool>(
            context: context,
            builder: (dialogContext) {
              final dialog = AlertDialog(
                title: Text(title),
                content: Text(content),
                actions: [
                  StarflowButton(
                    label: '取消',
                    focusNode: cancelFocusNode,
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    variant: StarflowButtonVariant.ghost,
                    compact: true,
                  ),
                  StarflowButton(
                    label: confirmLabel,
                    focusNode: confirmFocusNode,
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    variant: StarflowButtonVariant.danger,
                    compact: true,
                  ),
                ],
              );
              return wrapTelevisionDialogBackHandling(
                enabled: isTelevision,
                dialogContext: dialogContext,
                inputFocusNodes: const [],
                contentFocusNodes: const [],
                actionFocusNodes: [confirmFocusNode, cancelFocusNode],
                child: dialog,
              );
            },
          ) ??
          false;
      return result;
    } finally {
      cancelFocusNode.dispose();
      confirmFocusNode.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final trailing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsToolbarButton(
          label: '刷新',
          icon: Icons.refresh_rounded,
          onPressed: _isLoading || _isDeleting ? null : _loadCurrent,
          loading: _isLoading,
        ),
        if (_entries.isNotEmpty)
          SettingsToolbarButton(
            label: '清空当前目录',
            icon: Icons.delete_sweep_rounded,
            onPressed: _isLoading || _isDeleting ? null : _clearCurrentDirectory,
            loading: _isDeleting,
          ),
      ],
    );

    return SettingsPageScaffold(
      trailing: trailing,
      children: [
        const Text(
          '夸克目录管理',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '这里只会操作当前夸克目录里的文件和文件夹。删除动作会移动到夸克回收站，不会直接做永久清除。',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var index = 0; index < _breadcrumbs.length; index++)
              StarflowChipButton(
                label: _breadcrumbs[index].path,
                selected: index == _breadcrumbs.length - 1,
                onPressed: index == _breadcrumbs.length - 1
                    ? null
                    : () => _goBackTo(index),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (_isLoading)
          const Center(child: CircularProgressIndicator())
        else if (_errorMessage != null) ...[
          Text(_errorMessage!),
          const SizedBox(height: 12),
          SettingsActionButton(
            label: '重试',
            icon: Icons.refresh_rounded,
            onPressed: _loadCurrent,
          ),
        ] else if (_entries.isEmpty)
          const Text('当前目录为空')
        else
          ..._entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _QuarkFileEntryTile(
                entry: entry,
                isBusy: _isDeleting,
                onOpen: entry.isDirectory ? () => _goToEntry(entry) : null,
                onDelete: _isDeleting ? null : () => _deleteEntry(entry),
              ),
            ),
          ),
      ],
    );
  }
}

class _QuarkFileEntryTile extends StatelessWidget {
  const _QuarkFileEntryTile({
    required this.entry,
    required this.onDelete,
    this.onOpen,
    this.isBusy = false,
  });

  final QuarkFileEntry entry;
  final VoidCallback? onOpen;
  final VoidCallback? onDelete;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = entry.isDirectory ? '文件夹' : '文件';
    final buttons = <Widget>[];
    if (entry.isDirectory) {
      buttons.add(
        StarflowButton(
          label: '进入',
          icon: Icons.chevron_right_rounded,
          onPressed: isBusy ? null : onOpen,
          variant: StarflowButtonVariant.secondary,
          compact: true,
        ),
      );
    }
    buttons.add(
      StarflowButton(
        label: '删除',
        icon: Icons.delete_outline_rounded,
        onPressed: isBusy ? null : onDelete,
        variant: StarflowButtonVariant.danger,
        compact: true,
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackVertically = constraints.maxWidth < 720;
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    entry.isDirectory
                        ? Icons.folder_outlined
                        : Icons.insert_drive_file_outlined,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      entry.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '$label · ${entry.path}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          );
          final actionRow = Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: buttons,
          );

          if (stackVertically) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                content,
                const SizedBox(height: 12),
                actionRow,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: content),
              const SizedBox(width: 12),
              actionRow,
            ],
          );
        },
      ),
    );
  }
}
