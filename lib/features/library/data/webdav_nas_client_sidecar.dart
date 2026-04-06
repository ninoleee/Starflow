part of 'webdav_nas_client.dart';

extension _WebDavNasClientSidecar on WebDavNasClient {
  Future<WebDavMetadataSeed> _resolveSidecarMetadata(
    _WebDavEntry videoEntry, {
    required List<_WebDavEntry> siblings,
    required MediaSourceConfig source,
  }) async {
    webDavTrace(
      'sidecar.start',
      fields: {
        'video': videoEntry.uri,
        'fileName': videoEntry.name,
      },
    );
    final currentDirectoryUri = _parentDirectoryUri(videoEntry.uri);
    final parentDirectoryUri = currentDirectoryUri == null
        ? null
        : _parentDirectoryUri(currentDirectoryUri);
    final grandParentDirectoryUri = parentDirectoryUri == null
        ? null
        : _parentDirectoryUri(parentDirectoryUri);

    final parentEntries = parentDirectoryUri == null
        ? const <_WebDavEntry>[]
        : await _loadDirectoryEntries(parentDirectoryUri, source: source);
    final grandParentEntries = grandParentDirectoryUri == null
        ? const <_WebDavEntry>[]
        : await _loadDirectoryEntries(grandParentDirectoryUri, source: source);

    final primaryNfoEntry = _findBestNfoEntry(videoEntry, siblings);
    final seasonNfoEntry = _findNamedNfoEntry(
      siblings,
      const ['season.nfo', 'index.nfo'],
      excluding: primaryNfoEntry,
    );
    final seriesNfoEntry = _findNamedNfoEntry(
          parentEntries,
          const ['tvshow.nfo', 'index.nfo'],
        ) ??
        _findNamedNfoEntry(
          grandParentEntries,
          const ['tvshow.nfo', 'index.nfo'],
        );

    final primaryNfoMetadata = primaryNfoEntry == null
        ? null
        : await _loadNfoMetadata(primaryNfoEntry, source: source);
    final seasonNfoMetadata = seasonNfoEntry == null
        ? null
        : await _loadNfoMetadata(seasonNfoEntry, source: source);
    final seriesNfoMetadata = seriesNfoEntry == null
        ? null
        : await _loadNfoMetadata(seriesNfoEntry, source: source);
    final nfoMetadata = _mergeNfoMetadata(
      primary: primaryNfoMetadata,
      secondary: _mergeNfoMetadata(
        primary: seasonNfoMetadata,
        secondary: seriesNfoMetadata,
      ),
    );
    final inferredMediaInfo = _inferMediaInfo(videoEntry);

    final localPosterEntry = _findBestPosterEntry(videoEntry, siblings) ??
        _findSeasonPosterEntry(
          videoEntry,
          siblings,
          seasonHint: nfoMetadata?.seasonNumber,
        ) ??
        _findPosterByRole(parentEntries) ??
        _findPosterByRole(grandParentEntries);
    final localBackdropEntry = _findBackdropByRole(siblings) ??
        _findBackdropByRole(parentEntries) ??
        _findBackdropByRole(grandParentEntries);
    final localLogoEntry = _findLogoByRole(siblings) ??
        _findLogoByRole(parentEntries) ??
        _findLogoByRole(grandParentEntries);
    final localBannerEntry = _findBannerByRole(siblings) ??
        _findBannerByRole(parentEntries) ??
        _findBannerByRole(grandParentEntries);
    final localExtraBackdropEntries = await _loadExtraBackdropEntries(
      source: source,
      candidates: [
        (entries: siblings, baseUri: currentDirectoryUri),
        if (parentDirectoryUri != null)
          (entries: parentEntries, baseUri: parentDirectoryUri),
        if (grandParentDirectoryUri != null)
          (entries: grandParentEntries, baseUri: grandParentDirectoryUri),
      ],
    );

    final posterArtwork = _resolveArtworkCandidate(
      source: source,
      localEntry: localPosterEntry,
      remoteUrl: nfoMetadata?.thumbUrl ?? '',
    );
    final backdropArtwork =
        localExtraBackdropEntries.isNotEmpty && localBackdropEntry == null
            ? _ArtworkResolution(
                url: localExtraBackdropEntries.first.uri.toString(),
                headers: _headers(source),
              )
            : _resolveArtworkCandidate(
                source: source,
                localEntry: localBackdropEntry,
                remoteUrl: nfoMetadata?.backdropUrl ??
                    (nfoMetadata?.extraBackdropUrls.isNotEmpty == true
                        ? nfoMetadata!.extraBackdropUrls.first
                        : ''),
              );
    final logoArtwork = _resolveArtworkCandidate(
      source: source,
      localEntry: localLogoEntry,
      remoteUrl: nfoMetadata?.logoUrl ?? '',
    );
    final bannerArtwork = _resolveArtworkCandidate(
      source: source,
      localEntry: localBannerEntry,
      remoteUrl: nfoMetadata?.bannerUrl ?? '',
    );
    final extraBackdropUrls = localExtraBackdropEntries.isNotEmpty
        ? localExtraBackdropEntries.map((entry) => entry.uri.toString()).toList(
              growable: false,
            )
        : nfoMetadata?.extraBackdropUrls ?? const <String>[];
    final extraBackdropHeaders = localExtraBackdropEntries.isNotEmpty
        ? _headers(source)
        : _headersForArtworkUrl(
            source,
            extraBackdropUrls.isEmpty ? '' : extraBackdropUrls.first,
          );

    final hasSidecarMatch = nfoMetadata != null ||
        localPosterEntry != null ||
        localBackdropEntry != null ||
        localLogoEntry != null ||
        localBannerEntry != null ||
        localExtraBackdropEntries.isNotEmpty;
    final seed = WebDavMetadataSeed(
      title: nfoMetadata?.title.trim().isNotEmpty == true
          ? nfoMetadata!.title.trim()
          : _stripExtension(videoEntry.name),
      overview: nfoMetadata?.overview ?? '',
      posterUrl: posterArtwork.url,
      posterHeaders: posterArtwork.headers,
      backdropUrl: backdropArtwork.url,
      backdropHeaders: backdropArtwork.headers,
      logoUrl: logoArtwork.url,
      logoHeaders: logoArtwork.headers,
      bannerUrl: bannerArtwork.url,
      bannerHeaders: bannerArtwork.headers,
      extraBackdropUrls: extraBackdropUrls,
      extraBackdropHeaders: extraBackdropHeaders,
      year: nfoMetadata?.year ?? 0,
      durationLabel: nfoMetadata?.durationLabel ?? '文件',
      genres: nfoMetadata?.genres ?? const [],
      directors: nfoMetadata?.directors ?? const [],
      actors: nfoMetadata?.actors ?? const [],
      itemType: nfoMetadata?.itemType ?? '',
      seasonNumber: nfoMetadata?.seasonNumber,
      episodeNumber: nfoMetadata?.episodeNumber,
      imdbId: nfoMetadata?.imdbId ?? '',
      tmdbId: nfoMetadata?.tmdbId ?? '',
      container: _firstNonEmpty(
        nfoMetadata?.container ?? '',
        inferredMediaInfo.container,
      ),
      videoCodec: _firstNonEmpty(
        nfoMetadata?.videoCodec ?? '',
        inferredMediaInfo.videoCodec,
      ),
      audioCodec: _firstNonEmpty(
        nfoMetadata?.audioCodec ?? '',
        inferredMediaInfo.audioCodec,
      ),
      width: nfoMetadata?.width ?? inferredMediaInfo.width,
      height: nfoMetadata?.height ?? inferredMediaInfo.height,
      bitrate: nfoMetadata?.bitrate ?? inferredMediaInfo.bitrate,
      hasSidecarMatch: hasSidecarMatch,
    );
    webDavTrace(
      'sidecar.done',
      fields: {
        'video': videoEntry.uri,
        'primaryNfo': primaryNfoEntry?.name ?? '',
        'seasonNfo': seasonNfoEntry?.name ?? '',
        'seriesNfo': seriesNfoEntry?.name ?? '',
        'title': seed.title,
        'itemType': seed.itemType,
        'season': seed.seasonNumber,
        'episode': seed.episodeNumber,
        'imdbId': seed.imdbId,
        'tmdbId': seed.tmdbId,
        'hasPoster': seed.posterUrl.isNotEmpty,
        'hasBackdrop': seed.backdropUrl.isNotEmpty,
        'hasLogo': seed.logoUrl.isNotEmpty,
        'hasSidecarMatch': seed.hasSidecarMatch,
      },
    );
    return seed;
  }

  WebDavMetadataSeed _buildBasicMetadataSeed(_WebDavEntry videoEntry) {
    final inferredMediaInfo = _inferMediaInfo(videoEntry);
    return WebDavMetadataSeed(
      title: _stripExtension(videoEntry.name),
      overview: '',
      posterUrl: '',
      posterHeaders: const {},
      backdropUrl: '',
      backdropHeaders: const {},
      logoUrl: '',
      logoHeaders: const {},
      bannerUrl: '',
      bannerHeaders: const {},
      extraBackdropUrls: const [],
      extraBackdropHeaders: const {},
      year: 0,
      durationLabel: '文件',
      genres: const [],
      directors: const [],
      actors: const [],
      itemType: '',
      seasonNumber: null,
      episodeNumber: null,
      imdbId: '',
      tmdbId: '',
      container: inferredMediaInfo.container,
      videoCodec: inferredMediaInfo.videoCodec,
      audioCodec: inferredMediaInfo.audioCodec,
      width: inferredMediaInfo.width,
      height: inferredMediaInfo.height,
      bitrate: inferredMediaInfo.bitrate,
      hasSidecarMatch: false,
    );
  }

  Future<List<_WebDavEntry>> _propfind(
    Uri uri, {
    required MediaSourceConfig source,
  }) async {
    webDavTrace(
      'propfind.request',
      fields: {
        'uri': uri,
        'sourceId': source.id,
      },
    );
    final request = http.Request('PROPFIND', uri)
      ..headers.addAll({
        ..._headers(source),
        'Depth': '1',
        'Content-Type': 'application/xml; charset=utf-8',
      })
      ..body = '''<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:displayname />
    <d:getcontentlength />
    <d:getcontenttype />
    <d:getlastmodified />
    <d:resourcetype />
  </d:prop>
</d:propfind>''';

    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 207 && response.statusCode != 200) {
      webDavTrace(
        'propfind.error',
        fields: {
          'uri': uri,
          'status': response.statusCode,
        },
      );
      throw WebDavNasException('WebDAV 请求失败：HTTP ${response.statusCode}');
    }
    if (response.body.trim().isEmpty) {
      webDavTrace(
        'propfind.empty',
        fields: {
          'uri': uri,
          'status': response.statusCode,
        },
      );
      return const [];
    }

    final document = XmlDocument.parse(response.body);
    final responses = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'response');
    final normalizedSelf = _normalizeUri(uri);

    final parsed = responses.map((node) {
      final href = _childText(node, 'href');
      final resolvedUri = _resolveHref(uri, href);
      final prop = node.descendants.whereType<XmlElement>().firstWhere(
            (element) => element.name.local == 'prop',
            orElse: () => XmlElement(XmlName('prop')),
          );
      final isCollection = prop.descendants
          .whereType<XmlElement>()
          .any((element) => element.name.local == 'collection');
      final displayName = _childText(prop, 'displayname');
      final contentType = _childText(prop, 'getcontenttype');
      final contentLength =
          _tryParseInt(_childText(prop, 'getcontentlength')) ?? 0;
      final modifiedAt = _parseModifiedAt(_childText(prop, 'getlastmodified'));

      return _WebDavEntry(
        uri: resolvedUri,
        name: displayName.trim().isEmpty
            ? _displayNameFromUri(resolvedUri, fallback: source.name)
            : displayName.trim(),
        isCollection: isCollection,
        contentType: contentType.trim(),
        sizeBytes: contentLength,
        modifiedAt: modifiedAt,
        isSelf: _normalizeUri(resolvedUri) == normalizedSelf,
      );
    }).toList();
    webDavTrace(
      'propfind.response',
      fields: {
        'uri': uri,
        'status': response.statusCode,
        'count': parsed.length,
        'entries': parsed
            .map((entry) =>
                '${entry.isCollection ? 'dir' : 'file'}:${entry.name}')
            .toList(),
      },
    );
    return parsed;
  }

  Map<String, String> _headers(MediaSourceConfig source) {
    final username = source.username.trim();
    final password = source.password;
    if (username.isEmpty) {
      return const {
        'Accept': '*/*',
      };
    }

    final token = base64Encode(utf8.encode('$username:$password'));
    return {
      'Accept': '*/*',
      'Authorization': 'Basic $token',
    };
  }

  String _browseRoot(MediaSourceConfig source) {
    final selectedPath = source.libraryPath.trim();
    if (selectedPath.isNotEmpty) {
      return selectedPath;
    }
    return source.endpoint.trim();
  }

  bool _isExcludedByKeyword(
    Uri uri, {
    required MediaSourceConfig source,
  }) {
    return source.matchesWebDavExcludedUri(uri);
  }

  List<_WebDavEntry> _filterExcludedEntries(
    List<_WebDavEntry> entries, {
    required MediaSourceConfig source,
  }) {
    final filtered = <_WebDavEntry>[];
    for (final entry in entries) {
      if (!entry.isSelf && _isExcludedByKeyword(entry.uri, source: source)) {
        webDavTrace(
          'filter.exclude',
          fields: {
            'uri': entry.uri,
            'name': entry.name,
            'keywords': source.normalizedWebDavExcludedPathKeywords,
          },
        );
        continue;
      }
      filtered.add(entry);
    }
    return filtered;
  }

  /// 详情页「地址」用：优先显示完整的 WebDAV 路径，而不是播放直链。
  String _relativePathForNasDisplay(
    Uri resource, {
    required MediaSourceConfig source,
  }) {
    final path = resource.path.trim();
    if (path.isNotEmpty) {
      try {
        return Uri.decodeFull(path);
      } catch (_) {
        return path;
      }
    }
    return resource.toString();
  }

  bool _isPlayableVideo(_WebDavEntry entry) {
    final type = entry.contentType.toLowerCase();
    if (type.startsWith('video/')) {
      return true;
    }

    final path = entry.uri.path.toLowerCase();
    return const [
      '.mp4',
      '.m4v',
      '.mov',
      '.mkv',
      '.avi',
      '.ts',
      '.webm',
      '.flv',
      '.wmv',
      '.mpg',
      '.mpeg',
      '.strm',
    ].any(path.endsWith);
  }

  bool _isStrmFile(_WebDavEntry entry) {
    return entry.uri.path.toLowerCase().endsWith('.strm');
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

  Future<_ResolvedPlayableSource> _resolvePlayableSource(
    _WebDavEntry entry, {
    required MediaSourceConfig source,
    required bool resolveStrmTarget,
  }) async {
    if (!_isStrmFile(entry)) {
      return _ResolvedPlayableSource(
        streamUrl: entry.uri.toString(),
        headers: _headersForResolvedStream(source, entry.uri.toString()),
      );
    }
    if (!resolveStrmTarget) {
      webDavTrace(
        'resolvePlayable.strm.deferred',
        fields: {
          'uri': entry.uri,
          'streamUrl': entry.uri,
        },
      );
      return _ResolvedPlayableSource(
        streamUrl: entry.uri.toString(),
        headers: _headers(source),
      );
    }

    final resolvedStreamUrl =
        await _resolvePlayableUrlFromUri(entry.uri, source: source);
    return _ResolvedPlayableSource(
      streamUrl: resolvedStreamUrl,
      headers: _headersForResolvedStream(source, resolvedStreamUrl),
    );
  }

  Future<String> _resolvePlayableUrlFromUri(
    Uri uri, {
    required MediaSourceConfig source,
  }) async {
    webDavTrace(
      'resolvePlayable.strm.start',
      fields: {
        'uri': uri,
      },
    );
    final response = await _client.get(uri, headers: _headers(source));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      webDavTrace(
        'resolvePlayable.strm.error',
        fields: {
          'uri': uri,
          'status': response.statusCode,
        },
      );
      throw WebDavNasException(
        'STRM 读取失败：HTTP ${response.statusCode} ($uri)',
      );
    }

    final rawBody = utf8.decode(response.bodyBytes, allowMalformed: true);
    for (final line in const LineSplitter().convert(rawBody)) {
      final normalized = line.trim().replaceFirst('\uFEFF', '');
      if (normalized.isEmpty || normalized.startsWith('#')) {
        continue;
      }
      final parsed = Uri.tryParse(normalized);
      if (parsed != null && parsed.hasScheme) {
        webDavTrace(
          'resolvePlayable.strm.done',
          fields: {
            'uri': uri,
            'streamUrl': normalized,
          },
        );
        return normalized;
      }
      final resolved = uri.resolve(normalized).toString();
      webDavTrace(
        'resolvePlayable.strm.relative',
        fields: {
          'uri': uri,
          'streamUrl': resolved,
        },
      );
      return resolved;
    }
    webDavTrace(
      'resolvePlayable.strm.empty',
      fields: {
        'uri': uri,
      },
    );
    return '';
  }

  Uri? _resolvePlaybackTargetUri(
    MediaSourceConfig source, {
    required String streamUrl,
    required String actualAddress,
  }) {
    final directUri = Uri.tryParse(streamUrl);
    if (directUri != null && directUri.hasScheme) {
      return directUri;
    }
    final normalizedActualAddress = actualAddress.trim();
    if (normalizedActualAddress.isEmpty) {
      return null;
    }
    return _resolveResourceUri(
      source,
      resourcePath: normalizedActualAddress,
      sectionId: '',
    );
  }

  _WebDavEntry? _findBestNfoEntry(
    _WebDavEntry videoEntry,
    List<_WebDavEntry> siblings,
  ) {
    final baseName = _stripExtension(videoEntry.name).toLowerCase();
    final loweredEntries = siblings
        .where((entry) => !entry.isCollection)
        .where((entry) => entry.name.toLowerCase().endsWith('.nfo'))
        .toList(growable: false);
    for (final preferredName in [
      '$baseName.nfo',
      'movie.nfo',
      'tvshow.nfo',
      'index.nfo',
    ]) {
      for (final entry in loweredEntries) {
        if (entry.name.toLowerCase() == preferredName) {
          return entry;
        }
      }
    }
    return null;
  }

  _WebDavEntry? _findNamedNfoEntry(
    List<_WebDavEntry> entries,
    List<String> preferredNames, {
    _WebDavEntry? excluding,
  }) {
    final loweredEntries = entries
        .where((entry) => !entry.isCollection)
        .where((entry) => entry.name.toLowerCase().endsWith('.nfo'))
        .toList(growable: false);
    for (final preferredName in preferredNames) {
      for (final entry in loweredEntries) {
        if (excluding != null && entry.uri == excluding.uri) {
          continue;
        }
        if (entry.name.toLowerCase() == preferredName.toLowerCase()) {
          return entry;
        }
      }
    }
    return null;
  }

  _WebDavEntry? _findBestPosterEntry(
    _WebDavEntry videoEntry,
    List<_WebDavEntry> siblings,
  ) {
    final baseName = _stripExtension(videoEntry.name).toLowerCase();
    final imageEntries = siblings
        .where((entry) => !entry.isCollection)
        .where(_isLikelyPosterImage)
        .toList(growable: false);
    for (final preferredName in [
      '$baseName-poster.jpg',
      '$baseName-poster.jpeg',
      '$baseName-poster.png',
      '$baseName.jpg',
      '$baseName.jpeg',
      '$baseName.png',
      'poster.jpg',
      'poster.jpeg',
      'poster.png',
      'folder.jpg',
      'folder.jpeg',
      'folder.png',
      'cover.jpg',
      'cover.jpeg',
      'cover.png',
    ]) {
      for (final entry in imageEntries) {
        if (entry.name.toLowerCase() == preferredName) {
          return entry;
        }
      }
    }
    return null;
  }

  _WebDavEntry? _findSeasonPosterEntry(
    _WebDavEntry videoEntry,
    List<_WebDavEntry> siblings, {
    int? seasonHint,
  }) {
    if (seasonHint == null || seasonHint < 0) {
      return null;
    }
    final imageEntries = siblings
        .where((entry) => !entry.isCollection)
        .where(_isLikelyPosterImage)
        .toList(growable: false);
    final preferredNames = <String>[
      if (seasonHint == 0) ...[
        'season-specials-poster.jpg',
        'season-specials-poster.jpeg',
        'season-specials-poster.png',
      ],
      'season${seasonHint.toString().padLeft(2, '0')}-poster.jpg',
      'season${seasonHint.toString().padLeft(2, '0')}-poster.jpeg',
      'season${seasonHint.toString().padLeft(2, '0')}-poster.png',
    ];
    for (final preferredName in preferredNames) {
      for (final entry in imageEntries) {
        if (entry.name.toLowerCase() == preferredName) {
          return entry;
        }
      }
    }
    return null;
  }

  _WebDavEntry? _findPosterByRole(List<_WebDavEntry> entries) {
    final imageEntries = entries
        .where((entry) => !entry.isCollection)
        .where(_isLikelyPosterImage)
        .toList(growable: false);
    for (final preferredName in const [
      'poster.jpg',
      'poster.jpeg',
      'poster.png',
      'folder.jpg',
      'folder.jpeg',
      'folder.png',
      'cover.jpg',
      'cover.jpeg',
      'cover.png',
    ]) {
      for (final entry in imageEntries) {
        if (entry.name.toLowerCase() == preferredName) {
          return entry;
        }
      }
    }
    return null;
  }

  _WebDavEntry? _findBackdropByRole(List<_WebDavEntry> entries) {
    return _findArtworkByNames(entries, const [
      'fanart.jpg',
      'fanart.jpeg',
      'fanart.png',
      'backdrop.jpg',
      'backdrop.jpeg',
      'backdrop.png',
      'landscape.jpg',
      'landscape.jpeg',
      'landscape.png',
    ]);
  }

  _WebDavEntry? _findLogoByRole(List<_WebDavEntry> entries) {
    return _findArtworkByNames(entries, const [
      'clearlogo.png',
      'clearlogo.webp',
      'clearlogo.jpg',
      'logo.png',
      'logo.webp',
      'logo.jpg',
    ]);
  }

  _WebDavEntry? _findBannerByRole(List<_WebDavEntry> entries) {
    return _findArtworkByNames(entries, const [
      'banner.jpg',
      'banner.jpeg',
      'banner.png',
    ]);
  }

  _WebDavEntry? _findArtworkByNames(
    List<_WebDavEntry> entries,
    List<String> preferredNames,
  ) {
    final imageEntries = entries
        .where((entry) => !entry.isCollection)
        .where(_isLikelyPosterImage)
        .toList(growable: false);
    for (final preferredName in preferredNames) {
      for (final entry in imageEntries) {
        if (entry.name.toLowerCase() == preferredName.toLowerCase()) {
          return entry;
        }
      }
    }
    return null;
  }

  _WebDavEntry? _findNamedDirectoryEntry(
    List<_WebDavEntry> entries,
    List<String> preferredNames,
  ) {
    for (final preferredName in preferredNames) {
      for (final entry in entries) {
        if (!entry.isCollection) {
          continue;
        }
        if (entry.name.toLowerCase() == preferredName.toLowerCase()) {
          return entry;
        }
      }
    }
    return null;
  }

  Future<List<_WebDavEntry>> _loadExtraBackdropEntries({
    required MediaSourceConfig source,
    required List<({List<_WebDavEntry> entries, Uri? baseUri})> candidates,
  }) async {
    for (final candidate in candidates) {
      final baseUri = candidate.baseUri;
      if (baseUri == null) {
        continue;
      }
      final extraDir = _findNamedDirectoryEntry(
        candidate.entries,
        const ['extrafanart'],
      );
      if (extraDir == null) {
        continue;
      }
      final loaded = await _loadDirectoryEntries(extraDir.uri, source: source);
      final imageEntries = loaded
          .where((entry) => !entry.isSelf && !entry.isCollection)
          .where(_isLikelyPosterImage)
          .toList(growable: false)
        ..sort((left, right) => left.name.compareTo(right.name));
      if (imageEntries.isNotEmpty) {
        return imageEntries;
      }
    }
    return const [];
  }

  bool _isLikelyPosterImage(_WebDavEntry entry) {
    final type = entry.contentType.toLowerCase();
    if (type.startsWith('image/')) {
      return true;
    }
    final path = entry.uri.path.toLowerCase();
    return path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.png') ||
        path.endsWith('.webp');
  }

  Future<_ParsedNfoMetadata?> _loadNfoMetadata(
    _WebDavEntry entry, {
    required MediaSourceConfig source,
  }) {
    final key = _webDavCacheKey(source, entry.uri);
    if (_nfoCache.containsKey(key)) {
      return Future.value(_nfoCache[key]);
    }
    final inflight = _nfoInflight[key];
    if (inflight != null) {
      return inflight;
    }

    final future =
        _loadNfoMetadataUncached(entry, source: source).then((value) {
      _nfoCache[key] = value;
      return value;
    });
    _nfoInflight[key] = future;
    future.whenComplete(() {
      _nfoInflight.remove(key);
    });
    return future;
  }

  Future<_ParsedNfoMetadata?> _loadNfoMetadataUncached(
    _WebDavEntry entry, {
    required MediaSourceConfig source,
  }) async {
    final response = await _client.get(entry.uri, headers: _headers(source));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    final body = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
    if (body.isEmpty) {
      return null;
    }

    try {
      final document = XmlDocument.parse(body);
      final root = document.rootElement;
      final title = _xmlSingleText(root, 'title');
      final plot = _xmlSingleText(root, 'plot');
      final outline = _xmlSingleText(root, 'outline');
      final year = _parseNfoYear(
        _xmlSingleText(root, 'year'),
        fallbackDateText: _xmlSingleText(root, 'premiered'),
      );
      final runtime = _formatRuntimeLabel(
        _xmlSingleText(root, 'runtime'),
        durationSeconds:
            _tryParseInt(_xmlSingleText(root, 'durationinseconds')),
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
        entry.uri,
        _xmlSingleText(root, 'thumb'),
      );
      final backdropUrl = _resolveNfoBackdropUrl(root, entry.uri);
      final logoUrl = _resolveNfoArtUrl(
        root,
        entry.uri,
        types: const ['clearlogo', 'logo'],
      );
      final bannerUrl = _resolveNfoArtUrl(
        root,
        entry.uri,
        types: const ['banner'],
      );
      final extraBackdropUrls = _resolveNfoExtraBackdropUrls(root, entry.uri);
      final streamDetails = _parseNfoStreamDetails(root);
      return _ParsedNfoMetadata(
        title: title,
        overview: plot.trim().isNotEmpty ? plot : outline,
        thumbUrl: thumbUrl,
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

  Future<List<_WebDavEntry>> _loadDirectoryEntries(
    Uri uri, {
    required MediaSourceConfig source,
  }) {
    if (_isExcludedByKeyword(uri, source: source)) {
      return Future.value(const <_WebDavEntry>[]);
    }
    final key = _webDavCacheKey(source, uri);
    final cached = _directoryCache[key];
    if (cached != null) {
      return Future.value(cached);
    }
    final inflight = _directoryInflight[key];
    if (inflight != null) {
      return inflight;
    }
    final future = _propfind(uri, source: source).then(
      (entries) {
        final filtered = _filterExcludedEntries(entries, source: source);
        _directoryCache[key] = filtered;
        return filtered;
      },
    ).catchError((_) {
      return const <_WebDavEntry>[];
    });
    _directoryInflight[key] = future;
    future.whenComplete(() {
      _directoryInflight.remove(key);
    });
    return future;
  }

  void _resetScanCaches() {
    _nfoCache.clear();
    _nfoInflight.clear();
    _directoryCache.clear();
    _directoryInflight.clear();
  }

  void _throwIfCancelled(bool Function()? shouldCancel) {
    if (shouldCancel?.call() ?? false) {
      throw const _WebDavScanCancelledException();
    }
  }

  _DirectorySubtreeCacheEntry? _loadCachedDirectorySubtree({
    required MediaSourceConfig source,
    required Uri uri,
    required bool includeSidecarMetadata,
    required DateTime? directoryModifiedAt,
  }) {
    if (directoryModifiedAt == null) {
      return null;
    }
    final key = _directorySubtreeCacheKey(
      source,
      uri,
      includeSidecarMetadata: includeSidecarMetadata,
    );
    final cached = _directorySubtreeCache[key];
    if (cached == null || cached.directoryModifiedAt != directoryModifiedAt) {
      return null;
    }
    return cached;
  }

  void _storeCachedDirectorySubtree({
    required MediaSourceConfig source,
    required Uri uri,
    required bool includeSidecarMetadata,
    required DateTime directoryModifiedAt,
    required List<_PendingWebDavScannedItem> items,
  }) {
    final key = _directorySubtreeCacheKey(
      source,
      uri,
      includeSidecarMetadata: includeSidecarMetadata,
    );
    _directorySubtreeCache[key] = _DirectorySubtreeCacheEntry(
      directoryModifiedAt: directoryModifiedAt,
      items: items,
    );
  }

  List<_PendingWebDavScannedItem> _rebasePendingItemsForRoot(
    List<_PendingWebDavScannedItem> items, {
    required Uri rootUri,
    required String sectionId,
    required String sectionName,
  }) {
    return items.map((item) {
      final fileUri = Uri.tryParse(item.resourceId);
      if (fileUri == null) {
        return item.copyWith(
          sectionId: sectionId,
          sectionName: sectionName,
        );
      }
      return item.copyWith(
        sectionId: sectionId,
        sectionName: sectionName,
        relativeDirectories: _relativeDirectorySegmentsFromRoot(
          fileUri: fileUri,
          rootUri: rootUri,
        ),
      );
    }).toList(growable: false);
  }

  String _webDavCacheKey(MediaSourceConfig source, Uri uri) {
    return '${source.id}|${uri.toString()}';
  }

  String _directorySubtreeCacheKey(
    MediaSourceConfig source,
    Uri uri, {
    required bool includeSidecarMetadata,
  }) {
    final keywords = source.normalizedWebDavExcludedPathKeywords.join(',');
    return '${source.id}|${includeSidecarMetadata ? 'sidecar' : 'plain'}|$keywords|${uri.toString()}';
  }

  Uri? _parentDirectoryUri(Uri uri) {
    final segments = uri.pathSegments.toList(growable: true);
    while (segments.isNotEmpty && segments.last.isEmpty) {
      segments.removeLast();
    }
    if (segments.isNotEmpty) {
      segments.removeLast();
    }
    if (segments.isEmpty) {
      return null;
    }
    return uri.replace(
      pathSegments: [...segments, ''],
      query: null,
      fragment: null,
    );
  }

  _ParsedNfoMetadata? _mergeNfoMetadata({
    required _ParsedNfoMetadata? primary,
    required _ParsedNfoMetadata? secondary,
  }) {
    if (primary == null) {
      return secondary;
    }
    if (secondary == null) {
      return primary;
    }
    return _ParsedNfoMetadata(
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
      logoUrl: primary.logoUrl.trim().isNotEmpty
          ? primary.logoUrl
          : secondary.logoUrl,
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
      directors: primary.directors.isNotEmpty
          ? primary.directors
          : secondary.directors,
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

  Uri _resolveHref(Uri requestUri, String href) {
    final trimmed = href.trim();
    if (trimmed.isEmpty) {
      return requestUri;
    }
    String decoded;
    try {
      decoded = Uri.decodeFull(trimmed);
    } catch (_) {
      decoded = trimmed;
    }
    final parsed = Uri.tryParse(decoded);
    if (parsed != null && parsed.hasScheme) {
      return parsed;
    }
    return requestUri.resolve(decoded);
  }

  String _childText(XmlElement node, String localName) {
    final match = node.children.whereType<XmlElement>().firstWhere(
          (element) => element.name.local == localName,
          orElse: () => XmlElement(XmlName(localName)),
        );
    return match.innerText.trim();
  }

  String _displayNameFromUri(Uri uri, {required String fallback}) {
    final segments = uri.pathSegments.where((segment) => segment.isNotEmpty);
    if (segments.isEmpty) {
      return fallback;
    }
    final raw = segments.last;
    try {
      return Uri.decodeComponent(raw);
    } catch (_) {
      return raw;
    }
  }

  String _normalizeUri(Uri uri) {
    final path = uri.path.endsWith('/') && uri.path.length > 1
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return uri.replace(path: path, query: null, fragment: null).toString();
  }

  DateTime? _parseModifiedAt(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return null;
    }

    final iso = DateTime.tryParse(text);
    if (iso != null) {
      return iso;
    }

    final match = RegExp(
      r'^[A-Za-z]{3},\s+(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+'
      r'(\d{2}):(\d{2}):(\d{2})\s+GMT$',
    ).firstMatch(text);
    if (match == null) {
      return null;
    }

    final month = _httpMonthIndex(match.group(2)!);
    if (month == null) {
      return null;
    }

    return DateTime.utc(
      int.parse(match.group(3)!),
      month,
      int.parse(match.group(1)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    );
  }

  int? _httpMonthIndex(String value) {
    switch (value.toLowerCase()) {
      case 'jan':
        return 1;
      case 'feb':
        return 2;
      case 'mar':
        return 3;
      case 'apr':
        return 4;
      case 'may':
        return 5;
      case 'jun':
        return 6;
      case 'jul':
        return 7;
      case 'aug':
        return 8;
      case 'sep':
        return 9;
      case 'oct':
        return 10;
      case 'nov':
        return 11;
      case 'dec':
        return 12;
    }
    return null;
  }

  String _stripExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex <= 0) {
      return fileName;
    }
    return fileName.substring(0, dotIndex);
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

  String _resolveThumbUrl(Uri nfoUri, String rawThumb) {
    final trimmed = rawThumb.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final parsed = Uri.tryParse(trimmed);
    if (parsed != null && parsed.hasScheme) {
      return trimmed;
    }
    return nfoUri.resolve(trimmed).toString();
  }

  String _resolveNfoBackdropUrl(XmlElement root, Uri nfoUri) {
    final artFanart = _resolveNfoArtUrl(
      root,
      nfoUri,
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
          .map((child) => _resolveThumbUrl(nfoUri, child.innerText))
          .where((value) => value.trim().isNotEmpty)
          .toList(growable: false);
      if (thumbs.isNotEmpty) {
        return thumbs.first;
      }
      final direct = _resolveThumbUrl(nfoUri, element.innerText);
      if (direct.trim().isNotEmpty) {
        return direct;
      }
    }
    return '';
  }

  List<String> _resolveNfoExtraBackdropUrls(XmlElement root, Uri nfoUri) {
    final fanartElements = root.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'fanart');
    for (final element in fanartElements) {
      final urls = element.children
          .whereType<XmlElement>()
          .where((child) => child.name.local == 'thumb')
          .map((child) => _resolveThumbUrl(nfoUri, child.innerText))
          .where((value) => value.trim().isNotEmpty)
          .toList(growable: false);
      if (urls.length >= 2) {
        return urls;
      }
    }
    return const [];
  }

  String _resolveNfoArtUrl(
    XmlElement root,
    Uri nfoUri, {
    required List<String> types,
  }) {
    final normalizedTypes = types.map((type) => type.toLowerCase()).toSet();
    for (final art in root.descendants.whereType<XmlElement>()) {
      if (art.name.local != 'art') {
        continue;
      }
      for (final child in art.children.whereType<XmlElement>()) {
        if (!normalizedTypes.contains(child.name.local.toLowerCase())) {
          continue;
        }
        final resolved = _resolveThumbUrl(nfoUri, child.innerText);
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
      width:
          video == null ? null : _tryParseInt(_xmlSingleText(video, 'width')),
      height:
          video == null ? null : _tryParseInt(_xmlSingleText(video, 'height')),
      bitrate: _tryParseInt(
        video == null ? '' : _xmlSingleText(video, 'bitrate'),
      ),
    );
  }

  _InferredMediaInfo _inferMediaInfo(_WebDavEntry entry) {
    final path = entry.uri.path.toLowerCase();
    final fileName = entry.name.toLowerCase();
    final extension =
        path.contains('.') ? path.substring(path.lastIndexOf('.') + 1) : '';

    int? width;
    int? height;
    int? bitrate;
    String videoCodec = '';
    String audioCodec = '';

    if (fileName.contains('4320p') || fileName.contains('8k')) {
      width = 7680;
      height = 4320;
    } else if (fileName.contains('2160p') || fileName.contains('4k')) {
      width = 3840;
      height = 2160;
    } else if (fileName.contains('1440p')) {
      width = 2560;
      height = 1440;
    } else if (fileName.contains('1080p')) {
      width = 1920;
      height = 1080;
    } else if (fileName.contains('720p')) {
      width = 1280;
      height = 720;
    } else if (fileName.contains('480p')) {
      width = 854;
      height = 480;
    }

    if (fileName.contains('hevc') ||
        fileName.contains('x265') ||
        fileName.contains('h265')) {
      videoCodec = 'hevc';
    } else if (fileName.contains('avc') ||
        fileName.contains('x264') ||
        fileName.contains('h264')) {
      videoCodec = 'h264';
    } else if (fileName.contains('av1')) {
      videoCodec = 'av1';
    }

    if (fileName.contains('truehd')) {
      audioCodec = fileName.contains('atmos') ? 'truehd atmos' : 'truehd';
    } else if (fileName.contains('dtshd') || fileName.contains('dts-hd')) {
      audioCodec = 'dtshd';
    } else if (fileName.contains('dts')) {
      audioCodec = 'dts';
    } else if (fileName.contains('eac3') || fileName.contains('ddp')) {
      audioCodec = 'eac3';
    } else if (fileName.contains('ac3') || fileName.contains('dd5')) {
      audioCodec = 'ac3';
    } else if (fileName.contains('aac')) {
      audioCodec = 'aac';
    }

    final bitrateMatch =
        RegExp(r'(?<!\d)(\d{1,3})\s?mbps(?!\d)').firstMatch(fileName);
    if (bitrateMatch != null) {
      bitrate = int.tryParse(bitrateMatch.group(1) ?? '') == null
          ? null
          : int.parse(bitrateMatch.group(1)!) * 1000000;
    }

    return _InferredMediaInfo(
      container: extension,
      videoCodec: videoCodec,
      audioCodec: audioCodec,
      width: width,
      height: height,
      bitrate: bitrate,
    );
  }

  _ArtworkResolution _resolveArtworkCandidate({
    required MediaSourceConfig source,
    _WebDavEntry? localEntry,
    String remoteUrl = '',
  }) {
    if (localEntry != null) {
      return _ArtworkResolution(
        url: localEntry.uri.toString(),
        headers: _headers(source),
      );
    }
    final url = remoteUrl.trim();
    if (url.isEmpty) {
      return const _ArtworkResolution();
    }
    return _ArtworkResolution(
      url: url,
      headers: _headersForArtworkUrl(source, url),
    );
  }

  Map<String, String> _headersForArtworkUrl(
    MediaSourceConfig source,
    String url,
  ) {
    final resolvedUri = Uri.tryParse(url.trim());
    if (resolvedUri == null) {
      return const {};
    }
    if (_shouldUseSourceHeadersForUri(resolvedUri, source)) {
      return _headers(source);
    }
    return const {};
  }

  String _firstNonEmpty(String primary, String fallback) {
    return primary.trim().isNotEmpty ? primary.trim() : fallback.trim();
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

  bool _shouldUseSourceHeadersForUri(Uri uri, MediaSourceConfig source) {
    final endpoint = Uri.tryParse(source.endpoint.trim());
    if (endpoint == null) {
      return false;
    }
    return uri.scheme == endpoint.scheme &&
        uri.host == endpoint.host &&
        uri.port == endpoint.port;
  }

  Map<String, String> _headersForResolvedStream(
    MediaSourceConfig source,
    String streamUrl,
  ) {
    final resolvedUri = Uri.tryParse(streamUrl.trim());
    if (resolvedUri == null) {
      return const {};
    }
    if (_shouldUseSourceHeadersForUri(resolvedUri, source)) {
      return _headers(source);
    }
    return const {};
  }
}
