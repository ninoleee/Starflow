import 'package:flutter/material.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/playback/presentation/widgets/player_mpv_controls_sections.dart';
import 'package:starflow/features/playback/presentation/widgets/player_playback_formatters.dart';
import 'package:starflow/features/playback/presentation/widgets/player_playback_overlays.dart';

class PlayerTvPlaybackSurface extends StatelessWidget {
  const PlayerTvPlaybackSurface({
    super.key,
    required this.aspectRatio,
    required this.videoSurface,
    this.chrome,
  });

  final double aspectRatio;
  final Widget videoSurface;
  final Widget? chrome;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: Colors.black,
          child: Center(
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: videoSurface,
            ),
          ),
        ),
        if (chrome != null) chrome!,
      ],
    );
  }
}

class PlayerTvPlaybackChrome extends StatelessWidget {
  const PlayerTvPlaybackChrome({
    super.key,
    required this.title,
    required this.position,
    required this.duration,
    required this.playing,
    required this.bufferingPercentage,
    required this.onBack,
    required this.onTogglePlayback,
    required this.onOpenSubtitle,
    required this.onOpenAudio,
    required this.onOpenOptions,
  });

  final String title;
  final Duration position;
  final Duration duration;
  final bool playing;
  final double bufferingPercentage;
  final VoidCallback onBack;
  final VoidCallback onTogglePlayback;
  final VoidCallback onOpenSubtitle;
  final VoidCallback onOpenAudio;
  final VoidCallback onOpenOptions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final durationMs = duration.inMilliseconds;
    final playedProgress = durationMs <= 0
        ? 0.0
        : (position.inMilliseconds / durationMs).clamp(0.0, 1.0);
    final rawBuffered = bufferingPercentage / 100;
    final bufferedProgress = rawBuffered.clamp(playedProgress, 1.0);
    final titleText = title.trim().isEmpty ? 'Starflow' : title.trim();
    final durationText = duration > Duration.zero
        ? formatPlaybackClockDuration(duration)
        : '--:--';

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                StarflowIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: '返回',
                  variant: StarflowButtonVariant.ghost,
                  onPressed: onBack,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    titleText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: SafeArea(
            top: false,
            child: PlayerMpvBottomPanel(
              backgroundColor: const Color(0xC810141A),
              borderRadius: 18,
              showBorder: false,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TvPlaybackBottomProgressBar(
                    playedProgress: playedProgress,
                    bufferedProgress: bufferedProgress,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      StarflowIconButton(
                        icon: playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        tooltip: playing ? '暂停' : '播放',
                        variant: StarflowButtonVariant.ghost,
                        onPressed: onTogglePlayback,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${formatPlaybackClockDuration(position)} / $durationText',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      StarflowIconButton(
                        icon: Icons.closed_caption_rounded,
                        tooltip: '字幕',
                        variant: StarflowButtonVariant.ghost,
                        onPressed: onOpenSubtitle,
                      ),
                      const SizedBox(width: 10),
                      StarflowIconButton(
                        icon: Icons.audiotrack_rounded,
                        tooltip: '音轨',
                        variant: StarflowButtonVariant.ghost,
                        onPressed: onOpenAudio,
                      ),
                      const SizedBox(width: 10),
                      StarflowIconButton(
                        icon: Icons.more_horiz_rounded,
                        tooltip: '更多',
                        variant: StarflowButtonVariant.ghost,
                        onPressed: onOpenOptions,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TvPlaybackBottomProgressBar extends StatelessWidget {
  const _TvPlaybackBottomProgressBar({
    required this.playedProgress,
    required this.bufferedProgress,
  });

  final double playedProgress;
  final double bufferedProgress;

  @override
  Widget build(BuildContext context) {
    final clampedPlayed = playedProgress.clamp(0.0, 1.0);
    final clampedBuffered = bufferedProgress.clamp(clampedPlayed, 1.0);
    return SizedBox(
      height: 20,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Stack(
          alignment: Alignment.center,
          children: [
            TvPlaybackProgressBar(
              playedProgress: clampedPlayed,
              bufferedProgress: clampedBuffered,
            ),
            Align(
              alignment: Alignment(
                clampedPlayed * 2 - 1,
                0,
              ),
              child: Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
