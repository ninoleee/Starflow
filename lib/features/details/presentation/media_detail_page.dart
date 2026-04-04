import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

final seriesBrowserProvider =
    FutureProvider.family<_SeriesBrowserState?, MediaDetailTarget>((
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
      .toList();
  if (seasons.isEmpty) {
    final episodes = children
        .where((item) => item.itemType.trim().toLowerCase() == 'episode')
        .toList();
    if (episodes.isEmpty) {
      return null;
    }
    return _SeriesBrowserState(
      groups: [
        _EpisodeGroup(
          id: 'all',
          title: '全部剧集',
          seasonNumber: null,
          episodes: _sortEpisodes(episodes),
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

  final groups = <_EpisodeGroup>[];
  for (var index = 0; index < seasons.length; index++) {
    final season = seasons[index];
    final episodes = seasonEpisodes[index]
        .where((item) => item.itemType.trim().toLowerCase() == 'episode')
        .toList();
    if (episodes.isEmpty) {
      continue;
    }
    groups.add(
      _EpisodeGroup(
        id: season.id,
        title: season.title,
        seasonNumber: season.seasonNumber,
        episodes: _sortEpisodes(episodes),
      ),
    );
  }

  return groups.isEmpty ? null : _SeriesBrowserState(groups: groups);
});

class MediaDetailPage extends ConsumerStatefulWidget {
  const MediaDetailPage({super.key, required this.target});

  final MediaDetailTarget target;

  @override
  ConsumerState<MediaDetailPage> createState() => _MediaDetailPageState();
}

class _MediaDetailPageState extends ConsumerState<MediaDetailPage> {
  String _selectedSeasonId = '';

  @override
  void didUpdateWidget(covariant MediaDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target.itemId != widget.target.itemId) {
      _selectedSeasonId = '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.target;
    final seriesAsync = ref.watch(seriesBrowserProvider(target));

    return Scaffold(
      backgroundColor: const Color(0xFF030914),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const SizedBox.shrink(),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF07121F),
              Color(0xFF08101A),
              Color(0xFF030914),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _HeroSection(target: target),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (target.isSeries)
                    seriesAsync.when(
                      data: (browser) {
                        if (browser == null || browser.groups.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        final selectedGroup =
                            _resolveSelectedGroup(browser.groups);
                        return _DetailBlock(
                          title: '剧集',
                          child: _EpisodeBrowser(
                            groups: browser.groups,
                            selectedGroupId: selectedGroup.id,
                            onSeasonSelected: (groupId) {
                              setState(() {
                                _selectedSeasonId = groupId;
                              });
                            },
                          ),
                        );
                      },
                      loading: () => const _DetailBlock(
                        title: '剧集',
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child:
                                CircularProgressIndicator(color: Colors.white),
                          ),
                        ),
                      ),
                      error: (error, stackTrace) => _DetailBlock(
                        title: '剧集',
                        child: Text(
                          '加载剧集失败：$error',
                          style: const TextStyle(
                            color: Color(0xFF90A0BD),
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  if (target.overview.trim().isNotEmpty)
                    _DetailBlock(
                      title: '剧情简介',
                      child: Text(
                        target.overview,
                        style: const TextStyle(
                          color: Color(0xFFDCE6F8),
                          fontSize: 15,
                          height: 1.7,
                        ),
                      ),
                    ),
                  if (target.directors.isNotEmpty || target.actors.isNotEmpty)
                    _DetailBlock(
                      title: '演职员',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (target.directors.isNotEmpty) ...[
                            const _InfoLabel('导演'),
                            const SizedBox(height: 10),
                            _NameRail(names: target.directors),
                          ],
                          if (target.directors.isNotEmpty &&
                              target.actors.isNotEmpty)
                            const SizedBox(height: 18),
                          if (target.actors.isNotEmpty) ...[
                            const _InfoLabel('演员'),
                            const SizedBox(height: 10),
                            _NameRail(names: target.actors),
                          ],
                        ],
                      ),
                    ),
                  if (target.sourceName.trim().isNotEmpty ||
                      target.availabilityLabel.trim().isNotEmpty)
                    _DetailBlock(
                      title: '资源信息',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (target.availabilityLabel.trim().isNotEmpty)
                            _FactRow(
                              label: '状态',
                              value: target.availabilityLabel,
                            ),
                          if (target.sourceName.trim().isNotEmpty) ...[
                            if (target.availabilityLabel.trim().isNotEmpty)
                              const SizedBox(height: 12),
                            _FactRow(
                              label: '来源',
                              value: target.sourceKind == null
                                  ? target.sourceName
                                  : '${target.sourceKind!.label} · ${target.sourceName}',
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  _EpisodeGroup _resolveSelectedGroup(List<_EpisodeGroup> groups) {
    if (_selectedSeasonId.trim().isNotEmpty) {
      for (final group in groups) {
        if (group.id == _selectedSeasonId) {
          return group;
        }
      }
    }
    return groups.first;
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.target});

  final MediaDetailTarget target;

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final topInset = MediaQuery.paddingOf(context).top;
    final heroHeight = math.max(560.0, math.min(screenHeight * 0.76, 760.0));
    final metadata = <String>[
      if (target.year > 0) '${target.year}',
      if (target.durationLabel.trim().isNotEmpty) target.durationLabel,
      ...target.genres.take(3).where((item) => item.trim().isNotEmpty),
    ];
    final peopleLine = <String>[
      if (target.directors.isNotEmpty)
        '导演 ${target.directors.take(2).join(' / ')}',
      if (target.actors.isNotEmpty) '演员 ${target.actors.take(3).join(' / ')}',
    ].join('  ·  ');

    return SizedBox(
      height: heroHeight,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          _BackdropImage(imageUrl: target.posterUrl),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withValues(alpha: 0.08),
                  Colors.black.withValues(alpha: 0.22),
                  const Color(0xFF030914),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.48, 1],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withValues(alpha: 0.52),
                  Colors.black.withValues(alpha: 0.18),
                  Colors.transparent,
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Padding(
              padding: EdgeInsets.only(top: topInset + 44),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 760;
                  final poster = _PosterArt(posterUrl: target.posterUrl);
                  final content = _HeroContent(
                    target: target,
                    metadata: metadata,
                    peopleLine: peopleLine,
                  );

                  if (isCompact) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        poster,
                        const SizedBox(height: 18),
                        content,
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      poster,
                      const SizedBox(width: 24),
                      Expanded(child: content),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroContent extends StatelessWidget {
  const _HeroContent({
    required this.target,
    required this.metadata,
    required this.peopleLine,
  });

  final MediaDetailTarget target;
  final List<String> metadata;
  final String peopleLine;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (metadata.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: metadata
                  .map(
                    (item) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Text(
                        item,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          if (metadata.isNotEmpty) const SizedBox(height: 14),
          Text(
            target.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 38,
                  height: 1.04,
                ),
          ),
          if (peopleLine.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              peopleLine,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFD7E2F8),
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ],
          if (target.overview.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              target.overview,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFE7EEFF),
                fontSize: 15,
                height: 1.6,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (target.isPlayable)
                FilledButton.icon(
                  onPressed: () {
                    context.pushNamed('player', extra: target.playbackTarget);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF081120),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 15,
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('立即播放'),
                ),
              if (!target.isPlayable && target.searchQuery.trim().isNotEmpty)
                FilledButton.icon(
                  onPressed: () {
                    context.goNamed(
                      'search',
                      queryParameters: {'q': target.searchQuery},
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF081120),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 15,
                    ),
                  ),
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('搜索资源'),
                ),
              if (target.isPlayable && target.searchQuery.trim().isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () {
                    context.goNamed(
                      'search',
                      queryParameters: {'q': target.searchQuery},
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.24),
                    ),
                    backgroundColor: Colors.white.withValues(alpha: 0.06),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 15,
                    ),
                  ),
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('搜索资源'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BackdropImage extends StatelessWidget {
  const _BackdropImage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.trim().isEmpty) {
      return const ColoredBox(color: Color(0xFF0A1423));
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          imageUrl,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          errorBuilder: (context, error, stackTrace) {
            return const ColoredBox(color: Color(0xFF0A1423));
          },
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF081120).withValues(alpha: 0.28),
          ),
        ),
      ],
    );
  }
}

class _PosterArt extends StatelessWidget {
  const _PosterArt({required this.posterUrl});

  final String posterUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 168,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: AspectRatio(
          aspectRatio: 0.69,
          child: Container(
            color: const Color(0xFF0D192A),
            child: posterUrl.trim().isEmpty
                ? const Icon(
                    Icons.movie_creation_outlined,
                    size: 42,
                    color: Colors.white70,
                  )
                : Image.network(
                    posterUrl,
                    fit: BoxFit.cover,
                    cacheWidth: 720,
                    filterQuality: FilterQuality.low,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Icon(
                          Icons.movie_creation_outlined,
                          size: 42,
                          color: Colors.white70,
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

class _SeriesBrowserState {
  const _SeriesBrowserState({required this.groups});

  final List<_EpisodeGroup> groups;
}

class _EpisodeGroup {
  const _EpisodeGroup({
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

List<MediaItem> _sortEpisodes(List<MediaItem> items) {
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

class _EpisodeBrowser extends StatelessWidget {
  const _EpisodeBrowser({
    required this.groups,
    required this.selectedGroupId,
    required this.onSeasonSelected,
  });

  final List<_EpisodeGroup> groups;
  final String selectedGroupId;
  final ValueChanged<String> onSeasonSelected;

  @override
  Widget build(BuildContext context) {
    _EpisodeGroup selectedGroup = groups.first;
    for (final group in groups) {
      if (group.id == selectedGroupId) {
        selectedGroup = group;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (groups.length > 1) ...[
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: groups.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final group = groups[index];
                final selected = group.id == selectedGroup.id;
                return _SeasonChip(
                  label: group.label,
                  selected: selected,
                  onTap: () => onSeasonSelected(group.id),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
        SizedBox(
          height: 272,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: selectedGroup.episodes.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final episode = selectedGroup.episodes[index];
              return SizedBox(
                width: 292,
                child: _EpisodeCard(item: episode),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SeasonChip extends StatelessWidget {
  const _SeasonChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color:
                selected ? Colors.white : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? const Color(0xFF081120) : Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final label = _episodeMeta(item);
    final summary = _episodeSummary(item);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: item.isPlayable
            ? () {
                context.pushNamed(
                  'player',
                  extra: item.isPlayable ? _itemToPlaybackTarget(item) : null,
                );
              }
            : null,
        child: Ink(
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
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _EpisodeArtwork(item: item),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.12),
                            Colors.black.withValues(alpha: 0.42),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      bottom: 12,
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
                          item.episodeNumber != null
                              ? '第 ${item.episodeNumber} 集'
                              : '剧集',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: Icon(
                        item.isPlayable
                            ? Icons.play_circle_fill_rounded
                            : Icons.lock_outline_rounded,
                        color: item.isPlayable
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.42),
                        size: 28,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (label.trim().isNotEmpty) ...[
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF90A0BD),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Text(
                          summary,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFD7E0F1),
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _episodeMeta(MediaItem item) {
    final entries = <String>[
      if (item.seasonNumber != null && item.episodeNumber != null)
        'S${item.seasonNumber!.toString().padLeft(2, '0')}E${item.episodeNumber!.toString().padLeft(2, '0')}',
      if (item.durationLabel.trim().isNotEmpty && item.durationLabel != '时长未知')
        item.durationLabel,
    ];
    return entries.join(' · ');
  }

  String _episodeSummary(MediaItem item) {
    if (item.overview.trim().isNotEmpty) {
      return item.overview;
    }
    final fallback = <String>[
      if (item.seasonNumber != null && item.episodeNumber != null)
        '第 ${item.seasonNumber} 季 第 ${item.episodeNumber} 集',
      if (item.durationLabel.trim().isNotEmpty && item.durationLabel != '时长未知')
        item.durationLabel,
      if (!item.isPlayable) '当前没有可直接播放的资源',
    ];
    if (fallback.isEmpty) {
      return '暂无简介';
    }
    return fallback.join(' · ');
  }
}

class _EpisodeArtwork extends StatelessWidget {
  const _EpisodeArtwork({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    if (item.posterUrl.trim().isNotEmpty) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Image.network(
          item.posterUrl,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _EpisodeArtworkFallback(
            item: item,
          ),
        ),
      );
    }
    return _EpisodeArtworkFallback(item: item);
  }
}

class _EpisodeArtworkFallback extends StatelessWidget {
  const _EpisodeArtworkFallback({required this.item});

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

PlaybackTarget _itemToPlaybackTarget(MediaItem item) {
  return PlaybackTarget.fromMediaItem(item);
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _InfoLabel extends StatelessWidget {
  const _InfoLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF8FA0BD),
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _NameRail extends StatelessWidget {
  const _NameRail({required this.names});

  final List<String> names;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: names
          .where((item) => item.trim().isNotEmpty)
          .map(
            (item) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
              child: Text(
                item,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8FA0BD),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Color(0xFFE6EDFD),
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
