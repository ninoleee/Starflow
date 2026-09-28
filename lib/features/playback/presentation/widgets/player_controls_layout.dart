import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
// ignore: implementation_imports
import 'package:media_kit_video/media_kit_video_controls/src/controls/widgets/video_controls_theme_data_injector.dart';

class PlayerEmbeddedSurface extends StatelessWidget {
  const PlayerEmbeddedSurface({
    super.key,
    required this.isTelevision,
    required this.aspectRatio,
    required this.child,
  });

  final bool isTelevision;
  final double aspectRatio;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isTelevision) return SizedBox.expand(child: child);
    return Center(
      child: AspectRatio(aspectRatio: aspectRatio, child: child),
    );
  }
}

class PlayerAdaptiveControlsLayout extends StatelessWidget {
  const PlayerAdaptiveControlsLayout({
    super.key,
    required this.state,
    required this.materialThemeBuilder,
    required this.desktopThemeBuilder,
    this.controlsKey,
  });

  final VideoState state;
  final MaterialVideoControlsThemeData Function(EdgeInsets padding)
      materialThemeBuilder;
  final MaterialDesktopVideoControlsThemeData Function(EdgeInsets padding)
      desktopThemeBuilder;
  final Key? controlsKey;

  @override
  Widget build(BuildContext context) {
    final padding = playbackControlsPadding(
      viewport: MediaQuery.sizeOf(context),
      safeArea: MediaQuery.viewPaddingOf(context),
    );
    final materialTheme = materialThemeBuilder(padding);
    final desktopTheme = desktopThemeBuilder(padding);
    final adaptiveControls = AdaptiveVideoControls(state);
    // media_kit 2.0.1's injector caches themes with inverted notifications.
    // Supply both themes directly and refresh Theme.of consumers without keys
    // that would remount controls or reset their visibility and gesture state.
    final controls = adaptiveControls is VideoControlsThemeDataInjector
        ? adaptiveControls.child
        : adaptiveControls;
    final appTheme = Theme.of(context);
    return Theme(
      data: appTheme.copyWith(extensions: [
        ...appTheme.extensions.values,
        _PlayerControlsThemeRefresh(materialTheme, desktopTheme),
      ]),
      child: MaterialVideoControlsTheme(
        normal: materialTheme,
        fullscreen: materialTheme,
        child: MaterialDesktopVideoControlsTheme(
          normal: desktopTheme,
          fullscreen: desktopTheme,
          child: KeyedSubtree(key: controlsKey, child: controls),
        ),
      ),
    );
  }
}

class _PlayerControlsThemeRefresh
    extends ThemeExtension<_PlayerControlsThemeRefresh> {
  const _PlayerControlsThemeRefresh(this.material, this.desktop);

  final MaterialVideoControlsThemeData material;
  final MaterialDesktopVideoControlsThemeData desktop;

  @override
  _PlayerControlsThemeRefresh copyWith() => this;

  @override
  _PlayerControlsThemeRefresh lerp(
    covariant _PlayerControlsThemeRefresh? other,
    double t,
  ) =>
      other ?? this;
}

const playbackSeekBarMargin = EdgeInsets.only(bottom: 6);
const playbackButtonBarHeight = 56.0;
const playbackTopActionsHeight = 40.0;
const playbackTopMetricsHeight = 20.0;
const playbackTopMetricsOffset = playbackTopActionsHeight;
const playbackTopMetricsOverflow =
    playbackTopMetricsOffset + playbackTopMetricsHeight - playbackButtonBarHeight;

/// Top actions already include their own touch-target clearance.
EdgeInsets playbackTopBarPadding(EdgeInsets controlsPadding) =>
    controlsPadding.copyWith(
      left: controlsPadding.left - 8,
      right: controlsPadding.right - 8,
      bottom: 0,
    );

class PlayerMpvTopBarRow extends StatelessWidget {
  const PlayerMpvTopBarRow({
    super.key,
    required this.backButton,
    required this.title,
    required this.metrics,
    required this.actions,
    this.format = const SizedBox.shrink(),
  });

  final Widget backButton;
  final Widget title;
  final Widget metrics;
  final Widget format;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            height: playbackTopActionsHeight,
            child: Row(children: [
              SizedBox(width: 48, child: Center(child: backButton)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: title,
                ),
              ),
              for (final action in actions)
                SizedBox(width: 48, child: Center(child: action)),
            ]),
          ),
          Positioned(
            top: playbackTopMetricsOffset,
            left: 56,
            right: 12,
            child: Row(children: [
              Expanded(child: format),
              const SizedBox(width: 8),
              Expanded(
                child: Align(alignment: Alignment.centerRight, child: metrics),
              ),
            ]),
          ),
        ],
      );
}

/// All orientations and playback states share clearance inside the safe area.
EdgeInsets playbackControlsPadding({
  required Size viewport,
  required EdgeInsets safeArea,
}) =>
    safeArea + const EdgeInsets.symmetric(horizontal: 12, vertical: 6);
