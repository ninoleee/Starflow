import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_text_input_field.dart';
import '../data/live_backup.dart';
import '../data/live_backup_file.dart';
import '../data/live_repository.dart';

class LiveBackupDialog extends StatefulWidget {
  const LiveBackupDialog(
      {super.key, required this.repository, required this.isTelevision});
  final LiveRepository repository;
  final bool isTelevision;
  @override
  State<LiveBackupDialog> createState() => _LiveBackupDialogState();
}

class _LiveBackupDialogState extends State<LiveBackupDialog> {
  final _path = TextEditingController();
  Uint8List? _selected;
  bool _busy = false;
  String _status = '';
  LiveBackupImportMode _mode = LiveBackupImportMode.merge;
  @override
  void initState() {
    super.initState();
    _path.addListener(() => _selected = null);
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
      if (mounted) setState(() => _status = '操作失败，请检查文件路径、大小和备份格式；现有数据未被部分导入');
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
        if (await file.length() > liveBackupMaxBytes)
          throw const FormatException();
        final bytes = await file.readAsBytes();
        await compute(LiveBackup.decode, bytes);
        if (mounted)
          setState(() {
            _path.text = file.name;
            _selected = bytes;
          });
      });

  Future<void> _export() => _run(() async {
        final bytes = await widget.repository.exportBackup();
        if (!mounted) return;
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
        final bytes = _selected ?? await readLiveBackupFile(_path.text.trim());
        final backup = await compute(LiveBackup.decode, bytes);
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
                  title: const Text('确认恢复直播备份？'),
                  content: Text(
                      '${backup.stores['sources']!.length} 个订阅，${backup.stores['channels']!.length} 个频道。${_mode == LiveBackupImportMode.replace ? '替换将删除当前全部直播数据。' : '合并保留同 ID 的现有订阅和全部偏好，只添加新订阅。'}'),
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
        await widget.repository.importBackup(bytes, _mode);
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
                if (!kIsWeb)
                  SettingsTextInputField(
                      controller: _path, labelText: '直播备份 JSON 文件路径'),
                if (!widget.isTelevision)
                  StarflowButton(
                      label: '选择备份文件',
                      icon: Icons.file_open_outlined,
                      onPressed: _busy ? null : _pick),
                DropdownButtonFormField<LiveBackupImportMode>(
                  initialValue: _mode,
                  decoration: const InputDecoration(labelText: '恢复方式'),
                  items: const [
                    DropdownMenuItem(
                        value: LiveBackupImportMode.merge,
                        child: Text('合并：保留现有订阅')),
                    DropdownMenuItem(
                        value: LiveBackupImportMode.replace,
                        child: Text('替换：全部直播数据'))
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
              label: '导出',
              icon: Icons.download,
              onPressed: _busy ? null : _export),
          StarflowButton(
              label: '恢复',
              icon: Icons.restore,
              onPressed: _busy ? null : _import),
        ],
      );
}
