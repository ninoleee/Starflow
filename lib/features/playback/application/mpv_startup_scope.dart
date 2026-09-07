import 'dart:async';

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

/// Only allowlisted facts leave the native log; URLs and headers never do.
Map<String, Object?> summarizeMpvError(String prefix, String text) {
  final lower = text.toLowerCase();
  final status = RegExp(
    r'(?:http(?:\s+error)?|status\s+code)\s*[:=]?\s*(\d{3})',
  ).firstMatch(lower);
  return {
    'component': const {'ffmpeg', 'stream', 'cplayer', 'vd', 'ad', 'file'}
            .contains(prefix)
        ? prefix
        : 'other',
    if (status != null) 'httpStatus': int.parse(status.group(1)!),
    'kind': lower.contains('tcp:')
        ? 'tcp-read'
        : lower.contains('failed to open')
            ? 'open-failed'
            : lower.contains('hls') || lower.contains('.ts?')
                ? 'hls'
                : 'native-error',
  };
}
