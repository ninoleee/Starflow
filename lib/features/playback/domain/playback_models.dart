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
    this.itemType = '',
    this.year = 0,
    this.seriesId = '',
    this.seriesTitle = '',
    this.preferredMediaSourceId = '',
    this.subtitle = '',
    this.headers = const {},
    this.container = '',
    this.videoCodec = '',
    this.audioCodec = '',
    this.seasonNumber,
    this.episodeNumber,
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
  final String itemType;
  final int year;
  final String seriesId;
  final String seriesTitle;
  final String preferredMediaSourceId;
  final String subtitle;
  final Map<String, String> headers;
  final String container;
  final String videoCodec;
  final String audioCodec;
  final int? seasonNumber;
  final int? episodeNumber;
  final int? width;
  final int? height;
  final int? bitrate;
  final int? fileSizeBytes;

  PlaybackTarget copyWith({
    String? title,
    String? sourceId,
    String? streamUrl,
    String? sourceName,
    MediaSourceKind? sourceKind,
    String? actualAddress,
    String? itemId,
    String? itemType,
    int? year,
    String? seriesId,
    String? seriesTitle,
    String? preferredMediaSourceId,
    String? subtitle,
    Map<String, String>? headers,
    String? container,
    String? videoCodec,
    String? audioCodec,
    int? seasonNumber,
    int? episodeNumber,
    int? width,
    int? height,
    int? bitrate,
    int? fileSizeBytes,
  }) {
    return PlaybackTarget(
      title: title ?? this.title,
      sourceId: sourceId ?? this.sourceId,
      streamUrl: streamUrl ?? this.streamUrl,
      sourceName: sourceName ?? this.sourceName,
      sourceKind: sourceKind ?? this.sourceKind,
      actualAddress: actualAddress ?? this.actualAddress,
      itemId: itemId ?? this.itemId,
      itemType: itemType ?? this.itemType,
      year: year ?? this.year,
      seriesId: seriesId ?? this.seriesId,
      seriesTitle: seriesTitle ?? this.seriesTitle,
      preferredMediaSourceId:
          preferredMediaSourceId ?? this.preferredMediaSourceId,
      subtitle: subtitle ?? this.subtitle,
      headers: headers ?? this.headers,
      container: container ?? this.container,
      videoCodec: videoCodec ?? this.videoCodec,
      audioCodec: audioCodec ?? this.audioCodec,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      width: width ?? this.width,
      height: height ?? this.height,
      bitrate: bitrate ?? this.bitrate,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
    );
  }

  bool get needsResolution =>
      (streamUrl.trim().isEmpty &&
          sourceKind == MediaSourceKind.emby &&
          itemId.trim().isNotEmpty) ||
      (sourceKind == MediaSourceKind.nas &&
          (_looksLikeStrmReference(streamUrl) ||
              (streamUrl.trim().isEmpty &&
                  _looksLikeStrmReference(actualAddress))));

  bool get canPlay => streamUrl.trim().isNotEmpty || needsResolution;

  String get normalizedItemType => itemType.trim().toLowerCase();

  bool get isEpisode => normalizedItemType == 'episode';

  bool get isSeries => normalizedItemType == 'series';

  bool get isMovie => normalizedItemType == 'movie';

  String get resolvedSeriesTitle {
    final trimmed = seriesTitle.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
    return isSeries ? title.trim() : '';
  }

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
      itemType: item.itemType,
      year: item.year,
      preferredMediaSourceId: item.preferredMediaSourceId,
      subtitle: item.overview,
      headers: item.streamHeaders,
      container: item.container.trim().isNotEmpty
          ? item.container
          : _inferContainerFromUrl(item.streamUrl),
      videoCodec: item.videoCodec,
      audioCodec: item.audioCodec,
      seasonNumber: item.seasonNumber,
      episodeNumber: item.episodeNumber,
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
      'itemType': itemType,
      'year': year,
      'seriesId': seriesId,
      'seriesTitle': seriesTitle,
      'preferredMediaSourceId': preferredMediaSourceId,
      'subtitle': subtitle,
      'headers': headers,
      'container': container,
      'videoCodec': videoCodec,
      'audioCodec': audioCodec,
      'seasonNumber': seasonNumber,
      'episodeNumber': episodeNumber,
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
      sourceKind:
          MediaSourceKindX.fromName(json['sourceKind'] as String? ?? ''),
      actualAddress: json['actualAddress'] as String? ?? '',
      itemId: json['itemId'] as String? ?? '',
      itemType: json['itemType'] as String? ?? '',
      year: (json['year'] as num?)?.toInt() ?? 0,
      seriesId: json['seriesId'] as String? ?? '',
      seriesTitle: json['seriesTitle'] as String? ?? '',
      preferredMediaSourceId: json['preferredMediaSourceId'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      headers: (json['headers'] as Map<dynamic, dynamic>? ?? const {})
          .map((key, value) => MapEntry('$key', '$value')),
      container: json['container'] as String? ?? '',
      videoCodec: json['videoCodec'] as String? ?? '',
      audioCodec: json['audioCodec'] as String? ?? '',
      seasonNumber: (json['seasonNumber'] as num?)?.toInt(),
      episodeNumber: (json['episodeNumber'] as num?)?.toInt(),
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

bool _looksLikeStrmReference(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) {
    return false;
  }
  final uri = Uri.tryParse(normalized);
  final path = (uri?.path ?? normalized).trim().toLowerCase();
  return path.endsWith('.strm');
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
