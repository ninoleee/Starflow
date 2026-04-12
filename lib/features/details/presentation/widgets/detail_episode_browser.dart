import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/core/widgets/app_network_image.dart';
import 'package:starflow/core/widgets/desktop_horizontal_pager.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_target_resolver.dart';
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

  final seasons = children
      .where((item) => item.itemType.trim().toLowerCase() == 'season')
      .toList(growable: false);
  if (seasons.isEmpty) {
    final episodes = children
        .where((item) => item.itemType.trim().toLowerCase() == 'episode')
        .toList(growable: false);
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

  final seasonEpisodes = await Future.wait(
    seasons.map(
      (season) => repository.fetchChildren(
        sourceId: target.sourceId,
        parentId: season.id,
        sectionId: target.sectionId,
        sectionName: target.sectionName,
      ),
    ),
  );

  final groups = <DetailEpisodeGroup>[];
  for (var index = 0; index < seasons.length; index++) {
    final season = seasons[index];
    final episodes = seasonEpisodes[index]
        .where((item) => item.itemType.trim().toLowerCase() == 'episode')
        .toList(growable: false);
    if (episodes.isEmpty) {
      continue;
    }
    groups.add(
      DetailEpisodeGroup(
        id: season.id,
        title: season.title,
        seasonNumber: season.seasonNumber,
        episodes: sortEpisodesForDetailBrowser(episodes),
      ),
    );
  }
  return groups.isEmpty ? null : DetailSeriesBrowserState(groups: groups);
});

final detailEpisodeDisplayFileSizeProvider = FutureProvider.autoDispose
    .family<int?, _DetailEpisodeFileSizeRequest>((ref, request) async {
  final target = PlaybackTarget.fromMediaItem(request.item);
  if (!target.needsResolution) {
    return request.item.fileSizeBytes;
  }

  try {
    final resolved = await PlaybackTargetResolver(read: ref.read).resolve(
      target,
    );
    return resolved.fileSizeBytes ??
        _fallbackEpisodeDisplayFileSizeBytes(request.item, target);
  } catch (_) {
    return _fallbackEpisodeDisplayFileSizeBytes(request.item, target);
  }
});

class _DetailEpisodeFileSizeRequest {
  const _DetailEpisodeFileSizeRequest(this.item);

  final MediaItem item;

  String get _cacheKey {
    return [
      item.sourceKind.name,
      item.sourceId.trim(),
      item.playbackItemId.trim(),
      item.streamUrl.trim(),
      item.actualAddress.trim(),
      item.itemType.trim(),
      item.title.trim(),
      '${item.seasonNumber ?? ''}',
      '${item.episodeNumber ?? ''}',
    ].join('|');
  }

  @override
  bool operator ==(Object other) {
    return other is _DetailEpisodeFileSizeRequest &&
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
  });

  final String id;
  final String title;
  final int? seasonNumber;
  final List<MediaItem> episodes;

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

class DetailEpisodeBrowser extends StatefulWidget {
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
  State<DetailEpisodeBrowser> createState() => _DetailEpisodeBrowserState();
}

class _DetailEpisodeBrowserState extends State<DetailEpisodeBrowser> {
  static const double _episodeCardWidth = 292;
  static const double _episodeCardSpacing = 14;

  final ScrollController _seasonScrollController = ScrollController();
  final Map<String, FocusNode> _seasonFocusNodes = <String, FocusNode>{};
  final Map<String, FocusNode> _episodeFocusNodes = <String, FocusNode>{};

  @override
  void initState() {
    super.initState();
    _syncFocusNodes();
  }

  @override
  void didUpdateWidget(covariant DetailEpisodeBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFocusNodes();
  }

  @override
  void dispose() {
    _seasonScrollController.dispose();
    for (final node in _seasonFocusNodes.values) {
      node.dispose();
    }
    for (final node in _episodeFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _syncFocusNodes() {
    final seasonIds = widget.groups.map((group) => group.id).toSet();
    _disposeRemovedFocusNodes(_seasonFocusNodes, activeKeys: seasonIds);
    for (final group in widget.groups) {
      _seasonFocusNodes.putIfAbsent(
        group.id,
        () => FocusNode(debugLabel: 'detail-season-${group.id}'),
      );
    }

    final episodeKeys = <String>{};
    for (final group in widget.groups) {
      for (var index = 0; index < group.episodes.length; index++) {
        final key = _episodeNodeKey(group, group.episodes[index], index);
        episodeKeys.add(key);
        _episodeFocusNodes.putIfAbsent(
          key,
          () => FocusNode(debugLabel: 'detail-episode-$key'),
        );
      }
    }
    _disposeRemovedFocusNodes(_episodeFocusNodes, activeKeys: episodeKeys);
  }

  void _disposeRemovedFocusNodes(
    Map<String, FocusNode> nodes, {
    required Set<String> activeKeys,
  }) {
    final removedKeys = nodes.keys
        .where((key) => !activeKeys.contains(key))
        .toList(growable: false);
    for (final key in removedKeys) {
      nodes.remove(key)?.dispose();
    }
  }

  String _episodeNodeKey(
      DetailEpisodeGroup group, MediaItem episode, int index) {
    final episodeSeed = episode.id.isNotEmpty
        ? episode.id
        : '${episode.seasonNumber ?? 0}-${episode.episodeNumber ?? index}';
    return '${group.id}::$episodeSeed';
  }

  String _episodeFocusId(MediaItem episode, int index) {
    final episodeSeed = episode.id.isNotEmpty
        ? episode.id
        : '${episode.seasonNumber ?? 0}-${episode.episodeNumber ?? index}';
    return 'detail:episode:$episodeSeed';
  }

  void _ensureFocusNodeVisible(FocusNode? node) {
    final focusContext = node?.context;
    if (focusContext == null) {
      return;
    }
    unawaited(
      Scrollable.ensureVisible(
        focusContext,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedGroup = resolveSelectedEpisodeGroup(
      groups: widget.groups,
      selectedGroupId: widget.selectedGroupId,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.groups.length > 1) ...[
          SizedBox(
            height: 52,
            child: ListView.separated(
              controller: _seasonScrollController,
              scrollDirection: Axis.horizontal,
              itemCount: widget.groups.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final group = widget.groups[index];
                final selected = group.id == selectedGroup.id;
                return _DetailSeasonChip(
                  label: group.label,
                  selected: selected,
                  focusNode: _seasonFocusNodes[group.id],
                  focusId: 'detail:season:${group.id}',
                  autofocus: index == 0,
                  onFocused: () {
                    if (widget.selectedGroupId != group.id) {
                      widget.onSeasonSelected(group.id);
                    }
                    _ensureFocusNodeVisible(_seasonFocusNodes[group.id]);
                  },
                  onTap: () {
                    if (widget.selectedGroupId != group.id) {
                      widget.onSeasonSelected(group.id);
                    }
                    _ensureFocusNodeVisible(_seasonFocusNodes[group.id]);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
        SizedBox(
          height: 272,
          child: DesktopHorizontalPager(
            key: ValueKey<String>('detail-episodes:${selectedGroup.id}'),
            builder: (context, controller) => ListView.separated(
              controller: controller,
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              cacheExtent: _episodeCardWidth * 2,
              itemCount: selectedGroup.episodes.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(width: _episodeCardSpacing),
              itemBuilder: (context, index) {
                final episode = selectedGroup.episodes[index];
                final nodeKey = _episodeNodeKey(selectedGroup, episode, index);
                final episodeFocusNode = _episodeFocusNodes[nodeKey];
                return SizedBox(
                  width: _episodeCardWidth,
                  child: _DetailEpisodeCard(
                    item: episode,
                    seriesTarget: widget.seriesTarget,
                    focusNode: episodeFocusNode,
                    onFocused: () {
                      _ensureFocusNodeVisible(episodeFocusNode);
                    },
                    focusId: _episodeFocusId(episode, index),
                    autofocus: index == 0,
                  ),
                );
              },
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
    this.onFocused,
    this.focusNode,
    this.focusId,
    this.autofocus = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onFocused;
  final FocusNode? focusNode;
  final String? focusId;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return StarflowChipButton(
      label: label,
      selected: selected,
      onPressed: onTap,
      onFocused: onFocused,
      focusNode: focusNode,
      focusId: focusId,
      autofocus: autofocus,
    );
  }
}

class _DetailEpisodeCard extends ConsumerWidget {
  const _DetailEpisodeCard({
    required this.item,
    required this.seriesTarget,
    this.onFocused,
    this.focusNode,
    this.focusId,
    this.autofocus = false,
  });

  final MediaItem item;
  final MediaDetailTarget seriesTarget;
  final VoidCallback? onFocused;
  final FocusNode? focusNode;
  final String? focusId;
  final bool autofocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playbackEntry =
        ref.watch(playbackEntryForMediaItemProvider(item)).value;
    final badgeText = _episodeBadgeText(item, playbackEntry);
    final summary = _episodeSummary(
      item,
      seriesTarget: seriesTarget,
    );
    final titleText = _episodeTitleText(item);
    final needsFileSizeResolution =
        _needsEpisodeDisplayFileSizeResolution(item);
    final resolvedFileSizeBytes = needsFileSizeResolution
        ? ref
            .watch(
              detailEpisodeDisplayFileSizeProvider(
                _DetailEpisodeFileSizeRequest(item),
              ),
            )
            .maybeWhen(
              data: (value) => value,
              orElse: () => null,
            )
        : item.fileSizeBytes;
    final fileSizeText = _episodeDisplayFileSizeLabel(resolvedFileSizeBytes);

    void onOpenDetail() {
      context.pushNamed(
        'detail',
        extra: episodeToDetailTarget(item, seriesTarget: seriesTarget),
      );
    }

    final effectiveFocusId = focusId?.trim() ?? '';
    return TvFocusableAction(
      onPressed: onOpenDetail,
      onFocused: onFocused,
      focusNode: focusNode,
      focusId: effectiveFocusId.isEmpty ? null : effectiveFocusId,
      autofocus: autofocus,
      borderRadius: BorderRadius.circular(24),
      visualStyle: TvFocusVisualStyle.floating,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
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
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                          shadows: [
                            Shadow(
                              color: Color(0xAA000000),
                              blurRadius: 16,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
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
      ),
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
    final fileName = _episodeFileName(item);
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

bool _needsEpisodeDisplayFileSizeResolution(MediaItem item) {
  return PlaybackTarget.fromMediaItem(item).needsResolution;
}

int? _fallbackEpisodeDisplayFileSizeBytes(
  MediaItem item,
  PlaybackTarget target,
) {
  if (target.sourceKind == MediaSourceKind.nas && target.needsResolution) {
    return null;
  }
  return item.fileSizeBytes;
}

String _episodeFileName(MediaItem item) {
  for (final value in [item.actualAddress, item.streamUrl]) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final uri = Uri.tryParse(trimmed);
    final rawPath = uri != null && uri.hasScheme ? uri.path : trimmed;
    final normalized = rawPath.replaceAll('\\', '/').trim();
    if (normalized.isEmpty) {
      continue;
    }
    final fileName = normalized.split('/').last.trim();
    if (fileName.isEmpty) {
      continue;
    }
    try {
      return Uri.decodeComponent(fileName);
    } on ArgumentError {
      return fileName;
    }
  }
  return '';
}

class _DetailEpisodeArtwork extends StatelessWidget {
  const _DetailEpisodeArtwork({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final artwork = _resolveEpisodeArtworkAsset(item);
    if (artwork.url.isNotEmpty) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: AppNetworkImage(
          artwork.url,
          headers: artwork.headers,
          fallbackSources: _buildEpisodeArtworkFallbackSources(item),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _DetailEpisodeArtworkFallback(item: item),
        ),
      );
    }
    return _DetailEpisodeArtworkFallback(item: item);
  }
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

class _DetailImageAsset {
  const _DetailImageAsset({
    required this.url,
    this.headers = const {},
  });

  final String url;
  final Map<String, String> headers;
}

_DetailImageAsset _resolveEpisodeArtworkAsset(MediaItem item) {
  if (item.backdropUrl.trim().isNotEmpty) {
    return _DetailImageAsset(
      url: item.backdropUrl.trim(),
      headers: item.backdropHeaders,
    );
  }
  if (item.bannerUrl.trim().isNotEmpty) {
    return _DetailImageAsset(
      url: item.bannerUrl.trim(),
      headers: item.bannerHeaders,
    );
  }
  if (item.extraBackdropUrls.isNotEmpty) {
    return _DetailImageAsset(
      url: item.extraBackdropUrls.first,
      headers: item.extraBackdropHeaders,
    );
  }
  if (item.posterUrl.trim().isNotEmpty) {
    return _DetailImageAsset(
      url: item.posterUrl.trim(),
      headers: item.posterHeaders,
    );
  }
  return const _DetailImageAsset(url: '');
}

List<AppNetworkImageSource> _buildEpisodeArtworkFallbackSources(
  MediaItem item,
) {
  final sources = <AppNetworkImageSource>[];
  final seen = <String>{item.backdropUrl.trim()};

  void add(String url, Map<String, String> headers) {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty || !seen.add(trimmedUrl)) {
      return;
    }
    sources.add(
      AppNetworkImageSource(
        url: trimmedUrl,
        headers: headers,
      ),
    );
  }

  add(item.bannerUrl, item.bannerHeaders);
  for (final url in item.extraBackdropUrls) {
    add(url, item.extraBackdropHeaders);
  }
  add(item.posterUrl, item.posterHeaders);
  return sources;
}
