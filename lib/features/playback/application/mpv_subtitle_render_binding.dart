import 'dart:async';

import 'package:media_kit/media_kit.dart';
import 'package:starflow/features/playback/application/subtitle_render_policy.dart';

/// One serialized, coalesced visibility writer per player lifetime.
class MpvSubtitleRenderBinding {
  MpvSubtitleRenderBinding({
    required this.selected,
    required this.tracks,
    required this.readSid,
    required this.write,
    required this.onBitmapChanged,
    required this.onError,
  });

  final SubtitleTrack Function() selected;
  final Iterable<SubtitleTrack> Function() tracks;
  final Future<String> Function() readSid;
  final Future<void> Function(String, String) write;
  final void Function(bool) onBitmapChanged;
  final void Function(Object, StackTrace) onError;
  bool _closed = false;
  bool _dirty = false;
  Future<void>? _running;
  bool? _applied;

  void refresh() {
    if (_closed) return;
    _dirty = true;
    _running ??= Future<void>.microtask(_drain).whenComplete(() {
      _running = null;
      if (_dirty && !_closed) refresh();
    });
  }

  Future<void> _drain() async {
    while (_dirty && !_closed) {
      _dirty = false;
      try {
        final sid = await readSid();
        if (_closed) return;
        if (_dirty) continue;
        final track = resolveMpvSubtitleTrack(
            selected: selected(), tracks: tracks(), sid: sid);
        // Metadata may be late. Keep native rendering available until its type is known.
        final bitmap = track == null
            ? (sid.trim().isNotEmpty && sid.trim() != 'auto'
                ? sid.trim() != 'no'
                : selected().id != 'no')
            : isBitmapSubtitle(image: track.image, codec: track.codec);
        if (_applied == bitmap) continue;
        // A change arriving during the native write must not reuse the previous cache value.
        _applied = null;
        await write('sub-visibility', bitmap ? 'yes' : 'no');
        if (_closed) return;
        if (_dirty) continue;
        await write('secondary-sub-visibility', 'no');
        if (_closed) return;
        if (_dirty) continue;
        _applied = bitmap;
        onBitmapChanged(bitmap);
      } catch (error, stack) {
        if (!_closed) onError(error, stack);
      }
    }
  }

  Future<void> close() async {
    _closed = true;
    _dirty = false;
    await _running;
  }
}
