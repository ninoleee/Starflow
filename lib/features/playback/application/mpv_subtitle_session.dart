import 'dart:async';

import 'mpv_subtitle_render_binding.dart';

/// Owns the renderer and sid/track observations for one player lifetime.
class MpvSubtitleSession {
  MpvSubtitleRenderBinding? _binding;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Future<void>? _registration;
  Future<void> Function()? _unobserve;
  Future<void>? _closing;
  bool _closed = false;

  void refresh() {
    if (!_closed) _binding?.refresh();
  }

  void listen<T>(Stream<T> stream) {
    if (_closed) return;
    _subscriptions.add(stream.listen((_) => refresh()));
  }

  Future<void> bind({
    required MpvSubtitleRenderBinding binding,
    required Future<void> Function(void Function()) observe,
    required Future<void> Function() unobserve,
    required void Function(Object, StackTrace) onObservationError,
  }) async {
    if (_closed) {
      await binding.close();
      return;
    }
    if (_binding != null) throw StateError('Subtitle session already bound');
    _binding = binding;
    _registration = () async {
      try {
        await observe(refresh);
        _unobserve = unobserve;
      } catch (error, stack) {
        if (!_closed) onObservationError(error, stack);
      }
    }();
    await _registration;
    refresh();
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    final bindingClosed = _binding?.close();
    return _closing = Future.wait<void>([
      if (bindingClosed != null) bindingClosed,
      for (final subscription in _subscriptions)
        Future<void>.sync(subscription.cancel),
      () async {
        // A late registration must be removed before the native player dies.
        await _registration;
        final unobserve = _unobserve;
        _unobserve = null;
        await unobserve?.call();
      }(),
    ]).whenComplete(() {
      _subscriptions.clear();
      _binding = null;
    });
  }
}
