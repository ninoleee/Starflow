import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:starflow/app/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/core/widgets/app_network_image.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/application/detail_start_playback_resolver.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/widgets/detail_shared_widgets.dart';
import 'package:starflow/features/playback/application/active_playback_cleanup.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
import 'package:starflow/features/playback/domain/playback_memory_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/presentation/widgets/player_playback_formatters.dart';

class DetailHeroSection extends ConsumerWidget {
  const DetailHeroSection({
    super.key,
    required this.target,
    required this.simplifyVisualEffects,
    required this.isTelevision,
    this.artworkFocusNode,
    this.playFocusNode,
    this.onHeroFocused,
  });

  final MediaDetailTarget target;
  final bool simplifyVisualEffects;
  final bool isTelevision;
  final FocusNode? artworkFocusNode;
  final FocusNode? playFocusNode;
  final VoidCallback? onHeroFocused;

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
    final snapshotAsync = ref.watch(playbackMemorySnapshotProvider);
    final snapshot = snapshotAsync.value;
    final resumeEntry = snapshot == null
        ? null
        : ref
            .read(playbackMemoryRepositoryProvider)
            .resumeEntryForDetailTargetFromSnapshot(snapshot, target);
    final playbackActionsReady =
        snapshotAsync.hasValue || snapshotAsync.hasError;
    final resumePlaybackTarget = resolveResumePlaybackTarget(
      target,
      resumeEntry,
    );
    final resumePositionLabel = buildDetailHeroResumePositionLabel(
      target,
      resumeEntry,
    );
    final hasHeroAction =
        target.hasMatchedResource || resumePlaybackTarget != null;
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
                autofocus: playbackActionsReady && !hasHeroAction,
                borderRadius: BorderRadius.zero,
                visualStyle: TvFocusVisualStyle.none,
                focusScale: 1.015,
                onFocused: onHeroFocused,
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
                    resolveStartTarget: target.hasMatchedResource
                        ? () => ref
                            .read(detailStartPlaybackResolverProvider)
                            .resolve(detail: target)
                        : null,
                    resumePlaybackTarget: resumePlaybackTarget,
                    resumePositionLabel: resumePositionLabel,
                    playbackActionsReady: playbackActionsReady,
                    artworkFocusNode: artworkFocusNode,
                    playFocusNode: playFocusNode,
                    onHeroFocused: onHeroFocused,
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

class DetailHeroContent extends StatefulWidget {
  const DetailHeroContent({
    super.key,
    required this.target,
    required this.metadata,
    required this.peopleLine,
    required this.simplifyVisualEffects,
    required this.isTelevision,
    required this.resumePlaybackTarget,
    this.resolveStartTarget,
    this.resumePositionLabel = '',
    this.playbackActionsReady = true,
    this.artworkFocusNode,
    this.playFocusNode,
    this.onHeroFocused,
  });

  final MediaDetailTarget target;
  final List<String> metadata;
  final String peopleLine;
  final bool simplifyVisualEffects;
  final bool isTelevision;
  final PlaybackTarget? resumePlaybackTarget;
  final Future<PlaybackTarget> Function()? resolveStartTarget;
  final String resumePositionLabel;
  final bool playbackActionsReady;
  final FocusNode? artworkFocusNode;
  final FocusNode? playFocusNode;
  final VoidCallback? onHeroFocused;

  @override
  State<DetailHeroContent> createState() => _DetailHeroContentState();
}

class _DetailHeroContentState extends State<DetailHeroContent> {
  bool get _openingPlayback => activePlaybackLaunchInProgress.value;

  @override
  void initState() {
    super.initState();
    activePlaybackLaunchInProgress.addListener(_handlePlaybackLaunchChanged);
  }

  @override
  void dispose() {
    activePlaybackLaunchInProgress.removeListener(_handlePlaybackLaunchChanged);
    super.dispose();
  }

  void _handlePlaybackLaunchChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.target;
    final metadata = widget.metadata;
    final peopleLine = widget.peopleLine;
    final simplifyVisualEffects = widget.simplifyVisualEffects;
    final isTelevision = widget.isTelevision;
    final resolveStartTarget = widget.resolveStartTarget;
    final resumePlaybackTarget = widget.resumePlaybackTarget;
    final resumePositionLabel = widget.resumePositionLabel;
    final artworkFocusNode = widget.artworkFocusNode;
    final playFocusNode = widget.playFocusNode;
    final onHeroFocused = widget.onHeroFocused;
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

    Future<void> openPlaybackTarget(
      Future<PlaybackTarget> Function() resolveTarget,
    ) async {
      if (_openingPlayback) {
        return;
      }
      activePlaybackLaunchInProgress.value = true;
      try {
        final resolvedTarget = await resolveTarget();
        if (!context.mounted) return;
        await ActivePlaybackCleanupCoordinator.cleanupAll(
          reason: 'open-new-playback',
        );
        if (!context.mounted) return;
        await context.pushNamed('player', extra: resolvedTarget);
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('播放失败：$error')),
          );
        }
      } finally {
        activePlaybackLaunchInProgress.value = false;
      }
    }

    Widget buildPlaybackButton({
      required String label,
      required IconData icon,
      required Future<PlaybackTarget> Function() resolveTarget,
      required String focusId,
      FocusNode? focusNode,
      bool autofocus = false,
    }) {
      return StarflowButton(
        key: ValueKey(focusId),
        label: label,
        icon: icon,
        variant: StarflowButtonVariant.secondary,
        focusNode: focusNode,
        focusId: focusId,
        onFocused: onHeroFocused,
        autofocus: autofocus,
        focusScale: isTelevision ? 1.06 : 1.0,
        onPressed:
            _openingPlayback ? null : () => openPlaybackTarget(resolveTarget),
      );
    }

    final playbackActions = <Widget>[
      if (resumePlaybackTarget != null)
        buildPlaybackButton(
          label: '继续播放',
          icon: Icons.history_rounded,
          resolveTarget: () async => resumePlaybackTarget,
          focusNode: playFocusNode,
          focusId: 'detail:hero:play:resume',
          autofocus: true,
        ),
      if (resolveStartTarget != null)
        buildPlaybackButton(
          label: '从头播放',
          icon: Icons.play_arrow_rounded,
          resolveTarget: resolveStartTarget,
          focusNode: resumePlaybackTarget == null ? playFocusNode : null,
          focusId: 'detail:hero:play:start',
          autofocus:
              widget.playbackActionsReady && resumePlaybackTarget == null,
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
          color: AppColors.foreground,
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
                        borderRadius: BorderRadius.circular(AppRadii.pill),
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
                throttleOnTelevision: false,
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
                        borderRadius: BorderRadius.circular(AppRadii.pill),
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
                color: AppColors.foreground,
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
          if (resumePositionLabel.trim().isNotEmpty) ...[
            Text(
              resumePositionLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.foregroundMuted,
                fontSize: simplifyVisualEffects ? 13 : 14,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            SizedBox(height: simplifyVisualEffects ? 10 : 12),
          ],
          if (playbackActions.isNotEmpty)
            KeyedSubtree(
              key: const ValueKey('detail:hero:playback-actions'),
              child: wrapTelevisionDirectionalHandling(
                onDirection: (direction) {
                  if (direction == TraversalDirection.up) {
                    return requestDetailFocus([artworkFocusNode]);
                  }
                  return false;
                },
                child: actionRow,
              ),
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
    requestTvFocus(
      node,
    );
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
      return const ColoredBox(color: AppColors.neutral1);
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
          throttleOnTelevision: false,
          errorBuilder: (context, error, stackTrace) {
            return const ColoredBox(color: AppColors.neutral1);
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

PlaybackTarget? resolveResumePlaybackTarget(
  MediaDetailTarget target,
  PlaybackProgressEntry? resumeEntry,
) {
  if (resumeEntry == null || !resumeEntry.canResume) {
    return null;
  }
  final targetSubtitle = target.playbackTarget;
  if (targetSubtitle == null) {
    return _attachDetailArtworkToPlaybackTarget(
      resumeEntry.target,
      target,
    ).copyWith(allowResume: true);
  }
  return _attachDetailArtworkToPlaybackTarget(
    resumeEntry.target,
    target,
  ).copyWith(
    allowResume: true,
    externalSubtitleFilePath: targetSubtitle.externalSubtitleFilePath,
    externalSubtitleDisplayName: targetSubtitle.externalSubtitleDisplayName,
  );
}

String buildDetailHeroResumePositionLabel(
  MediaDetailTarget target,
  PlaybackProgressEntry? resumeEntry,
) {
  if (resumeEntry == null || !resumeEntry.canResume) {
    return '';
  }
  final resumeTarget = resumeEntry.target;
  final parts = <String>[
    if (resumeTarget.seasonNumber != null && resumeTarget.seasonNumber! > 0)
      '第 ${resumeTarget.seasonNumber} 季',
    if (resumeTarget.episodeNumber != null && resumeTarget.episodeNumber! > 0)
      '第 ${resumeTarget.episodeNumber} 集',
    if (resumeEntry.position > Duration.zero)
      formatPlaybackClockDuration(resumeEntry.position),
  ];
  if (parts.isEmpty) {
    return '';
  }
  return '上次播放：${parts.join(' · ')}';
}

PlaybackTarget _attachDetailArtworkToPlaybackTarget(
  PlaybackTarget playbackTarget,
  MediaDetailTarget detailTarget,
) {
  return playbackTarget.copyWith(
    posterUrl: detailTarget.posterUrl.trim().isNotEmpty
        ? detailTarget.posterUrl
        : playbackTarget.posterUrl,
    posterHeaders: detailTarget.posterUrl.trim().isNotEmpty
        ? detailTarget.posterHeaders
        : playbackTarget.posterHeaders,
    backdropUrl: detailTarget.backdropUrl.trim().isNotEmpty
        ? detailTarget.backdropUrl
        : playbackTarget.backdropUrl,
    backdropHeaders: detailTarget.backdropUrl.trim().isNotEmpty
        ? detailTarget.backdropHeaders
        : playbackTarget.backdropHeaders,
  );
}
