import 'package:flutter/widgets.dart';

const playbackSeekBarMargin = EdgeInsets.only(bottom: 6);

/// Orientation, fullscreen and playback state do not add control spacing.
EdgeInsets playbackControlsPadding({
  required Size viewport,
  required EdgeInsets safeArea,
}) =>
    safeArea;
