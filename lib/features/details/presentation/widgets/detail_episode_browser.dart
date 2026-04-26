import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/app_network_image.dart';
import 'package:starflow/core/widgets/desktop_horizontal_pager.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/widgets/detail_shared_widgets.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/active_playback_cleanup.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
import 'package:starflow/features/playback/domain/playback_memory_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

final detailSeriesBrowserProvider = FutureProvider.autoDispose
    .family<DetailSeriesBrowserState?, MediaDetailTarget>((
  ref,
  target,
) async {
  if (!target.isSeries ||
      target.sourceId.trim().isEmpty ||
      target.itemId.trim().isEmpty) {
    return null;
  }

  final repository = ref.read(mediaRepositoryProvider);
  final children = await repository.fetchChildren(
    sourceId: target.sourceId,
    parentId: target.itemId,
    sectionId: target.sectionId,
    sectionName: target.sectionName,
  );

  final seasons = children.where(_isSeasonItem).toList(growable: false);
  if (seasons.isEmpty) {
    final episodes = children.where(_isEpisodeItem).toList(growable: false);
    if (episodes.isEmpty) {
      return null;
    }
    return DetailSeriesBrowserState(
      groups: [
        DetailEpisodeGroup(
          id: 'all',
          title: '全部剧集',
          seasonNumber: null,
          episodes: sortEpisodesForDetailBrowser(episodes),
        ),
      ],
    );
  }

  final firstSeason = seasons.first;
  List<MediaItem> firstSeasonEpisodes = const <MediaItem>[];
  var firstSeasonPreloaded = false;
  try {
    final firstChildren = await repository.fetchChildren(
      sourceId: target.sourceId,
      parentId: firstSeason.id,
      sectionId: target.sectionId,
      sectionName: target.sectionName,
    );
    firstSeasonPreloaded = true;
    firstSeasonEpisodes = firstChildren.where(_isEpisodeItem).toList(
          growable: false,
        );
  } catch (_) {
    firstSeasonPreloaded = false;
    firstSeasonEpisodes = const <MediaItem>[];
  }

  final groups = <DetailEpisodeGroup>[];
  for (var index = 0; index < seasons.length; index++) {
    final season = seasons[index];
    final preloadEpisodes = index == 0
        ? sortEpisodesForDetailBrowser(firstSeasonEpisodes)
        : const <MediaItem>[];
    groups.add(
      DetailEpisodeGroup(
        id: season.id,
        title: season.title,
        seasonNumber: season.seasonNumber,
        episodes: preloadEpisodes,
        episodesLoaded: index == 0 ? firstSeasonPreloaded : false,
      ),
    );
  }
  return groups.isEmpty ? null : DetailSeriesBrowserState(groups: groups);
});

final detailSeasonEpisodesProvider = FutureProvider.autoDispose
    .family<List<MediaItem>, _DetailSeasonEpisodesRequest>(
        (ref, request) async {
  final repository = ref.read(mediaRepositoryProvider);
  final children = await repository.fetchChildren(
    sourceId: request.sourceId,
    parentId: request.seasonId,
    sectionId: request.sectionId,
    sectionName: request.sectionName,
  );
  final episodes = children.where(_isEpisodeItem).toList(growable: false);
  return sortEpisodesForDetailBrowser(episodes);
});

bool _isSeasonItem(MediaItem item) {
  return item.itemType.trim().toLowerCase() == 'season';
}

bool _isEpisodeItem(MediaItem item) {
  return item.itemType.trim().toLowerCase() == 'episode';
}

class _DetailSeasonEpisodesRequest {
  const _DetailSeasonEpisodesRequest({
    required this.sourceId,
    required this.seasonId,
    required this.sectionId,
    required this.sectionName,
  });

  factory _DetailSeasonEpisodesRequest.fromTargetAndGroup({
    required MediaDetailTarget target,
    required DetailEpisodeGroup group,
  }) {
    return _DetailSeasonEpisodesRequest(
      sourceId: target.sourceId.trim(),
      seasonId: group.id.trim(),
      sectionId: target.sectionId.trim(),
      sectionName: target.sectionName.trim(),
    );
  }

  final String sourceId;
  final String seasonId;
  final String sectionId;
  final String sectionName;

  String get _cacheKey => '$sourceId|$seasonId|$sectionId|$sectionName';

  @override
  bool operator ==(Object other) {
    return other is _DetailSeasonEpisodesRequest &&
        other._cacheKey == _cacheKey;
  }

  @override
  int get hashCode => _cacheKey.hashCode;
}

class DetailSeriesBrowserState {
  const DetailSeriesBrowserState({required this.groups});

  final List<DetailEpisodeGroup> groups;
}

class DetailEpisodeGroup {
  const DetailEpisodeGroup({
    required this.id,
    required this.title,
    required this.seasonNumber,
    required this.episodes,
    this.episodesLoaded = true,
  });

  final String id;
  final String title;
  final int? seasonNumber;
  final List<MediaItem> episodes;
  final bool episodesLoaded;

  DetailEpisodeGroup copyWith({
    List<MediaItem>? episodes,
    bool? episodesLoaded,
  }) {
    return DetailEpisodeGroup(
      id: id,
      title: title,
      seasonNumber: seasonNumber,
      episodes: episodes ?? this.episodes,
      episodesLoaded: episodesLoaded ?? this.episodesLoaded,
    );
  }

  String get label {
    if (seasonNumber != null && seasonNumber! > 0) {
      return '第 $seasonNumber 季';
    }
    return title;
  }
}

List<MediaItem> sortEpisodesForDetailBrowser(List<MediaItem> items) {
  final sorted = [...items]..sort((left, right) {
      final seasonComparison =
          (left.seasonNumber ?? 0).compareTo(right.seasonNumber ?? 0);
      if (seasonComparison != 0) {
        return seasonComparison;
      }

      final episodeComparison =
          (left.episodeNumber ?? 0).compareTo(right.episodeNumber ?? 0);
      if (episodeComparison != 0) {
        return episodeComparison;
      }

      return left.title.toLowerCase().compareTo(right.title.toLowerCase());
    });
  return sorted;
}

DetailEpisodeGroup resolveSelectedEpisodeGroup({
  required List<DetailEpisodeGroup> groups,
  required String selectedGroupId,
}) {
  DetailEpisodeGroup selectedGroup = groups.first;
  for (final group in groups) {
    if (group.id == selectedGroupId) {
      selectedGroup = group;
      break;
    }
  }
  return selectedGroup;
}

class DetailEpisodeBrowser extends ConsumerStatefulWidget {
  const DetailEpisodeBrowser({
    super.key,
    required this.seriesTarget,
    required this.groups,
    required this.selectedGroupId,
    required this.onSeasonSelected,
  });

  final MediaDetailTarget seriesTarget;
  final List<DetailEpisodeGroup> groups;
  final String selectedGroupId;
  final ValueChanged<String> onSeasonSelected;

  @override
  ConsumerState<DetailEpisodeBrowser> createState() =>
      _DetailEpisodeBrowserState();
}

class _DetailEpisodeBrowserState extends ConsumerState<DetailEpisodeBrowser> {
  static const double _episodeCardWidth = 292;
  static const double _episodeCardSpacing = 14;

  String _episodeFocusId(MediaItem episode, int index) {
    final episodeSeed = episode.id.isNotEmpty
        ? episode.id
        : '${episode.seasonNumber ?? 0}-${episode.episodeNumber ?? index}';
    return 'detail:episode:$episodeSeed';
  }

  AsyncValue<DetailEpisodeGroup> _selectedGroupAsync(
    DetailEpisodeGroup selectedGroup,
  ) {
    if (selectedGroup.episodesLoaded) {
      return AsyncData<DetailEpisodeGroup>(selectedGroup);
    }
    final request = _DetailSeasonEpisodesRequest.fromTargetAndGroup(
      target: widget.seriesTarget,
      group: selectedGroup,
    );
    final episodesAsync = ref.watch(detailSeasonEpisodesProvider(request));
    return episodesAsync.whenData(
      (episodes) => selectedGroup.copyWith(
        episodes: episodes,
        episodesLoaded: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedGroup = resolveSelectedEpisodeGroup(
      groups: widget.groups,
      selectedGroupId: widget.selectedGroupId,
    );
    final selectedGroupAsync = _selectedGroupAsync(selectedGroup);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.groups.length > 1) ...[
          SizedBox(
            height: 52,
            child: DesktopHorizontalPager(
              builder: (context, controller) => ListView.separated(
                controller: controller,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: widget.groups.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final group = widget.groups[index];
                  final selected = group.id == selectedGroup.id;
                  return _DetailSeasonChip(
                    label: group.label,
                    selected: selected,
                    focusId: 'detail:season:${group.id}',
                    autofocus: false,
                    onTap: () {
                      if (widget.selectedGroupId != group.id) {
                        widget.onSeasonSelected(group.id);
                      }
                    },
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        SizedBox(
          height: 292,
          child: selectedGroupAsync.when(
            data: (resolvedGroup) {
              final episodes = resolvedGroup.episodes;
              if (episodes.isEmpty) {
                return const Center(
                  child: Text(
                    '当前分组暂无剧集',
                    style: TextStyle(
                      color: Color(0xFF90A0BD),
                      fontSize: 14,
                    ),
                  ),
                );
              }
              return DesktopHorizontalPager(
                key: ValueKey<String>('detail-episodes:${resolvedGroup.id}'),
                builder: (context, controller) => ListView.separated(
                  controller: controller,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  clipBehavior: Clip.none,
                  itemCount: episodes.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: _episodeCardSpacing),
                  itemBuilder: (context, index) {
                    final episode = episodes[index];
                    return SizedBox(
                      width: _episodeCardWidth,
                      child: _DetailEpisodeCard(
                        item: episode,
                        seriesTarget: widget.seriesTarget,
                        focusId: _episodeFocusId(episode, index),
                        autofocus: false,
                      ),
                    );
                  },
                ),
              );
            },
            loading: () => const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
            error: (error, stackTrace) => Center(
              child: Text(
                '加载剧集失败：$error',
                style: const TextStyle(
                  color: Color(0xFF90A0BD),
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailSeasonChip extends StatelessWidget {
  const _DetailSeasonChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.focusId,
    this.autofocus = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? focusId;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return StarflowChipButton(
      label: label,
      selected: selected,
      onPressed: onTap,
      focusId: focusId,
      autofocus: autofocus,
    );
  }
}

class _DetailEpisodeCard extends ConsumerWidget {
  const _DetailEpisodeCard({
    required this.item,
    required this.seriesTarget,
    this.focusId,
    this.autofocus = false,
  });

  final MediaItem item;
  final MediaDetailTarget seriesTarget;
  final String? focusId;
  final bool autofocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    final playbackEntry =
        ref.watch(playbackEntryForMediaItemProvider(item)).value;
    final badgeText = _episodeBadgeText(item, playbackEntry);
    final summary = _episodeSummary(
      item,
      seriesTarget: seriesTarget,
    );
    final titleText = _episodeTitleText(item);
    final fileSizeText = _episodeDisplayFileSizeLabel(item.fileSizeBytes);

    void onOpenDetail() {
      context.pushNamed(
        'detail',
        extra: episodeToDetailTarget(item, seriesTarget: seriesTarget),
      );
    }

    Future<void> openPlaybackTarget() async {
      final playbackTarget = itemToEpisodePlaybackTarget(
        item,
        seriesTarget: seriesTarget,
      );
      if (!playbackTarget.canPlay) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('当前分集没有可直接播放的资源')),
        );
        return;
      }
      await ActivePlaybackCleanupCoordinator.cleanupAll(
        reason: 'open-new-playback',
      );
      if (!context.mounted) {
        return;
      }
      context.pushNamed(
        'player',
        extra: playbackTarget,
      );
    }

    final effectiveFocusId = focusId?.trim() ?? '';
    final borderRadius = BorderRadius.circular(24);
    final titleStyle = TextStyle(
      color: Colors.white,
      fontSize: 16,
      fontWeight: FontWeight.w800,
      height: 1.25,
      shadows: isTelevision
          ? null
          : const [
              Shadow(
                color: Color(0xAA000000),
                blurRadius: 16,
                offset: Offset(0, 3),
              ),
            ],
    );
    final cardChild = DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: isTelevision ? 0.045 : 0.06),
        borderRadius: borderRadius,
        border: Border.all(
          color: Colors.white.withValues(alpha: isTelevision ? 0.05 : 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(24),
            ),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _DetailEpisodeArtwork(item: item),
                  if (!isTelevision)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withValues(alpha: 0.18),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.12),
                            Colors.black.withValues(alpha: 0.58),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomCenter,
                          stops: const [0, 0.34, 0.62, 1],
                        ),
                      ),
                    ),
                  Positioned(
                    left: 14,
                    right: 14,
                    top: 14,
                    child: Text(
                      titleText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    ),
                  ),
                  Positioned(
                    left: 12,
                    bottom: 12,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 214),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.46),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          badgeText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (fileSizeText.isNotEmpty)
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.54),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          fileSizeText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Text(
                summary,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFD7E0F1),
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    final actionChild = RepaintBoundary(
      child: isTelevision
          ? GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => unawaited(openPlaybackTarget()),
              onLongPress: onOpenDetail,
              onSecondaryTap: onOpenDetail,
              child: cardChild,
            )
          : cardChild,
    );
    return TvFocusableAction(
      onPressed: () => unawaited(openPlaybackTarget()),
      onContextAction: onOpenDetail,
      focusId: effectiveFocusId.isEmpty ? null : effectiveFocusId,
      autofocus: autofocus,
      borderRadius: borderRadius,
      visualStyle: TvFocusVisualStyle.subtle,
      focusScale: isTelevision ? 1.035 : 1.0,
      child: actionChild,
    );
  }

  String _episodeBadgeText(
    MediaItem item,
    PlaybackProgressEntry? playbackEntry,
  ) {
    final entries = <String>[
      item.episodeNumber != null ? '第 ${item.episodeNumber} 集' : '剧集',
      if (item.durationLabel.trim().isNotEmpty && item.durationLabel != '时长未知')
        item.durationLabel,
      if (_progressLabel(item, playbackEntry).trim().isNotEmpty)
        _progressLabel(item, playbackEntry),
    ];
    return entries.join(' · ');
  }

  String _episodeSummary(
    MediaItem item, {
    required MediaDetailTarget seriesTarget,
  }) {
    final episodeOverview = item.overview.trim();
    final seriesOverview = seriesTarget.overview.trim();
    if (episodeOverview.isNotEmpty && episodeOverview != seriesOverview) {
      return episodeOverview;
    }
    final fallback = <String>[
      if (item.seasonNumber != null && item.episodeNumber != null)
        '第 ${item.seasonNumber} 季 第 ${item.episodeNumber} 集',
      if (item.durationLabel.trim().isNotEmpty && item.durationLabel != '时长未知')
        item.durationLabel,
      if (!item.isPlayable) '当前没有可直接播放的资源',
    ];
    final fileName = resolveDetailMediaItemFileName(item);
    if (fallback.isNotEmpty) {
      final detailLine = fallback.join(' · ');
      if (fileName.isNotEmpty) {
        return '$detailLine\n$fileName';
      }
      return detailLine;
    }
    if (fileName.isNotEmpty) {
      return fileName;
    }
    return '暂无简介';
  }

  String _episodeTitleText(MediaItem item) {
    final title = item.title.trim();
    if (title.isNotEmpty) {
      return title;
    }
    if (item.episodeNumber != null) {
      return '第 ${item.episodeNumber} 集';
    }
    return '剧集';
  }

  String _progressLabel(
    MediaItem item,
    PlaybackProgressEntry? playbackEntry,
  ) {
    final progress = playbackEntry?.progress ?? item.playbackProgress;
    if (progress == null || progress <= 0) {
      return '';
    }
    if (progress >= 0.995) {
      return '已看完';
    }
    return '已看 ${(progress * 100).round()}%';
  }
}

String _episodeDisplayFileSizeLabel(int? fileSizeBytes) {
  return formatByteSize(fileSizeBytes).trim();
}

class _DetailEpisodeArtwork extends StatelessWidget {
  const _DetailEpisodeArtwork({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final artwork = buildDetailBackdropImageSourcesForMediaItem(item);
    final primaryArtwork = artwork.primary;
    if (primaryArtwork.url.isNotEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final decodeSize = _resolveEpisodeArtworkDecodeSize(
            context,
            constraints,
          );
          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: AppNetworkImage(
              primaryArtwork.url,
              headers: primaryArtwork.headers,
              fallbackSources: artwork.fallbackSources,
              cachePolicy: primaryArtwork.cachePolicy,
              cacheWidth: decodeSize?.width,
              cacheHeight: decodeSize?.height,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  _DetailEpisodeArtworkFallback(item: item),
            ),
          );
        },
      );
    }
    return _DetailEpisodeArtworkFallback(item: item);
  }
}

class _DetailEpisodeArtworkDecodeSize {
  const _DetailEpisodeArtworkDecodeSize({
    required this.width,
    required this.height,
  });

  final int width;
  final int height;
}

_DetailEpisodeArtworkDecodeSize? _resolveEpisodeArtworkDecodeSize(
  BuildContext context,
  BoxConstraints constraints,
) {
  final mediaQuery = MediaQuery.maybeOf(context);
  final logicalWidth = constraints.hasBoundedWidth
      ? constraints.maxWidth
      : (mediaQuery?.size.width ?? 0);
  final logicalHeight = constraints.hasBoundedHeight
      ? constraints.maxHeight
      : (logicalWidth * 9 / 16);
  if (logicalWidth <= 0 || logicalHeight <= 0) {
    return null;
  }
  final dpr = (mediaQuery?.devicePixelRatio ?? 1.0).clamp(1.0, 2.5);
  final decodeWidth = (logicalWidth * dpr).round();
  final decodeHeight = (logicalHeight * dpr).round();
  return _DetailEpisodeArtworkDecodeSize(
    width: math.max(1, math.min(decodeWidth, 1920)),
    height: math.max(1, math.min(decodeHeight, 1080)),
  );
}

class _DetailEpisodeArtworkFallback extends StatelessWidget {
  const _DetailEpisodeArtworkFallback({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        gradient: LinearGradient(
          colors: [
            Color(0xFF24324B),
            Color(0xFF101B2E),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          item.isPlayable
              ? Icons.play_circle_outline_rounded
              : Icons.movie_outlined,
          color: Colors.white.withValues(alpha: 0.78),
          size: 34,
        ),
      ),
    );
  }
}

PlaybackTarget itemToEpisodePlaybackTarget(
  MediaItem item, {
  MediaDetailTarget? seriesTarget,
}) {
  final base = PlaybackTarget.fromMediaItem(item);
  if (seriesTarget == null) {
    return base;
  }
  final isSeriesLike = seriesTarget.itemType.trim().toLowerCase() == 'series';
  if (!isSeriesLike) {
    return base;
  }
  return base.copyWith(
    seriesId: seriesTarget.itemId,
    seriesTitle: seriesTarget.title,
  );
}

MediaDetailTarget episodeToDetailTarget(
  MediaItem item, {
  required MediaDetailTarget seriesTarget,
}) {
  final seriesQuery = seriesTarget.searchQuery.trim().isNotEmpty
      ? seriesTarget.searchQuery.trim()
      : seriesTarget.title.trim();
  final target = MediaDetailTarget.fromMediaItem(
    item,
    searchQuery: seriesQuery.isNotEmpty ? seriesQuery : item.title,
  );
  final useOwnPoster = target.posterUrl.trim().isNotEmpty;
  final useOwnBackdrop = target.backdropUrl.trim().isNotEmpty;
  final useOwnLogo = target.logoUrl.trim().isNotEmpty;
  final useOwnBanner = target.bannerUrl.trim().isNotEmpty;
  final useOwnExtraBackdrops = target.extraBackdropUrls.isNotEmpty;
  return target.copyWith(
    playbackTarget: item.isPlayable
        ? itemToEpisodePlaybackTarget(item, seriesTarget: seriesTarget)
        : target.playbackTarget,
    posterUrl: useOwnPoster ? target.posterUrl : seriesTarget.posterUrl,
    posterHeaders:
        useOwnPoster ? target.posterHeaders : seriesTarget.posterHeaders,
    backdropUrl: useOwnBackdrop ? target.backdropUrl : seriesTarget.backdropUrl,
    backdropHeaders:
        useOwnBackdrop ? target.backdropHeaders : seriesTarget.backdropHeaders,
    logoUrl: useOwnLogo ? target.logoUrl : seriesTarget.logoUrl,
    logoHeaders: useOwnLogo ? target.logoHeaders : seriesTarget.logoHeaders,
    bannerUrl: useOwnBanner ? target.bannerUrl : seriesTarget.bannerUrl,
    bannerHeaders:
        useOwnBanner ? target.bannerHeaders : seriesTarget.bannerHeaders,
    extraBackdropUrls: useOwnExtraBackdrops
        ? target.extraBackdropUrls
        : seriesTarget.extraBackdropUrls,
    extraBackdropHeaders: useOwnExtraBackdrops
        ? target.extraBackdropHeaders
        : seriesTarget.extraBackdropHeaders,
    doubanId: target.doubanId.trim().isNotEmpty
        ? target.doubanId
        : seriesTarget.doubanId,
    imdbId:
        target.imdbId.trim().isNotEmpty ? target.imdbId : seriesTarget.imdbId,
    tmdbId:
        target.tmdbId.trim().isNotEmpty ? target.tmdbId : seriesTarget.tmdbId,
    tvdbId:
        target.tvdbId.trim().isNotEmpty ? target.tvdbId : seriesTarget.tvdbId,
    wikidataId: target.wikidataId.trim().isNotEmpty
        ? target.wikidataId
        : seriesTarget.wikidataId,
    tmdbSetId: target.tmdbSetId.trim().isNotEmpty
        ? target.tmdbSetId
        : seriesTarget.tmdbSetId,
    providerIds: target.providerIds.isNotEmpty
        ? target.providerIds
        : seriesTarget.providerIds,
  );
}
