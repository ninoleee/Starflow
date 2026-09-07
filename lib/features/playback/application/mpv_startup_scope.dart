import 'dart:async';

import 'package:starflow/features/playback/application/mpv_tuning_policy.dart';

class MpvStartupCancelled implements Exception {
  const MpvStartupCancelled();
}

/// Cancels waits, not native operations. Native player shutdown remains serial.
class MpvStartupScope {
  final Completer<void> _cancelled = Completer<void>();
  DateTime? deadline;

  void checkActive() {
    if (_cancelled.isCompleted) throw const MpvStartupCancelled();
    if (deadline != null && !DateTime.now().isBefore(deadline!)) {
      throw TimeoutException('Playback startup deadline exceeded');
    }
  }

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  Future<T> wait<T>(Future<T> operation) async {
    final remaining = deadline?.difference(DateTime.now());
    final result = Future.any<T>([
      _cancelled.future.then<T>((_) => throw const MpvStartupCancelled()),
      operation,
    ]);
    if (remaining == null) return result;
    return result
        .timeout(remaining > Duration.zero ? remaining : Duration.zero);
  }
}

/// media_kit forwards log errors, including failures mpv can recover from while
/// opening HLS segments. Confirm that loading has stopped before aborting it.
class MpvStartupErrorGate {
  MpvStartupErrorGate({
    required this.remote,
    required this.readIdleActive,
    required this.onConfirmed,
    this.consumeProgress,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final bool remote;
  final Future<bool?> Function() readIdleActive;
  final void Function(MpvOpenFailure failure) onConfirmed;
  final bool Function()? consumeProgress;
  final DateTime Function() _clock;
  Timer? _timer;
  MpvOpenFailure? _pendingFailure;
  DateTime? _lastProgressAt;
  var _closed = false;
  var _idleSamples = 0;
  var _unknownSamples = 0;
  int deferredErrorCount = 0;
  String? confirmation;

  void report(String message, {int? httpStatus}) {
    if (_closed || message.trim().isEmpty) return;
    final failure = MpvOpenFailure(message, httpStatus: httpStatus);
    if (!remote ||
        classifyMpvOpenFailure(failure) !=
            MpvOpenFailureKind.transientNetwork) {
      _confirm(failure, 'immediate');
      return;
    }
    deferredErrorCount++;
    final alreadyPending = _pendingFailure != null;
    _pendingFailure = failure;
    if (alreadyPending) return;
    _lastProgressAt = _clock();
    consumeProgress?.call();
    _scheduleCheck();
  }

  void _scheduleCheck() {
    _timer = Timer(const Duration(milliseconds: 250), () {
      unawaited(_check());
    });
  }

  Future<void> _check() async {
    bool? idle;
    try {
      idle = await readIdleActive().timeout(const Duration(milliseconds: 250));
    } catch (_) {
      // Unsupported properties keep a bounded fallback instead of hanging.
    }
    if (_closed) return;
    _idleSamples = idle == true ? _idleSamples + 1 : 0;
    _unknownSamples = idle == null ? _unknownSamples + 1 : 0;
    if (_idleSamples >= 2 || _unknownSamples >= 6) {
      _confirm(_pendingFailure!,
          _idleSamples >= 2 ? 'idle-active' : 'idle-unavailable');
      return;
    }
    if (consumeProgress != null) {
      final now = _clock();
      if (consumeProgress!()) _lastProgressAt = now;
      if (idle == false &&
          now.difference(_lastProgressAt!) >= const Duration(seconds: 15)) {
        _confirm(_pendingFailure!, 'load-stalled');
        return;
      }
    }
    // An active load remains governed by the shared startup deadline.
    _scheduleCheck();
  }

  void _confirm(MpvOpenFailure failure, String reason) {
    confirmation = reason;
    dispose();
    onConfirmed(failure);
  }

  void dispose() {
    _closed = true;
    _timer?.cancel();
    _timer = null;
  }
}

/// Associate a nearby native HTTP error with media_kit's generic stream error.
/// Evidence expires quickly and is cleared on real progress or a new load.
class MpvHttpFailureEvidence {
  MpvHttpFailureEvidence({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  int? _status;
  DateTime? _recordedAt;
  Uri? _resource;

  void record(String prefix, String message) {
    final component = prefix.toLowerCase().split('/').first;
    if (!const {'ffmpeg', 'stream', 'lavf'}.contains(component)) return;
    final status = mpvHttpErrorStatus(message);
    if (status == null) return;
    _status = status;
    _resource = _mpvErrorResource(message);
    _recordedAt = _clock();
  }

  int? statusFor(String message) {
    final direct = mpvHttpErrorStatus(message);
    if (direct != null) return direct;
    if (_recordedAt == null ||
        _clock().difference(_recordedAt!) > const Duration(seconds: 1) ||
        classifyMpvOpenFailure(message) !=
            MpvOpenFailureKind.transientNetwork) {
      return null;
    }
    final resource = _mpvErrorResource(message);
    if (_resource != null && resource != null && _resource != resource) {
      return null;
    }
    return _status;
  }

  void clear() {
    _status = null;
    _resource = null;
    _recordedAt = null;
  }
}

Uri? _mpvErrorResource(String text) {
  final url = RegExp(r'https?://[^\s]+').firstMatch(text)?.group(0);
  return url == null ? null : Uri.tryParse(url);
}

/// Only allowlisted facts leave the native log; URLs and headers never do.
Map<String, Object?> summarizeMpvError(String prefix, String text) {
  final lower = text.toLowerCase();
  final component = prefix.toLowerCase().split('/').first;
  final status = mpvHttpErrorStatus(text);
  final path = _mpvErrorResource(text)?.path.toLowerCase() ?? '';
  return {
    'component': const {
      'ffmpeg',
      'stream',
      'cplayer',
      'vd',
      'ad',
      'file',
      'demux',
      'lavf'
    }.contains(component)
        ? component
        : 'other',
    if (status != null) 'httpStatus': status,
    if (path.endsWith('.ts') || path.endsWith('.m4s')) 'resource': 'segment',
    if (path.endsWith('.m3u8')) 'resource': 'playlist',
    'kind': lower.contains('tcp:')
        ? 'tcp-read'
        : status != null
            ? 'http-error'
            : lower.contains('tls') || lower.contains('ssl')
                ? 'tls-error'
                : lower.contains('timed out') || lower.contains('timeout')
                    ? 'timeout'
                    : lower.contains('failed to open')
                        ? 'open-failed'
                        : lower.contains('hls') || lower.contains('.ts?')
                            ? 'hls'
                            : 'native-error',
  };
}
