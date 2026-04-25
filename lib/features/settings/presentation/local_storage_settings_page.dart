import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/storage/local_storage_models.dart';
import 'package:starflow/core/storage/persistent_image_cache.dart';
import 'package:starflow/core/widgets/section_panel.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/library/data/nas_media_index_store.dart';
import 'package:starflow/features/playback/data/online_subtitle_repository.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
import 'package:starflow/features/search/data/search_preferences_repository.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

final localStorageSummariesProvider =
    FutureProvider.autoDispose<List<LocalStorageCacheSummary>>((ref) async {
  final indexStore = ref.read(nasMediaIndexStoreProvider);
  final repository = ref.read(localStorageCacheRepositoryProvider);
  final playbackMemoryRepository = ref.read(playbackMemoryRepositoryProvider);
  final searchPreferencesRepository =
      ref.read(searchPreferencesRepositoryProvider);
  final indexSummary = await indexStore.inspectSummary();
  final embyLibrarySummary = await repository.inspectEmbyLibraryCache();
  final detailSummary = await repository.inspectDetailCache();
  final playbackSummary = await playbackMemoryRepository.inspectSummary();
  final subtitleSummary =
      await ref.read(onlineSubtitleRepositoryProvider).inspectCacheSummary();
  final searchPreferencesSummary =
      await searchPreferencesRepository.inspectSummary();
  final imageSummary = await persistentImageCache.inspect();
  return [
    indexSummary,
    embyLibrarySummary,
    detailSummary,
    subtitleSummary,
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
  static const _groups = [
    _LocalStorageGroup(
      title: '媒体资料',
      subtitle: '和媒体库、Emby、详情页相关的索引、匹配结果与图片缓存。',
      types: [
        LocalStorageCacheType.nasMetadataIndex,
        LocalStorageCacheType.embyLibraryCache,
        LocalStorageCacheType.detailData,
        LocalStorageCacheType.subtitleCache,
        LocalStorageCacheType.images,
      ],
    ),
    _LocalStorageGroup(
      title: '使用记录',
      subtitle: '和播放、搜索习惯相关的历史记录与记忆。',
      showItems: false,
      types: [
        LocalStorageCacheType.playbackMemory,
        LocalStorageCacheType.televisionSearchPreferences,
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final summariesAsync = ref.watch(localStorageSummariesProvider);

    return SettingsPageScaffold(
      children: [
        SectionPanel(
          title: '本地存储',
          subtitle: '这里只展示可安全清理的本地索引、缓存和历史记录，不包含应用设置本身。',
          child: summariesAsync.when(
            data: (summaries) {
              final totalEntryCount = summaries.fold<int>(
                0,
                (sum, summary) => sum + summary.entryCount,
              );
              final totalBytes = summaries.fold<int>(
                0,
                (sum, summary) => sum + summary.totalBytes,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LocalStorageOverviewCard(
                    itemCount: summaries.length,
                    entryCount: totalEntryCount,
                    totalBytes: totalBytes,
                  ),
                  const SizedBox(height: 14),
                  for (var index = 0; index < _groups.length; index++) ...[
                    _LocalStorageGroupCard(
                      group: _groups[index],
                      summaries: _summariesForGroup(
                        summaries,
                        _groups[index],
                      ),
                      onClearGroup: () {
                        _clearGroup(context, ref, _groups[index]);
                      },
                      onClearItem: (type) {
                        _clearCache(context, ref, type);
                      },
                    ),
                    if (index != _groups.length - 1) const SizedBox(height: 14),
                  ],
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SettingsActionButton(
                      label: '清空全部（不含应用设置）',
                      icon: Icons.delete_sweep_rounded,
                      onPressed: () => _clearAll(context, ref),
                      variant: StarflowButtonVariant.danger,
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
    );
  }

  List<LocalStorageCacheSummary> _summariesForGroup(
    List<LocalStorageCacheSummary> summaries,
    _LocalStorageGroup group,
  ) {
    final summaryByType = {
      for (final summary in summaries) summary.type: summary,
    };
    return group.types
        .map((type) => summaryByType[type])
        .whereType<LocalStorageCacheSummary>()
        .toList(growable: false);
  }

  Future<void> _clearCache(
    BuildContext context,
    WidgetRef ref,
    LocalStorageCacheType type,
  ) {
    return _clearTypes(
      context,
      ref,
      [type],
      successMessage: '已清理 ${type.label}',
    );
  }

  Future<void> _clearGroup(
    BuildContext context,
    WidgetRef ref,
    _LocalStorageGroup group,
  ) {
    return _clearTypes(
      context,
      ref,
      group.types,
      successMessage: '已清理 ${group.title}',
    );
  }

  Future<void> _clearAll(BuildContext context, WidgetRef ref) {
    return _clearTypes(
      context,
      ref,
      LocalStorageCacheType.values,
      successMessage: '已清空全部本地数据',
    );
  }

  Future<void> _clearTypes(
    BuildContext context,
    WidgetRef ref,
    List<LocalStorageCacheType> types, {
    required String successMessage,
  }) async {
    for (final type in types.toSet()) {
      await _clearType(ref, type);
    }
    ref.invalidate(localStorageSummariesProvider);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(successMessage)),
    );
  }

  Future<void> _clearType(WidgetRef ref, LocalStorageCacheType type) async {
    switch (type) {
      case LocalStorageCacheType.nasMetadataIndex:
        await ref.read(nasMediaIndexStoreProvider).clearAll();
        break;
      case LocalStorageCacheType.embyLibraryCache:
        await ref
            .read(localStorageCacheRepositoryProvider)
            .clearAllEmbyLibrarySnapshots();
        break;
      case LocalStorageCacheType.detailData:
        await ref.read(localStorageCacheRepositoryProvider).clearDetailCache();
        break;
      case LocalStorageCacheType.playbackMemory:
        await ref.read(playbackMemoryRepositoryProvider).clearAll();
        break;
      case LocalStorageCacheType.subtitleCache:
        await ref.read(onlineSubtitleRepositoryProvider).clearCache();
        break;
      case LocalStorageCacheType.televisionSearchPreferences:
        await ref.read(searchPreferencesRepositoryProvider).clear();
        break;
      case LocalStorageCacheType.images:
        await persistentImageCache.clear();
        break;
    }
  }
}

class _LocalStorageOverviewCard extends StatelessWidget {
  const _LocalStorageOverviewCard({
    required this.itemCount,
    required this.entryCount,
    required this.totalBytes,
  });

  final int itemCount;
  final int entryCount;
  final int totalBytes;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '总览',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            '当前共 $itemCount 个可清理存储项，累计 $entryCount 项记录，约 ${_formatBytes(totalBytes)}。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _LocalStorageGroupCard extends StatelessWidget {
  const _LocalStorageGroupCard({
    required this.group,
    required this.summaries,
    required this.onClearGroup,
    required this.onClearItem,
  });

  final _LocalStorageGroup group;
  final List<LocalStorageCacheSummary> summaries;
  final VoidCallback onClearGroup;
  final ValueChanged<LocalStorageCacheType> onClearItem;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final totalEntryCount = summaries.fold<int>(
      0,
      (sum, summary) => sum + summary.entryCount,
    );
    final totalBytes = summaries.fold<int>(
      0,
      (sum, summary) => sum + summary.totalBytes,
    );
    final hasData = summaries.any(_hasSummaryData);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      group.subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${summaries.length} 个存储项 · $totalEntryCount 项记录 · ${_formatBytes(totalBytes)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              StarflowButton(
                label: '清理本组',
                onPressed: hasData ? onClearGroup : null,
                variant: StarflowButtonVariant.danger,
                compact: true,
              ),
            ],
          ),
          if (group.showItems) ...[
            const SizedBox(height: 14),
            for (var index = 0; index < summaries.length; index++) ...[
              _LocalStorageTile(
                summary: summaries[index],
                onClear: _hasSummaryData(summaries[index])
                    ? () => onClearItem(summaries[index].type)
                    : null,
              ),
              if (index != summaries.length - 1) const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }
}

class _LocalStorageTile extends StatelessWidget {
  const _LocalStorageTile({
    required this.summary,
    required this.onClear,
  });

  final LocalStorageCacheSummary summary;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return StarflowSelectionTile(
      title: summary.type.label,
      subtitle:
          '${summary.type.description}\n${summary.entryCount} 项 · ${_formatBytes(summary.totalBytes)}',
      onPressed: onClear,
      trailing: StarflowButton(
        label: onClear == null ? '已空' : '清理',
        onPressed: onClear,
        variant: StarflowButtonVariant.danger,
        compact: true,
      ),
    );
  }
}

class _LocalStorageGroup {
  const _LocalStorageGroup({
    required this.title,
    required this.subtitle,
    this.showItems = true,
    required this.types,
  });

  final String title;
  final String subtitle;
  final bool showItems;
  final List<LocalStorageCacheType> types;
}

bool _hasSummaryData(LocalStorageCacheSummary summary) {
  return summary.entryCount > 0 || summary.totalBytes > 0;
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
