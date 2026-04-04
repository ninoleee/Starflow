import 'package:starflow/features/library/domain/media_models.dart';

class PlaybackTarget {
  const PlaybackTarget({
    required this.title,
    required this.sourceId,
    required this.streamUrl,
    required this.sourceName,
    required this.sourceKind,
    this.itemId = '',
    this.preferredMediaSourceId = '',
    this.subtitle = '',
    this.headers = const {},
    this.container = '',
    this.videoCodec = '',
    this.audioCodec = '',
    this.width,
    this.height,
    this.bitrate,
    this.fileSizeBytes,
  });

  final String title;
  final String sourceId;
  final String streamUrl;
  final String sourceName;
  final MediaSourceKind sourceKind;
  final String itemId;
  final String preferredMediaSourceId;
  final String subtitle;
  final Map<String, String> headers;
  final String container;
  final String videoCodec;
  final String audioCodec;
  final int? width;
  final int? height;
  final int? bitrate;
  final int? fileSizeBytes;

  bool get needsResolution =>
      streamUrl.trim().isEmpty &&
      sourceKind == MediaSourceKind.emby &&
      itemId.trim().isNotEmpty;

  bool get canPlay => streamUrl.trim().isNotEmpty || needsResolution;

  String get formatLabel {
    final parts = <String>[
      if (container.trim().isNotEmpty) _prettyMediaToken(container),
      if (videoCodec.trim().isNotEmpty) _prettyMediaToken(videoCodec),
      if (audioCodec.trim().isNotEmpty) _prettyMediaToken(audioCodec),
    ];
    return parts.join(' · ');
  }

  String get resolutionLabel {
    final resolvedWidth = width ?? 0;
    final resolvedHeight = height ?? 0;
    if (resolvedWidth <= 0 || resolvedHeight <= 0) {
      return '';
    }
    return '${resolvedWidth}x$resolvedHeight';
  }

  String get bitrateLabel {
    final resolvedBitrate = bitrate ?? 0;
    if (resolvedBitrate <= 0) {
      return '';
    }
    if (resolvedBitrate >= 1000000) {
      return '${(resolvedBitrate / 1000000).toStringAsFixed(1)} Mbps';
    }
    if (resolvedBitrate >= 1000) {
      return '${(resolvedBitrate / 1000).toStringAsFixed(0)} Kbps';
    }
    return '$resolvedBitrate bps';
  }

  String get fileSizeLabel => formatByteSize(fileSizeBytes);

  factory PlaybackTarget.fromMediaItem(MediaItem item) {
    return PlaybackTarget(
      title: item.title,
      sourceId: item.sourceId,
      streamUrl: item.streamUrl,
      sourceName: item.sourceName,
      sourceKind: item.sourceKind,
      itemId: item.playbackItemId,
      preferredMediaSourceId: item.preferredMediaSourceId,
      subtitle: item.overview,
      headers: item.streamHeaders,
      container: _inferContainerFromUrl(item.streamUrl),
    );
  }
}

String formatByteSize(int? bytes) {
  final resolvedBytes = bytes ?? 0;
  if (resolvedBytes <= 0) {
    return '';
  }

  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  double value = resolvedBytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }

  final digits = value >= 100 || unitIndex == 0
      ? 0
      : value >= 10
          ? 1
          : 2;
  return '${value.toStringAsFixed(digits)} ${units[unitIndex]}';
}

String _inferContainerFromUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) {
    return '';
  }

  final uri = Uri.tryParse(trimmed);
  final path = uri?.path ?? trimmed;
  final dotIndex = path.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex >= path.length - 1) {
    return '';
  }

  final candidate = path.substring(dotIndex + 1).trim();
  if (candidate.isEmpty || candidate.length > 6) {
    return '';
  }
  return candidate;
}

String _prettyMediaToken(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return '';
  }

  final upper = normalized.toUpperCase();
  return switch (upper) {
    'H264' || 'AVC' => 'H.264',
    'H265' || 'HEVC' => 'HEVC',
    'TRUEHD' => 'TrueHD',
    'DTSHD_MA' => 'DTS-HD MA',
    'DTSHD' => 'DTS-HD',
    'AAC' => 'AAC',
    'AC3' => 'AC3',
    'EAC3' => 'EAC3',
    _ => upper,
  };
}
