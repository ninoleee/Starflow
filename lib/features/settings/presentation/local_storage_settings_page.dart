import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/storage/local_storage_models.dart';
import 'package:starflow/core/storage/persistent_image_cache.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/core/widgets/section_panel.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

final localStorageSummariesProvider =
    FutureProvider.autoDispose<List<LocalStorageCacheSummary>>((ref) async {
  final repository = ref.read(localStorageCacheRepositoryProvider);
  final detailSummary = await repository.inspectDetailCache();
  final imageSummary = await persistentImageCache.inspect();
  return [
    detailSummary,
    imageSummary,
  ];
});

class LocalStorageSettingsPage extends ConsumerWidget {
  const LocalStorageSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summariesAsync = ref.watch(localStorageSummariesProvider);

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
                  height: MediaQuery.paddingOf(context).top + kToolbarHeight + 12,
                ),
                SectionPanel(
                  title: '本地存储',
                  child: summariesAsync.when(
                    data: (summaries) {
                      return Column(
                        children: [
                          for (var index = 0; index < summaries.length; index++)
                            Padding(
                              padding: EdgeInsets.only(
                                bottom: index == summaries.length - 1 ? 0 : 12,
                              ),
                              child: _LocalStorageTile(
                                summary: summaries[index],
                                onClear: () =>
                                    _clearCache(context, ref, summaries[index].type),
                              ),
                            ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => _clearAll(context, ref),
                              icon: const Icon(Icons.delete_sweep_rounded),
                              label: const Text('清空全部缓存'),
                            ),
                          ),
                        ],
                      );
                    },
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: LinearProgressIndicator(),
                    ),
                    error: (error, _) => Text('读取本地缓存失败：$error'),
                  ),
                ),
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

  Future<void> _clearCache(
    BuildContext context,
    WidgetRef ref,
    LocalStorageCacheType type,
  ) async {
    switch (type) {
      case LocalStorageCacheType.detailData:
        await ref.read(localStorageCacheRepositoryProvider).clearDetailCache();
        break;
      case LocalStorageCacheType.images:
        await persistentImageCache.clear();
        break;
    }
    ref.invalidate(localStorageSummariesProvider);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已清理 ${type.label}缓存')),
    );
  }

  Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
    await ref.read(localStorageCacheRepositoryProvider).clearDetailCache();
    await persistentImageCache.clear();
    ref.invalidate(localStorageSummariesProvider);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已清空全部本地缓存')),
    );
  }
}

class _LocalStorageTile extends StatelessWidget {
  const _LocalStorageTile({
    required this.summary,
    required this.onClear,
  });

  final LocalStorageCacheSummary summary;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(summary.type.label),
      subtitle: Text(
        '${summary.entryCount} 项 · ${_formatBytes(summary.totalBytes)}',
      ),
      trailing: TextButton(
        onPressed: onClear,
        child: const Text('删除'),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes <= 0) {
    return '0 B';
  }
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  final digits = value >= 100 || unitIndex == 0
      ? 0
      : value >= 10
          ? 1
          : 2;
  return '${value.toStringAsFixed(digits)} ${units[unitIndex]}';
}
