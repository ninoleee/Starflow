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

/// All orientations and playback states share clearance inside the safe area.
EdgeInsets playbackControlsPadding({
  required Size viewport,
  required EdgeInsets safeArea,
}) =>
    safeArea + const EdgeInsets.symmetric(horizontal: 12, vertical: 6);
