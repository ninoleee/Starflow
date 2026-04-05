import 'package:starflow/features/library/domain/media_models.dart';

class PlaybackTarget {
  const PlaybackTarget({
    required this.title,
    required this.sourceId,
    required this.streamUrl,
    required this.sourceName,
    required this.sourceKind,
    this.actualAddress = '',
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
  final String actualAddress;
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
      actualAddress: item.actualAddress,
      itemId: item.playbackItemId,
      preferredMediaSourceId: item.preferredMediaSourceId,
      subtitle: item.overview,
      headers: item.streamHeaders,
      container: item.container.trim().isNotEmpty
          ? item.container
          : _inferContainerFromUrl(item.streamUrl),
      videoCodec: item.videoCodec,
      audioCodec: item.audioCodec,
      width: item.width,
      height: item.height,
      bitrate: item.bitrate,
      fileSizeBytes: item.fileSizeBytes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'sourceId': sourceId,
      'streamUrl': streamUrl,
      'sourceName': sourceName,
      'sourceKind': sourceKind.name,
      'actualAddress': actualAddress,
      'itemId': itemId,
      'preferredMediaSourceId': preferredMediaSourceId,
      'subtitle': subtitle,
      'headers': headers,
      'container': container,
      'videoCodec': videoCodec,
      'audioCodec': audioCodec,
      'width': width,
      'height': height,
      'bitrate': bitrate,
      'fileSizeBytes': fileSizeBytes,
    };
  }

  factory PlaybackTarget.fromJson(Map<String, dynamic> json) {
    return PlaybackTarget(
      title: json['title'] as String? ?? '',
      sourceId: json['sourceId'] as String? ?? '',
      streamUrl: json['streamUrl'] as String? ?? '',
      sourceName: json['sourceName'] as String? ?? '',
      sourceKind: MediaSourceKindX.fromName(json['sourceKind'] as String? ?? ''),
      actualAddress: json['actualAddress'] as String? ?? '',
      itemId: json['itemId'] as String? ?? '',
      preferredMediaSourceId: json['preferredMediaSourceId'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      headers:
          (json['headers'] as Map<dynamic, dynamic>? ?? const {})
              .map((key, value) => MapEntry('$key', '$value')),
      container: json['container'] as String? ?? '',
      videoCodec: json['videoCodec'] as String? ?? '',
      audioCodec: json['audioCodec'] as String? ?? '',
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      bitrate: (json['bitrate'] as num?)?.toInt(),
      fileSizeBytes: (json['fileSizeBytes'] as num?)?.toInt(),
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
