import 'package:flutter/material.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/presentation/widgets/player_playback_formatters.dart';

class PlayerStartupOverlay extends StatelessWidget {
  const PlayerStartupOverlay({
    super.key,
    required this.target,
    required this.speedLabel,
    this.bufferingProgress,
  });

  final PlaybackTarget target;
  final String speedLabel;
  final double? bufferingProgress;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: Colors.white,
            ),
          ),
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + kToolbarHeight + 12,
          right: 18,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _StartupMetricText(
                label: '网速',
                value: speedLabel.isEmpty ? '测速中' : speedLabel,
              ),
              const SizedBox(height: 6),
              _StartupMetricText(
                label: '格式',
                value: buildPlaybackStartupFormatValue(target),
              ),
              if (_normalizeBufferProgress(bufferingProgress)
                  case final progress?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SizedBox(
                    width: 108,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 2.5,
                        value: progress,
                        color: Colors.white,
                        backgroundColor: Colors.white.withValues(alpha: 0.16),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static double? _normalizeBufferProgress(double? value) {
    final progress = value ?? 0;
    if (progress <= 0) {
      return null;
    }
    if (progress > 1) {
      return (progress / 100).clamp(0.0, 1.0);
    }
    return progress.clamp(0.0, 1.0);
  }
}

class TvPlaybackProgressBar extends StatelessWidget {
  const TvPlaybackProgressBar({
    super.key,
    required this.playedProgress,
    required this.bufferedProgress,
  });

  final double playedProgress;
  final double bufferedProgress;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 6,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: Colors.white.withValues(alpha: 0.18),
            ),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: bufferedProgress.clamp(0.0, 1.0),
              child: ColoredBox(
                color: Colors.white.withValues(alpha: 0.34),
              ),
            ),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: playedProgress.clamp(0.0, 1.0),
              child: const ColoredBox(
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StartupMetricText extends StatelessWidget {
  const _StartupMetricText({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RichText(
      textAlign: TextAlign.right,
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              shadows: const [
                Shadow(
                  color: Color(0xA6000000),
                  blurRadius: 10,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              shadows: [
                Shadow(
                  color: Color(0xB8000000),
                  blurRadius: 12,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
