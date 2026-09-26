import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/search/application/aliyun_to115_workflow.dart';
import 'package:starflow/features/search/data/aliyun_transfer_journal.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';

class AliyunTransferTasksPage extends ConsumerStatefulWidget {
  const AliyunTransferTasksPage({super.key});
  @override
  ConsumerState<AliyunTransferTasksPage> createState() => _TasksState();
}

class _TasksState extends ConsumerState<AliyunTransferTasksPage> {
  List<Map<String, dynamic>> _rows = [];
  String _message = '';
  bool _busy = false;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    unawaited(_reload());
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final rows = await ref.read(aliyunTransferJournalProvider).list();
      if (mounted) setState(() => _rows = rows);
    } catch (_) {
      if (mounted) setState(() => _message = '任务记录读取失败，未执行恢复');
    }
  }

  Future<void> _run(String id, {bool cleanup = false}) async {
    if (_busy) return;
    if (cleanup) {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('清理本次阿里副本？'),
                  content: const Text('重新核验 115 文件后，仅将任务记录中的阿里副本移入回收站。'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消')),
                    TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('核验并清理'))
                  ]));
      if (!mounted || confirmed != true) return;
    }
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      final result = await ref.read(aliyunTo115WorkflowProvider).resume(
          id, ref.read(appSettingsProvider).networkStorage,
          cleanupOnly: cleanup);
      if (mounted) setState(() => _message = result);
    } catch (error) {
      if (mounted) {
        setState(() => _message =
            error is QuarkSaveException ? error.message : '任务未完成，记录与副本保留');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _reload();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final workflow = ref.read(aliyunTo115WorkflowProvider);
    return SettingsPageScaffold(
        onBack: () => Navigator.pop(context),
        children: [
          Text('阿里转 115 任务', style: Theme.of(context).textTheme.headlineSmall),
          if (_message.isNotEmpty) Text(_message),
          if (workflow.isRunning)
            SettingsActionButton(
                label: '停止当前任务',
                icon: Icons.stop_rounded,
                onPressed: () {
                  workflow.requestStop();
                  setState(() => _message = '正在停止，等待当前请求确认');
                }),
          if (_rows.isEmpty) const Text('暂无任务'),
          for (final row in _rows) ...[
            const Divider(),
            Text('${row['saveName'] == '' ? row['id'] : row['saveName']}'),
            Text('${row['stage']} · ${row['updated'] ?? ''}'),
            Text('阿里暂存：/${row['stagingName'] ?? "待创建"}'),
            Text(
                '文件 ${(row['files'] as Map).length} · 已清理 ${(row['files'] as Map).values.where((v) => (v as Map)['cleaned'] == true).length}'),
            Wrap(spacing: 12, runSpacing: 12, children: [
              SettingsActionButton(
                  label: '继续任务',
                  icon: Icons.play_arrow_rounded,
                  onPressed:
                      _busy || workflow.isRunning || row['stage'] == '已完成'
                          ? null
                          : () => _run(row['id'] as String)),
              SettingsActionButton(
                  label: '核验并清理副本',
                  icon: Icons.cleaning_services_outlined,
                  onPressed: _busy || workflow.isRunning
                      ? null
                      : () => _run(row['id'] as String, cleanup: true)),
              SettingsActionButton(
                  label: '移除记录',
                  icon: Icons.delete_outline,
                  onPressed: _busy || workflow.isRunning
                      ? null
                      : () async {
                          final remove = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                      title: const Text('移除任务记录？'),
                                      content: const Text(
                                          '不会删除两端文件，但此记录对应的恢复和暂存清理入口将丢失。'),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: const Text('取消')),
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: const Text('移除'))
                                      ]));
                          if (!mounted || remove != true) return;
                          await ref
                              .read(aliyunTransferJournalProvider)
                              .remove(row['id'] as String);
                          await _reload();
                        }),
            ]),
          ],
        ]);
  }
}
