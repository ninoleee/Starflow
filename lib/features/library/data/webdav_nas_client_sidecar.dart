part of 'webdav_nas_client.dart';

extension _WebDavNasClientSidecar on WebDavNasClient {
  Future<WebDavMetadataSeed> _resolveSidecarMetadata(
    _WebDavEntry videoEntry, {
    required List<_WebDavEntry> siblings,
    required MediaSourceConfig source,
  }) async {
    final directoryContext = await _loadSidecarDirectoryContext(
      videoEntry,
      siblings: siblings,
      source: source,
    );
    final primaryNfoEntry = _findBestNfoEntry(videoEntry, siblings);
    final primaryNfoMetadata = primaryNfoEntry == null
        ? null
        : await _loadNfoMetadata(primaryNfoEntry, source: source);
    final nfoMetadata = mergeNfoMetadata(
      primary: primaryNfoMetadata,
      secondary: mergeNfoMetadata(
        primary: directoryContext.seasonNfoMetadata,
        secondary: directoryContext.seriesNfoMetadata,
      ),
    );
    final inferredMediaInfo = _inferMediaInfo(videoEntry);

    final localPosterEntry = _findBestPosterEntry(videoEntry, siblings) ??
        _findSeasonPosterEntry(
          videoEntry,
          siblings,
          seasonHint: nfoMetadata?.seasonNumber,
        ) ??
        directoryContext.parentPosterEntry;
    final localBackdropEntry = directoryContext.backdropEntry;
    final localLogoEntry = directoryContext.logoEntry;
    final localBannerEntry = directoryContext.bannerEntry;
    final localExtraBackdropEntries = directoryContext.extraBackdropEntries;

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

    return seed;
  }

  Future<_WebDavSidecarDirectoryContext> _loadSidecarDirectoryContext(
    _WebDavEntry videoEntry, {
    required List<_WebDavEntry> siblings,
    required MediaSourceConfig source,
  }) {
    final currentDirectoryUri = _parentDirectoryUri(videoEntry.uri);
    if (currentDirectoryUri == null) {
      return Future.value(const _WebDavSidecarDirectoryContext());
    }
    final key = _webDavCacheKey(source, currentDirectoryUri);
    final cached = _sidecarDirectoryCache[key];
    if (cached != null) {
      return Future.value(cached);
    }
    final inflight = _sidecarDirectoryInflight[key];
    if (inflight != null) {
      return inflight;
    }

    final future = (() async {
      final parentDirectoryUri = _parentDirectoryUri(currentDirectoryUri);
      final grandParentDirectoryUri = parentDirectoryUri == null
          ? null
          : _parentDirectoryUri(parentDirectoryUri);
      final parentEntries = parentDirectoryUri == null
          ? const <_WebDavEntry>[]
          : await _loadDirectoryEntries(parentDirectoryUri, source: source);
      final grandParentEntries = grandParentDirectoryUri == null
          ? const <_WebDavEntry>[]
          : await _loadDirectoryEntries(
              grandParentDirectoryUri,
              source: source,
            );
      final seasonNfoEntry = _findNamedNfoEntry(
        siblings,
        const ['season.nfo', 'index.nfo'],
      );
      final seriesNfoEntry = _findNamedNfoEntry(
            parentEntries,
            const ['tvshow.nfo', 'index.nfo'],
          ) ??
          _findNamedNfoEntry(
            grandParentEntries,
            const ['tvshow.nfo', 'index.nfo'],
          );
      final seasonNfoMetadata = seasonNfoEntry == null
          ? null
          : await _loadNfoMetadata(seasonNfoEntry, source: source);
      final seriesNfoMetadata = seriesNfoEntry == null
          ? null
          : await _loadNfoMetadata(seriesNfoEntry, source: source);
      final extraBackdropEntries = await _loadExtraBackdropEntries(
        source: source,
        candidates: [
          (entries: siblings, baseUri: currentDirectoryUri),
          if (parentDirectoryUri != null)
            (entries: parentEntries, baseUri: parentDirectoryUri),
          if (grandParentDirectoryUri != null)
            (entries: grandParentEntries, baseUri: grandParentDirectoryUri),
        ],
      );
      if (seasonNfoMetadata != null ||
          seriesNfoMetadata != null ||
          extraBackdropEntries.isNotEmpty) {
        appLogTrace(
          'library.scan-cache',
          'WebDAV sidecar directory context prepared',
          fields: <String, Object?>{
            'sourceId': source.id,
            'directory': currentDirectoryUri.toString(),
            'siblingCount': siblings.length,
            'hasSeasonNfo': seasonNfoMetadata != null,
            'hasSeriesNfo': seriesNfoMetadata != null,
            'extraBackdropCount': extraBackdropEntries.length,
          },
        );
      }
      return _WebDavSidecarDirectoryContext(
        seasonNfoMetadata: seasonNfoMetadata,
        seriesNfoMetadata: seriesNfoMetadata,
        parentPosterEntry: _findPosterByRole(parentEntries) ??
            _findPosterByRole(grandParentEntries),
        backdropEntry: _findBackdropByRole(siblings) ??
            _findBackdropByRole(parentEntries) ??
            _findBackdropByRole(grandParentEntries),
        logoEntry: _findLogoByRole(siblings) ??
            _findLogoByRole(parentEntries) ??
            _findLogoByRole(grandParentEntries),
        bannerEntry: _findBannerByRole(siblings) ??
            _findBannerByRole(parentEntries) ??
            _findBannerByRole(grandParentEntries),
        extraBackdropEntries: extraBackdropEntries,
      );
    })();
    _sidecarDirectoryInflight[key] = future;
    future.then((value) {
      _sidecarDirectoryCache[key] = value;
    }).whenComplete(() {
      _sidecarDirectoryInflight.remove(key);
    });
    return future;
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
    _requireSourceResource(uri, source);
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

    late final http.Response response;
    try {
      response = await sendBoundedRequest(
        _client,
        request.method,
        request.url,
        headers: request.headers,
        body: request.body,
        timeout: const Duration(seconds: 30),
        maxBytes: 32 * 1024 * 1024,
        allowUri: (next) => _isSourceResource(next, source),
      );
    } catch (_) {
      rethrow;
    }
    if (response.statusCode != 207 && response.statusCode != 200) {
      throw WebDavNasException('WebDAV 请求失败：HTTP ${response.statusCode}');
    }
    final responseSizeBytes = response.bodyBytes.length;
    if (responseSizeBytes == 0) {
      return const [];
    }
    final parseStopwatch = Stopwatch()..start();
    final usesBackgroundIsolate =
        !kIsWeb && responseSizeBytes >= _webDavXmlBackgroundThreshold;
    if (usesBackgroundIsolate) {
      appLogInfo(
        'library.scan',
        'Large WebDAV XML parse started',
        fields: <String, Object?>{
          'sourceId': source.id,
          'responseBytes': responseSizeBytes,
        },
      );
    }
    final responseBody = response.body;
    if (responseBody.trim().isEmpty) {
      return const [];
    }
    final parsed = await _parseWebDavXmlInBackground(
      body: responseBody,
      requestUri: uri,
      fallbackName: source.name,
      useBackgroundIsolate: usesBackgroundIsolate,
    );
    if (usesBackgroundIsolate || parseStopwatch.elapsedMilliseconds >= 250) {
      appLogInfo(
        'library.scan',
        'WebDAV XML parse completed',
        fields: <String, Object?>{
          'sourceId': source.id,
          'responseBytes': responseSizeBytes,
          'entryCount': parsed.length,
          'durationMs': parseStopwatch.elapsedMilliseconds,
          'backgroundIsolate': usesBackgroundIsolate,
        },
      );
    }
    return parsed
        .where((entry) =>
            _isSourceResource(entry.uri, source) &&
            isWithinHttpDirectory(entry.uri, uri))
        .toList(growable: false);
  }

  bool _isSourceResource(Uri uri, MediaSourceConfig source) {
    final endpoint = Uri.tryParse(source.endpoint.trim());
    return endpoint != null && isWithinHttpDirectory(uri, endpoint);
  }

  void _requireSourceResource(Uri uri, MediaSourceConfig source) {
    if (!_isSourceResource(uri, source)) {
      throw const WebDavNasException('WebDAV 地址超出来源目录或 origin');
    }
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
    if (ExternalMediaStructure.isKnownAudio(entry.name) ||
        entry.contentType.toLowerCase().startsWith('audio/')) {
      return false;
    }
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
      '.iso',
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
    _requireSourceResource(uri, source);
    final response = await sendBoundedRequest(_client, 'GET', uri,
        headers: _headers(source),
        timeout: const Duration(seconds: 20),
        maxBytes: 1024 * 1024,
        allowUri: (next) => _isSourceResource(next, source));
    if (response.statusCode < 200 || response.statusCode >= 300) {
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
      final playbackUrl = _normalizeStrmPlaybackUrl(normalized);
      final parsed = Uri.tryParse(playbackUrl);
      if (parsed != null && parsed.hasScheme) {
        return playbackUrl;
      }
      final resolved = uri.resolve(playbackUrl).toString();

      return resolved;
    }

    return '';
  }

  String _normalizeStrmPlaybackUrl(String value) {
    final normalized = value.trim();
    if (!normalized.contains('#')) {
      return normalized;
    }
    return normalized.replaceAll('#', '%23');
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
    return resolveResourceUri(
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

  Future<ParsedNfoMetadata?> _loadNfoMetadata(
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
    }).catchError((Object _) {
      // A rejected or unavailable sidecar must not discard the media entry.
      return null;
    }).whenComplete(() {
      _nfoInflight.remove(key);
    });
    _nfoInflight[key] = future;
    return future;
  }

  Future<ParsedNfoMetadata?> _loadNfoMetadataUncached(
    _WebDavEntry entry, {
    required MediaSourceConfig source,
  }) async {
    _requireSourceResource(entry.uri, source);
    final response = await sendBoundedRequest(_client, 'GET', entry.uri,
        headers: _headers(source),
        timeout: const Duration(seconds: 20),
        maxBytes: 4 * 1024 * 1024,
        allowUri: (next) => _isSourceResource(next, source));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    final body = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
    if (body.isEmpty) {
      return null;
    }

    return parseNfoMetadata(body,
        resolveArtwork: (value) => entry.uri.resolve(value).toString());
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
    _sidecarDirectoryCache.clear();
    _sidecarDirectoryInflight.clear();
    _directorySubtreeCache.clear();
  }

  void _throwIfCancelled(bool Function()? shouldCancel) {
    if (shouldCancel?.call() ?? false) {
      throw const _WebDavScanCancelledException();
    }
  }

  Future<_DirectorySubtreeCacheEntry?> _loadCachedDirectorySubtree({
    required MediaSourceConfig source,
    required Uri uri,
    required bool includeSidecarMetadata,
    required DateTime? directoryModifiedAt,
    required String directoryEtag,
  }) {
    final normalizedEtag = directoryEtag.trim();
    if (directoryModifiedAt == null && normalizedEtag.isEmpty) {
      return Future.value(null);
    }
    final key = _directorySubtreeCacheKey(
      source,
      uri,
      includeSidecarMetadata: includeSidecarMetadata,
    );
    final cached = _directorySubtreeCache[key];
    if (cached != null &&
        ((normalizedEtag.isNotEmpty &&
                cached.directoryEtag == normalizedEtag) ||
            (normalizedEtag.isEmpty &&
                cached.directoryModifiedAt == directoryModifiedAt))) {
      return Future.value(cached);
    }
    final cacheStore = _directoryCacheStore;
    if (cacheStore == null) {
      return Future.value(null);
    }
    return cacheStore.load(key).then((raw) {
      if (raw == null) {
        return null;
      }
      final matchesFingerprint = normalizedEtag.isNotEmpty
          ? raw['directoryEtag'] == normalizedEtag
          : raw['directoryModifiedAt'] ==
              directoryModifiedAt?.toIso8601String();
      if (!matchesFingerprint) {
        return null;
      }
      final cachedAt = DateTime.tryParse(raw['cachedAt'] as String? ?? '');
      if (cachedAt == null ||
          DateTime.now().difference(cachedAt) > const Duration(days: 30)) {
        return null;
      }
      final items = (raw['items'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) => ExternalScanPendingItem.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false);
      final entry = _DirectorySubtreeCacheEntry(
        directoryModifiedAt:
            directoryModifiedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        directoryEtag: normalizedEtag,
        items: items,
      );
      _directorySubtreeCache[key] = entry;
      appLogTrace(
        'library.scan-cache',
        'Persistent WebDAV directory cache hit',
        fields: <String, Object?>{
          'sourceId': source.id,
          'itemCount': items.length,
        },
      );
      return entry;
    }).catchError((error, stackTrace) {
      appLogWarning(
        'library.scan-cache',
        'Persistent WebDAV directory cache read failed',
        fields: <String, Object?>{'sourceId': source.id},
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    });
  }

  void _storeCachedDirectorySubtree({
    required MediaSourceConfig source,
    required Uri uri,
    required bool includeSidecarMetadata,
    required DateTime? directoryModifiedAt,
    required String directoryEtag,
    required List<_PendingWebDavScannedItem> items,
  }) {
    final key = _directorySubtreeCacheKey(
      source,
      uri,
      includeSidecarMetadata: includeSidecarMetadata,
    );
    _directorySubtreeCache[key] = _DirectorySubtreeCacheEntry(
      directoryModifiedAt:
          directoryModifiedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      directoryEtag: directoryEtag.trim(),
      items: items,
    );
    final cacheStore = _directoryCacheStore;
    if (cacheStore != null) {
      unawaited(
        _serializeWebDavSubtreeInBackground(items).then((serializedItems) {
          return cacheStore.save(key, <String, dynamic>{
            'sourceId': source.id,
            'directoryModifiedAt': directoryModifiedAt?.toIso8601String() ?? '',
            'directoryEtag': directoryEtag.trim(),
            'cachedAt': DateTime.now().toIso8601String(),
            'items': serializedItems,
          });
        }).catchError((error, stackTrace) {
          appLogWarning(
            'library.scan-cache',
            'Persistent WebDAV directory cache write failed',
            fields: <String, Object?>{'sourceId': source.id},
            error: error,
            stackTrace: stackTrace,
          );
        }),
      );
    }
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
    // Old persisted subtrees may contain hrefs accepted before origin checks.
    return 'origin-v1|${source.id}|${includeSidecarMetadata ? 'sidecar' : 'plain'}|$keywords|${uri.toString()}';
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

  String _stripExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex <= 0) {
      return fileName;
    }
    return fileName.substring(0, dotIndex);
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

  bool _shouldUseSourceHeadersForUri(Uri uri, MediaSourceConfig source) {
    final endpoint = Uri.tryParse(source.endpoint.trim());
    if (endpoint == null) {
      return false;
    }
    return isWithinHttpDirectory(uri, endpoint);
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
