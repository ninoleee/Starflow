import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/core/widgets/section_panel.dart';
import 'package:starflow/features/search/data/smart_strm_log_repository.dart';

class SmartStrmLogsPage extends ConsumerWidget {
  const SmartStrmLogsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(smartStrmWebhookLogsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppPageBackground(
        contentPadding: appPageContentPadding(context),
        child: Stack(
          children: [
            ListView(
              padding: EdgeInsets.zero,
              children: [
                SizedBox(
                  height:
                      MediaQuery.paddingOf(context).top + kToolbarHeight + 12,
                ),
                SectionPanel(
                  title: 'STRM 日志',
                  child: logsAsync.when(
                    data: (logs) {
                      if (logs.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('还没有 STRM 返回日志。'),
                        );
                      }
                      return Column(
                        children: [
                          for (var index = 0; index < logs.length; index++)
                            Padding(
                              padding: EdgeInsets.only(
                                bottom: index == logs.length - 1 ? 0 : 12,
                              ),
                              child: _LogTile(entry: logs[index]),
                            ),
                        ],
                      );
                    },
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: LinearProgressIndicator(),
                    ),
                    error: (error, _) => Text('读取 STRM 日志失败：$error'),
                  ),
                ),
              ],
            ),
            OverlayToolbar(
              onBack: () => Navigator.of(context).maybePop(),
              trailing: TextButton(
                onPressed: () async {
                  await ref.read(smartStrmWebhookLogRepositoryProvider).clear();
                  if (!context.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已清空 STRM 日志')),
                  );
                },
                child: const Text('清空'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});

  final SmartStrmWebhookLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor =
        entry.success ? theme.colorScheme.primary : theme.colorScheme.error;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _formatTime(entry.createdAt),
                  style: theme.textTheme.labelMedium,
                ),
              ),
              Text(
                entry.success ? '成功' : '失败',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            entry.taskName.isEmpty ? '未命名任务' : entry.taskName,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (entry.storagePath.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            SelectableText(
              '目录：${entry.storagePath}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (entry.webhookUrl.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            SelectableText(
              'Webhook：${entry.webhookUrl}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 8),
          Text(entry.message.trim().isEmpty ? '无返回信息' : entry.message),
          if (entry.httpStatusCode != null || entry.addedCount != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (entry.httpStatusCode != null)
                  _MetaChip(label: 'HTTP ${entry.httpStatusCode}'),
                if (entry.addedCount != null)
                  _MetaChip(label: '新增 ${entry.addedCount} 条'),
              ],
            ),
          ],
          if (entry.payloadText.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            SelectableText(
              entry.payloadText,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      ),
      child: Text(label, style: theme.textTheme.labelSmall),
    );
  }
}

String _formatTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}
