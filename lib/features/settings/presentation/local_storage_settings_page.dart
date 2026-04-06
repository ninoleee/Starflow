import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/storage/local_storage_models.dart';
import 'package:starflow/core/storage/persistent_image_cache.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/core/widgets/section_panel.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/library/data/nas_media_index_store.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
import 'package:starflow/features/search/data/search_preferences_repository.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

final localStorageSummariesProvider =
    FutureProvider.autoDispose<List<LocalStorageCacheSummary>>((ref) async {
  final indexStore = ref.read(nasMediaIndexStoreProvider);
  final repository = ref.read(localStorageCacheRepositoryProvider);
  final playbackMemoryRepository = ref.read(playbackMemoryRepositoryProvider);
  final searchPreferencesRepository =
      ref.read(searchPreferencesRepositoryProvider);
  final indexSummary = await indexStore.inspectSummary();
  final detailSummary = await repository.inspectDetailCache();
  final playbackSummary = await playbackMemoryRepository.inspectSummary();
  final searchPreferencesSummary =
      await searchPreferencesRepository.inspectSummary();
  final imageSummary = await persistentImageCache.inspect();
  return [
    indexSummary,
    detailSummary,
    playbackSummary,
    searchPreferencesSummary,
    imageSummary,
  ];
});

class LocalStorageSettingsPage extends ConsumerStatefulWidget {
  const LocalStorageSettingsPage({super.key});

  @override
  ConsumerState<LocalStorageSettingsPage> createState() =>
      _LocalStorageSettingsPageState();
}

class _LocalStorageSettingsPageState
    extends ConsumerState<LocalStorageSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final summariesAsync = ref.watch(localStorageSummariesProvider);
    final isTelevision = ref.watch(isTelevisionProvider).valueOrNull ?? false;

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
                  title: '本地存储',
                  subtitle: '这里只展示可安全清理的本地缓存、索引和历史记录，不包含应用设置本身。',
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
                                onClear: () => _clearCache(
                                    context, ref, summaries[index].type),
                              ),
                            ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: isTelevision
                                ? TvAdaptiveButton(
                                    label: '清空全部缓存',
                                    icon: Icons.delete_sweep_rounded,
                                    onPressed: () => _clearAll(context, ref),
                                    variant: TvButtonVariant.text,
                                  )
                                : StarflowButton(
                                    label: '清空全部缓存',
                                    icon: Icons.delete_sweep_rounded,
                                    onPressed: () => _clearAll(context, ref),
                                    variant: StarflowButtonVariant.danger,
                                    compact: true,
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

  Future<void> _clearCache(
    BuildContext context,
    WidgetRef ref,
    LocalStorageCacheType type,
  ) async {
    switch (type) {
      case LocalStorageCacheType.nasMetadataIndex:
        await ref.read(nasMediaIndexStoreProvider).clearAll();
        break;
      case LocalStorageCacheType.detailData:
        await ref.read(localStorageCacheRepositoryProvider).clearDetailCache();
        break;
      case LocalStorageCacheType.playbackMemory:
        await ref.read(playbackMemoryRepositoryProvider).clearAll();
        break;
      case LocalStorageCacheType.televisionSearchPreferences:
        await ref.read(searchPreferencesRepositoryProvider).clear();
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
    await ref.read(nasMediaIndexStoreProvider).clearAll();
    await ref.read(localStorageCacheRepositoryProvider).clearDetailCache();
    await ref.read(playbackMemoryRepositoryProvider).clearAll();
    await ref.read(searchPreferencesRepositoryProvider).clear();
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

class _LocalStorageTile extends ConsumerWidget {
  const _LocalStorageTile({
    required this.summary,
    required this.onClear,
  });

  final LocalStorageCacheSummary summary;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StarflowSelectionTile(
      title: summary.type.label,
      subtitle:
          '${summary.type.description} · ${summary.entryCount} 项 · ${_formatBytes(summary.totalBytes)}',
      onPressed: onClear,
      trailing: StarflowButton(
        label: '删除',
        onPressed: onClear,
        variant: StarflowButtonVariant.danger,
        compact: true,
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
