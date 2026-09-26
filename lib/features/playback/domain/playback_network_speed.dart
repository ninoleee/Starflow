String formatPlaybackNetworkSpeed(int? bytesPerSecond) {
  final size = formatPlaybackCacheBytes(bytesPerSecond);
  return size == '--' ? size : '$size/s';
}

String formatPlaybackCacheBytes(int? bytes) {
  if (bytes == null || bytes < 0) return '--';
  var value = bytes.toDouble();
  const units = ['B', 'KB', 'MB', 'GB'];
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  // Promote after rounding too, so a boundary never reads "1024.0 KB/s".
  if (unit > 0 && unit < units.length - 1 && value >= 1023.95) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}

String formatPlaybackBufferDuration(int? durationMs) {
  if (durationMs == null || durationMs < 0) return '--';
  final totalSeconds = (durationMs / 1000).round();
  return '${totalSeconds}s';
}

String formatPlaybackMetrics(
    int? bytesPerSecond, int? cacheBytes, int? bufferDurationMs,
    {int? diskCacheBytes,
    bool showDiskCache = false,
    String memoryCacheLabel = ''}) {
  final cache = diskCacheBytes == null && !showDiskCache
      ? formatPlaybackCacheBytes(cacheBytes)
      : '${memoryCacheLabel.isEmpty ? '' : '$memoryCacheLabel '}${formatPlaybackCacheBytes(cacheBytes)} | ${formatPlaybackCacheBytes(diskCacheBytes)}';
  return [
    formatPlaybackNetworkSpeed(bytesPerSecond),
    cache,
    formatPlaybackBufferDuration(bufferDurationMs),
  ].join(' · ');
}

int? parsePlaybackByteCount(String raw) {
  final value = double.tryParse(raw);
  return value != null && value.isFinite && value >= 0 ? value.round() : null;
}

int? parsePlaybackDurationMilliseconds(String raw) {
  final seconds = double.tryParse(raw);
  return seconds != null && (seconds * 1000).isFinite && seconds >= 0
      ? (seconds * 1000).round()
      : null;
}

class PlaybackNetworkSpeedWindow {
  final _samples = <int>[];

  int? add(int? speed) {
    if (speed == null || speed <= 0) {
      _samples.clear();
      return speed == 0 ? 0 : null;
    }
    _samples.add(speed);
    if (_samples.length > 3) _samples.removeAt(0);
    return (_samples.fold<double>(0, (sum, value) => sum + value) /
            _samples.length)
        .round();
  }
}
