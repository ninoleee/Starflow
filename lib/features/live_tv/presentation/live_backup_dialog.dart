import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import '../data/live_backup.dart';
import '../data/live_backup_file.dart';
import '../data/live_repository.dart';
import '../data/live_playlist_transfer_service.dart';
import 'live_playlist_transfer_dialog.dart';
import 'live_widgets.dart';

class LiveBackupDialog extends ConsumerStatefulWidget {
  const LiveBackupDialog(
      {super.key, required this.repository, required this.isTelevision});
  final LiveRepository repository;
  final bool isTelevision;
  @override
  ConsumerState<LiveBackupDialog> createState() => _LiveBackupDialogState();
}

class _LiveBackupDialogState extends ConsumerState<LiveBackupDialog> {
  final _path = TextEditingController();
  Uint8List? _selected;
  bool _busy = false;
  String _status = '';
  LiveBackupImportMode _mode = LiveBackupImportMode.merge;
  @override
  void initState() {
    super.initState();
    _path.addListener(() => _selected = null);
    if (widget.isTelevision) return;
    defaultLiveBackupPath().then((value) {
      if (mounted && _path.text.isEmpty) _path.text = value;
    }).catchError((Object _) {});
  }

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '';
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(() => _status = widget.isTelevision
            ? '操作失败，请检查网络、大小和备份格式；现有数据未被部分导入'
            : '操作失败，请检查文件路径、大小和备份格式；现有数据未被部分导入');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick() => _run(() async {
        final file = await openFile(acceptedTypeGroups: const [
          XTypeGroup(
              label: '直播备份 JSON',
              extensions: ['json'],
              uniformTypeIdentifiers: ['public.json']),
        ]);
        if (file == null || !mounted) return;
        if (await file.length() > liveBackupMaxBytes) {
          throw const FormatException();
        }
        final bytes = await file.readAsBytes();
        await compute(LiveBackup.decode, bytes);
        if (mounted) {
          setState(() {
            _path.text = file.name;
            _selected = bytes;
          });
        }
      });

  Future<LivePlaylistTransferResult?> _transfer(LivePlaylistTransferMode mode,
      {Uint8List? bytes}) {
    final service = ref.read(livePlaylistTransferServiceProvider);
    return showDialog<LivePlaylistTransferResult>(
        context: context,
        builder: (_) => LivePlaylistTransferDialog(
            mode: mode,
            start: () => service.start(mode: mode, backupBytes: bytes)));
  }

  Future<void> _export() => _run(() async {
        final bytes = await widget.repository.exportBackup();
        if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
        if (widget.isTelevision) {
          final result = await _transfer(LivePlaylistTransferMode.backupExport,
              bytes: bytes);
          if (mounted && result is LiveBackupDownloaded) {
            setState(() => _status = '直播备份已发送，请在手机确认下载文件');
          }
          return;
        }
        if (kIsWeb) {
          await XFile.fromData(bytes,
                  mimeType: 'application/json', name: 'starflow-live-tv.json')
              .saveTo('starflow-live-tv.json');
        } else {
          await writeLiveBackupFile(_path.text.trim(), bytes);
        }
        if (mounted) setState(() => _status = '直播备份已导出');
      });

  Future<void> _import() => _run(() async {
        final mode = _mode;
        final Uint8List bytes;
        if (widget.isTelevision) {
          final result = await _transfer(LivePlaylistTransferMode.backupImport);
          if (!mounted || result is! LivePlaylistUpload) return;
          bytes = result.bytes;
        } else {
          bytes = _selected ?? await readLiveBackupFile(_path.text.trim());
        }
        final backup = await compute(LiveBackup.decode, bytes);
        if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
        final confirmed = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
                  title: const Text('确认恢复直播备份？'),
                  content: Text(
                      '${backup.stores['sources']!.length} 个订阅，${backup.stores['channels']!.length} 个频道。${mode == LiveBackupImportMode.replace ? '替换将删除当前全部直播数据。' : '合并保留同 ID 的现有订阅和全部偏好，只添加新订阅。'}'),
                  actions: [
                    StarflowButton(
                        label: '取消',
                        autofocus: true,
                        onPressed: () => Navigator.pop(c, false)),
                    StarflowButton(
                        label: '恢复', onPressed: () => Navigator.pop(c, true)),
                  ],
                ));
        if (confirmed != true || !mounted) return;
        await widget.repository.importBackup(bytes, mode);
        if (mounted) setState(() => _status = '直播备份已恢复');
      });

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('直播备份与恢复'),
        content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
                child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    '备份含订阅、频道、收藏、隐藏、排序、映射、线路偏好和节目单。地址与媒体请求头可能含凭据；文件未加密。'),
                const SizedBox(height: 16),
                if (!kIsWeb && !widget.isTelevision)
                  TextField(
                      controller: _path,
                      enabled: !_busy,
                      decoration:
                          const InputDecoration(labelText: '直播备份 JSON 文件路径')),
                if (!widget.isTelevision)
                  StarflowButton(
                      label: '选择备份文件',
                      icon: Icons.file_open_outlined,
                      onPressed: _busy ? null : _pick),
                DropdownButtonFormField<LiveBackupImportMode>(
                  initialValue: _mode,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '恢复方式'),
                  items: [
                    DropdownMenuItem(
                        value: LiveBackupImportMode.merge,
                        child: LiveSelectionLabel(
                            label: '合并：保留现有订阅',
                            selected: _mode == LiveBackupImportMode.merge,
                            enabled: !_busy)),
                    DropdownMenuItem(
                        value: LiveBackupImportMode.replace,
                        child: LiveSelectionLabel(
                            label: '替换：全部直播数据',
                            selected: _mode == LiveBackupImportMode.replace,
                            enabled: !_busy))
                  ],
                  onChanged: _busy ? null : (v) => setState(() => _mode = v!),
                ),
                if (_status.isNotEmpty) Text(_status),
              ],
            ))),
        actions: [
          StarflowButton(
              label: '关闭',
              onPressed: _busy ? null : () => Navigator.pop(context)),
          StarflowButton(
              label: widget.isTelevision ? '手机备份' : '导出',
              icon:
                  widget.isTelevision ? Icons.qr_code_scanner : Icons.download,
              onPressed: _busy ? null : _export),
          StarflowButton(
              label: widget.isTelevision ? '手机恢复' : '恢复',
              icon: widget.isTelevision ? Icons.qr_code_scanner : Icons.restore,
              onPressed: _busy ? null : _import),
        ],
      );
}
