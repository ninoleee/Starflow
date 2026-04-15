import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/core/widgets/app_network_image.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/widgets/detail_shared_widgets.dart';
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
    final startPlaybackTarget = resolveStartPlaybackTarget(target);
    final resumePlaybackTarget = resolveResumePlaybackTarget(
      target,
      resumeEntry,
    );
    final hasHeroAction =
        startPlaybackTarget != null || resumePlaybackTarget != null;
    final primaryBackdropSources = buildDetailBackdropImageSourcesForTarget(
      target,
    );
    final primaryBackdropAsset = primaryBackdropSources.primary;
    final heroArtwork = Stack(
      fit: StackFit.expand,
      children: [
        DetailBackdropImage(
          imageUrl: primaryBackdropAsset.url,
          imageHeaders: primaryBackdropAsset.headers,
          fallbackSources: primaryBackdropSources.fallbackSources,
          cachePolicy: primaryBackdropAsset.cachePolicy,
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
                visualStyle: TvFocusVisualStyle.none,
                focusScale: 1.015,
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
                    isTelevision: isTelevision,
                    startPlaybackTarget: startPlaybackTarget,
                    resumePlaybackTarget: resumePlaybackTarget,
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

class DetailHeroContent extends StatelessWidget {
  const DetailHeroContent({
    super.key,
    required this.target,
    required this.metadata,
    required this.peopleLine,
    required this.simplifyVisualEffects,
    required this.isTelevision,
    required this.startPlaybackTarget,
    required this.resumePlaybackTarget,
    this.artworkFocusNode,
    this.playFocusNode,
  });

  final MediaDetailTarget target;
  final List<String> metadata;
  final String peopleLine;
  final bool simplifyVisualEffects;
  final bool isTelevision;
  final PlaybackTarget? startPlaybackTarget;
  final PlaybackTarget? resumePlaybackTarget;
  final FocusNode? artworkFocusNode;
  final FocusNode? playFocusNode;

  @override
  Widget build(BuildContext context) {
    final hasLogo = target.logoUrl.trim().isNotEmpty;
    final primaryTitle = resolveDetailPrimaryTitle(
      currentTarget: target,
      preferResolvedSeriesTitle: true,
    );
    final episodeTitle = resolveDetailEpisodeTitleLine(
      currentTarget: target,
      preferResolvedSeriesTitle: true,
    );
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

    Future<void> openPlaybackTarget(PlaybackTarget playbackTarget) async {
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

    Widget buildPlaybackButton({
      required String label,
      required IconData icon,
      required PlaybackTarget playbackTarget,
      required String focusId,
      FocusNode? focusNode,
      bool autofocus = false,
      TvButtonVariant televisionVariant = TvButtonVariant.filled,
    }) {
      if (isTelevision) {
        return TvAdaptiveButton(
          label: label,
          icon: icon,
          variant: televisionVariant,
          focusNode: focusNode,
          focusId: focusId,
          autofocus: autofocus,
          onPressed: () => openPlaybackTarget(playbackTarget),
        );
      }
      if (televisionVariant == TvButtonVariant.outlined) {
        return OutlinedButton.icon(
          onPressed: () => openPlaybackTarget(playbackTarget),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(
              color: Colors.white.withValues(alpha: 0.36),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 15,
            ),
          ),
          icon: Icon(icon),
          label: Text(label),
        );
      }
      return FilledButton.icon(
        onPressed: () => openPlaybackTarget(playbackTarget),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF081120),
          padding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 15,
          ),
        ),
        icon: Icon(icon),
        label: Text(label),
      );
    }

    final playbackActions = <Widget>[
      if (startPlaybackTarget != null)
        buildPlaybackButton(
          label: '从头播放',
          icon: Icons.play_arrow_rounded,
          playbackTarget: startPlaybackTarget!,
          focusNode: playFocusNode,
          focusId: 'detail:hero:play:start',
          autofocus: true,
        ),
      if (resumePlaybackTarget != null)
        buildPlaybackButton(
          label: '继续播放',
          icon: Icons.history_rounded,
          playbackTarget: resumePlaybackTarget!,
          focusNode: startPlaybackTarget == null ? playFocusNode : null,
          focusId: 'detail:hero:play:resume',
          autofocus: startPlaybackTarget == null,
          televisionVariant: TvButtonVariant.outlined,
        ),
    ];

    final actionRow = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: playbackActions,
    );

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
          if (playbackActions.isNotEmpty)
            wrapTelevisionDirectionalHandling(
              onDirection: (direction) {
                if (direction == TraversalDirection.up) {
                  return requestDetailFocus([artworkFocusNode]);
                }
                return false;
              },
              child: actionRow,
            ),
        ],
      ),
    );
  }
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
    this.cachePolicy = AppNetworkImageCachePolicy.persistent,
  });

  final String imageUrl;
  final Map<String, String> imageHeaders;
  final List<AppNetworkImageSource> fallbackSources;
  final AppNetworkImageCachePolicy cachePolicy;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.trim().isEmpty) {
      return const ColoredBox(color: Color(0xFF0A1423));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final decodeSize = _resolveDetailBackdropDecodeSize(
          context,
          constraints,
        );
        return AppNetworkImage(
          imageUrl,
          headers: imageHeaders,
          fallbackSources: fallbackSources,
          cachePolicy: cachePolicy,
          cacheWidth: decodeSize?.width,
          cacheHeight: decodeSize?.height,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          errorBuilder: (context, error, stackTrace) {
            return const ColoredBox(color: Color(0xFF0A1423));
          },
        );
      },
    );
  }
}

class _DetailBackdropDecodeSize {
  const _DetailBackdropDecodeSize({
    required this.width,
    required this.height,
  });

  final int width;
  final int height;
}

_DetailBackdropDecodeSize? _resolveDetailBackdropDecodeSize(
  BuildContext context,
  BoxConstraints constraints,
) {
  final mediaQuery = MediaQuery.maybeOf(context);
  final screenSize = mediaQuery?.size;
  final logicalWidth = constraints.hasBoundedWidth
      ? constraints.maxWidth
      : (screenSize?.width ?? 0);
  final logicalHeight = constraints.hasBoundedHeight
      ? constraints.maxHeight
      : (screenSize?.height ?? 0);
  if (logicalWidth <= 0 || logicalHeight <= 0) {
    return null;
  }
  final dpr = (mediaQuery?.devicePixelRatio ?? 1.0).clamp(1.0, 3.0);
  final decodeWidth = (logicalWidth * dpr).round();
  final decodeHeight = (logicalHeight * dpr).round();
  return _DetailBackdropDecodeSize(
    width: math.max(1, math.min(decodeWidth, 4096)),
    height: math.max(1, math.min(decodeHeight, 4096)),
  );
}

DetailImageAsset resolvePrimaryBackdropAsset(MediaDetailTarget target) {
  return buildDetailBackdropImageSourcesForTarget(target).primary;
}

List<AppNetworkImageSource> buildPrimaryBackdropFallbackSources(
  MediaDetailTarget target,
) {
  return buildDetailBackdropImageSourcesForTarget(target).fallbackSources;
}

PlaybackTarget? resolveStartPlaybackTarget(
  MediaDetailTarget target,
) {
  final playbackTarget = target.playbackTarget;
  if (playbackTarget == null) {
    return null;
  }
  return playbackTarget.copyWith(allowResume: false);
}

PlaybackTarget? resolveResumePlaybackTarget(
  MediaDetailTarget target,
  PlaybackProgressEntry? resumeEntry,
) {
  if (resumeEntry == null || !resumeEntry.canResume) {
    return null;
  }
  final targetSubtitle = target.playbackTarget;
  if (targetSubtitle == null) {
    return resumeEntry.target.copyWith(allowResume: true);
  }
  return resumeEntry.target.copyWith(
    allowResume: true,
    externalSubtitleFilePath: targetSubtitle.externalSubtitleFilePath,
    externalSubtitleDisplayName: targetSubtitle.externalSubtitleDisplayName,
  );
}
