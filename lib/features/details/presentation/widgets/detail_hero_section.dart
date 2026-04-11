import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/app_network_image.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/playback/application/active_playback_cleanup.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
import 'package:starflow/features/playback/domain/playback_memory_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

class DetailHeroSection extends ConsumerWidget {
  const DetailHeroSection({
    super.key,
    required this.target,
    required this.simplifyVisualEffects,
    required this.isTelevision,
    this.artworkFocusNode,
    this.playFocusNode,
  });

  final MediaDetailTarget target;
  final bool simplifyVisualEffects;
  final bool isTelevision;
  final FocusNode? artworkFocusNode;
  final FocusNode? playFocusNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final isCompact = screenWidth < 760;
    final heroHeight = simplifyVisualEffects
        ? math.max(440.0, math.min(screenHeight * 0.62, 620.0))
        : math.max(560.0, math.min(screenHeight * 0.76, 760.0));
    final hasHeroLogo = target.logoUrl.trim().isNotEmpty;
    final metadata = <String>[
      ...target.ratingLabels.where((item) => item.trim().isNotEmpty),
      if (target.year > 0) '${target.year}',
      if (target.durationLabel.trim().isNotEmpty) target.durationLabel,
      ...target.genres.take(3).where((item) => item.trim().isNotEmpty),
    ];
    final peopleLine = <String>[
      if (target.directors.isNotEmpty)
        '导演 ${target.directors.take(2).join(' / ')}',
      if (target.actors.isNotEmpty) '演员 ${target.actors.take(3).join(' / ')}',
    ].join('  ·  ');
    final overlayWidthFactor = isCompact
        ? 1.0
        : simplifyVisualEffects
            ? (hasHeroLogo ? 0.62 : 0.54)
            : (hasHeroLogo ? 0.76 : 0.64);
    final overlayHeightFactor = isCompact
        ? (simplifyVisualEffects ? 0.64 : 0.74)
        : (simplifyVisualEffects ? 0.74 : 0.84);
    final Gradient overlayGradient = simplifyVisualEffects
        ? RadialGradient(
            center: isCompact
                ? const Alignment(-0.72, 0.96)
                : const Alignment(-0.94, 0.96),
            radius: isCompact ? 1.06 : 0.98,
            colors: [
              Colors.black.withValues(alpha: hasHeroLogo ? 0.76 : 0.68),
              Colors.black.withValues(alpha: hasHeroLogo ? 0.28 : 0.22),
              Colors.transparent,
            ],
            stops: const [0, 0.46, 1],
          )
        : RadialGradient(
            center: isCompact
                ? const Alignment(-0.72, 0.96)
                : const Alignment(-0.96, 0.96),
            radius: isCompact ? 1.22 : 1.08,
            colors: [
              Colors.black.withValues(
                alpha: hasHeroLogo ? 0.82 : 0.74,
              ),
              Colors.black.withValues(
                alpha: hasHeroLogo ? 0.44 : 0.32,
              ),
              Colors.transparent,
            ],
            stops: const [0, 0.5, 1],
          );
    final resumeEntry =
        ref.watch(playbackResumeForDetailTargetProvider(target)).value;
    final showResumeAction =
        resumeEntry != null && (target.isSeries || resumeEntry.canResume);
    final primaryPlaybackTarget = resolvePrimaryPlaybackTarget(
      target,
      resumeEntry,
      preferResume: showResumeAction,
    );
    final hasHeroAction = primaryPlaybackTarget != null;
    final primaryBackdropAsset = resolvePrimaryBackdropAsset(target);
    final heroArtwork = Stack(
      fit: StackFit.expand,
      children: [
        DetailBackdropImage(
          imageUrl: primaryBackdropAsset.url,
          imageHeaders: primaryBackdropAsset.headers,
          fallbackSources: buildPrimaryBackdropFallbackSources(target),
        ),
        IgnorePointer(
          child: Align(
            alignment: Alignment.bottomLeft,
            child: FractionallySizedBox(
              widthFactor: overlayWidthFactor,
              heightFactor: overlayHeightFactor,
              alignment: Alignment.bottomLeft,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: overlayGradient,
                ),
              ),
            ),
          ),
        ),
      ],
    );

    return SizedBox(
      height: heroHeight,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          if (!isTelevision)
            heroArtwork
          else
            TvDirectionalActionPanel(
              onDirection: (direction) {
                switch (direction) {
                  case TraversalDirection.down:
                    return requestDetailFocus([playFocusNode]);
                  case TraversalDirection.left:
                  case TraversalDirection.right:
                  case TraversalDirection.up:
                    return false;
                }
              },
              child: TvFocusableAction(
                onPressed: () {},
                focusNode: artworkFocusNode,
                focusId: 'detail:hero:artwork',
                autofocus: !hasHeroAction,
                borderRadius: BorderRadius.zero,
                visualStyle: TvFocusVisualStyle.subtle,
                child: heroArtwork,
              ),
            ),
          Positioned(
            left: 16,
            right: 16,
            bottom: simplifyVisualEffects ? 18 : 24,
            child: Padding(
              padding: const EdgeInsets.only(top: kToolbarHeight),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final content = DetailHeroContent(
                    target: target,
                    metadata: metadata,
                    peopleLine: peopleLine,
                    simplifyVisualEffects: simplifyVisualEffects,
                    artworkFocusNode: artworkFocusNode,
                    playFocusNode: playFocusNode,
                  );

                  if (isCompact) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [content],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [Expanded(child: content)],
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

class DetailHeroContent extends ConsumerWidget {
  const DetailHeroContent({
    super.key,
    required this.target,
    required this.metadata,
    required this.peopleLine,
    required this.simplifyVisualEffects,
    this.artworkFocusNode,
    this.playFocusNode,
  });

  final MediaDetailTarget target;
  final List<String> metadata;
  final String peopleLine;
  final bool simplifyVisualEffects;
  final FocusNode? artworkFocusNode;
  final FocusNode? playFocusNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    final hasLogo = target.logoUrl.trim().isNotEmpty;
    final primaryTitle = _resolveDetailHeroPrimaryTitle(target);
    final episodeTitle = _resolveDetailHeroEpisodeTitle(target);
    final resumeEntry =
        ref.watch(playbackResumeForDetailTargetProvider(target)).value;
    final showResumeAction =
        resumeEntry != null && (target.isSeries || resumeEntry.canResume);
    final primaryPlaybackTarget = resolvePrimaryPlaybackTarget(
      target,
      resumeEntry,
      preferResume: showResumeAction,
    );
    final primaryPlaybackLabel = showResumeAction ? '继续播放' : '立即播放';
    final metadataChipPadding = EdgeInsets.symmetric(
      horizontal: simplifyVisualEffects ? 10 : 11,
      vertical: simplifyVisualEffects ? 5 : 6,
    );

    Widget wrapTelevisionDirectionalHandling({
      required Widget child,
      required bool Function(TraversalDirection direction) onDirection,
    }) {
      return TvDirectionalActionPanel(
        enabled: isTelevision,
        onDirection: onDirection,
        child: child,
      );
    }

    final titleStyle = Theme.of(context).textTheme.headlineSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: simplifyVisualEffects ? 32 : 38,
          height: 1.04,
        );
    final episodeTitleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          color: const Color(0xFFE7EEFF),
          fontWeight: FontWeight.w600,
          fontSize: simplifyVisualEffects ? 16 : 18,
          height: 1.25,
        );
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: hasLogo
            ? (simplifyVisualEffects ? 680 : 760)
            : (simplifyVisualEffects ? 520 : 560),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!hasLogo && metadata.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: metadata
                  .map(
                    (item) => Container(
                      padding: metadataChipPadding,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(
                          alpha: simplifyVisualEffects ? 0.08 : 0.12,
                        ),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(
                            alpha: simplifyVisualEffects ? 0.05 : 0.08,
                          ),
                        ),
                      ),
                      child: Text(
                        item,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: simplifyVisualEffects ? 11.5 : 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          if (!hasLogo && metadata.isNotEmpty)
            SizedBox(height: simplifyVisualEffects ? 12 : 14),
          if (hasLogo)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: simplifyVisualEffects ? 460 : 520,
                maxHeight: simplifyVisualEffects ? 112 : 148,
              ),
              child: AppNetworkImage(
                target.logoUrl,
                headers: target.logoHeaders,
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                errorBuilder: (context, error, stackTrace) {
                  return Text(
                    primaryTitle,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  );
                },
              ),
            )
          else
            Text(
              primaryTitle,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: titleStyle,
            ),
          if (episodeTitle != null) ...[
            SizedBox(height: simplifyVisualEffects ? 8 : 10),
            Text(
              episodeTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: episodeTitleStyle,
            ),
          ],
          if (hasLogo && metadata.isNotEmpty) ...[
            SizedBox(height: simplifyVisualEffects ? 14 : 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: metadata
                  .map(
                    (item) => Container(
                      padding: metadataChipPadding,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(
                          alpha: simplifyVisualEffects ? 0.08 : 0.12,
                        ),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(
                            alpha: simplifyVisualEffects ? 0.05 : 0.08,
                          ),
                        ),
                      ),
                      child: Text(
                        item,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: simplifyVisualEffects ? 11.5 : 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (peopleLine.trim().isNotEmpty) ...[
            SizedBox(
              height: hasLogo
                  ? (simplifyVisualEffects ? 12 : 14)
                  : (simplifyVisualEffects ? 10 : 12),
            ),
            Text(
              peopleLine,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: const Color(0xFFD7E2F8),
                fontSize: simplifyVisualEffects ? 13 : 14,
                height: 1.45,
              ),
            ),
          ],
          SizedBox(
            height: hasLogo
                ? (simplifyVisualEffects ? 18 : 24)
                : (simplifyVisualEffects ? 16 : 20),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (primaryPlaybackTarget != null)
                isTelevision
                    ? wrapTelevisionDirectionalHandling(
                        onDirection: (direction) {
                          switch (direction) {
                            case TraversalDirection.right:
                              return true;
                            case TraversalDirection.left:
                            case TraversalDirection.down:
                              return false;
                            case TraversalDirection.up:
                              return requestDetailFocus([artworkFocusNode]);
                          }
                        },
                        child: TvAdaptiveButton(
                          label: primaryPlaybackLabel,
                          icon: Icons.play_arrow_rounded,
                          focusNode: playFocusNode,
                          focusId: 'detail:hero:play',
                          autofocus: true,
                          onPressed: () async {
                            await ActivePlaybackCleanupCoordinator.cleanupAll(
                              reason: 'open-new-playback',
                            );
                            if (!context.mounted) {
                              return;
                            }
                            context.pushNamed(
                              'player',
                              extra: primaryPlaybackTarget,
                            );
                          },
                        ),
                      )
                    : FilledButton.icon(
                        onPressed: () async {
                          await ActivePlaybackCleanupCoordinator.cleanupAll(
                            reason: 'open-new-playback',
                          );
                          if (!context.mounted) {
                            return;
                          }
                          context.pushNamed(
                            'player',
                            extra: primaryPlaybackTarget,
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
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(primaryPlaybackLabel),
                      ),
            ],
          ),
        ],
      ),
    );
  }
}

bool _isEpisodeDetailTarget(MediaDetailTarget target) {
  return target.itemType.trim().toLowerCase() == 'episode';
}

String _resolveDetailHeroPrimaryTitle(MediaDetailTarget target) {
  final title = target.title.trim();
  final query = target.searchQuery.trim();
  final seriesTitle = target.playbackTarget?.resolvedSeriesTitle.trim() ?? '';
  if (_isEpisodeDetailTarget(target)) {
    if (seriesTitle.isNotEmpty) {
      return seriesTitle;
    }
    if (query.isNotEmpty && query != title) {
      return query;
    }
  }
  if (title.isNotEmpty) {
    return title;
  }
  if (seriesTitle.isNotEmpty) {
    return seriesTitle;
  }
  if (query.isNotEmpty) {
    return query;
  }
  return '';
}

String? _resolveDetailHeroEpisodeTitle(MediaDetailTarget target) {
  if (!_isEpisodeDetailTarget(target)) {
    return null;
  }
  final episodeTitle = target.title.trim().isNotEmpty
      ? target.title.trim()
      : (target.playbackTarget?.title.trim() ?? '');
  if (episodeTitle.isEmpty) {
    return null;
  }
  final primaryTitle = _resolveDetailHeroPrimaryTitle(target);
  if (episodeTitle == primaryTitle) {
    return null;
  }
  return episodeTitle;
}

bool requestDetailFocus(Iterable<FocusNode?> nodes) {
  for (final node in nodes) {
    if (node == null || !node.canRequestFocus || node.context == null) {
      continue;
    }
    node.requestFocus();
    return true;
  }
  return false;
}

class DetailBackdropImage extends StatelessWidget {
  const DetailBackdropImage({
    super.key,
    required this.imageUrl,
    this.imageHeaders = const {},
    this.fallbackSources = const [],
  });

  final String imageUrl;
  final Map<String, String> imageHeaders;
  final List<AppNetworkImageSource> fallbackSources;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.trim().isEmpty) {
      return const ColoredBox(color: Color(0xFF0A1423));
    }

    return AppNetworkImage(
      imageUrl,
      headers: imageHeaders,
      fallbackSources: fallbackSources,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      errorBuilder: (context, error, stackTrace) {
        return const ColoredBox(color: Color(0xFF0A1423));
      },
    );
  }
}

class DetailHeroImageAsset {
  const DetailHeroImageAsset({
    required this.url,
    this.headers = const {},
  });

  final String url;
  final Map<String, String> headers;
}

DetailHeroImageAsset resolvePrimaryBackdropAsset(MediaDetailTarget target) {
  if (target.backdropUrl.trim().isNotEmpty) {
    return DetailHeroImageAsset(
      url: target.backdropUrl.trim(),
      headers: target.backdropHeaders,
    );
  }
  if (target.bannerUrl.trim().isNotEmpty) {
    return DetailHeroImageAsset(
      url: target.bannerUrl.trim(),
      headers: target.bannerHeaders,
    );
  }
  if (target.extraBackdropUrls.isNotEmpty) {
    return DetailHeroImageAsset(
      url: target.extraBackdropUrls.first,
      headers: target.extraBackdropHeaders,
    );
  }
  if (target.posterUrl.trim().isNotEmpty) {
    return DetailHeroImageAsset(
      url: target.posterUrl.trim(),
      headers: target.posterHeaders,
    );
  }
  return const DetailHeroImageAsset(url: '');
}

List<AppNetworkImageSource> buildPrimaryBackdropFallbackSources(
  MediaDetailTarget target,
) {
  final sources = <AppNetworkImageSource>[];
  final seen = <String>{target.backdropUrl.trim()};

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

  add(target.bannerUrl, target.bannerHeaders);
  for (final url in target.extraBackdropUrls) {
    add(url, target.extraBackdropHeaders);
  }
  add(target.posterUrl, target.posterHeaders);
  return sources;
}

PlaybackTarget? resolvePrimaryPlaybackTarget(
  MediaDetailTarget target,
  PlaybackProgressEntry? resumeEntry, {
  required bool preferResume,
}) {
  if (resumeEntry != null && preferResume) {
    final targetSubtitle = target.playbackTarget;
    if (targetSubtitle == null) {
      return resumeEntry.target;
    }
    return resumeEntry.target.copyWith(
      externalSubtitleFilePath: targetSubtitle.externalSubtitleFilePath,
      externalSubtitleDisplayName: targetSubtitle.externalSubtitleDisplayName,
    );
  }
  return target.playbackTarget;
}
