import 'package:flutter/material.dart';

@immutable
class PlayerMpvSeekSectionData {
  const PlayerMpvSeekSectionData({
    required this.max,
    required this.value,
    required this.bufferedProgress,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double max;
  final double value;
  final double bufferedProgress;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
}

@immutable
class PlayerMpvPlaybackInfoSectionData {
  const PlayerMpvPlaybackInfoSectionData({
    required this.isPlaying,
    required this.positionText,
    required this.onTogglePlayback,
  });

  final bool isPlaying;
  final String positionText;
  final VoidCallback onTogglePlayback;
}

@immutable
class PlayerMpvVolumeSectionData {
  const PlayerMpvVolumeSectionData({
    required this.visible,
    required this.volume,
    required this.icon,
    required this.onToggleMute,
    required this.onVolumeChanged,
  });

  final bool visible;
  final double volume;
  final IconData icon;
  final VoidCallback onToggleMute;
  final ValueChanged<double> onVolumeChanged;
}

@immutable
class PlayerMpvActionButtonsSectionData {
  const PlayerMpvActionButtonsSectionData({
    required this.isFullscreen,
    required this.onOpenSubtitle,
    required this.onOpenAudio,
    required this.onOpenOptions,
    required this.onToggleFullscreen,
  });

  final bool isFullscreen;
  final VoidCallback onOpenSubtitle;
  final VoidCallback onOpenAudio;
  final VoidCallback onOpenOptions;
  final VoidCallback onToggleFullscreen;
}

class PlayerMpvBottomControlsSection extends StatelessWidget {
  const PlayerMpvBottomControlsSection({
    super.key,
    required this.seek,
    required this.playbackInfo,
    required this.volume,
    required this.actions,
    this.compact = false,
  });

  final PlayerMpvSeekSectionData seek;
  final PlayerMpvPlaybackInfoSectionData playbackInfo;
  final PlayerMpvVolumeSectionData volume;
  final PlayerMpvActionButtonsSectionData actions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return PlayerMpvBottomPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlayerMpvSeekSection(data: seek),
          const SizedBox(height: 12),
          PlayerMpvBottomMainRowSection(
            compact: compact,
            playbackInfo: playbackInfo,
            volume: volume,
            actions: actions,
          ),
        ],
      ),
    );
  }
}

class PlayerMpvBottomPanel extends StatelessWidget {
  const PlayerMpvBottomPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 12),
    this.backgroundColor = const Color(0xAA0A0F16),
    this.borderRadius = 18,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color backgroundColor;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class PlayerMpvSeekSection extends StatelessWidget {
  const PlayerMpvSeekSection({
    super.key,
    required this.data,
  });

  final PlayerMpvSeekSectionData data;

  @override
  Widget build(BuildContext context) {
    final max = data.max <= 0 ? 1.0 : data.max;
    final value = data.value.clamp(0.0, max);
    final bufferedProgress = data.bufferedProgress.clamp(0.0, 1.0);

    return SizedBox(
      height: 20,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 4,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: Colors.white.withValues(alpha: 0.12)),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: bufferedProgress,
                    child: ColoredBox(
                      color: Colors.white.withValues(alpha: 0.28),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              inactiveTrackColor: Colors.transparent,
              activeTrackColor: Colors.white,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              min: 0,
              max: max,
              value: value,
              onChanged: data.enabled ? data.onChanged : null,
              onChangeEnd: data.enabled ? data.onChangeEnd : null,
            ),
          ),
        ],
      ),
    );
  }
}

class PlayerMpvBottomMainRowSection extends StatelessWidget {
  const PlayerMpvBottomMainRowSection({
    super.key,
    required this.playbackInfo,
    required this.volume,
    required this.actions,
    this.compact = false,
  });

  final PlayerMpvPlaybackInfoSectionData playbackInfo;
  final PlayerMpvVolumeSectionData volume;
  final PlayerMpvActionButtonsSectionData actions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final leading = PlayerMpvPlaybackInfoSection(data: playbackInfo);
    final trailing = PlayerMpvTrailingSections(
      compact: compact,
      volume: volume,
      actions: actions,
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(height: 10),
          trailing,
        ],
      );
    }

    return Row(
      children: [
        leading,
        const Spacer(),
        trailing,
      ],
    );
  }
}

class PlayerMpvPlaybackInfoSection extends StatelessWidget {
  const PlayerMpvPlaybackInfoSection({
    super.key,
    required this.data,
  });

  final PlayerMpvPlaybackInfoSectionData data;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlayerMpvControlButton(
          icon: data.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          tooltip: data.isPlaying ? '暂停' : '播放',
          onPressed: data.onTogglePlayback,
        ),
        const SizedBox(width: 12),
        Text(
          data.positionText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class PlayerMpvTrailingSections extends StatelessWidget {
  const PlayerMpvTrailingSections({
    super.key,
    required this.compact,
    required this.volume,
    required this.actions,
  });

  final bool compact;
  final PlayerMpvVolumeSectionData volume;
  final PlayerMpvActionButtonsSectionData actions;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      PlayerMpvVolumeSection(data: volume),
      PlayerMpvActionButtonsSection(data: actions),
    ];
    if (compact) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: _withGap(children, 8));
  }
}

class PlayerMpvVolumeSection extends StatelessWidget {
  const PlayerMpvVolumeSection({
    super.key,
    required this.data,
  });

  final PlayerMpvVolumeSectionData data;

  @override
  Widget build(BuildContext context) {
    if (!data.visible) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: data.onToggleMute,
          splashRadius: 18,
          icon: Icon(
            data.icon,
            color: Colors.white,
            size: 20,
          ),
        ),
        SizedBox(
          width: 110,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              min: 0,
              max: 100,
              value: data.volume.clamp(0.0, 100.0),
              onChanged: data.onVolumeChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class PlayerMpvActionButtonsSection extends StatelessWidget {
  const PlayerMpvActionButtonsSection({
    super.key,
    required this.data,
  });

  final PlayerMpvActionButtonsSectionData data;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: _withGap(
        [
          PlayerMpvControlButton(
            icon: Icons.closed_caption_rounded,
            tooltip: '字幕',
            onPressed: data.onOpenSubtitle,
          ),
          PlayerMpvControlButton(
            icon: Icons.audiotrack_rounded,
            tooltip: '音轨',
            onPressed: data.onOpenAudio,
          ),
          PlayerMpvControlButton(
            icon: Icons.tune_rounded,
            tooltip: '播放设置',
            onPressed: data.onOpenOptions,
          ),
          PlayerMpvControlButton(
            icon: data.isFullscreen
                ? Icons.fullscreen_exit_rounded
                : Icons.fullscreen_rounded,
            tooltip: data.isFullscreen ? '退出全屏' : '全屏',
            onPressed: data.onToggleFullscreen,
          ),
        ],
        8,
      ),
    );
  }
}

class PlayerMpvControlButton extends StatelessWidget {
  const PlayerMpvControlButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkResponse(
        radius: 22,
        onTap: onPressed,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0x66101822),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

List<Widget> _withGap(List<Widget> children, double gap) {
  if (children.isEmpty) {
    return children;
  }
  final result = <Widget>[];
  for (var i = 0; i < children.length; i++) {
    if (i > 0) {
      result.add(SizedBox(width: gap));
    }
    result.add(children[i]);
  }
  return result;
}
