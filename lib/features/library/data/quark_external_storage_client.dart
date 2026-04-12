import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/domain/nas_media_recognition.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:xml/xml.dart';

final quarkExternalStorageClientProvider =
    Provider<QuarkExternalStorageClient>((ref) {
  return QuarkExternalStorageClient(
    quarkSaveClient: ref.read(quarkSaveClientProvider),
    readSettings: () => ref.read(appSettingsProvider),
  );
});

class QuarkExternalStorageClient {
  QuarkExternalStorageClient({
    required QuarkSaveClient quarkSaveClient,
    required AppSettings Function() readSettings,
  })  : _quarkSaveClient = quarkSaveClient,
        _readSettings = readSettings;

  final QuarkSaveClient _quarkSaveClient;
  final AppSettings Function() _readSettings;

  String get _quarkCookie {
    return _readSettings().networkStorage.quarkCookie.trim();
  }

  Future<List<MediaCollection>> fetchCollections(
    MediaSourceConfig source, {
    String? directoryId,
  }) async {
    if (!source.hasConfiguredQuarkFolder) {
      return const [];
    }
    final cookie = _quarkCookie;
    if (cookie.isEmpty) {
      return const [];
    }
    final parentFid = directoryId?.trim().isNotEmpty == true
        ? directoryId!.trim()
        : source.quarkFolderId;
    final parentPath =
        directoryId?.trim().isNotEmpty == true ? '/' : source.quarkFolderPath;
    final entries = _normalizeQuarkListedEntries(
      await _quarkSaveClient.listEntries(
        cookie: cookie,
        parentFid: parentFid,
      ),
      parentDirectoryPath: parentPath,
    );
    final directories = entries
        .where((entry) => entry.isDirectory)
        .map(QuarkDirectoryEntry.fromFileEntry)
        .whereType<QuarkDirectoryEntry>()
        .toList(growable: false);
    return directories
        .where((entry) => !source.matchesWebDavExcludedPath(entry.path))
        .map(
          (entry) => MediaCollection(
            id: entry.fid,
            title: entry.name,
            sourceId: source.id,
            sourceName: source.name,
            sourceKind: source.kind,
            subtitle: entry.path,
          ),
        )
        .toList(growable: false);
  }

  Future<List<WebDavScannedItem>> scanLibrary(
    MediaSourceConfig source, {
    String? sectionId,
    String sectionName = '',
    int limit = 200,
    bool? loadSidecarMetadata,
    bool resolvePlayableStreams = false,
    bool resetCaches = true,
    bool Function()? shouldCancel,
  }) async {
    if (!source.hasConfiguredQuarkFolder) {
      return const [];
    }
    final cookie = _quarkCookie;
    if (cookie.isEmpty) {
      return const [];
    }
    final rootFid = sectionId?.trim().isNotEmpty == true
        ? sectionId!.trim()
        : source.quarkFolderId;
    final rootPath =
        sectionId?.trim().isNotEmpty == true ? '/' : source.quarkFolderPath;
    final result = await _scanQuarkLibrary(
      source,
      cookie: cookie,
      roots: [
        _QuarkDirectoryCursor(
          fid: rootFid,
          path: rootPath,
          rootPath: rootPath,
          sectionId: sectionId?.trim() ?? '',
          sectionName: sectionName.trim(),
        ),
      ],
      limit: limit,
      shouldCancel: shouldCancel,
    );
    if (result.mediaEntries.isEmpty) {
      return const [];
    }
    final textFileCache = <String, Future<String>>{};
    final downloadCache = <String, Future<QuarkResolvedDownload>>{};
    final shouldLoadSidecarMetadata =
        loadSidecarMetadata ?? source.webDavSidecarScrapingEnabled;
    final pendingItems = <ExternalScanPendingItem>[];
    for (final queuedEntry in result.mediaEntries) {
      _throwIfCancelled(shouldCancel);
      final item = await _buildQuarkScannedItem(
        source: source,
        entry: queuedEntry.entry,
        parentFid: queuedEntry.parentFid,
        cookie: cookie,
        sectionId: queuedEntry.sectionId,
        sectionName: queuedEntry.sectionName,
        directoryEntriesByPath: result.directoryEntriesByPath,
        textFileCache: textFileCache,
        downloadCache: downloadCache,
        loadSidecarMetadata: shouldLoadSidecarMetadata,
      );
      pendingItems.add(
        ExternalScanPendingItem(
          resourceId: item.resourceId,
          fileName: item.fileName,
          actualAddress: item.actualAddress,
          sectionId: item.sectionId,
          sectionName: item.sectionName,
          streamUrl: item.streamUrl,
          streamHeaders: item.streamHeaders,
          playbackItemId: item.playbackItemId,
          addedAt: item.addedAt,
          modifiedAt: item.modifiedAt,
          fileSizeBytes: item.fileSizeBytes,
          metadataSeed: item.metadataSeed,
          relativeDirectories: _relativeQuarkDirectorySegmentsFromRoot(
            filePath: queuedEntry.entry.path,
            rootPath: queuedEntry.rootPath,
          ),
        ),
      );
    }
    final items = (source.webDavStructureInferenceEnabled
            ? applyExternalDirectoryStructureInference(
                pendingItems,
                source: source,
              )
            : pendingItems)
        .map(_quarkPendingItemToScannedItem)
        .toList(growable: false);
    items.sort((left, right) => right.addedAt.compareTo(left.addedAt));
    return items;
  }

  Future<WebDavScannedItem?> scanResource(
    MediaSourceConfig source, {
    required String resourceId,
    required String sectionId,
    required String sectionName,
    bool? loadSidecarMetadata,
    bool resolvePlayableStreams = false,
    bool Function()? shouldCancel,
  }) async {
    if (!source.hasConfiguredQuarkFolder) {
      return null;
    }
    final cookie = _quarkCookie;
    if (cookie.isEmpty) {
      return null;
    }
    final parsed = _parseQuarkResourceId(resourceId);
    if (parsed == null) {
      return null;
    }
    final shouldLoadSidecarMetadata =
        loadSidecarMetadata ?? source.webDavSidecarScrapingEnabled;
    final context = shouldLoadSidecarMetadata || parsed.parentFid.trim().isEmpty
        ? await _findEntryByTreeWalk(
            source,
            cookie: cookie,
            fid: parsed.fid,
            path: parsed.path,
            sectionId: sectionId,
            sectionName: sectionName,
            shouldCancel: shouldCancel,
          )
        : await (() async {
            final fastPathContext = await _findEntryFromParent(
              source,
              cookie: cookie,
              fid: parsed.fid,
              path: parsed.path,
              parentFid: parsed.parentFid,
              sectionId: sectionId,
              sectionName: sectionName,
            );
            if (fastPathContext != null) {
              return fastPathContext;
            }
            return _findEntryByTreeWalk(
              source,
              cookie: cookie,
              fid: parsed.fid,
              path: parsed.path,
              sectionId: sectionId,
              sectionName: sectionName,
              shouldCancel: shouldCancel,
            );
          })();
    if (context == null) {
      return null;
    }
    return _buildQuarkScannedItem(
      source: source,
      entry: context.entry,
      parentFid: context.parentFid,
      cookie: cookie,
      sectionId: context.sectionId,
      sectionName: context.sectionName,
      directoryEntriesByPath: context.directoryEntriesByPath,
      textFileCache: <String, Future<String>>{},
      downloadCache: <String, Future<QuarkResolvedDownload>>{},
      loadSidecarMetadata: shouldLoadSidecarMetadata,
    );
  }

  Future<_QuarkLibraryScanResult> _scanQuarkLibrary(
    MediaSourceConfig source, {
    required String cookie,
    required List<_QuarkDirectoryCursor> roots,
    required int limit,
    bool Function()? shouldCancel,
  }) async {
    final normalizedRoots = <_QuarkDirectoryCursor>[];
    for (final root in roots) {
      final normalizedParentFid =
          root.fid.trim().isEmpty ? source.quarkFolderId : root.fid.trim();
      final normalizedParentPath = _normalizeQuarkDirectoryPath(
        root.path.trim().isNotEmpty
            ? root.path.trim()
            : normalizedParentFid == source.quarkFolderId
                ? source.quarkFolderPath
                : '/',
      );
      if (source.matchesWebDavExcludedPath(normalizedParentPath)) {
        continue;
      }
      normalizedRoots.add(
        _QuarkDirectoryCursor(
          fid: normalizedParentFid,
          path: normalizedParentPath,
          rootPath: normalizedParentPath,
          sectionId: root.sectionId,
          sectionName: root.sectionName,
        ),
      );
    }
    if (normalizedRoots.isEmpty) {
      return const _QuarkLibraryScanResult();
    }

    final directoryEntriesByPath = <String, List<QuarkFileEntry>>{};
    final mediaEntries = <_QuarkQueuedMediaEntry>[];
    final queue = [...normalizedRoots];
    for (var index = 0;
        index < queue.length && mediaEntries.length < limit;
        index++) {
      _throwIfCancelled(shouldCancel);
      final cursor = queue[index];
      final entries = _normalizeQuarkListedEntries(
        await _quarkSaveClient.listEntries(
          cookie: cookie,
          parentFid: cursor.fid,
        ),
        parentDirectoryPath: cursor.path,
      );
      directoryEntriesByPath[cursor.path] = entries;
      for (final entry in entries) {
        if (source.matchesWebDavExcludedPath(entry.path)) {
          continue;
        }
        if (entry.isDirectory) {
          queue.add(
            _QuarkDirectoryCursor(
              fid: entry.fid,
              path: _normalizeQuarkDirectoryPath(entry.path),
              rootPath: cursor.rootPath,
              sectionId: cursor.sectionId,
              sectionName: cursor.sectionName,
            ),
          );
          continue;
        }
        if (!entry.isVideo) {
          continue;
        }
        mediaEntries.add(
          _QuarkQueuedMediaEntry(
            entry: entry,
            parentFid: cursor.fid,
            rootPath: cursor.rootPath,
            sectionId: cursor.sectionId,
            sectionName: cursor.sectionName,
          ),
        );
        if (mediaEntries.length >= limit) {
          break;
        }
      }
    }
    return _QuarkLibraryScanResult(
      directoryEntriesByPath: directoryEntriesByPath,
      mediaEntries: mediaEntries,
    );
  }

  Future<WebDavScannedItem> _buildQuarkScannedItem({
    required MediaSourceConfig source,
    required QuarkFileEntry entry,
    required String parentFid,
    required String cookie,
    required String sectionId,
    required String sectionName,
    required Map<String, List<QuarkFileEntry>> directoryEntriesByPath,
    required Map<String, Future<String>> textFileCache,
    required Map<String, Future<QuarkResolvedDownload>> downloadCache,
    required bool loadSidecarMetadata,
  }) async {
    final recognition = _resolveQuarkRecognition(source, entry);
    var seed = _buildQuarkBaseMetadataSeed(
      entry: entry,
      recognition: recognition,
    );
    if (loadSidecarMetadata) {
      seed = await _applyQuarkSidecarMetadata(
        entry: entry,
        cookie: cookie,
        seed: seed,
        directoryEntriesByPath: directoryEntriesByPath,
        textFileCache: textFileCache,
        downloadCache: downloadCache,
      );
    }
    final normalizedSectionName = sectionName.trim().isEmpty
        ? _displayNameFromPath(
            sectionId.trim().isEmpty ? source.quarkFolderPath : entry.path,
            fallback: source.name,
          )
        : sectionName.trim();
    return WebDavScannedItem(
      resourceId: _buildQuarkResourceId(
        fid: entry.fid,
        path: entry.path,
        parentFid: parentFid,
      ),
      fileName: entry.name,
      actualAddress: entry.path,
      sectionId: sectionId.trim(),
      sectionName: normalizedSectionName,
      streamUrl: '',
      streamHeaders: const <String, String>{},
      playbackItemId: entry.fid,
      addedAt: entry.updatedAt ?? DateTime.now(),
      modifiedAt: entry.updatedAt,
      fileSizeBytes: entry.sizeBytes ?? 0,
      metadataSeed: seed,
    );
  }

  WebDavScannedItem _quarkPendingItemToScannedItem(
    ExternalScanPendingItem item,
  ) {
    return WebDavScannedItem(
      resourceId: item.resourceId,
      fileName: item.fileName,
      actualAddress: item.actualAddress,
      sectionId: item.sectionId,
      sectionName: item.sectionName,
      streamUrl: item.streamUrl,
      streamHeaders: item.streamHeaders,
      playbackItemId: item.playbackItemId,
      addedAt: item.addedAt,
      modifiedAt: item.modifiedAt,
      fileSizeBytes: item.fileSizeBytes,
      metadataSeed: item.metadataSeed,
    );
  }

  List<String> _relativeQuarkDirectorySegmentsFromRoot({
    required String filePath,
    required String rootPath,
  }) {
    final normalizedFilePath = _normalizeQuarkDirectoryPath(filePath);
    final normalizedRootPath = _normalizeQuarkDirectoryPath(rootPath);
    final fileSegments = normalizedFilePath
        .split('/')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    final rootSegments = normalizedRootPath
        .split('/')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    var commonLength = 0;
    while (commonLength < fileSegments.length &&
        commonLength < rootSegments.length &&
        fileSegments[commonLength] == rootSegments[commonLength]) {
      commonLength += 1;
    }
    if (fileSegments.length <= commonLength + 1) {
      return const <String>[];
    }
    return fileSegments.sublist(commonLength, fileSegments.length - 1);
  }

  NasMediaRecognition _resolveQuarkRecognition(
    MediaSourceConfig source,
    QuarkFileEntry entry,
  ) {
    final useStructureInference = source.webDavStructureInferenceEnabled;
    return NasMediaRecognizer.recognize(
      useStructureInference ? entry.path : entry.name,
      seriesTitleFilterKeywords: useStructureInference
          ? source.normalizedWebDavSeriesTitleFilterKeywords
          : const <String>[],
      specialEpisodeKeywords: source.normalizedWebDavSpecialCategoryKeywords,
    );
  }

  WebDavMetadataSeed _buildQuarkBaseMetadataSeed({
    required QuarkFileEntry entry,
    required NasMediaRecognition recognition,
  }) {
    final normalizedTitle = recognition.title.trim().isNotEmpty
        ? recognition.title.trim()
        : _stripFileExtension(entry.name);
    final normalizedItemType = recognition.itemType.trim().isNotEmpty
        ? recognition.itemType.trim()
        : 'movie';
    return WebDavMetadataSeed(
      title: normalizedTitle,
      overview: '',
      posterUrl: '',
      posterHeaders: const <String, String>{},
      backdropUrl: '',
      backdropHeaders: const <String, String>{},
      logoUrl: '',
      logoHeaders: const <String, String>{},
      bannerUrl: '',
      bannerHeaders: const <String, String>{},
      extraBackdropUrls: const <String>[],
      extraBackdropHeaders: const <String, String>{},
      year: recognition.year,
      durationLabel: normalizedItemType == 'episode' ? '剧集' : '文件',
      genres: const <String>[],
      directors: const <String>[],
      actors: const <String>[],
      itemType: normalizedItemType,
      seasonNumber: recognition.seasonNumber,
      episodeNumber: recognition.episodeNumber,
      imdbId: recognition.imdbId,
      tmdbId: '',
      container: entry.extension,
      videoCodec: '',
      audioCodec: '',
      width: null,
      height: null,
      bitrate: null,
      hasSidecarMatch: false,
    );
  }

  Future<WebDavMetadataSeed> _applyQuarkSidecarMetadata({
    required QuarkFileEntry entry,
    required String cookie,
    required WebDavMetadataSeed seed,
    required Map<String, List<QuarkFileEntry>> directoryEntriesByPath,
    required Map<String, Future<String>> textFileCache,
    required Map<String, Future<QuarkResolvedDownload>> downloadCache,
  }) async {
    final currentDirectoryPath = _parentQuarkDirectoryPath(entry.path) ?? '/';
    final parentDirectoryPath = _parentQuarkDirectoryPath(currentDirectoryPath);
    final grandParentDirectoryPath = parentDirectoryPath == null
        ? null
        : _parentQuarkDirectoryPath(parentDirectoryPath);
    final siblings = directoryEntriesByPath[currentDirectoryPath] ??
        const <QuarkFileEntry>[];
    final parentEntries = parentDirectoryPath == null
        ? const <QuarkFileEntry>[]
        : (directoryEntriesByPath[parentDirectoryPath] ??
            const <QuarkFileEntry>[]);
    final grandParentEntries = grandParentDirectoryPath == null
        ? const <QuarkFileEntry>[]
        : (directoryEntriesByPath[grandParentDirectoryPath] ??
            const <QuarkFileEntry>[]);

    final primaryNfoEntry = _findBestQuarkNfoEntry(entry, siblings);
    final seasonNfoEntry = _findNamedQuarkFileEntry(
      siblings,
      const ['season.nfo', 'index.nfo'],
      excluding: primaryNfoEntry,
    );
    final seriesNfoEntry = _findNamedQuarkFileEntry(
          parentEntries,
          const ['tvshow.nfo', 'index.nfo'],
        ) ??
        _findNamedQuarkFileEntry(
          grandParentEntries,
          const ['tvshow.nfo', 'index.nfo'],
        );

    final primaryNfoMetadata = await _loadQuarkNfoMetadata(
      entry: primaryNfoEntry,
      cookie: cookie,
      textFileCache: textFileCache,
    );
    final seasonNfoMetadata = await _loadQuarkNfoMetadata(
      entry: seasonNfoEntry,
      cookie: cookie,
      textFileCache: textFileCache,
    );
    final seriesNfoMetadata = await _loadQuarkNfoMetadata(
      entry: seriesNfoEntry,
      cookie: cookie,
      textFileCache: textFileCache,
    );
    final nfoMetadata = _mergeQuarkNfoMetadata(
      primary: primaryNfoMetadata,
      secondary: _mergeQuarkNfoMetadata(
        primary: seasonNfoMetadata,
        secondary: seriesNfoMetadata,
      ),
    );

    final posterEntry = _findBestQuarkPosterEntry(entry, siblings) ??
        _findQuarkArtworkByRole(
          parentEntries,
          const ['poster', 'folder', 'cover'],
        ) ??
        _findQuarkArtworkByRole(
          grandParentEntries,
          const ['poster', 'folder', 'cover'],
        );
    final backdropEntry = _findQuarkArtworkByRole(
          siblings,
          const ['fanart', 'backdrop', 'landscape'],
        ) ??
        _findQuarkArtworkByRole(
          parentEntries,
          const ['fanart', 'backdrop', 'landscape'],
        ) ??
        _findQuarkArtworkByRole(
          grandParentEntries,
          const ['fanart', 'backdrop', 'landscape'],
        );
    final logoEntry = _findQuarkArtworkByRole(
          siblings,
          const ['clearlogo', 'logo'],
        ) ??
        _findQuarkArtworkByRole(
          parentEntries,
          const ['clearlogo', 'logo'],
        ) ??
        _findQuarkArtworkByRole(
          grandParentEntries,
          const ['clearlogo', 'logo'],
        );
    final bannerEntry = _findQuarkArtworkByRole(
          siblings,
          const ['banner'],
        ) ??
        _findQuarkArtworkByRole(
          parentEntries,
          const ['banner'],
        ) ??
        _findQuarkArtworkByRole(
          grandParentEntries,
          const ['banner'],
        );

    final posterArtwork = await _resolveQuarkArtwork(
      localEntry: posterEntry,
      remoteUrl: nfoMetadata?.thumbUrl ?? '',
      cookie: cookie,
      downloadCache: downloadCache,
    );
    final backdropArtwork = await _resolveQuarkArtwork(
      localEntry: backdropEntry,
      remoteUrl: nfoMetadata?.backdropUrl ?? '',
      cookie: cookie,
      downloadCache: downloadCache,
    );
    final logoArtwork = await _resolveQuarkArtwork(
      localEntry: logoEntry,
      remoteUrl: nfoMetadata?.logoUrl ?? '',
      cookie: cookie,
      downloadCache: downloadCache,
    );
    final bannerArtwork = await _resolveQuarkArtwork(
      localEntry: bannerEntry,
      remoteUrl: nfoMetadata?.bannerUrl ?? '',
      cookie: cookie,
      downloadCache: downloadCache,
    );

    final hasSidecarMatch = nfoMetadata != null ||
        posterArtwork.url.isNotEmpty ||
        backdropArtwork.url.isNotEmpty ||
        logoArtwork.url.isNotEmpty ||
        bannerArtwork.url.isNotEmpty ||
        (nfoMetadata?.extraBackdropUrls.isNotEmpty ?? false);
    return seed.copyWith(
      title: nfoMetadata?.title.trim().isNotEmpty == true
          ? nfoMetadata!.title.trim()
          : seed.title,
      overview: nfoMetadata?.overview.trim().isNotEmpty == true
          ? nfoMetadata!.overview.trim()
          : seed.overview,
      posterUrl:
          posterArtwork.url.isNotEmpty ? posterArtwork.url : seed.posterUrl,
      posterHeaders: posterArtwork.url.isNotEmpty
          ? posterArtwork.headers
          : seed.posterHeaders,
      backdropUrl: backdropArtwork.url.isNotEmpty
          ? backdropArtwork.url
          : seed.backdropUrl,
      backdropHeaders: backdropArtwork.url.isNotEmpty
          ? backdropArtwork.headers
          : seed.backdropHeaders,
      logoUrl: logoArtwork.url.isNotEmpty ? logoArtwork.url : seed.logoUrl,
      logoHeaders:
          logoArtwork.url.isNotEmpty ? logoArtwork.headers : seed.logoHeaders,
      bannerUrl:
          bannerArtwork.url.isNotEmpty ? bannerArtwork.url : seed.bannerUrl,
      bannerHeaders: bannerArtwork.url.isNotEmpty
          ? bannerArtwork.headers
          : seed.bannerHeaders,
      extraBackdropUrls: nfoMetadata?.extraBackdropUrls.isNotEmpty == true
          ? nfoMetadata!.extraBackdropUrls
          : seed.extraBackdropUrls,
      extraBackdropHeaders: nfoMetadata?.extraBackdropUrls.isNotEmpty == true
          ? const <String, String>{}
          : seed.extraBackdropHeaders,
      year: (nfoMetadata?.year ?? 0) > 0 ? nfoMetadata!.year : seed.year,
      durationLabel: nfoMetadata?.durationLabel.trim().isNotEmpty == true
          ? nfoMetadata!.durationLabel.trim()
          : seed.durationLabel,
      genres: nfoMetadata?.genres.isNotEmpty == true
          ? nfoMetadata!.genres
          : seed.genres,
      directors: nfoMetadata?.directors.isNotEmpty == true
          ? nfoMetadata!.directors
          : seed.directors,
      actors: nfoMetadata?.actors.isNotEmpty == true
          ? nfoMetadata!.actors
          : seed.actors,
      itemType: nfoMetadata?.itemType.trim().isNotEmpty == true
          ? nfoMetadata!.itemType.trim()
          : seed.itemType,
      seasonNumber: nfoMetadata?.seasonNumber ?? seed.seasonNumber,
      episodeNumber: nfoMetadata?.episodeNumber ?? seed.episodeNumber,
      imdbId: nfoMetadata?.imdbId.trim().isNotEmpty == true
          ? nfoMetadata!.imdbId.trim()
          : seed.imdbId,
      tmdbId: nfoMetadata?.tmdbId.trim().isNotEmpty == true
          ? nfoMetadata!.tmdbId.trim()
          : seed.tmdbId,
      container: nfoMetadata?.container.trim().isNotEmpty == true
          ? nfoMetadata!.container.trim()
          : seed.container,
      videoCodec: nfoMetadata?.videoCodec.trim().isNotEmpty == true
          ? nfoMetadata!.videoCodec.trim()
          : seed.videoCodec,
      audioCodec: nfoMetadata?.audioCodec.trim().isNotEmpty == true
          ? nfoMetadata!.audioCodec.trim()
          : seed.audioCodec,
      width: nfoMetadata?.width ?? seed.width,
      height: nfoMetadata?.height ?? seed.height,
      bitrate: nfoMetadata?.bitrate ?? seed.bitrate,
      hasSidecarMatch: seed.hasSidecarMatch || hasSidecarMatch,
    );
  }

  Future<_QuarkParsedNfoMetadata?> _loadQuarkNfoMetadata({
    required QuarkFileEntry? entry,
    required String cookie,
    required Map<String, Future<String>> textFileCache,
  }) async {
    if (entry == null) {
      return null;
    }
    try {
      final raw = await textFileCache.putIfAbsent(
        entry.fid,
        () => _quarkSaveClient.readTextFile(
          cookie: cookie,
          fid: entry.fid,
        ),
      );
      return _parseQuarkNfoMetadata(raw);
    } catch (_) {
      return null;
    }
  }

  _QuarkParsedNfoMetadata? _parseQuarkNfoMetadata(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      final document = XmlDocument.parse(trimmed);
      final root = document.rootElement;
      final durationLabel =
          _formatRuntimeLabel(_quarkXmlSingleText(root, 'runtime'));
      return _QuarkParsedNfoMetadata(
        title: _quarkXmlSingleText(root, 'title'),
        overview: _quarkXmlSingleText(root, 'plot'),
        thumbUrl: _quarkResolveNfoArtUrl(
          root,
          tagNames: const ['thumb', 'poster'],
        ),
        backdropUrl: _quarkResolveNfoArtUrl(
          root,
          tagNames: const ['fanart', 'backdrop', 'landscape'],
        ),
        logoUrl: _quarkResolveNfoArtUrl(
          root,
          tagNames: const ['clearlogo', 'logo'],
        ),
        bannerUrl: _quarkResolveNfoArtUrl(
          root,
          tagNames: const ['banner'],
        ),
        extraBackdropUrls: _quarkResolveNfoExtraBackdropUrls(root),
        year: _parseQuarkNfoYear(
          _quarkXmlSingleText(root, 'year'),
          fallbackDateText:
              '${_quarkXmlSingleText(root, 'premiered')} ${_quarkXmlSingleText(root, 'aired')}',
        ),
        durationLabel: durationLabel,
        genres: _quarkXmlTexts(root, 'genre'),
        directors: _quarkXmlTexts(root, 'director'),
        actors: _quarkResolveNfoActors(root),
        itemType: _resolveQuarkNfoItemType(root.name.local),
        seasonNumber: _tryParseInt(_quarkXmlSingleText(root, 'season')),
        episodeNumber: _tryParseInt(_quarkXmlSingleText(root, 'episode')),
        imdbId: _resolveQuarkNfoExternalId(
          root,
          type: 'imdb',
          fallbackTag: 'imdbid',
        ),
        tmdbId: _resolveQuarkNfoExternalId(
          root,
          type: 'tmdb',
          fallbackTag: 'tmdbid',
        ),
        container: _quarkResolveNfoStreamValue(
          root,
          primary: 'container',
          section: 'fileinfo',
        ),
        videoCodec: _quarkResolveNfoStreamValue(
          root,
          primary: 'codec',
          section: 'video',
        ),
        audioCodec: _quarkResolveNfoStreamValue(
          root,
          primary: 'codec',
          section: 'audio',
        ),
        width: _tryParseInt(
          _quarkResolveNfoStreamValue(
            root,
            primary: 'width',
            section: 'video',
          ),
        ),
        height: _tryParseInt(
          _quarkResolveNfoStreamValue(
            root,
            primary: 'height',
            section: 'video',
          ),
        ),
        bitrate: _tryParseInt(
          _quarkResolveNfoStreamValue(
            root,
            primary: 'bitrate',
            section: 'video',
          ),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  _QuarkParsedNfoMetadata? _mergeQuarkNfoMetadata({
    required _QuarkParsedNfoMetadata? primary,
    required _QuarkParsedNfoMetadata? secondary,
  }) {
    if (primary == null) {
      return secondary;
    }
    if (secondary == null) {
      return primary;
    }
    return _QuarkParsedNfoMetadata(
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

  QuarkFileEntry? _findBestQuarkNfoEntry(
    QuarkFileEntry videoEntry,
    List<QuarkFileEntry> siblings,
  ) {
    final baseName = _stripFileExtension(videoEntry.name).toLowerCase();
    return _findNamedQuarkFileEntry(
      siblings,
      [
        '$baseName.nfo',
        'movie.nfo',
        'tvshow.nfo',
        'index.nfo',
      ],
    );
  }

  QuarkFileEntry? _findNamedQuarkFileEntry(
    List<QuarkFileEntry> entries,
    List<String> preferredNames, {
    QuarkFileEntry? excluding,
  }) {
    final loweredEntries = entries
        .where((entry) => !entry.isDirectory)
        .where((entry) => entry.name.toLowerCase().endsWith('.nfo'))
        .toList(growable: false);
    for (final preferredName in preferredNames) {
      for (final entry in loweredEntries) {
        if (excluding != null && entry.fid == excluding.fid) {
          continue;
        }
        if (entry.name.toLowerCase() == preferredName.toLowerCase()) {
          return entry;
        }
      }
    }
    return null;
  }

  QuarkFileEntry? _findBestQuarkPosterEntry(
    QuarkFileEntry videoEntry,
    List<QuarkFileEntry> siblings,
  ) {
    final baseName = _stripFileExtension(videoEntry.name);
    return _findQuarkArtworkByRole(
      siblings,
      [
        '$baseName-poster',
        baseName,
        'poster',
        'folder',
        'cover',
      ],
    );
  }

  QuarkFileEntry? _findQuarkArtworkByRole(
    List<QuarkFileEntry> entries,
    List<String> names,
  ) {
    final preferredNames = _expandQuarkArtworkNames(names);
    final imageEntries = entries
        .where((entry) => !entry.isDirectory && _isQuarkImageEntry(entry))
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

  List<String> _expandQuarkArtworkNames(List<String> names) {
    final values = <String>[];
    final seen = <String>{};
    for (final rawName in names) {
      final normalized = rawName.trim();
      if (normalized.isEmpty) {
        continue;
      }
      if (normalized.contains('.')) {
        final lowered = normalized.toLowerCase();
        if (seen.add(lowered)) {
          values.add(normalized);
        }
        continue;
      }
      for (final extension in _quarkImageExtensions) {
        final candidate = '$normalized.$extension';
        final lowered = candidate.toLowerCase();
        if (seen.add(lowered)) {
          values.add(candidate);
        }
      }
    }
    return values;
  }

  bool _isQuarkImageEntry(QuarkFileEntry entry) {
    return _quarkImageExtensions.contains(entry.extension.trim().toLowerCase());
  }

  Future<_QuarkArtworkResolution> _resolveQuarkArtwork({
    required QuarkFileEntry? localEntry,
    required String remoteUrl,
    required String cookie,
    required Map<String, Future<QuarkResolvedDownload>> downloadCache,
  }) async {
    if (localEntry != null) {
      try {
        final download = await downloadCache.putIfAbsent(
          localEntry.fid,
          () => _quarkSaveClient.resolveDownload(
            cookie: cookie,
            fid: localEntry.fid,
          ),
        );
        return _QuarkArtworkResolution(
          url: download.url,
          headers: download.headers,
        );
      } catch (_) {
        // Fall back to remote artwork URL.
      }
    }
    final normalizedRemoteUrl = remoteUrl.trim();
    final parsedRemoteUrl = Uri.tryParse(normalizedRemoteUrl);
    if (parsedRemoteUrl != null && parsedRemoteUrl.hasScheme) {
      return _QuarkArtworkResolution(url: normalizedRemoteUrl);
    }
    return const _QuarkArtworkResolution();
  }

  String _normalizeQuarkDirectoryPath(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed == '/') {
      return '/';
    }
    final normalized =
        trimmed.replaceAll('\\', '/').replaceAll(RegExp(r'/+'), '/');
    final withLeadingSlash =
        normalized.startsWith('/') ? normalized : '/$normalized';
    return withLeadingSlash.endsWith('/')
        ? withLeadingSlash.substring(0, withLeadingSlash.length - 1)
        : withLeadingSlash;
  }

  List<QuarkFileEntry> _normalizeQuarkListedEntries(
    List<QuarkFileEntry> entries, {
    required String parentDirectoryPath,
  }) {
    final normalizedParentDirectoryPath =
        _normalizeQuarkDirectoryPath(parentDirectoryPath);
    return entries
        .map(
          (entry) => _normalizeQuarkListedEntry(
            entry,
            parentDirectoryPath: normalizedParentDirectoryPath,
          ),
        )
        .toList(growable: false);
  }

  QuarkFileEntry _normalizeQuarkListedEntry(
    QuarkFileEntry entry, {
    required String parentDirectoryPath,
  }) {
    final normalizedPath = _resolveQuarkListedEntryPath(
      entry,
      parentDirectoryPath: parentDirectoryPath,
    );
    if (normalizedPath == entry.path) {
      return entry;
    }
    return QuarkFileEntry(
      fid: entry.fid,
      name: entry.name,
      path: normalizedPath,
      isDirectory: entry.isDirectory,
      sizeBytes: entry.sizeBytes,
      updatedAt: entry.updatedAt,
      mimeType: entry.mimeType,
      category: entry.category,
      extension: entry.extension,
    );
  }

  String _resolveQuarkListedEntryPath(
    QuarkFileEntry entry, {
    required String parentDirectoryPath,
  }) {
    final normalizedParentDirectoryPath =
        _normalizeQuarkDirectoryPath(parentDirectoryPath);
    final rawPath =
        entry.path.trim().isNotEmpty ? entry.path : '/${entry.name}';
    final normalizedPath = _normalizeQuarkDirectoryPath(rawPath);
    if (normalizedParentDirectoryPath == '/' ||
        normalizedPath == normalizedParentDirectoryPath ||
        normalizedPath.startsWith('$normalizedParentDirectoryPath/')) {
      return normalizedPath;
    }
    final relativePath = normalizedPath.startsWith('/')
        ? normalizedPath.substring(1)
        : normalizedPath;
    if (relativePath.isEmpty) {
      return normalizedParentDirectoryPath;
    }
    return _normalizeQuarkDirectoryPath(
      '$normalizedParentDirectoryPath/$relativePath',
    );
  }

  String? _parentQuarkDirectoryPath(String raw) {
    final normalized = _normalizeQuarkDirectoryPath(raw);
    if (normalized == '/') {
      return null;
    }
    final segments = normalized
        .split('/')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) {
      return null;
    }
    if (segments.length == 1) {
      return '/';
    }
    return '/${segments.take(segments.length - 1).join('/')}';
  }

  String _quarkXmlSingleText(XmlElement node, String localName) {
    final match = node.descendants.whereType<XmlElement>().firstWhere(
          (element) => element.name.local == localName,
          orElse: () => XmlElement(XmlName(localName)),
        );
    return match.innerText.trim();
  }

  List<String> _quarkXmlTexts(XmlElement node, String localName) {
    return node.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == localName)
        .map((element) => element.innerText.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  List<String> _quarkResolveNfoActors(XmlElement root) {
    return root.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'actor')
        .map((element) => _quarkXmlSingleText(element, 'name'))
        .where((value) => value.trim().isNotEmpty)
        .toList(growable: false);
  }

  String _resolveQuarkNfoItemType(String rawRootName) {
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

  String _formatRuntimeLabel(String raw) {
    final minutes = _tryParseInt(raw);
    if (minutes != null && minutes > 0) {
      return '$minutes分钟';
    }
    return '文件';
  }

  int? _tryParseInt(String raw) {
    return int.tryParse(raw.trim());
  }

  int _parseQuarkNfoYear(
    String raw, {
    String fallbackDateText = '',
  }) {
    final parsed = _tryParseInt(raw);
    if (parsed != null && parsed > 0) {
      return parsed;
    }
    final match = RegExp(r'(\d{4})').firstMatch(fallbackDateText);
    return match == null ? 0 : int.parse(match.group(1)!);
  }

  String _resolveQuarkNfoExternalId(
    XmlElement root, {
    required String type,
    required String fallbackTag,
  }) {
    for (final element in root.descendants.whereType<XmlElement>()) {
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
    return _quarkXmlSingleText(root, fallbackTag);
  }

  String _quarkResolveNfoArtUrl(
    XmlElement root, {
    required List<String> tagNames,
  }) {
    final normalizedTagNames =
        tagNames.map((item) => item.trim().toLowerCase()).toSet();
    for (final element in root.descendants.whereType<XmlElement>()) {
      if (!normalizedTagNames.contains(element.name.local.toLowerCase())) {
        continue;
      }
      final value = element.innerText.trim();
      final parsed = Uri.tryParse(value);
      if (parsed != null && parsed.hasScheme) {
        return value;
      }
    }
    for (final art in root.descendants.whereType<XmlElement>()) {
      if (art.name.local != 'art') {
        continue;
      }
      for (final child in art.children.whereType<XmlElement>()) {
        if (!normalizedTagNames.contains(child.name.local.toLowerCase())) {
          continue;
        }
        final value = child.innerText.trim();
        final parsed = Uri.tryParse(value);
        if (parsed != null && parsed.hasScheme) {
          return value;
        }
      }
    }
    return '';
  }

  List<String> _quarkResolveNfoExtraBackdropUrls(XmlElement root) {
    final urls = <String>[];
    for (final element in root.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'thumb') {
        continue;
      }
      final parentName = element.parentElement?.name.local.toLowerCase() ?? '';
      if (parentName != 'fanart') {
        continue;
      }
      final value = element.innerText.trim();
      final parsed = Uri.tryParse(value);
      if (parsed != null && parsed.hasScheme) {
        urls.add(value);
      }
    }
    return urls;
  }

  String _quarkResolveNfoStreamValue(
    XmlElement root, {
    required String primary,
    required String section,
  }) {
    final streamDetails = root.descendants.whereType<XmlElement>().firstWhere(
          (element) => element.name.local == 'streamdetails',
          orElse: () => XmlElement(XmlName('streamdetails')),
        );
    if (streamDetails.children.isEmpty) {
      return '';
    }

    for (final child in streamDetails.descendants.whereType<XmlElement>()) {
      if (child.name.local != section) {
        continue;
      }
      final value = _quarkXmlSingleText(child, primary);
      if (value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return '';
  }

  String _buildQuarkResourceId({
    required String fid,
    required String path,
    required String parentFid,
  }) {
    final normalizedFid = Uri.encodeComponent(fid.trim());
    return Uri(
      scheme: 'quark',
      host: 'entry',
      path: '/$normalizedFid',
      queryParameters: {
        if (path.trim().isNotEmpty) 'path': path.trim(),
        if (parentFid.trim().isNotEmpty) 'parentFid': parentFid.trim(),
      },
    ).toString();
  }

  _ParsedQuarkResourceId? _parseQuarkResourceId(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != 'quark') {
      return null;
    }
    final segments = uri.pathSegments
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) {
      return null;
    }
    final fid = Uri.decodeComponent(segments.last);
    if (fid.isEmpty) {
      return null;
    }
    return _ParsedQuarkResourceId(
      fid: fid,
      path: uri.queryParameters['path']?.trim() ?? '',
      parentFid: uri.queryParameters['parentFid']?.trim() ?? '',
    );
  }

  String? _resolveQuarkParentDirectoryPath(
    MediaSourceConfig source, {
    required String path,
    required String parentFid,
    required String sectionId,
  }) {
    final normalizedParentFid = parentFid.trim();
    if (normalizedParentFid.isEmpty) {
      return null;
    }
    final normalizedSectionId = sectionId.trim();
    if (normalizedSectionId.isNotEmpty &&
        normalizedParentFid == normalizedSectionId) {
      return '/';
    }
    if (normalizedSectionId.isEmpty &&
        normalizedParentFid == source.quarkFolderId) {
      return _normalizeQuarkDirectoryPath(source.quarkFolderPath);
    }
    final parentDirectoryPath = _parentQuarkDirectoryPath(path);
    if (parentDirectoryPath == null || parentDirectoryPath == '/') {
      return null;
    }
    return parentDirectoryPath;
  }

  Future<_QuarkEntryContext?> _findEntryFromParent(
    MediaSourceConfig source, {
    required String cookie,
    required String fid,
    required String path,
    required String parentFid,
    required String sectionId,
    required String sectionName,
  }) async {
    final parentDirectoryPath = _resolveQuarkParentDirectoryPath(
      source,
      path: path,
      parentFid: parentFid,
      sectionId: sectionId,
    );
    if (parentDirectoryPath == null) {
      return null;
    }
    final entries = _normalizeQuarkListedEntries(
      await _quarkSaveClient.listEntries(
        cookie: cookie,
        parentFid: parentFid,
      ),
      parentDirectoryPath: parentDirectoryPath,
    );
    final matched = entries.where((entry) {
      if (entry.isDirectory) {
        return false;
      }
      if (entry.fid == fid) {
        return true;
      }
      return path.trim().isNotEmpty && entry.path.trim() == path.trim();
    });
    if (matched.isEmpty) {
      return null;
    }
    final entry = matched.first;
    final currentDirectoryPath = _parentQuarkDirectoryPath(entry.path) ?? '/';
    return _QuarkEntryContext(
      entry: entry,
      parentFid: parentFid,
      sectionId: sectionId,
      sectionName: sectionName,
      directoryEntriesByPath: {
        currentDirectoryPath: entries,
      },
    );
  }

  Future<_QuarkEntryContext?> _findEntryByTreeWalk(
    MediaSourceConfig source, {
    required String cookie,
    required String fid,
    required String path,
    required String sectionId,
    required String sectionName,
    bool Function()? shouldCancel,
  }) async {
    final rootFid =
        sectionId.trim().isNotEmpty ? sectionId.trim() : source.quarkFolderId;
    final rootPath = sectionId.trim().isNotEmpty ? '/' : source.quarkFolderPath;
    final directoryEntriesByPath = <String, List<QuarkFileEntry>>{};
    final queue = <_QuarkDirectoryCursor>[
      _QuarkDirectoryCursor(
        fid: rootFid,
        path: _normalizeQuarkDirectoryPath(rootPath),
        rootPath: _normalizeQuarkDirectoryPath(rootPath),
        sectionId: sectionId,
        sectionName: sectionName,
      ),
    ];
    for (var index = 0; index < queue.length; index++) {
      _throwIfCancelled(shouldCancel);
      final cursor = queue[index];
      final entries = _normalizeQuarkListedEntries(
        await _quarkSaveClient.listEntries(
          cookie: cookie,
          parentFid: cursor.fid,
        ),
        parentDirectoryPath: cursor.path,
      );
      directoryEntriesByPath[cursor.path] = entries;
      for (final entry in entries) {
        if (source.matchesWebDavExcludedPath(entry.path)) {
          continue;
        }
        if (!entry.isDirectory &&
            (entry.fid == fid ||
                (path.trim().isNotEmpty && entry.path.trim() == path.trim()))) {
          return _QuarkEntryContext(
            entry: entry,
            parentFid: cursor.fid,
            sectionId: cursor.sectionId,
            sectionName: cursor.sectionName,
            directoryEntriesByPath: Map<String, List<QuarkFileEntry>>.from(
              directoryEntriesByPath,
            ),
          );
        }
        if (entry.isDirectory) {
          queue.add(
            _QuarkDirectoryCursor(
              fid: entry.fid,
              path: _normalizeQuarkDirectoryPath(entry.path),
              rootPath: cursor.rootPath,
              sectionId: cursor.sectionId,
              sectionName: cursor.sectionName,
            ),
          );
        }
      }
    }
    return null;
  }

  String _stripFileExtension(String value) {
    final trimmed = value.trim();
    final dotIndex = trimmed.lastIndexOf('.');
    if (dotIndex <= 0) {
      return trimmed;
    }
    return trimmed.substring(0, dotIndex);
  }

  String _displayNameFromPath(String rawPath, {required String fallback}) {
    final normalized = _normalizeQuarkDirectoryPath(rawPath);
    if (normalized == '/') {
      return fallback;
    }
    final segments = normalized
        .split('/')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    return segments.isEmpty ? fallback : segments.last;
  }

  void _throwIfCancelled(bool Function()? shouldCancel) {
    if (shouldCancel?.call() == true) {
      throw _QuarkScanCancelledException();
    }
  }
}

class _QuarkScanCancelledException implements Exception {
  const _QuarkScanCancelledException();
}

class _QuarkDirectoryCursor {
  const _QuarkDirectoryCursor({
    required this.fid,
    required this.path,
    required this.rootPath,
    this.sectionId = '',
    this.sectionName = '',
  });

  final String fid;
  final String path;
  final String rootPath;
  final String sectionId;
  final String sectionName;
}

class _QuarkQueuedMediaEntry {
  const _QuarkQueuedMediaEntry({
    required this.entry,
    required this.parentFid,
    required this.rootPath,
    required this.sectionId,
    required this.sectionName,
  });

  final QuarkFileEntry entry;
  final String parentFid;
  final String rootPath;
  final String sectionId;
  final String sectionName;
}

class _QuarkLibraryScanResult {
  const _QuarkLibraryScanResult({
    this.directoryEntriesByPath = const <String, List<QuarkFileEntry>>{},
    this.mediaEntries = const <_QuarkQueuedMediaEntry>[],
  });

  final Map<String, List<QuarkFileEntry>> directoryEntriesByPath;
  final List<_QuarkQueuedMediaEntry> mediaEntries;
}

class _QuarkEntryContext {
  const _QuarkEntryContext({
    required this.entry,
    required this.parentFid,
    required this.sectionId,
    required this.sectionName,
    required this.directoryEntriesByPath,
  });

  final QuarkFileEntry entry;
  final String parentFid;
  final String sectionId;
  final String sectionName;
  final Map<String, List<QuarkFileEntry>> directoryEntriesByPath;
}

class _QuarkParsedNfoMetadata {
  const _QuarkParsedNfoMetadata({
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

class _QuarkArtworkResolution {
  const _QuarkArtworkResolution({
    this.url = '',
    this.headers = const <String, String>{},
  });

  final String url;
  final Map<String, String> headers;
}

const Set<String> _quarkImageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'webp',
};

class _ParsedQuarkResourceId {
  const _ParsedQuarkResourceId({
    required this.fid,
    required this.path,
    required this.parentFid,
  });

  final String fid;
  final String path;
  final String parentFid;
}
