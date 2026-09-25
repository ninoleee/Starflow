import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/core/network/network_proxy_config.dart';
import 'package:starflow/features/playback/application/active_playback_cleanup.dart';
import 'package:starflow/features/playback/domain/playback_network_speed.dart';
import 'package:starflow/features/playback/data/mpv_playback_format.dart';
import '../domain/live_models.dart';
import 'live_mpv_options.dart';
import 'live_playback_error.dart';

const livePlaybackTimeout = Duration(seconds: 5);

abstract class LiveEngine {
  Future<void> open(
      LiveLine line, int generation, void Function(int, String) onState);
  Future<void> stop();
  Future<void> dispose();
  Future<void> setVolume(double volume);
  Future<List<(String, String)>> audioTracks();
  Future<void> selectAudio(String id);
}

abstract interface class LiveNetworkSpeedSource {
  Future<int?> readNetworkSpeed(int generation);
}

abstract interface class LiveCacheSizeSource {
  Future<int?> readCacheBytes(int generation);

  Future<int?> readBufferDurationMs(int generation);
}

abstract interface class LiveVideoFormatSource {
  Future<String?> readVideoFormat(int generation);
}

/// Cancellation acknowledges resource quiescence, not merely a dropped Future.
/// No replacement open is permitted until this acknowledgement completes.
abstract interface class CancellableLiveEngine implements LiveEngine {
  Future<void> cancelOpen();
}

class LiveOpenCancelled implements Exception {}

enum LivePlaybackFailure {
  openException,
  openTimeout,
  progressTimeout,
  engineError,
  streamEnded;

  String get label => switch (this) {
        openException => '播放器启动异常',
        openTimeout => '播放器打开超时',
        progressTimeout => '等待播放进度超时',
        engineError => '播放内核报告错误',
        streamEnded => '直播流已结束',
      };
}

class MpvLiveEngine
    implements CancellableLiveEngine, LiveNetworkSpeedSource, LiveCacheSizeSource, LiveVideoFormatSource {
  MpvLiveEngine(this.proxy);
  final NetworkProxyConfig proxy;
  Player? player;
  VideoController? video;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Completer<void>? _cancel;
  Future<void>? _cancelling;
  Future<void>? _preparing;
  double _volume = 1;
  bool _cancelRequested = false;
  int? _generation;

  @override
  Future<String?> readVideoFormat(int generation) async {
    final current = player;
    if (_generation != generation || current?.platform is! NativePlayer) return null;
    final format = await readMpvPlaybackFormat((current!.platform as NativePlayer).getProperty);
    return _generation == generation && identical(current, player) ? format : null;
  }

  @override
  Future<int?> readCacheBytes(int generation) async {
    final current = player;
    if (_generation != generation || current?.platform is! NativePlayer) {
      return null;
    }
    final raw = await (current!.platform as NativePlayer)
        .getProperty('demuxer-cache-state/fw-bytes');
    if (_generation != generation || !identical(current, player)) return null;
    return parsePlaybackByteCount(raw);
  }

  @override
  Future<int?> readBufferDurationMs(int generation) async {
    final current = player;
    if (_generation != generation || current?.platform is! NativePlayer) {
      return null;
    }
    final raw = await (current!.platform as NativePlayer)
        .getProperty('demuxer-cache-duration');
    if (_generation != generation || !identical(current, player)) return null;
    return parsePlaybackDurationMilliseconds(raw);
  }

  @override
  Future<int?> readNetworkSpeed(int generation) async {
    final current = player;
    if (_generation != generation || current?.platform is! NativePlayer) {
      return null;
    }
    final raw =
        await (current!.platform as NativePlayer).getProperty('cache-speed');
    if (_generation != generation || !identical(current, player)) return null;
    final speed = double.tryParse(raw);
    return speed != null && speed.isFinite && speed >= 0 ? speed.round() : null;
  }

  @override
  Future<void> open(
      LiveLine line, int generation, void Function(int, String) onState) async {
    final cancel = Completer<void>();
    _cancel = cancel;
    _cancelling = null;
    _cancelRequested = false;
    // Publish cancellation ownership before the first asynchronous boundary.
    await (_preparing = stop());
    if (_cancelRequested) throw LiveOpenCancelled();
    _generation = generation;
    final p = Player(
        configuration: const PlayerConfiguration(
            bufferSize: 32 * 1024 * 1024, protocolWhitelist: liveMpvProtocols));
    player = p;
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
      final headers = liveMediaHeaders(line.headers);
      // media_kit's on_load hook consults this list and Media's header cache.
      native.current = [Media(line.url, httpHeaders: headers)];
      for (final entry in {
        'user-agent': headers.entries
            .firstWhere((entry) => entry.key.toLowerCase() == 'user-agent')
            .value,
        'demuxer-lavf-o': liveMpvDemuxerOptions,
        'http-proxy': proxy.mpvProxyUrlFor(Uri.parse(line.url)),
        'cache-secs': '12',
        'demuxer-max-bytes': '${32 * 1024 * 1024}',
        'demuxer-max-back-bytes': '0',
        'network-timeout': '10',
        'msg-level': 'all=no',
        'volume': '${_volume * 100}',
        'http-header-fields': headers.entries
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
    await step(() =>
        p.open(Media(line.url, httpHeaders: liveMediaHeaders(line.headers))));
  }

  @override
  Future<void> cancelOpen() {
    _cancelRequested = true;
    return _cancelling ??= _cancelOpen();
  }

  Future<void> _cancelOpen() async {
    final cancel = _cancel;
    await _preparing;
    final p = player;
    if (cancel == null || cancel.isCompleted) return;
    // The native stop command interrupts the pending load and acknowledges
    // unloading before the serial owner is allowed to dispose or reopen.
    if (p?.platform is NativePlayer) {
      await (p!.platform as NativePlayer).stop(synchronized: false);
    } else {
      await p?.stop();
    }
    if (!cancel.isCompleted) cancel.complete();
  }

  @override
  Future<void> stop() async {
    _generation = null;
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

class ExoLiveEngine
    implements
        CancellableLiveEngine,
        LiveNetworkSpeedSource,
        LiveCacheSizeSource,
        LiveVideoFormatSource,
        LivePlaybackErrorSource {
  ExoLiveEngine(int viewId)
      : channel = MethodChannel('starflow/live_tv/$viewId');
  final MethodChannel channel;
  Completer<void>? _cancel;
  int? _generation;
  LivePlaybackErrorDetails? _error;
  double _volume = 1;
  @override
  LivePlaybackErrorDetails? errorFor(int generation) =>
      _generation == generation ? _error : null;

  @override
  Future<String?> readVideoFormat(int generation) async {
    if (_generation != generation) return null;
    final format = await channel.invokeMethod<String>(
        'videoFormat', {'generation': generation});
    return _generation == generation ? format : null;
  }

  @override
  Future<int?> readCacheBytes(int generation) async {
    if (_generation != generation) return null;
    final bytes = await channel
        .invokeMethod<num>('cacheBytes', {'generation': generation});
    if (_generation != generation ||
        bytes == null ||
        !bytes.isFinite ||
        bytes < 0) {
      return null;
    }
    return bytes.round();
  }

  @override
  Future<int?> readBufferDurationMs(int generation) async {
    if (_generation != generation) return null;
    final durationMs = await channel.invokeMethod<num>(
        'cacheDurationMs', {'generation': generation});
    if (_generation != generation ||
        durationMs == null ||
        !durationMs.isFinite ||
        durationMs < 0) {
      return null;
    }
    return durationMs.round();
  }

  @override
  Future<int?> readNetworkSpeed(int generation) async {
    if (_generation != generation) return null;
    final speed = await channel
        .invokeMethod<num>('networkSpeed', {'generation': generation});
    if (_generation != generation ||
        speed == null ||
        !speed.isFinite ||
        speed < 0) {
      return null;
    }
    return speed.round();
  }

  @override
  Future<void> open(
      LiveLine line, int generation, void Function(int, String) onState) async {
    final cancel = Completer<void>();
    _cancel = cancel;
    _generation = generation;
    _error = null;
    channel.setMethodCallHandler((call) async {
      if (call.method != 'state' || call.arguments is! Map) return;
      final args = call.arguments as Map;
      if (_generation != generation ||
          !identical(_cancel, cancel) ||
          args['generation'] != generation ||
          args['state'] is! String) {
        return;
      }
      if (args['state'] == 'error') {
        _error = LivePlaybackErrorDetails.fromNative(args['error']);
      }
      onState(generation, args['state'] as String);
    });
    try {
      await Future.any([
        channel.invokeMethod<void>('open', {
          'url': line.url,
          'headers': line.headers,
          'generation': generation,
          'volume': _volume
        }),
        cancel.future.then((_) => throw LiveOpenCancelled()),
      ]);
    } on PlatformException catch (error) {
      if (_generation == generation && identical(_cancel, cancel)) {
        _error = LivePlaybackErrorDetails.fromNative(error.details);
      }
      rethrow;
    }
  }

  @override
  Future<void> cancelOpen() async {
    final cancel = _cancel;
    if (cancel == null || cancel.isCompleted) return;
    await channel.invokeMethod<void>('cancelOpen', {'generation': _generation});
    if (!cancel.isCompleted) cancel.complete();
  }

  @override
  Future<void> stop() {
    _generation = null;
    _error = null;
    return channel.invokeMethod<void>('stop');
  }

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
  LivePlaybackFailure? failure;
  LivePlaybackErrorDetails? errorDetails;
  String? get failureLabel => errorDetails?.label ?? failure?.label;
  String get recoveryLabel {
    final current = channel;
    if (current == null || current.lines.length <= 1) return '正在重新连接';
    final next = (line + 1) % current.lines.length;
    return '正在切换到线路 ${next + 1}';
  }

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
    failure = null;
    errorDetails = null;
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
          pauseReason = '';
          if (engine is CancellableLiveEngine) {
            await engine.setVolume(muted ? 0 : 1);
          }
          if (!_isActive(token)) return;
          _startup = Stopwatch()..start();
          appLogInfo('live.playback', 'Live playback opening', fields: {
            'channelId': value.id,
            'line': line,
            'lineCount': value.lines.length,
            'engine': engine is ExoLiveEngine ? 'exo' : 'mpv',
            'attempt': retries + 1,
            'platform': defaultTargetPlatform.name,
          });
          // The engine cancellation path bypasses this queue, but ownership
          // stays here until native unloading has acknowledged cancellation.
          final deadline = Timer(livePlaybackTimeout,
              () => _fail(token, LivePlaybackFailure.openTimeout));
          _openDeadline = deadline;
          _armDeadline(token);
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
        } catch (error) {
          _fail(token, LivePlaybackFailure.openException,
              errorType: error.runtimeType.toString());
        }
      }));
    });
    _emit('opening');
  }

  void _armDeadline(int token) {
    _deadline?.cancel();
    _deadline = Timer(livePlaybackTimeout,
        () => _fail(token, LivePlaybackFailure.progressTimeout));
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
      _fail(
          token,
          value == 'error'
              ? LivePlaybackFailure.engineError
              : LivePlaybackFailure.streamEnded);
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

  void _fail(int token, LivePlaybackFailure reason, {String? errorType}) {
    if (_closed ||
        token != generation ||
        status == 'retrying' ||
        status == 'failed' ||
        status == 'suspended') {
      return;
    }
    failure = reason;
    final source = engine;
    errorDetails = source is LivePlaybackErrorSource &&
            (reason == LivePlaybackFailure.engineError ||
                reason == LivePlaybackFailure.openException)
        ? (source as LivePlaybackErrorSource).errorFor(token)
        : null;
    // Native exception messages can contain complete URLs and media headers.
    appLogWarning('live.playback', 'Live playback attempt failed', fields: {
      'channelId': channel?.id,
      'line': line,
      'lineCount': channel?.lines.length,
      'engine': engine is ExoLiveEngine ? 'exo' : 'mpv',
      'attempt': retries + 1,
      'reason': reason.name,
      'errorType': errorType,
      ...?errorDetails?.fields,
      'elapsedMs': _startup?.elapsedMilliseconds,
      'willRetry': retries < 3,
    });
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
