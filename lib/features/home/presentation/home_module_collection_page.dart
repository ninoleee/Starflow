import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/core/widgets/media_poster_tile.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/discovery/data/mock_discovery_repository.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

class HomeModuleCollectionPage extends ConsumerStatefulWidget {
  const HomeModuleCollectionPage({super.key, required this.module});

  final HomeModuleConfig module;

  @override
  ConsumerState<HomeModuleCollectionPage> createState() =>
      _HomeModuleCollectionPageState();
}

class _HomeModuleCollectionPageState
    extends ConsumerState<HomeModuleCollectionPage> {
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(_homeModuleEntriesProvider(widget.module));

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          AppPageBackground(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(_homeModuleEntriesProvider(widget.module));
                await ref
                    .read(_homeModuleEntriesProvider(widget.module).future);
              },
              child: ListView(
                padding: overlayToolbarPagePadding(context),
                children: [
                  Text(
                    widget.module.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _moduleSubtitle(widget.module),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF90A0BD),
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 20),
                  entriesAsync.when(
                    data: (entries) => _DoubanPagedGrid(
                      entries: entries,
                      currentPage: _currentPage,
                      onPageChanged: (page) {
                        setState(() {
                          _currentPage = page;
                        });
                      },
                    ),
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, stackTrace) => Text('加载失败：$error'),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: OverlayToolbar(
              onBack: () => context.pop(),
            ),
          ),
        ],
      ),
    );
  }
}

final _homeModuleEntriesProvider =
    FutureProvider.family<List<DoubanEntry>, HomeModuleConfig>((ref, module) {
  return ref.read(discoveryRepositoryProvider).fetchEntries(module);
});

String _moduleSubtitle(HomeModuleConfig module) {
  switch (module.type) {
    case HomeModuleType.doubanInterest:
      return '豆瓣 · ${module.doubanInterestStatus.label}';
    case HomeModuleType.doubanSuggestion:
      return '豆瓣 · 个性化推荐 · ${module.doubanSuggestionType.label}';
    case HomeModuleType.doubanList:
      return '豆瓣片单';
    case HomeModuleType.recentlyAdded:
      return '最近新增';
    case HomeModuleType.librarySection:
      return module.description;
    case HomeModuleType.doubanCarousel:
      return '豆瓣首页轮播';
  }
}

class _DoubanPagedGrid extends StatelessWidget {
  const _DoubanPagedGrid({
    required this.entries,
    required this.currentPage,
    required this.onPageChanged,
  });

  final List<DoubanEntry> entries;
  final int currentPage;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const normalizedPageSize = 24;
    if (entries.isEmpty) {
      return Text(
        '无',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final totalPages =
        math.max(1, (entries.length / normalizedPageSize).ceil());
    final safePage = currentPage.clamp(0, totalPages - 1);
    final pageItems = entries
        .skip(safePage * normalizedPageSize)
        .take(normalizedPageSize)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DoubanPagerSummary(
          totalItems: entries.length,
          currentPage: safePage,
          totalPages: totalPages,
          onPageChanged: onPageChanged,
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 10.0;
            final maxWidth = constraints.maxWidth;
            final crossAxisCount =
                math.max(2, ((maxWidth + spacing) / 150).floor());
            final itemWidth =
                (maxWidth - (crossAxisCount - 1) * spacing) / crossAxisCount;
            final itemHeight = itemWidth / 0.7 + 54;
            final childAspectRatio = itemWidth / itemHeight;

            return GridView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: pageItems.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
                childAspectRatio: childAspectRatio,
              ),
              itemBuilder: (context, index) {
                final entry = pageItems[index];
                return MediaPosterTile(
                  title: entry.title,
                  subtitle: entry.year > 0 ? '${entry.year}' : '',
                  posterUrl: entry.posterUrl,
                  width: null,
                  onTap: () {
                    context.pushNamed(
                      'detail',
                      extra: MediaDetailTarget(
                        title: entry.title,
                        posterUrl: entry.posterUrl,
                        overview: entry.note,
                        year: entry.year,
                        durationLabel: entry.durationLabel,
                        ratingLabels: entry.ratingLabel.trim().isEmpty
                            ? const []
                            : [entry.ratingLabel],
                        genres: entry.genres.isNotEmpty
                            ? entry.genres
                            : (entry.subjectType.trim().isEmpty
                                ? const []
                                : [entry.subjectType]),
                        directors: entry.directors,
                        actors: entry.actors,
                        availabilityLabel: '无',
                        searchQuery: entry.title,
                        doubanId: entry.id,
                        sourceName: '豆瓣',
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
        if (totalPages > 1) ...[
          const SizedBox(height: 18),
          _DoubanPagerSummary(
            totalItems: entries.length,
            currentPage: safePage,
            totalPages: totalPages,
            onPageChanged: onPageChanged,
            compact: true,
          ),
        ],
      ],
    );
  }
}

class _DoubanPagerSummary extends StatelessWidget {
  const _DoubanPagerSummary({
    required this.totalItems,
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
    this.compact = false,
  });

  final int totalItems;
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canGoPrevious = currentPage > 0;
    final canGoNext = currentPage < totalPages - 1;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                compact
                    ? '第 ${currentPage + 1} / $totalPages 页'
                    : '共 $totalItems 部内容',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (!compact)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    '第 ${currentPage + 1} / $totalPages 页',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
        _PagerButton(
          icon: Icons.arrow_back_ios_new_rounded,
          enabled: canGoPrevious,
          onTap: () => onPageChanged(currentPage - 1),
        ),
        const SizedBox(width: 8),
        _PagerButton(
          icon: Icons.arrow_forward_ios_rounded,
          enabled: canGoNext,
          onTap: () => onPageChanged(currentPage + 1),
        ),
      ],
    );
  }
}

class _PagerButton extends StatelessWidget {
  const _PagerButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: enabled ? onTap : null,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: enabled
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? Colors.white : Colors.white.withValues(alpha: 0.26),
        ),
      ),
    );
  }
}
