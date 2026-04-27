import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/core/utils/media_rating_labels.dart';
import 'package:starflow/core/widgets/app_network_image.dart';
import 'package:starflow/core/widgets/media_poster_tile.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/application/library_cached_items.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';

class _PreviousLibraryPageIntent extends Intent {
  const _PreviousLibraryPageIntent();
}

class _NextLibraryPageIntent extends Intent {
  const _NextLibraryPageIntent();
}

class LibraryPagedGrid extends ConsumerWidget {
  const LibraryPagedGrid({
    super.key,
    required this.pageItems,
    required this.totalItems,
    required this.currentPage,
    required this.onPageChanged,
    required this.isTelevision,
    this.focusScopePrefix = 'library',
    this.onItemContextAction,
    this.emptyMessage = '无',
    this.pageSize = 24,
    this.header,
  });

  final List<MediaItem> pageItems;
  final int totalItems;
  final int currentPage;
  final ValueChanged<int> onPageChanged;
  final bool isTelevision;
  final String focusScopePrefix;
  final ValueChanged<MediaItem>? onItemContextAction;
  final String emptyMessage;
  final int pageSize;
  final Widget? header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final normalizedPageSize = math.max(1, pageSize);
    if (totalItems <= 0) {
      return Text(
        emptyMessage,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final totalPages = math.max(1, (totalItems / normalizedPageSize).ceil());
    final safePage = currentPage.clamp(0, totalPages - 1);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (header != null) ...[
          header!,
          const SizedBox(height: 16),
        ],
        _LibraryPagerSummary(
          totalItems: totalItems,
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
              padding: const EdgeInsets.symmetric(vertical: 10),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              clipBehavior: Clip.none,
              itemCount: pageItems.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
                childAspectRatio: childAspectRatio,
              ),
              itemBuilder: (context, index) => _LibraryPagedGridTile(
                seedItem: pageItems[index],
                index: index,
                focusScopePrefix: focusScopePrefix,
                onItemContextAction: onItemContextAction,
              ),
            );
          },
        ),
        if (totalPages > 1) ...[
          const SizedBox(height: 18),
          _LibraryPagerSummary(
            totalItems: totalItems,
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

    return LibraryPagedGridKeyboardActions(
      enabled: isTelevision,
      totalItems: totalItems,
      currentPage: currentPage,
      pageSize: pageSize,
      onPageChanged: onPageChanged,
      child: content,
    );
  }
}

class LibraryPagedGridSliver extends ConsumerWidget {
  const LibraryPagedGridSliver({
    super.key,
    required this.pageItems,
    required this.totalItems,
    required this.currentPage,
    required this.onPageChanged,
    required this.isTelevision,
    this.focusScopePrefix = 'library',
    this.onItemContextAction,
    this.emptyMessage = '无',
    this.pageSize = 24,
    this.header,
  });

  final List<MediaItem> pageItems;
  final int totalItems;
  final int currentPage;
  final ValueChanged<int> onPageChanged;
  final bool isTelevision;
  final String focusScopePrefix;
  final ValueChanged<MediaItem>? onItemContextAction;
  final String emptyMessage;
  final int pageSize;
  final Widget? header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final normalizedPageSize = math.max(1, pageSize);
    if (totalItems <= 0) {
      return SliverToBoxAdapter(
        child: Text(
          emptyMessage,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final totalPages = math.max(1, (totalItems / normalizedPageSize).ceil());
    final safePage = currentPage.clamp(0, totalPages - 1);

    return SliverMainAxisGroup(
      slivers: [
        if (header != null) ...[
          SliverToBoxAdapter(child: header!),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
        SliverToBoxAdapter(
          child: _LibraryPagerSummary(
            totalItems: totalItems,
            currentPage: safePage,
            totalPages: totalPages,
            onPageChanged: onPageChanged,
            isTelevision: isTelevision,
            focusScopePrefix: '$focusScopePrefix:pager:top',
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
        SliverLayoutBuilder(
          builder: (context, constraints) {
            const spacing = 10.0;
            final maxWidth = constraints.crossAxisExtent;
            final crossAxisCount =
                math.max(2, ((maxWidth + spacing) / 150).floor());
            final itemWidth =
                (maxWidth - (crossAxisCount - 1) * spacing) / crossAxisCount;
            final itemHeight = itemWidth / 0.7 + 54;
            final childAspectRatio = itemWidth / itemHeight;

            return SliverPadding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: spacing,
                  childAspectRatio: childAspectRatio,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _LibraryPagedGridTile(
                    seedItem: pageItems[index],
                    index: index,
                    focusScopePrefix: focusScopePrefix,
                    onItemContextAction: onItemContextAction,
                  ),
                  childCount: pageItems.length,
                ),
              ),
            );
          },
        ),
        if (totalPages > 1) ...[
          const SliverToBoxAdapter(child: SizedBox(height: 18)),
          SliverToBoxAdapter(
            child: _LibraryPagerSummary(
              totalItems: totalItems,
              currentPage: safePage,
              totalPages: totalPages,
              onPageChanged: onPageChanged,
              isTelevision: isTelevision,
              focusScopePrefix: '$focusScopePrefix:pager:bottom',
              compact: true,
            ),
          ),
        ],
      ],
    );
  }
}

class LibraryPagedGridKeyboardActions extends StatelessWidget {
  const LibraryPagedGridKeyboardActions({
    super.key,
    required this.enabled,
    required this.totalItems,
    required this.currentPage,
    required this.pageSize,
    required this.onPageChanged,
    required this.child,
  });

  final bool enabled;
  final int totalItems;
  final int currentPage;
  final int pageSize;
  final ValueChanged<int> onPageChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled || totalItems <= 0) {
      return child;
    }

    final normalizedPageSize = math.max(1, pageSize);
    final totalPages = math.max(1, (totalItems / normalizedPageSize).ceil());
    final safePage = currentPage.clamp(0, totalPages - 1);

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
        child: child,
      ),
    );
  }
}

class _LibraryPagedGridTile extends ConsumerWidget {
  const _LibraryPagedGridTile({
    required this.seedItem,
    required this.index,
    required this.focusScopePrefix,
    required this.onItemContextAction,
  });

  final MediaItem seedItem;
  final int index;
  final String focusScopePrefix;
  final ValueChanged<MediaItem>? onItemContextAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cachedTarget = ref.watch(
      libraryCachedDetailTargetProvider(
        LibraryItemOverlayRequest(seedItem),
      ),
    );
    final item = mergeLibraryItemWithCachedDetails(
      item: seedItem,
      cachedTarget: cachedTarget,
    );
    final posterAssets = _resolveLibraryPosterAssets(item)
        .map(
          (asset) => _resolveLibraryPosterAssetForDisplay(
            item,
            asset,
          ),
        )
        .toList(growable: false);
    final posterAsset = posterAssets.isNotEmpty
        ? posterAssets.first
        : const _LibraryImageAsset(url: '');
    final posterCachePolicy = item.sourceKind == MediaSourceKind.emby
        ? AppNetworkImageCachePolicy.networkOnly
        : AppNetworkImageCachePolicy.persistent;
    return MediaPosterTile(
      focusId: _libraryItemFocusId(
        focusScopePrefix: focusScopePrefix,
        item: item,
      ),
      autofocus: index == 0,
      tvPosterFocusOutlineOnly: true,
      tvPosterFocusShowBorder: false,
      tvPosterFocusScale: 1.06,
      title: item.title,
      subtitle: item.year > 0 ? '${item.year}' : '',
      posterUrl: posterAsset.url,
      posterCachePolicy: posterCachePolicy,
      posterHeaders: posterAsset.headers,
      imageBadgeText: resolvePreferredPosterRatingLabel(item.ratingLabels),
      posterFallbackSources: posterAssets
          .skip(1)
          .map(
            (asset) => AppNetworkImageSource(
              url: asset.url,
              headers: asset.headers,
              cachePolicy: posterCachePolicy,
            ),
          )
          .toList(growable: false),
      onContextAction:
          onItemContextAction == null ? null : () => onItemContextAction!(item),
      width: null,
      onTap: () {
        context.pushNamed(
          'detail',
          extra: MediaDetailTarget.fromMediaItem(item),
        );
      },
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
  if (!_isLibraryDetailOnlyEpisodeBackdrop(item)) {
    add(item.backdropUrl, item.backdropHeaders);
  }
  return assets;
}

_LibraryImageAsset _resolveLibraryPosterAssetForDisplay(
  MediaItem item,
  _LibraryImageAsset asset,
) {
  if (item.sourceKind != MediaSourceKind.emby) {
    return asset;
  }

  final optimizedUrl = EmbyApiClient.buildImageUrlForProfile(
    asset.url,
    profile: EmbyImageRequestProfile.libraryGrid,
  );
  if (optimizedUrl == asset.url) {
    return asset;
  }

  return _LibraryImageAsset(
    url: optimizedUrl,
    headers: asset.headers,
  );
}

bool _isLibraryDetailOnlyEpisodeBackdrop(MediaItem item) {
  final itemType = item.itemType.trim().toLowerCase();
  if (itemType != 'episode') {
    return false;
  }
  final backdropUrl = item.backdropUrl.trim();
  final bannerUrl = item.bannerUrl.trim();
  return backdropUrl.isNotEmpty &&
      bannerUrl.isNotEmpty &&
      backdropUrl != bannerUrl;
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
