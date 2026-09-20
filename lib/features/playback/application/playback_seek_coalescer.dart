import 'dart:async';

/// Accumulates input independently of delayed decoder position events.
class PlaybackSeekCoalescer {
  PlaybackSeekCoalescer(
      {required this.seek, this.interval = const Duration(milliseconds: 250)});

  final Future<void> Function(Duration) seek;
  final Duration interval;
  Timer? _timer;
  Duration? _target;
  Duration? _pending;
  bool _inFlight = false;
  int _generation = 0;

  void add(Duration delta,
      {required Duration position, required Duration duration}) {
    var next = (_target ?? position) + delta;
    if (next < Duration.zero) next = Duration.zero;
    if (duration > Duration.zero && next > duration) next = duration;
    final first = _target == null;
    _target = next;
    _pending = next;
    if (first) {
      _submit();
    } else {
      _timer ??= Timer(interval, () {
        _timer = null;
        _submit();
      });
    }
  }

  void flush() {
    _timer?.cancel();
    _timer = null;
    _submit();
  }

  void cancel() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _pending = null;
    _target = null;
    _inFlight = false;
  }

  void _submit() {
    if (_inFlight || _pending == null) return;
    final target = _pending!;
    final generation = _generation;
    _pending = null;
    _inFlight = true;
    unawaited(Future<void>.sync(() => seek(target)).catchError((Object _) {
      // Runtime playback recovery owns seek errors.
    }).whenComplete(() {
      if (generation != _generation) return;
      _inFlight = false;
      if (_pending != null && _timer == null) _submit();
    }));
  }
}
