import 'package:xml/xml.dart';

class ParsedNfoMetadata {
  const ParsedNfoMetadata({
    required this.title,
    required this.overview,
    required this.thumbUrl,
    required this.backdropUrl,
    required this.logoUrl,
    required this.bannerUrl,
    required this.extraBackdropUrls,
    required this.year,
    required this.durationLabel,
    required this.genres,
    required this.directors,
    required this.actors,
    required this.itemType,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.imdbId,
    required this.tmdbId,
    required this.container,
    required this.videoCodec,
    required this.audioCodec,
    required this.width,
    required this.height,
    required this.bitrate,
  });

  final String title;
  final String overview;
  final String thumbUrl;
  final String backdropUrl;
  final String logoUrl;
  final String bannerUrl;
  final List<String> extraBackdropUrls;
  final int year;
  final String durationLabel;
  final List<String> genres;
  final List<String> directors;
  final List<String> actors;
  final String itemType;
  final int? seasonNumber;
  final int? episodeNumber;
  final String imdbId;
  final String tmdbId;
  final String container;
  final String videoCodec;
  final String audioCodec;
  final int? width;
  final int? height;
  final int? bitrate;
}

class _NfoStreamDetails {
  const _NfoStreamDetails({
    this.container = '',
    this.videoCodec = '',
    this.audioCodec = '',
    this.width,
    this.height,
    this.bitrate,
  });

  final String container;
  final String videoCodec;
  final String audioCodec;
  final int? width;
  final int? height;
  final int? bitrate;
}

ParsedNfoMetadata? parseNfoMetadata(String body,
    {String Function(String)? resolveArtwork}) {
  try {
    final document = XmlDocument.parse(body);
    final root = document.rootElement;
    final title = _xmlSingleText(root, 'title');
    final plot = _xmlSingleText(root, 'plot');
    final outline = _xmlSingleText(root, 'outline');
    final year = _parseNfoYear(
      _xmlSingleText(root, 'year'),
      fallbackDateText:
          '${_xmlSingleText(root, 'premiered')} ${_xmlSingleText(root, 'aired')}',
    );
    final runtime = _formatRuntimeLabel(
      _xmlSingleText(root, 'runtime'),
      durationSeconds: _tryParseInt(_xmlSingleText(root, 'durationinseconds')),
    );
    final genres = _xmlTexts(root, 'genre');
    final directors = _xmlTexts(root, 'director');
    final actors = root
        .findElements('actor')
        .map((element) => _xmlSingleText(element, 'name'))
        .where((item) => item.trim().isNotEmpty)
        .toList(growable: false);
    final imdbId = _resolveNfoExternalId(
      root,
      type: 'imdb',
      fallbackTag: 'imdbid',
    );
    final tmdbId = _resolveNfoExternalId(
      root,
      type: 'tmdb',
      fallbackTag: 'tmdbid',
    );
    final thumbUrl = _resolveThumbUrl(
      resolveArtwork,
      _xmlSingleText(root, 'thumb'),
    );
    final backdropUrl = _resolveNfoBackdropUrl(root, resolveArtwork);
    final logoUrl = _resolveNfoArtUrl(
      root,
      resolveArtwork,
      types: const ['clearlogo', 'logo'],
    );
    final bannerUrl = _resolveNfoArtUrl(
      root,
      resolveArtwork,
      types: const ['banner'],
    );
    final extraBackdropUrls =
        _resolveNfoExtraBackdropUrls(root, resolveArtwork);
    final streamDetails = _parseNfoStreamDetails(root);
    return ParsedNfoMetadata(
      title: title,
      overview: plot.trim().isNotEmpty ? plot : outline,
      thumbUrl: thumbUrl.isNotEmpty
          ? thumbUrl
          : _resolveNfoArtUrl(root, resolveArtwork, types: const ['poster']),
      backdropUrl: backdropUrl,
      logoUrl: logoUrl,
      bannerUrl: bannerUrl,
      extraBackdropUrls: extraBackdropUrls,
      year: year,
      durationLabel: runtime,
      genres: genres,
      directors: directors,
      actors: actors,
      itemType: _resolveNfoItemType(root.name.local),
      seasonNumber: _tryParseInt(_xmlSingleText(root, 'season')),
      episodeNumber: _tryParseInt(_xmlSingleText(root, 'episode')),
      imdbId: imdbId,
      tmdbId: tmdbId,
      container: streamDetails.container,
      videoCodec: streamDetails.videoCodec,
      audioCodec: streamDetails.audioCodec,
      width: streamDetails.width,
      height: streamDetails.height,
      bitrate: streamDetails.bitrate,
    );
  } catch (_) {
    return null;
  }
}

ParsedNfoMetadata? mergeNfoMetadata({
  required ParsedNfoMetadata? primary,
  required ParsedNfoMetadata? secondary,
}) {
  if (primary == null) {
    return secondary;
  }
  if (secondary == null) {
    return primary;
  }
  return ParsedNfoMetadata(
    title: primary.title.trim().isNotEmpty ? primary.title : secondary.title,
    overview: primary.overview.trim().isNotEmpty
        ? primary.overview
        : secondary.overview,
    thumbUrl: primary.thumbUrl.trim().isNotEmpty
        ? primary.thumbUrl
        : secondary.thumbUrl,
    backdropUrl: primary.backdropUrl.trim().isNotEmpty
        ? primary.backdropUrl
        : secondary.backdropUrl,
    logoUrl:
        primary.logoUrl.trim().isNotEmpty ? primary.logoUrl : secondary.logoUrl,
    bannerUrl: primary.bannerUrl.trim().isNotEmpty
        ? primary.bannerUrl
        : secondary.bannerUrl,
    extraBackdropUrls: primary.extraBackdropUrls.isNotEmpty
        ? primary.extraBackdropUrls
        : secondary.extraBackdropUrls,
    year: primary.year > 0 ? primary.year : secondary.year,
    durationLabel: primary.durationLabel.trim().isNotEmpty &&
            primary.durationLabel.trim() != '文件'
        ? primary.durationLabel
        : secondary.durationLabel,
    genres: primary.genres.isNotEmpty ? primary.genres : secondary.genres,
    directors:
        primary.directors.isNotEmpty ? primary.directors : secondary.directors,
    actors: primary.actors.isNotEmpty ? primary.actors : secondary.actors,
    itemType: primary.itemType.trim().isNotEmpty
        ? primary.itemType
        : secondary.itemType,
    seasonNumber: primary.seasonNumber ?? secondary.seasonNumber,
    episodeNumber: primary.episodeNumber ?? secondary.episodeNumber,
    imdbId:
        primary.imdbId.trim().isNotEmpty ? primary.imdbId : secondary.imdbId,
    tmdbId:
        primary.tmdbId.trim().isNotEmpty ? primary.tmdbId : secondary.tmdbId,
    container: primary.container.trim().isNotEmpty
        ? primary.container
        : secondary.container,
    videoCodec: primary.videoCodec.trim().isNotEmpty
        ? primary.videoCodec
        : secondary.videoCodec,
    audioCodec: primary.audioCodec.trim().isNotEmpty
        ? primary.audioCodec
        : secondary.audioCodec,
    width: primary.width ?? secondary.width,
    height: primary.height ?? secondary.height,
    bitrate: primary.bitrate ?? secondary.bitrate,
  );
}

String _xmlSingleText(XmlElement node, String localName) {
  final match = node.children.whereType<XmlElement>().firstWhere(
        (element) => element.name.local == localName,
        orElse: () => XmlElement(XmlName(localName)),
      );
  return match.innerText.trim();
}

List<String> _xmlTexts(XmlElement node, String localName) {
  return node.children
      .whereType<XmlElement>()
      .where((element) => element.name.local == localName)
      .map((element) => element.innerText.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

int _parseNfoYear(String raw, {String fallbackDateText = ''}) {
  final parsed = _tryParseInt(raw);
  if (parsed != null && parsed > 0) {
    return parsed;
  }
  final match = RegExp(r'(\d{4})').firstMatch(fallbackDateText);
  return match == null ? 0 : int.parse(match.group(1)!);
}

int? _tryParseInt(String raw) {
  return int.tryParse(raw.trim());
}

String _formatRuntimeLabel(String raw, {int? durationSeconds}) {
  final minutes = int.tryParse(raw.trim());
  if (minutes != null && minutes > 0) {
    return '$minutes分钟';
  }
  final resolvedSeconds = durationSeconds ?? 0;
  if (resolvedSeconds > 0) {
    final roundedMinutes = (resolvedSeconds / 60).round();
    if (roundedMinutes > 0) {
      return '$roundedMinutes分钟';
    }
  }
  return '文件';
}

String _resolveNfoExternalId(
  XmlElement root, {
  required String type,
  required String fallbackTag,
}) {
  for (final element in root.children.whereType<XmlElement>()) {
    if (element.name.local != 'uniqueid') {
      continue;
    }
    final idType = element.getAttribute('type')?.trim().toLowerCase() ?? '';
    if (idType == type) {
      final value = element.innerText.trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
  }
  return _xmlSingleText(root, fallbackTag);
}

String _resolveThumbUrl(
    String Function(String)? resolveArtwork, String rawThumb) {
  final trimmed = rawThumb.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final parsed = Uri.tryParse(trimmed);
  if (parsed != null && parsed.hasScheme) {
    return trimmed;
  }
  return resolveArtwork?.call(trimmed) ?? '';
}

String _resolveNfoBackdropUrl(
    XmlElement root, String Function(String)? resolveArtwork) {
  final artFanart = _resolveNfoArtUrl(
    root,
    resolveArtwork,
    types: const ['fanart', 'backdrop', 'landscape'],
  );
  if (artFanart.isNotEmpty) {
    return artFanart;
  }
  final fanartElements = root.descendants
      .whereType<XmlElement>()
      .where((element) => element.name.local == 'fanart');
  for (final element in fanartElements) {
    final thumbs = element.children
        .whereType<XmlElement>()
        .where((child) => child.name.local == 'thumb')
        .map((child) => _resolveThumbUrl(resolveArtwork, child.innerText))
        .where((value) => value.trim().isNotEmpty)
        .toList(growable: false);
    if (thumbs.isNotEmpty) {
      return thumbs.first;
    }
    final direct = _resolveThumbUrl(resolveArtwork, element.innerText);
    if (direct.trim().isNotEmpty) {
      return direct;
    }
  }
  return '';
}

List<String> _resolveNfoExtraBackdropUrls(
    XmlElement root, String Function(String)? resolveArtwork) {
  final fanartElements = root.descendants
      .whereType<XmlElement>()
      .where((element) => element.name.local == 'fanart');
  for (final element in fanartElements) {
    final urls = element.children
        .whereType<XmlElement>()
        .where((child) => child.name.local == 'thumb')
        .map((child) => _resolveThumbUrl(resolveArtwork, child.innerText))
        .where((value) => value.trim().isNotEmpty)
        .toList(growable: false);
    if (urls.isNotEmpty) {
      return urls;
    }
  }
  return const [];
}

String _resolveNfoArtUrl(
  XmlElement root,
  String Function(String)? resolveArtwork, {
  required List<String> types,
}) {
  final normalizedTypes = types.map((type) => type.toLowerCase()).toSet();
  for (final child in root.children.whereType<XmlElement>()) {
    if (!normalizedTypes.contains(child.name.local.toLowerCase()) ||
        child.childElements.isNotEmpty) {
      continue;
    }
    final resolved = _resolveThumbUrl(resolveArtwork, child.innerText);
    if (resolved.isNotEmpty) return resolved;
  }
  for (final art in root.descendants.whereType<XmlElement>()) {
    if (art.name.local != 'art') {
      continue;
    }
    for (final child in art.children.whereType<XmlElement>()) {
      if (!normalizedTypes.contains(child.name.local.toLowerCase())) {
        continue;
      }
      final resolved = _resolveThumbUrl(resolveArtwork, child.innerText);
      if (resolved.trim().isNotEmpty) {
        return resolved;
      }
    }
  }
  return '';
}

_NfoStreamDetails _parseNfoStreamDetails(XmlElement root) {
  final streamDetails = root.descendants.whereType<XmlElement>().firstWhere(
        (element) => element.name.local == 'streamdetails',
        orElse: () => XmlElement(XmlName('streamdetails')),
      );
  if (streamDetails.children.isEmpty) {
    return const _NfoStreamDetails();
  }

  final videoElements = streamDetails.children
      .whereType<XmlElement>()
      .where((element) => element.name.local == 'video')
      .toList(growable: false);
  final audioElements = streamDetails.children
      .whereType<XmlElement>()
      .where((element) => element.name.local == 'audio')
      .toList(growable: false);
  final fileInfoElements = root.descendants
      .whereType<XmlElement>()
      .where((element) => element.name.local == 'fileinfo')
      .toList(growable: false);

  final video = videoElements.isEmpty ? null : videoElements.first;
  final audio = audioElements.isEmpty ? null : audioElements.first;
  String container = '';
  for (final fileInfo in fileInfoElements) {
    final value = _xmlSingleText(fileInfo, 'container');
    if (value.trim().isNotEmpty) {
      container = value.trim();
      break;
    }
  }

  return _NfoStreamDetails(
    container: container,
    videoCodec: video == null ? '' : _xmlSingleText(video, 'codec'),
    audioCodec: audio == null ? '' : _xmlSingleText(audio, 'codec'),
    width: video == null ? null : _tryParseInt(_xmlSingleText(video, 'width')),
    height:
        video == null ? null : _tryParseInt(_xmlSingleText(video, 'height')),
    bitrate: _tryParseInt(
      video == null ? '' : _xmlSingleText(video, 'bitrate'),
    ),
  );
}

String _resolveNfoItemType(String rawRootName) {
  switch (rawRootName.trim().toLowerCase()) {
    case 'movie':
      return 'movie';
    case 'tvshow':
      return 'series';
    case 'episodedetails':
      return 'episode';
    default:
      return '';
  }
}
