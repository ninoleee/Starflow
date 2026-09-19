import 'package:starflow/features/library/domain/media_models.dart';

class FntvPlaybackQuality {
  const FntvPlaybackQuality({
    required this.index,
    this.resolution = '',
    this.bitrate = 0,
    this.url = '',
    this.isM3u8 = false,
    this.progressive = false,
    this.serverTranscode = false,
  });

  final int index;
  final String resolution;
  final int bitrate;
  final String url;
  final bool isM3u8;
  final bool progressive;
  final bool serverTranscode;

  String get label {
    final parts = <String>[
      if (resolution.trim().isNotEmpty)
        serverTranscode && int.tryParse(resolution) != null
            ? '${resolution}P'
            : resolution.trim(),
      if (bitrate > 0)
        bitrate >= 1000000
            ? '${(bitrate / 1000000).toStringAsFixed(1)} Mbps'
            : '${(bitrate / 1000).round()} Kbps',
      if (isM3u8) 'HLS',
      if (serverTranscode) '转码',
    ];
    return parts.isEmpty ? '画质 ${index + 1}' : parts.join(' · ');
  }

  Map<String, dynamic> toJson() => {
        'index': index,
        'resolution': resolution,
        'bitrate': bitrate,
        'url': url,
        'isM3u8': isM3u8,
        'progressive': progressive,
        'serverTranscode': serverTranscode,
      };

  factory FntvPlaybackQuality.fromJson(Map<String, dynamic> json) {
    return FntvPlaybackQuality(
      index: (json['index'] as num?)?.toInt() ?? 0,
      resolution: json['resolution'] as String? ?? '',
      bitrate: (json['bitrate'] as num?)?.toInt() ?? 0,
      url: json['url'] as String? ?? '',
      isM3u8: json['isM3u8'] as bool? ?? false,
      progressive: json['progressive'] as bool? ?? false,
      serverTranscode: json['serverTranscode'] as bool? ?? false,
    );
  }
}

class PlaybackAudioStream {
  const PlaybackAudioStream({
    required this.id,
    this.title = '',
    this.language = '',
    this.codec = '',
    this.channels = 0,
    this.isDefault = false,
    this.index = 0,
  });

  final String id;
  final String title;
  final String language;
  final String codec;
  final int channels;
  final bool isDefault;
  final int index;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'language': language,
        'codec': codec,
        'channels': channels,
        'isDefault': isDefault,
        'index': index,
      };

  factory PlaybackAudioStream.fromJson(Map<String, dynamic> json) {
    return PlaybackAudioStream(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      language: json['language'] as String? ?? '',
      codec: json['codec'] as String? ?? '',
      channels: (json['channels'] as num?)?.toInt() ?? 0,
      isDefault: json['isDefault'] as bool? ?? false,
      index: (json['index'] as num?)?.toInt() ?? 0,
    );
  }
}

class PlaybackSubtitleStream {
  const PlaybackSubtitleStream({
    required this.id,
    this.title = '',
    this.language = '',
    this.codec = '',
    this.isDefault = false,
    this.isForced = false,
    this.isExternal = false,
    this.isBitmap = false,
    this.index = 0,
  });

  final String id;
  final String title;
  final String language;
  final String codec;
  final bool isDefault;
  final bool isForced;
  final bool isExternal;
  final bool isBitmap;
  final int index;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'language': language,
        'codec': codec,
        'isDefault': isDefault,
        'isForced': isForced,
        'isExternal': isExternal,
        'isBitmap': isBitmap,
        'index': index,
      };

  factory PlaybackSubtitleStream.fromJson(Map<String, dynamic> json) {
    return PlaybackSubtitleStream(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      language: json['language'] as String? ?? '',
      codec: json['codec'] as String? ?? '',
      isDefault: json['isDefault'] as bool? ?? false,
      isForced: json['isForced'] as bool? ?? false,
      isExternal: json['isExternal'] as bool? ?? false,
      isBitmap: json['isBitmap'] as bool? ?? false,
      index: (json['index'] as num?)?.toInt() ?? 0,
    );
  }
}

class PlaybackTarget {
  const PlaybackTarget({
    required this.title,
    required this.sourceId,
    required this.streamUrl,
    required this.sourceName,
    required this.sourceKind,
    this.allowResume = true,
    this.actualAddress = '',
    this.originalTitle = '',
    this.itemId = '',
    this.itemType = '',
    this.year = 0,
    this.imdbId = '',
    this.tmdbId = '',
    this.seriesId = '',
    this.seriesTitle = '',
    this.preferredMediaSourceId = '',
    this.posterUrl = '',
    this.posterHeaders = const {},
    this.backdropUrl = '',
    this.backdropHeaders = const {},
    this.subtitle = '',
    this.externalSubtitleFilePath = '',
    this.externalSubtitleDisplayName = '',
    this.headers = const {},
    this.container = '',
    this.videoCodec = '',
    this.audioCodec = '',
    this.audioStreams = const [],
    this.subtitleStreams = const [],
    this.preferredAudioStreamId = '',
    this.preferredSubtitleStreamId = '',
    this.videoStreamId = '',
    this.playbackQualities = const [],
    this.preferredPlaybackQualityIndex,
    this.fntvSessionLink = '',
    this.fntvStartPositionMs = 0,
    this.fntvTrackSelectionExplicit = false,
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
  final bool allowResume;
  final String actualAddress;
  final String originalTitle;
  final String itemId;
  final String itemType;
  final int year;
  final String imdbId;
  final String tmdbId;
  final String seriesId;
  final String seriesTitle;
  final String preferredMediaSourceId;
  final String posterUrl;
  final Map<String, String> posterHeaders;
  final String backdropUrl;
  final Map<String, String> backdropHeaders;
  final String subtitle;
  final String externalSubtitleFilePath;
  final String externalSubtitleDisplayName;
  final Map<String, String> headers;
  final String container;
  final String videoCodec;
  final String audioCodec;
  final List<PlaybackAudioStream> audioStreams;
  final List<PlaybackSubtitleStream> subtitleStreams;
  final String preferredAudioStreamId;
  final String preferredSubtitleStreamId;
  final String videoStreamId;
  final List<FntvPlaybackQuality> playbackQualities;
  final int? preferredPlaybackQualityIndex;
  // Raw server control link; not the absolute player URL.
  final String fntvSessionLink;
  final int fntvStartPositionMs;
  final bool fntvTrackSelectionExplicit;
  bool get isFntvTranscoding =>
      sourceKind == MediaSourceKind.fntv && fntvSessionLink.isNotEmpty;
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
    bool? allowResume,
    String? actualAddress,
    String? originalTitle,
    String? itemId,
    String? itemType,
    int? year,
    String? imdbId,
    String? tmdbId,
    String? seriesId,
    String? seriesTitle,
    String? preferredMediaSourceId,
    String? posterUrl,
    Map<String, String>? posterHeaders,
    String? backdropUrl,
    Map<String, String>? backdropHeaders,
    String? subtitle,
    String? externalSubtitleFilePath,
    String? externalSubtitleDisplayName,
    Map<String, String>? headers,
    String? container,
    String? videoCodec,
    String? audioCodec,
    List<PlaybackAudioStream>? audioStreams,
    List<PlaybackSubtitleStream>? subtitleStreams,
    String? preferredAudioStreamId,
    String? preferredSubtitleStreamId,
    String? videoStreamId,
    List<FntvPlaybackQuality>? playbackQualities,
    int? preferredPlaybackQualityIndex,
    String? fntvSessionLink,
    int? fntvStartPositionMs,
    bool? fntvTrackSelectionExplicit,
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
      allowResume: allowResume ?? this.allowResume,
      actualAddress: actualAddress ?? this.actualAddress,
      originalTitle: originalTitle ?? this.originalTitle,
      itemId: itemId ?? this.itemId,
      itemType: itemType ?? this.itemType,
      year: year ?? this.year,
      imdbId: imdbId ?? this.imdbId,
      tmdbId: tmdbId ?? this.tmdbId,
      seriesId: seriesId ?? this.seriesId,
      seriesTitle: seriesTitle ?? this.seriesTitle,
      preferredMediaSourceId:
          preferredMediaSourceId ?? this.preferredMediaSourceId,
      posterUrl: posterUrl ?? this.posterUrl,
      posterHeaders: posterHeaders ?? this.posterHeaders,
      backdropUrl: backdropUrl ?? this.backdropUrl,
      backdropHeaders: backdropHeaders ?? this.backdropHeaders,
      subtitle: subtitle ?? this.subtitle,
      externalSubtitleFilePath:
          externalSubtitleFilePath ?? this.externalSubtitleFilePath,
      externalSubtitleDisplayName:
          externalSubtitleDisplayName ?? this.externalSubtitleDisplayName,
      headers: headers ?? this.headers,
      container: container ?? this.container,
      videoCodec: videoCodec ?? this.videoCodec,
      audioCodec: audioCodec ?? this.audioCodec,
      audioStreams: audioStreams ?? this.audioStreams,
      subtitleStreams: subtitleStreams ?? this.subtitleStreams,
      preferredAudioStreamId:
          preferredAudioStreamId ?? this.preferredAudioStreamId,
      preferredSubtitleStreamId:
          preferredSubtitleStreamId ?? this.preferredSubtitleStreamId,
      videoStreamId: videoStreamId ?? this.videoStreamId,
      playbackQualities: playbackQualities ?? this.playbackQualities,
      preferredPlaybackQualityIndex:
          preferredPlaybackQualityIndex ?? this.preferredPlaybackQualityIndex,
      fntvSessionLink: fntvSessionLink ?? this.fntvSessionLink,
      fntvStartPositionMs: fntvStartPositionMs ?? this.fntvStartPositionMs,
      fntvTrackSelectionExplicit:
          fntvTrackSelectionExplicit ?? this.fntvTrackSelectionExplicit,
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
          sourceKind.isMediaServer &&
          itemId.trim().isNotEmpty) ||
      (streamUrl.trim().isEmpty &&
          sourceKind == MediaSourceKind.quark &&
          itemId.trim().isNotEmpty) ||
      (sourceKind == MediaSourceKind.nas &&
          (_looksLikeStrmReference(streamUrl) ||
              (streamUrl.trim().isEmpty &&
                  _looksLikeStrmReference(actualAddress))));

  bool get canPlay => streamUrl.trim().isNotEmpty || needsResolution;

  bool get hasEffectiveHeaders {
    return headers.entries.any(
      (entry) => entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty,
    );
  }

  bool get requiresHeaderRestrictedPlayback =>
      sourceKind == MediaSourceKind.quark && hasEffectiveHeaders;

  String get normalizedItemType => itemType.trim().toLowerCase();

  bool get isEpisode => normalizedItemType == 'episode';

  bool get isSeries => normalizedItemType == 'series';

  bool get isMovie => normalizedItemType == 'movie';

  bool get isIsoLike =>
      _looksLikeIsoResource(container) ||
      _looksLikeIsoResource(streamUrl) ||
      _looksLikeIsoResource(actualAddress);

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
      actualAddress: normalizePlaybackActualAddress(item.actualAddress),
      originalTitle: item.originalTitle,
      itemId: item.playbackItemId,
      itemType: item.itemType,
      year: item.year,
      imdbId: item.imdbId,
      tmdbId: item.tmdbId,
      preferredMediaSourceId: item.preferredMediaSourceId,
      posterUrl: item.posterUrl,
      posterHeaders: item.posterHeaders,
      backdropUrl: item.backdropUrl,
      backdropHeaders: item.backdropHeaders,
      subtitle: item.overview,
      externalSubtitleFilePath: '',
      externalSubtitleDisplayName: '',
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
      'allowResume': allowResume,
      // A few old index records contained a literal `null:///` URI. Keep the
      // display path usable, but never forward that invalid scheme to native
      // playback or external-player integrations.
      'actualAddress': normalizePlaybackActualAddress(actualAddress),
      'originalTitle': originalTitle,
      'itemId': itemId,
      'itemType': itemType,
      'year': year,
      'imdbId': imdbId,
      'tmdbId': tmdbId,
      'seriesId': seriesId,
      'seriesTitle': seriesTitle,
      'preferredMediaSourceId': preferredMediaSourceId,
      'posterUrl': posterUrl,
      'posterHeaders': posterHeaders,
      'backdropUrl': backdropUrl,
      'backdropHeaders': backdropHeaders,
      'subtitle': subtitle,
      'externalSubtitleFilePath': externalSubtitleFilePath,
      'externalSubtitleDisplayName': externalSubtitleDisplayName,
      'headers': headers,
      'container': container,
      'videoCodec': videoCodec,
      'audioCodec': audioCodec,
      'audioStreams': audioStreams.map((item) => item.toJson()).toList(),
      'subtitleStreams': subtitleStreams.map((item) => item.toJson()).toList(),
      'preferredAudioStreamId': preferredAudioStreamId,
      'preferredSubtitleStreamId': preferredSubtitleStreamId,
      'videoStreamId': videoStreamId,
      'playbackQualities':
          playbackQualities.map((item) => item.toJson()).toList(),
      'preferredPlaybackQualityIndex': preferredPlaybackQualityIndex,
      'fntvSessionLink': fntvSessionLink,
      'fntvStartPositionMs': fntvStartPositionMs,
      'fntvTrackSelectionExplicit': fntvTrackSelectionExplicit,
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
      allowResume: json['allowResume'] as bool? ?? true,
      actualAddress: normalizePlaybackActualAddress(
        json['actualAddress'] as String? ?? '',
      ),
      originalTitle: json['originalTitle'] as String? ?? '',
      itemId: json['itemId'] as String? ?? '',
      itemType: json['itemType'] as String? ?? '',
      year: (json['year'] as num?)?.toInt() ?? 0,
      imdbId: json['imdbId'] as String? ?? '',
      tmdbId: json['tmdbId'] as String? ?? '',
      seriesId: json['seriesId'] as String? ?? '',
      seriesTitle: json['seriesTitle'] as String? ?? '',
      preferredMediaSourceId: json['preferredMediaSourceId'] as String? ?? '',
      posterUrl: json['posterUrl'] as String? ?? '',
      posterHeaders:
          _parseStringMap(json['posterHeaders'] as Map<dynamic, dynamic>?),
      backdropUrl: json['backdropUrl'] as String? ?? '',
      backdropHeaders:
          _parseStringMap(json['backdropHeaders'] as Map<dynamic, dynamic>?),
      subtitle: json['subtitle'] as String? ?? '',
      externalSubtitleFilePath:
          json['externalSubtitleFilePath'] as String? ?? '',
      externalSubtitleDisplayName:
          json['externalSubtitleDisplayName'] as String? ?? '',
      headers: _parseStringMap(json['headers'] as Map<dynamic, dynamic>?),
      container: json['container'] as String? ?? '',
      videoCodec: json['videoCodec'] as String? ?? '',
      audioCodec: json['audioCodec'] as String? ?? '',
      audioStreams: (json['audioStreams'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) =>
              PlaybackAudioStream.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false),
      subtitleStreams: (json['subtitleStreams'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) =>
              PlaybackSubtitleStream.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false),
      preferredAudioStreamId: json['preferredAudioStreamId'] as String? ?? '',
      preferredSubtitleStreamId:
          json['preferredSubtitleStreamId'] as String? ?? '',
      videoStreamId: json['videoStreamId'] as String? ?? '',
      playbackQualities:
          (json['playbackQualities'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map((item) =>
                  FntvPlaybackQuality.fromJson(Map<String, dynamic>.from(item)))
              .toList(growable: false),
      preferredPlaybackQualityIndex:
          (json['preferredPlaybackQualityIndex'] as num?)?.toInt(),
      fntvSessionLink: json['fntvSessionLink'] as String? ?? '',
      fntvStartPositionMs: (json['fntvStartPositionMs'] as num?)?.toInt() ?? 0,
      fntvTrackSelectionExplicit:
          json['fntvTrackSelectionExplicit'] as bool? ?? false,
      seasonNumber: (json['seasonNumber'] as num?)?.toInt(),
      episodeNumber: (json['episodeNumber'] as num?)?.toInt(),
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      bitrate: (json['bitrate'] as num?)?.toInt(),
      fileSizeBytes: (json['fileSizeBytes'] as num?)?.toInt(),
    );
  }
}

Map<String, String> _parseStringMap(Map<dynamic, dynamic>? raw) {
  return (raw ?? const {}).map((key, value) => MapEntry('$key', '$value'));
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

bool _looksLikeIsoResource(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) {
    return false;
  }
  if (normalized == 'iso') {
    return true;
  }
  final uri = Uri.tryParse(normalized);
  final path = (uri?.path ?? normalized).trim().toLowerCase();
  return path.endsWith('.iso');
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

/// Removes the invalid URI scheme emitted by older NAS index records.
///
/// `null:///path` is not a playable address; it is the string form of a
/// malformed URI created while a source URI was unavailable. The stream URL
/// remains authoritative for playback, while this address is used for display
/// and diagnostics only.
String normalizePlaybackActualAddress(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final parsed = Uri.tryParse(trimmed);
  if (parsed != null && parsed.scheme.toLowerCase() == 'null') {
    final path = parsed.path.trim();
    return path.isNotEmpty ? path : '';
  }
  return trimmed;
}
