import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/core/widgets/media_poster_tile.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';

class LibraryPagedGrid extends StatelessWidget {
  const LibraryPagedGrid({
    super.key,
    required this.items,
    required this.currentPage,
    required this.onPageChanged,
    this.emptyMessage = '无',
    this.pageSize = 24,
    this.header,
  });

  final List<MediaItem> items;
  final int currentPage;
  final ValueChanged<int> onPageChanged;
  final String emptyMessage;
  final int pageSize;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalizedPageSize = math.max(1, pageSize);
    if (items.isEmpty) {
      return Text(
        emptyMessage,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final totalPages = math.max(1, (items.length / normalizedPageSize).ceil());
    final safePage = currentPage.clamp(0, totalPages - 1);
    final pageItems = items
        .skip(safePage * normalizedPageSize)
        .take(normalizedPageSize)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (header != null) ...[
          header!,
          const SizedBox(height: 16),
        ],
        _LibraryPagerSummary(
          totalItems: items.length,
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
                final item = pageItems[index];
                return MediaPosterTile(
                  title: item.title,
                  subtitle: item.year > 0 ? '${item.year}' : '',
                  posterUrl: item.posterUrl,
                  width: null,
                  onTap: () {
                    context.pushNamed(
                      'detail',
                      extra: MediaDetailTarget.fromMediaItem(item),
                    );
                  },
                );
              },
            );
          },
        ),
        if (totalPages > 1) ...[
          const SizedBox(height: 18),
          _LibraryPagerSummary(
            totalItems: items.length,
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

class _LibraryPagerSummary extends StatelessWidget {
  const _LibraryPagerSummary({
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
          color: enabled
              ? Colors.white
              : Colors.white.withValues(alpha: 0.26),
        ),
      ),
    );
  }
}
