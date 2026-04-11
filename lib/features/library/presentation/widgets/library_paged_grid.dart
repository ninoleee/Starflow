import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/core/utils/media_rating_labels.dart';
import 'package:starflow/core/widgets/app_network_image.dart';
import 'package:starflow/core/widgets/media_poster_tile.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';

class _PreviousLibraryPageIntent extends Intent {
  const _PreviousLibraryPageIntent();
}

class _NextLibraryPageIntent extends Intent {
  const _NextLibraryPageIntent();
}

class LibraryPagedGrid extends StatelessWidget {
  const LibraryPagedGrid({
    super.key,
    required this.items,
    required this.currentPage,
    required this.onPageChanged,
    required this.isTelevision,
    this.focusScopePrefix = 'library',
    this.onItemContextAction,
    this.emptyMessage = '无',
    this.pageSize = 24,
    this.header,
  });

  final List<MediaItem> items;
  final int currentPage;
  final ValueChanged<int> onPageChanged;
  final bool isTelevision;
  final String focusScopePrefix;
  final ValueChanged<MediaItem>? onItemContextAction;
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

    final content = Column(
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
          isTelevision: isTelevision,
          focusScopePrefix: '$focusScopePrefix:pager:top',
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
                final posterAssets = _resolveLibraryPosterAssets(item);
                final posterAsset = posterAssets.isNotEmpty
                    ? posterAssets.first
                    : const _LibraryImageAsset(url: '');
                return MediaPosterTile(
                  focusId: _libraryItemFocusId(
                    focusScopePrefix: focusScopePrefix,
                    item: item,
                  ),
                  autofocus: index == 0,
                  title: item.title,
                  subtitle: item.year > 0 ? '${item.year}' : '',
                  posterUrl: posterAsset.url,
                  posterHeaders: posterAsset.headers,
                  imageBadgeText:
                      resolvePreferredPosterRatingLabel(item.ratingLabels),
                  posterFallbackSources: posterAssets
                      .skip(1)
                      .map(
                        (asset) => AppNetworkImageSource(
                          url: asset.url,
                          headers: asset.headers,
                        ),
                      )
                      .toList(growable: false),
                  onContextAction: onItemContextAction == null
                      ? null
                      : () => onItemContextAction!(item),
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
            isTelevision: isTelevision,
            focusScopePrefix: '$focusScopePrefix:pager:bottom',
            compact: true,
          ),
        ],
      ],
    );

    if (!isTelevision) {
      return content;
    }

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.pageUp):
            _PreviousLibraryPageIntent(),
        SingleActivator(LogicalKeyboardKey.pageDown): _NextLibraryPageIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _PreviousLibraryPageIntent:
              CallbackAction<_PreviousLibraryPageIntent>(
            onInvoke: (_) {
              if (safePage > 0) {
                onPageChanged(safePage - 1);
              }
              return null;
            },
          ),
          _NextLibraryPageIntent: CallbackAction<_NextLibraryPageIntent>(
            onInvoke: (_) {
              if (safePage < totalPages - 1) {
                onPageChanged(safePage + 1);
              }
              return null;
            },
          ),
        },
        child: content,
      ),
    );
  }
}

class _LibraryImageAsset {
  const _LibraryImageAsset({
    required this.url,
    this.headers = const {},
  });

  final String url;
  final Map<String, String> headers;
}

List<_LibraryImageAsset> _resolveLibraryPosterAssets(MediaItem item) {
  final assets = <_LibraryImageAsset>[];
  final seen = <String>{};

  void add(String url, Map<String, String> headers) {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty || !seen.add(trimmedUrl)) {
      return;
    }
    assets.add(
      _LibraryImageAsset(
        url: trimmedUrl,
        headers: headers,
      ),
    );
  }

  add(item.posterUrl, item.posterHeaders);
  add(item.bannerUrl, item.bannerHeaders);
  add(item.backdropUrl, item.backdropHeaders);
  for (final url in item.extraBackdropUrls) {
    add(url, item.extraBackdropHeaders);
  }
  return assets;
}

String _libraryItemFocusId({
  required String focusScopePrefix,
  required MediaItem item,
}) {
  return buildTvFocusId(
    prefix: '$focusScopePrefix:item',
    segments: [
      item.sourceKind.name,
      item.sourceId,
      item.sectionId,
      item.id,
      item.playbackItemId,
      item.tmdbId,
      item.imdbId,
      item.doubanId,
      item.tvdbId,
      item.wikidataId,
      item.tmdbSetId,
      item.actualAddress,
      item.itemType,
      if (item.seasonNumber != null) 'season-${item.seasonNumber}',
      if (item.episodeNumber != null) 'episode-${item.episodeNumber}',
      item.title,
    ],
  );
}

class _LibraryPagerSummary extends StatelessWidget {
  const _LibraryPagerSummary({
    required this.totalItems,
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
    required this.isTelevision,
    required this.focusScopePrefix,
    this.compact = false,
  });

  final int totalItems;
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;
  final bool isTelevision;
  final String focusScopePrefix;
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
          isTelevision: isTelevision,
          focusId: '$focusScopePrefix:previous',
          onTap: () => onPageChanged(currentPage - 1),
        ),
        const SizedBox(width: 8),
        _PagerButton(
          icon: Icons.arrow_forward_ios_rounded,
          enabled: canGoNext,
          isTelevision: isTelevision,
          focusId: '$focusScopePrefix:next',
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
    required this.isTelevision,
    this.focusId,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final bool isTelevision;
  final String? focusId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final child = Container(
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
    );
    if (isTelevision) {
      return TvFocusableAction(
        onPressed: enabled ? onTap : null,
        focusId: focusId,
        borderRadius: BorderRadius.circular(999),
        child: child,
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: enabled ? onTap : null,
      child: child,
    );
  }
}
