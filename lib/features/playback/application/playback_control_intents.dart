import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

const playbackMediaShortcuts = <SingleActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.mediaPlay): PlaybackPlayIntent(),
  SingleActivator(LogicalKeyboardKey.mediaPause): PlaybackPauseIntent(),
  SingleActivator(LogicalKeyboardKey.mediaPlayPause): PlaybackToggleIntent(),
};

class PlaybackPlayIntent extends Intent {
  const PlaybackPlayIntent();
}

class PlaybackPauseIntent extends Intent {
  const PlaybackPauseIntent();
}

class PlaybackToggleIntent extends Intent {
  const PlaybackToggleIntent();
}
