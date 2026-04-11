import 'package:flutter/material.dart';

const Key kPlayerMpvLeanActionsSectionKey =
    Key('player-mpv-controls:actions:lean');
const Key kPlayerMpvFullActionsSectionKey =
    Key('player-mpv-controls:actions:full');

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
    this.compact = false,
    this.showTooltips = true,
  });

  final bool isPlaying;
  final String positionText;
  final VoidCallback onTogglePlayback;
  final bool compact;
  final bool showTooltips;
}

@immutable
class PlayerMpvVolumeSectionData {
  const PlayerMpvVolumeSectionData({
    required this.visible,
    required this.volume,
    required this.icon,
    required this.onToggleMute,
    required this.onVolumeChanged,
    this.compact = false,
  });

  final bool visible;
  final double volume;
  final IconData icon;
  final VoidCallback onToggleMute;
  final ValueChanged<double> onVolumeChanged;
  final bool compact;
}

@immutable
class PlayerMpvActionButtonsSectionData {
  const PlayerMpvActionButtonsSectionData({
    required this.isFullscreen,
    required this.onOpenOptions,
    required this.onToggleFullscreen,
    this.onOpenSubtitle,
    this.onOpenAudio,
    this.leanMode = false,
    this.showSubtitleButton = true,
    this.showAudioButton = true,
    this.showTooltips = true,
    this.compact = false,
    this.optionsIcon = Icons.tune_rounded,
    this.optionsTooltip = '播放设置',
  });

  final bool isFullscreen;
  final VoidCallback? onOpenSubtitle;
  final VoidCallback? onOpenAudio;
  final VoidCallback onOpenOptions;
  final VoidCallback onToggleFullscreen;
  final bool leanMode;
  final bool showSubtitleButton;
  final bool showAudioButton;
  final bool showTooltips;
  final bool compact;
  final IconData optionsIcon;
  final String optionsTooltip;
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
    this.showBorder = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color backgroundColor;
  final double borderRadius;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        side: showBorder
            ? BorderSide(color: Colors.white.withValues(alpha: 0.08))
            : BorderSide.none,
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
          compact: data.compact,
          showTooltip: data.showTooltips,
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
      if (volume.visible) PlayerMpvVolumeSection(data: volume),
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
            size: data.compact ? 18 : 20,
          ),
        ),
        SizedBox(
          width: data.compact ? 92 : 110,
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
      key: data.leanMode
          ? kPlayerMpvLeanActionsSectionKey
          : kPlayerMpvFullActionsSectionKey,
      mainAxisSize: MainAxisSize.min,
      children: _withGap(
        [
          if (data.showSubtitleButton && data.onOpenSubtitle != null)
            PlayerMpvControlButton(
              icon: Icons.closed_caption_rounded,
              tooltip: '字幕',
              onPressed: data.onOpenSubtitle!,
              compact: data.compact,
              showTooltip: data.showTooltips,
            ),
          if (data.showAudioButton && data.onOpenAudio != null)
            PlayerMpvControlButton(
              icon: Icons.audiotrack_rounded,
              tooltip: '音轨',
              onPressed: data.onOpenAudio!,
              compact: data.compact,
              showTooltip: data.showTooltips,
            ),
          PlayerMpvControlButton(
            icon: data.optionsIcon,
            tooltip: data.optionsTooltip,
            onPressed: data.onOpenOptions,
            compact: data.compact,
            showTooltip: data.showTooltips,
          ),
          PlayerMpvControlButton(
            icon: data.isFullscreen
                ? Icons.fullscreen_exit_rounded
                : Icons.fullscreen_rounded,
            tooltip: data.isFullscreen ? '退出全屏' : '全屏',
            onPressed: data.onToggleFullscreen,
            compact: data.compact,
            showTooltip: data.showTooltips,
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
    this.compact = false,
    this.showTooltip = true,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final bool compact;
  final bool showTooltip;

  Widget _wrapTooltip(Widget child) {
    final message = tooltip?.trim() ?? '';
    if (!showTooltip || message.isEmpty) {
      return child;
    }
    return Tooltip(
      message: message,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _wrapTooltip(
      IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: compact ? 16 : 18),
        color: Colors.white,
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(
          width: compact ? 32 : 36,
          height: compact ? 32 : 36,
        ),
        style: IconButton.styleFrom(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }
}

List<Widget> _withGap(List<Widget> children, double gap) {
  final visibleChildren = children
      .where((child) => child is! SizedBox || child != const SizedBox.shrink())
      .toList(growable: false);
  if (visibleChildren.isEmpty) {
    return visibleChildren;
  }
  final result = <Widget>[];
  for (var i = 0; i < visibleChildren.length; i++) {
    if (i > 0) {
      result.add(SizedBox(width: gap));
    }
    result.add(visibleChildren[i]);
  }
  return result;
}
