import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/core/network/network_proxy_config.dart';
import 'package:starflow/features/playback/application/active_playback_cleanup.dart';
import '../domain/live_models.dart';

abstract class LiveEngine {
  Future<void> open(
      LiveLine line, int generation, void Function(int, String) onState);
  Future<void> stop();
  Future<void> dispose();
  Future<void> setVolume(double volume);
  Future<List<(String, String)>> audioTracks();
  Future<void> selectAudio(String id);
}

/// Cancellation acknowledges resource quiescence, not merely a dropped Future.
/// No replacement open is permitted until this acknowledgement completes.
abstract interface class CancellableLiveEngine implements LiveEngine {
  Future<void> cancelOpen();
}

class LiveOpenCancelled implements Exception {}

class MpvLiveEngine implements CancellableLiveEngine {
  MpvLiveEngine(this.proxy);
  final NetworkProxyConfig proxy;
  Player? player;
  VideoController? video;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Completer<void>? _cancel;
  Future<void>? _cancelling;
  double _volume = 1;
  bool _cancelRequested = false;
  @override
  Future<void> open(
      LiveLine line, int generation, void Function(int, String) onState) async {
    await stop();
    final p = Player(
        configuration: const PlayerConfiguration(bufferSize: 32 * 1024 * 1024));
    player = p;
    final cancel = Completer<void>();
    _cancel = cancel;
    _cancelling = null;
    _cancelRequested = false;
    Future<void> step(Future<void> Function() operation) async {
      if (_cancelRequested || cancel.isCompleted) {
        await cancel.future;
        throw LiveOpenCancelled();
      }
      await Future.any(
          [operation(), cancel.future.then((_) => throw LiveOpenCancelled())]);
      if (_cancelRequested || cancel.isCompleted) {
        await cancel.future;
        throw LiveOpenCancelled();
      }
    }

    video = VideoController(p);
    var lastPosition = Duration.zero;
    _subscriptions.addAll([
      p.stream.error.listen((_) => onState(generation, 'error')),
      p.stream.completed.listen((v) {
        if (v) onState(generation, 'ended');
      }),
      p.stream.buffering
          .listen((v) => onState(generation, v ? 'buffering' : 'ready')),
      p.stream.position.listen((v) {
        if (v > lastPosition) onState(generation, 'progress');
        lastPosition = v;
      }),
    ]);
    if (!kIsWeb && p.platform is NativePlayer) {
      final native = p.platform as NativePlayer;
      // media_kit's on_load hook consults this list and Media's header cache.
      native.current = [Media(line.url, httpHeaders: line.headers)];
      for (final entry in {
        'http-proxy': proxy.mpvProxyUrlFor(Uri.parse(line.url)),
        'cache-secs': '12',
        'demuxer-max-bytes': '${32 * 1024 * 1024}',
        'demuxer-max-back-bytes': '0',
        'network-timeout': '10',
        'msg-level': 'all=no',
        'volume': '${_volume * 100}',
        'http-header-fields': line.headers.entries
            .map((e) => '${e.key}: ${e.value}'.replaceAll(',', '\\,'))
            .join(','),
      }.entries) {
        await step(() => native.setProperty(entry.key, entry.value));
      }
      onState(generation, 'created');
      // Do not use media_kit.open: its lock and multi-step continuation can
      // outlive cancellation. A single native loadfile can be interrupted by
      // stop without leaving a Dart continuation that later starts playback.
      await step(() => native.play(synchronized: false));
      await step(() => native.command(['loadfile', line.url, 'replace']));
      return;
    }
    if (!identical(player, p)) return;
    onState(generation, 'created');
    await step(() => p.setVolume(_volume * 100));
    await step(() => p.open(Media(line.url, httpHeaders: line.headers)));
  }

  @override
  Future<void> cancelOpen() {
    _cancelRequested = true;
    return _cancelling ??= _cancelOpen();
  }

  Future<void> _cancelOpen() async {
    final cancel = _cancel;
    final p = player;
    if (cancel == null || cancel.isCompleted || p == null) return;
    // The native stop command interrupts the pending load and acknowledges
    // unloading before the serial owner is allowed to dispose or reopen.
    if (p.platform is NativePlayer) {
      await (p.platform as NativePlayer).stop(synchronized: false);
    } else {
      await p.stop();
    }
    if (!cancel.isCompleted) cancel.complete();
  }

  @override
  Future<void> stop() async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
    _subscriptions.clear();
    final old = player;
    player = null;
    video = null;
    if (old != null) await old.dispose();
  }

  @override
  Future<void> dispose() => stop();
  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    await player?.setVolume(volume * 100);
  }

  @override
  Future<List<(String, String)>> audioTracks() async => [
        for (final a in player?.state.tracks.audio ?? <AudioTrack>[])
          (a.id, a.title ?? a.language ?? a.id),
      ];
  @override
  Future<void> selectAudio(String id) async {
    final p = player;
    final track = p?.state.tracks.audio.where((a) => a.id == id).firstOrNull;
    if (p != null && track != null) await p.setAudioTrack(track);
  }
}

class ExoLiveEngine implements CancellableLiveEngine {
  ExoLiveEngine(int viewId)
      : channel = MethodChannel('starflow/live_tv/$viewId');
  final MethodChannel channel;
  Completer<void>? _cancel;
  int? _generation;
  double _volume = 1;
  @override
  Future<void> open(
      LiveLine line, int generation, void Function(int, String) onState) async {
    final cancel = Completer<void>();
    _cancel = cancel;
    _generation = generation;
    channel.setMethodCallHandler((call) async {
      if (call.method != 'state') return;
      final args = Map<String, dynamic>.from(call.arguments as Map);
      onState(args['generation'] as int, args['state'] as String);
    });
    await Future.any([
      channel.invokeMethod<void>('open', {
        'url': line.url,
        'headers': line.headers,
        'generation': generation,
        'volume': _volume
      }),
      cancel.future.then((_) => throw LiveOpenCancelled()),
    ]);
  }

  @override
  Future<void> cancelOpen() async {
    final cancel = _cancel;
    if (cancel == null || cancel.isCompleted) return;
    await channel.invokeMethod<void>('cancelOpen', {'generation': _generation});
    if (!cancel.isCompleted) cancel.complete();
  }

  @override
  Future<void> stop() => channel.invokeMethod<void>('stop');
  @override
  Future<void> dispose() async {
    channel.setMethodCallHandler(null);
    try {
      await stop();
    } on PlatformException catch (_) {
    } on MissingPluginException catch (_) {}
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    await channel.invokeMethod<void>('volume', {'value': volume});
  }

  @override
  Future<List<(String, String)>> audioTracks() async {
    final tracks = await channel.invokeListMethod<dynamic>(
            'audioTracks', {'generation': _generation}) ??
        [];
    return tracks.map((t) => ('${t['id']}', '${t['title']}')).toList();
  }

  @override
  Future<void> selectAudio(String id) => channel
      .invokeMethod<void>('audio', {'id': id, 'generation': _generation});
}

/// One serial engine owner, with a channel-level retry budget and stale-event guard.
class LivePlaybackController extends ChangeNotifier {
  LivePlaybackController(
      {required this.engine, required this.onReady, this.muted = false}) {
    _cleanupToken = ActivePlaybackCleanupCoordinator.register((_) => close());
  }
  late final int _cleanupToken;
  final LiveEngine engine;
  final Future<void> Function(String, int) onReady;
  LiveChannel? channel;
  int line = 0, generation = 0, retries = 0;
  String status = 'idle';
  bool _closed = false, _remembered = false, muted;
  bool _paused = false;
  String pauseReason = '';
  Future<void>? _openCancellation;
  Completer<void>? _openCancelled;
  Future<void> _tail = Future.value();
  Future<void>? _closing;
  Timer? _openDeadline, _deadline, _retry, _debounce;
  int? _activeToken;
  bool _needsStop = false;
  Stopwatch? _startup;
  bool get busy => const {'opening', 'buffering', 'retrying'}.contains(status);
  void _emit(String value) {
    if (_closed) return;
    status = value;
    notifyListeners();
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final pending = _tail.then((_) => operation());
    _tail = pending.catchError((Object _) {});
    return pending;
  }

  Future<void> _stopEngine() async {
    if (!_needsStop) return;
    await _openCancellation;
    await engine.stop();
    _needsStop = false;
  }

  void _cancelTimers() {
    _openDeadline?.cancel();
    _deadline?.cancel();
    _retry?.cancel();
    _debounce?.cancel();
  }

  bool _isActive(int token) =>
      !_closed && token == generation && token == _activeToken;

  void _cancelOpen() {
    final target = engine;
    if (target is CancellableLiveEngine && _needsStop) {
      final cancelled = _openCancelled;
      _openCancellation ??= target.cancelOpen().then((_) {
        if (cancelled != null && !cancelled.isCompleted) cancelled.complete();
      });
      unawaited(_openCancellation!.catchError((Object _) {}));
    }
  }

  void select(LiveChannel value,
      {int preferredLine = 0, bool resetBudget = true}) {
    if (_closed || value.lines.isEmpty) return;
    channel = value;
    line = preferredLine.clamp(0, value.lines.length - 1);
    if (resetBudget) retries = 0;
    _remembered = false;
    final token = ++generation;
    final selectedLine = value.lines[line];
    _activeToken = null;
    _cancelTimers();
    _cancelOpen();
    unawaited(_enqueue(_stopEngine).catchError((Object _) {}));
    _debounce = Timer(const Duration(milliseconds: 180), () {
      unawaited(_enqueue(() async {
        if (_closed || token != generation) return;
        try {
          await _stopEngine();
          if (_closed || token != generation) return;
          _activeToken = token;
          _needsStop = true;
          _openCancellation = null;
          final cancelled = _openCancelled = Completer<void>();
          _paused = false;
          if (engine is CancellableLiveEngine)
            await engine.setVolume(muted ? 0 : 1);
          if (!_isActive(token)) return;
          _startup = Stopwatch()..start();
          _armDeadline(token);
          // The engine cancellation path bypasses this queue, but ownership
          // stays here until native unloading has acknowledged cancellation.
          final deadline =
              Timer(const Duration(seconds: 15), () => _fail(token));
          _openDeadline = deadline;
          try {
            await Future.any([
              engine.open(selectedLine, token, (eventToken, state) {
                if (eventToken == token) _event(token, state);
              }),
              cancelled.future.then((_) => throw LiveOpenCancelled()),
            ]);
          } finally {
            deadline.cancel();
          }
          if (_isActive(token)) {
            await engine.setVolume(muted ? 0 : 1);
            if (_isActive(token)) notifyListeners();
          }
        } catch (_) {
          _fail(token);
        }
      }));
    });
    _emit('opening');
  }

  void _armDeadline(int token) {
    _deadline?.cancel();
    _deadline = Timer(const Duration(seconds: 18), () => _fail(token));
  }

  void _event(int token, String value) {
    if (!_isActive(token)) return;
    if (value.startsWith('paused:') || value.startsWith('suppressed:')) {
      _paused = true;
      pauseReason = value;
      _cancelTimers();
      _emit('paused');
      return;
    }
    if (value == 'resumed') {
      _paused = false;
      pauseReason = '';
      _armDeadline(token);
      _emit('buffering');
      return;
    }
    if (_paused) return;
    if (value == 'error' || value == 'ended') {
      _fail(token);
      return;
    }
    if (value == 'created') {
      notifyListeners();
      return;
    }
    if (value == 'buffering') {
      _emit('buffering');
      return;
    }
    if (value == 'ready' || value == 'progress' || value == 'frame') {
      // Readiness is engine telemetry, not proof of the first video frame on MPV.
      if (value == 'progress' || value == 'frame') _armDeadline(token);
      if (!_remembered && (value == 'progress' || value == 'frame')) {
        _remembered = true;
        final channelId = channel!.id;
        final selectedLine = line;
        unawaited(Future<void>.sync(() => onReady(channelId, selectedLine))
            .catchError((Object _) {}));
        appLogInfo('live.playback', 'Live playback started', fields: {
          'channelId': channelId,
          'line': selectedLine,
          'engine': engine is ExoLiveEngine ? 'exo' : 'mpv',
          'signal': value,
          'elapsedMs': _startup?.elapsedMilliseconds,
        });
      }
      if (_isActive(token) && status != 'playing') _emit('playing');
    }
  }

  void _fail(int token) {
    if (_closed ||
        token != generation ||
        status == 'retrying' ||
        status == 'failed' ||
        status == 'suspended') {
      return;
    }
    _activeToken = null;
    _cancelTimers();
    _cancelOpen();
    unawaited(_enqueue(_stopEngine).catchError((Object _) {}));
    if (retries >= 3) {
      _emit('failed');
      return;
    }
    retries++;
    _retry = Timer(Duration(seconds: retries * 2), () {
      if (_closed || token != generation || channel == null) return;
      select(channel!,
          preferredLine: (line + 1) % channel!.lines.length,
          resetBudget: false);
    });
    _emit('retrying');
  }

  void suspend() {
    if (_closed) return;
    ++generation;
    _activeToken = null;
    _cancelTimers();
    _cancelOpen();
    unawaited(_enqueue(_stopEngine).catchError((Object _) {}));
    _emit(_paused ? 'paused' : 'suspended');
  }

  Future<void> toggleMute() async {
    if (_closed) return;
    muted = !muted;
    notifyListeners();
    final token = generation;
    await _enqueue(() async {
      if (!_isActive(token)) return;
      await engine.setVolume(muted ? 0 : 1);
      if (_isActive(token)) notifyListeners();
    });
  }

  Future<void> close() => _closing ??= _finishClose();

  bool acceptsAudioSelection(int token) => _isActive(token);

  Future<void> selectAudio(int token, String id) => _enqueue(() async {
        if (_isActive(token)) await engine.selectAudio(id);
      });

  Future<void> _finishClose() async {
    _closed = true;
    ++generation;
    _activeToken = null;
    _cancelTimers();
    _cancelOpen();
    try {
      await _tail;
      await _openCancellation;
      await engine.dispose();
    } finally {
      ActivePlaybackCleanupCoordinator.unregister(_cleanupToken);
    }
  }

  @override
  void dispose() {
    unawaited(close().catchError((Object _) {}));
    super.dispose();
  }
}
