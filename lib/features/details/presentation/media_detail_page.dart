import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/domain/media_title_matcher.dart';
import 'package:starflow/features/metadata/data/imdb_rating_client.dart';
import 'package:starflow/features/metadata/data/metadata_match_resolver.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

final enrichedDetailTargetProvider =
    FutureProvider.family<MediaDetailTarget, MediaDetailTarget>((
  ref,
  target,
) async {
  final settings = ref.watch(appSettingsProvider);
  final imdbEnabled = ref.watch(
    appSettingsProvider.select((settings) => settings.imdbRatingMatchEnabled),
  );
  final query =
      target.searchQuery.trim().isEmpty ? target.title : target.searchQuery;

  var resolved = target;
  MetadataMatchResult? metadataMatch;

  if (resolved.needsLibraryMatch || resolved.needsMetadataMatch) {
    metadataMatch = await _tryPreferredMetadataMatch(
      metadataMatchResolver: ref.read(metadataMatchResolverProvider),
      settings: settings,
      target: resolved,
      query: query,
    );
  }

  if (resolved.needsLibraryMatch) {
    final matchedTarget = await _tryMatchLibraryResource(
      mediaRepository: ref.read(mediaRepositoryProvider),
      target: resolved,
      query: query,
      metadataMatch: metadataMatch,
    );
    if (matchedTarget != null) {
      resolved = matchedTarget;
    }
  }

  if (resolved.needsMetadataMatch && metadataMatch != null) {
    resolved = _applyMetadataMatch(resolved, metadataMatch);
  }

  if (imdbEnabled && resolved.needsImdbRatingMatch) {
    try {
      final ratingMatch = await ref.read(imdbRatingClientProvider).matchRating(
            query: query,
            year: resolved.year,
            preferSeries: resolved.isSeries,
            imdbId: resolved.imdbId,
          );
      if (ratingMatch != null) {
        final nextRatings = [...resolved.ratingLabels];
        final nextRatingLabel = ratingMatch.ratingLabel.trim();
        final hasSameRating = nextRatings.any(
          (label) => label.toLowerCase() == nextRatingLabel.toLowerCase(),
        );
        if (nextRatingLabel.isNotEmpty && !hasSameRating) {
          nextRatings.add(nextRatingLabel);
        }
        resolved = resolved.copyWith(
          imdbId: resolved.imdbId.trim().isEmpty
              ? ratingMatch.imdbId
              : resolved.imdbId,
          ratingLabels: nextRatings,
        );
      }
    } catch (_) {}
  }

  return resolved;
});

Future<MetadataMatchResult?> _tryPreferredMetadataMatch({
  required MetadataMatchResolver metadataMatchResolver,
  required AppSettings settings,
  required MediaDetailTarget target,
  required String query,
}) async {
  try {
    return await metadataMatchResolver.match(
      settings: settings,
      request: MetadataMatchRequest(
        query: query,
        doubanId: target.doubanId,
        year: target.year,
        preferSeries: target.isSeries,
        actors: target.actors,
      ),
    );
  } catch (_) {
    return null;
  }
}

Future<MediaDetailTarget?> _tryMatchLibraryResource({
  required MediaRepository mediaRepository,
  required MediaDetailTarget target,
  required String query,
  MetadataMatchResult? metadataMatch,
}) async {
  const detailLibraryMatchLimit = 2000;

  try {
    final library =
        await mediaRepository.fetchLibrary(limit: detailLibraryMatchLimit);
    final matched = matchMediaItemByTitles(
      library,
      titles: [
        target.title,
        query,
        if (metadataMatch != null) ...metadataMatch.titlesForMatching,
      ],
      year: target.year > 0 ? target.year : (metadataMatch?.year ?? 0),
    );
    if (matched == null) {
      return null;
    }

    final matchedTarget = MediaDetailTarget.fromMediaItem(
      matched,
      availabilityLabel:
          '资源已就绪：${matched.sourceKind.label} · ${matched.sourceName}',
      searchQuery: query,
    );
    return _mergeMatchedLibraryTarget(
      current: target,
      matched: matchedTarget,
    );
  } catch (_) {
    return null;
  }
}

MediaDetailTarget _mergeMatchedLibraryTarget({
  required MediaDetailTarget current,
  required MediaDetailTarget matched,
}) {
  return matched.copyWith(
    title: current.title,
    posterUrl: _firstNonEmpty(current.posterUrl, matched.posterUrl),
    overview: current.hasUsefulOverview ? current.overview : matched.overview,
    year: current.year > 0 ? current.year : matched.year,
    durationLabel: current.durationLabel.trim().isNotEmpty
        ? current.durationLabel
        : matched.durationLabel,
    genres: current.genres.isNotEmpty ? current.genres : matched.genres,
    directors:
        current.directors.isNotEmpty ? current.directors : matched.directors,
    actors: current.actors.isNotEmpty ? current.actors : matched.actors,
    actorProfiles: current.actorProfiles.isNotEmpty
        ? current.actorProfiles
        : matched.actorProfiles,
    ratingLabels: _mergeLabels(
      matched.ratingLabels,
      current.ratingLabels,
    ),
    doubanId: current.doubanId,
    imdbId: current.imdbId,
  );
}

MediaDetailTarget _applyMetadataMatch(
  MediaDetailTarget target,
  MetadataMatchResult match,
) {
  return target.copyWith(
    posterUrl:
        target.posterUrl.trim().isEmpty ? match.posterUrl : target.posterUrl,
    overview: target.hasUsefulOverview ? target.overview : match.overview,
    year: target.year > 0 ? target.year : match.year,
    durationLabel: target.durationLabel.trim().isEmpty
        ? match.durationLabel
        : target.durationLabel,
    genres: target.genres.isNotEmpty ? target.genres : match.genres,
    directors: target.directors.isNotEmpty ? target.directors : match.directors,
    actors: target.actors.isNotEmpty ? target.actors : match.actors,
    actorProfiles: target.actorProfiles.isNotEmpty
        ? target.actorProfiles
        : match.actorProfiles
            .map(
              (item) => MediaPersonProfile(
                name: item.name,
                avatarUrl: item.avatarUrl,
              ),
            )
            .toList(),
    ratingLabels: _mergeLabels(target.ratingLabels, match.ratingLabels),
    doubanId: target.doubanId.trim().isEmpty ? match.doubanId : target.doubanId,
    imdbId: target.imdbId.trim().isEmpty ? match.imdbId : target.imdbId,
  );
}

String _firstNonEmpty(String primary, String fallback) {
  final primaryTrimmed = primary.trim();
  if (primaryTrimmed.isNotEmpty) {
    return primaryTrimmed;
  }
  return fallback.trim();
}

List<String> _mergeLabels(List<String> primary, List<String> secondary) {
  final seen = <String>{};
  final merged = <String>[];
  for (final value in [...primary, ...secondary]) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final key = trimmed.toLowerCase();
    if (seen.add(key)) {
      merged.add(trimmed);
    }
  }
  return merged;
}

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
  MediaDetailTarget? _manualOverrideTarget;
  bool _isMatchingLocalResource = false;

  @override
  void didUpdateWidget(covariant MediaDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target.itemId != widget.target.itemId ||
        oldWidget.target.title != widget.target.title ||
        oldWidget.target.searchQuery != widget.target.searchQuery) {
      _selectedSeasonId = '';
      _manualOverrideTarget = null;
      _isMatchingLocalResource = false;
    }
  }

  Future<void> _matchLocalResource(MediaDetailTarget currentTarget) async {
    if (_isMatchingLocalResource) {
      return;
    }

    setState(() {
      _isMatchingLocalResource = true;
    });

    final settings = ref.read(appSettingsProvider);
    final query = currentTarget.searchQuery.trim().isEmpty
        ? currentTarget.title
        : currentTarget.searchQuery;
    final metadataMatch = await _tryPreferredMetadataMatch(
      metadataMatchResolver: ref.read(metadataMatchResolverProvider),
      settings: settings,
      target: currentTarget,
      query: query,
    );

    final matched = await _tryMatchLibraryResource(
      mediaRepository: ref.read(mediaRepositoryProvider),
      target: currentTarget,
      query: query,
      metadataMatch: metadataMatch,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isMatchingLocalResource = false;
      if (matched != null) {
        _manualOverrideTarget = matched;
      }
    });

    final messenger = ScaffoldMessenger.of(context);
    if (matched == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('没有找到可匹配的本地资源')),
      );
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(
            '已匹配到 ${matched.sourceKind?.label ?? '资源'} · ${matched.sourceName}'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final seedTarget = _manualOverrideTarget ?? widget.target;
    final targetAsync = ref.watch(enrichedDetailTargetProvider(seedTarget));
    final target = targetAsync.valueOrNull ?? seedTarget;
    final seriesAsync = ref.watch(seriesBrowserProvider(target));

    return Scaffold(
      backgroundColor: const Color(0xFF030914),
      body: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
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
                  padding: EdgeInsets.zero,
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
                                child: CircularProgressIndicator(
                                    color: Colors.white),
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
                      if (target.directors.isNotEmpty ||
                          target.resolvedActorProfiles.isNotEmpty)
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
                                  target.resolvedActorProfiles.isNotEmpty)
                                const SizedBox(height: 18),
                              if (target.resolvedActorProfiles.isNotEmpty) ...[
                                const _InfoLabel('演员'),
                                const SizedBox(height: 10),
                                _ActorRail(
                                  actors: target.resolvedActorProfiles,
                                ),
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
                              if (_shouldShowLocalResourceMatcher(target)) ...[
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: _isMatchingLocalResource
                                        ? null
                                        : () => _matchLocalResource(target),
                                    icon: _isMatchingLocalResource
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.link_rounded,
                                            size: 16,
                                          ),
                                    label: Text(
                                      _isMatchingLocalResource
                                          ? '匹配中...'
                                          : '匹配本地资源',
                                    ),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 0,
                                        vertical: 0,
                                      ),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ),
                              ],
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
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: OverlayToolbar(
              leadingColor: Colors.white,
              onBack: () => context.pop(),
            ),
          ),
        ],
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

bool _shouldShowLocalResourceMatcher(MediaDetailTarget target) {
  final availability = target.availabilityLabel.trim();
  return target.needsLibraryMatch &&
      !target.isPlayable &&
      (availability.isEmpty || availability == '无');
}

class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.target});

  final MediaDetailTarget target;

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final heroHeight = math.max(560.0, math.min(screenHeight * 0.76, 760.0));
    final metadata = <String>[
      ...target.ratingLabels.where((item) => item.trim().isNotEmpty).take(2),
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
              padding: EdgeInsets.only(top: kToolbarHeight),
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
    final badgeText = _episodeBadgeText(item);
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
                      right: 46,
                      top: 14,
                      child: Text(
                        item.title,
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
                      Expanded(
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

  String _episodeBadgeText(MediaItem item) {
    final entries = <String>[
      item.episodeNumber != null ? '第 ${item.episodeNumber} 集' : '剧集',
      if (item.durationLabel.trim().isNotEmpty && item.durationLabel != '时长未知')
        item.durationLabel,
      if (_progressLabel(item).trim().isNotEmpty) _progressLabel(item),
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

  String _progressLabel(MediaItem item) {
    final progress = item.playbackProgress;
    if (progress == null || progress <= 0) {
      return '';
    }
    if (progress >= 0.995) {
      return '已看完';
    }
    return '已看 ${(progress * 100).round()}%';
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

class _ActorRail extends StatelessWidget {
  const _ActorRail({required this.actors});

  final List<MediaPersonProfile> actors;

  @override
  Widget build(BuildContext context) {
    final visibleActors = actors
        .where((item) => item.name.trim().isNotEmpty)
        .toList(growable: false);
    if (visibleActors.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 128,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: visibleActors.length,
        separatorBuilder: (context, index) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final actor = visibleActors[index];
          return SizedBox(
            width: 86,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _ActorAvatar(actor: actor),
                const SizedBox(height: 10),
                Text(
                  actor.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ActorAvatar extends StatelessWidget {
  const _ActorAvatar({required this.actor});

  final MediaPersonProfile actor;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = actor.avatarUrl.trim();
    return Container(
      width: 74,
      height: 74,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF162233),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: avatarUrl.isEmpty
          ? Center(
              child: Text(
                _actorInitial(actor.name),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : Image.network(
              avatarUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Center(
                  child: Text(
                    _actorInitial(actor.name),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

String _actorInitial(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    return '?';
  }
  return String.fromCharCode(trimmed.runes.first).toUpperCase();
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
