import 'package:flutter/material.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
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
    required this.position,
    required this.duration,
    required this.playing,
    required this.bufferingPercentage,
    required this.onOpenSubtitle,
    required this.onOpenAudio,
  });

  final Duration position;
  final Duration duration;
  final bool playing;
  final double bufferingPercentage;
  final VoidCallback onOpenSubtitle;
  final VoidCallback onOpenAudio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final durationMs = duration.inMilliseconds;
    final playedProgress = durationMs <= 0
        ? 0.0
        : (position.inMilliseconds / durationMs).clamp(0.0, 1.0);
    final rawBuffered = bufferingPercentage / 100;
    final bufferedProgress = rawBuffered.clamp(playedProgress, 1.0);

    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xB8000000),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TvPlaybackProgressBar(
                    playedProgress: playedProgress,
                    bufferedProgress: bufferedProgress,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        playing
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_fill_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${formatPlaybackClockDuration(position)} / ${formatPlaybackClockDuration(duration)}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
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
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
