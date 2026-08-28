part of 'webdav_nas_client.dart';

List<ExternalScanPendingItem> applyExternalDirectoryStructureInference(
  List<ExternalScanPendingItem> items, {
  required MediaSourceConfig source,
}) {
  return _ExternalScanStructureModule().apply(
    items,
    source: source,
  );
}

List<String> _relativeDirectorySegmentsFromRoot({
  required Uri fileUri,
  required Uri rootUri,
}) {
  return NasMediaPathPolicy.resolvePathContext(
    resourcePath: fileUri.toString(),
    sectionId: rootUri.toString(),
  ).relativeDirectories;
}

class _ExternalScanStructureModule {
  List<_PendingWebDavScannedItem> apply(
    List<_PendingWebDavScannedItem> items, {
    required MediaSourceConfig source,
  }) {
    if (items.isEmpty) {
      return items;
    }

    final context = _buildStructureContext(
      items,
      source: source,
    );
    final seriesRootPlans = _buildSeriesRootPlans(context);
    final singleVideoMovieResourceIds = _resolveSingleVideoMovieResourceIds(
      context,
      seriesRootPlans: seriesRootPlans,
    );
    final seriesRootForResource = _mapSeriesRootForResource(
      items: items,
      seriesRootPlans: seriesRootPlans,
      movieVersionResourceIds: context.movieVersionResourceIds,
      singleVideoMovieResourceIds: singleVideoMovieResourceIds,
    );
    final assignment = _assignItemsToStructure(
      items: items,
      context: context,
      seriesRootPlans: seriesRootPlans,
      seriesRootForResource: seriesRootForResource,
    );
    final episodeOverrides = _resolveEpisodeOverrides(
      context: context,
      episodeItemsByGroup: assignment.episodeItemsByGroup,
      seasonOrderByRoot: assignment.seasonOrderByRoot,
    );

    final resolvedItems = assignment.items
        .map(
          (item) => item.copyWith(
            metadataSeed:
                episodeOverrides[item.resourceId] ?? item.metadataSeed,
          ),
        )
        .toList(growable: false);

    return resolvedItems;
  }

  _StructureInferenceContext _buildStructureContext(
    List<_PendingWebDavScannedItem> items, {
    required MediaSourceConfig source,
  }) {
    final filesByDirectory = <String, List<_PendingWebDavScannedItem>>{};
    final childVideoCountsByDirectory = <String, Map<String, int>>{};
    final childItemsByDirectory =
        <String, Map<String, List<_PendingWebDavScannedItem>>>{};
    final recognitionByResource = <String, NasMediaRecognition>{};

    final seriesTitleFilterKeywords =
        source.normalizedWebDavSeriesTitleFilterKeywords;
    final specialEpisodeKeywords =
        source.normalizedWebDavSpecialCategoryKeywords;
    for (final item in items) {
      final directoryKey = _segmentsKey(item.relativeDirectories);
      filesByDirectory.putIfAbsent(directoryKey, () => []).add(item);
      final recognition = NasMediaRecognizer.recognize(
        item.actualAddress,
        seriesTitleFilterKeywords: seriesTitleFilterKeywords,
        specialEpisodeKeywords: specialEpisodeKeywords,
      );
      recognitionByResource[item.resourceId] = recognition;
      for (var depth = 0; depth < item.relativeDirectories.length; depth++) {
        final parentKey = _segmentsKey(item.relativeDirectories.take(depth));
        final childName = item.relativeDirectories[depth];
        final counts = childVideoCountsByDirectory.putIfAbsent(
          parentKey,
          () => <String, int>{},
        );
        counts[childName] = (counts[childName] ?? 0) + 1;
        childItemsByDirectory
            .putIfAbsent(
              parentKey,
              () => <String, List<_PendingWebDavScannedItem>>{},
            )
            .putIfAbsent(childName, () => <_PendingWebDavScannedItem>[])
            .add(item);
      }
    }

    final movieVersionResourceIds = _resolveMovieVersionResourceIds(
      childItemsByDirectory: childItemsByDirectory,
      recognitionByResource: recognitionByResource,
    );

    return _StructureInferenceContext(
      filesByDirectory: filesByDirectory,
      childVideoCountsByDirectory: childVideoCountsByDirectory,
      childItemsByDirectory: childItemsByDirectory,
      recognitionByResource: recognitionByResource,
      movieVersionResourceIds: movieVersionResourceIds,
      specialEpisodeKeywords: specialEpisodeKeywords,
      seriesTitleFilterKeywords: seriesTitleFilterKeywords,
    );
  }

  Set<String> _resolveMovieVersionResourceIds({
    required Map<String, Map<String, List<_PendingWebDavScannedItem>>>
        childItemsByDirectory,
    required Map<String, NasMediaRecognition> recognitionByResource,
  }) {
    final resourceIds = <String>{};
    for (final parentEntry in childItemsByDirectory.entries) {
      final parentSegments = _segmentsFromKey(parentEntry.key);
      final parentDepth = parentSegments.length;
      final parentTitle = parentSegments.isEmpty ? '' : parentSegments.last;
      final movieVersionGroups = parentEntry.value.entries.where((entry) {
        if (!NasMediaRecognizer.matchesMovieVersionFolderLabel(entry.key) &&
            !NasMediaPathPolicy.looksLikeNestedMovieReleaseFolder(
              parentTitle: parentTitle,
              childDirectoryName: entry.key,
            )) {
          return false;
        }
        return entry.value.every((item) {
          final directories = item.relativeDirectories;
          // A version folder may contain another organization layer (for
          // example Disc 1, CD 2, or a release subdirectory).  The child map
          // already contains every descendant item, so only require that the
          // version directory is the first child below this parent.
          if (directories.length <= parentDepth ||
              directories[parentDepth] != entry.key) {
            return false;
          }
          final seed = item.metadataSeed;
          final recognition = recognitionByResource[item.resourceId];
          final seedType = seed.itemType.trim().toLowerCase();
          final recognitionType = recognition?.itemType.trim().toLowerCase();
          return seedType != 'episode' &&
              seedType != 'series' &&
              seedType != 'season' &&
              recognitionType != 'episode' &&
              recognitionType != 'series' &&
              recognitionType != 'season' &&
              seed.seasonNumber == null &&
              seed.episodeNumber == null &&
              recognition?.seasonNumber == null &&
              recognition?.episodeNumber == null;
        });
      }).toList(growable: false);
      if (movieVersionGroups.length < 2) {
        final isSingleNestedMovieWrapper = movieVersionGroups.length == 1 &&
            parentEntry.value.length == 1 &&
            movieVersionGroups.single.value.length == 1 &&
            parentTitle.trim().isNotEmpty &&
            !NasMediaRecognizer.isGenericLibraryFolderLabel(parentTitle);
        if (isSingleNestedMovieWrapper) {
          resourceIds.addAll(
            movieVersionGroups.single.value.map((item) => item.resourceId),
          );
        }
        continue;
      }
      resourceIds.addAll(
        movieVersionGroups.expand(
          (entry) => entry.value.map((item) => item.resourceId),
        ),
      );
    }
    return resourceIds;
  }

  Set<String> _resolveSingleVideoMovieResourceIds(
    _StructureInferenceContext context, {
    required Map<String, _SeriesRootInferencePlan> seriesRootPlans,
  }) {
    final resourceIds = <String>{};
    for (final scannedItem in context.filesByDirectory.values.expand(
      (items) => items,
    )) {
      final resourceId = scannedItem.resourceId;
      final directoryKey = _segmentsKey(scannedItem.relativeDirectories);
      final directItems = context.filesByDirectory[directoryKey] ?? const [];
      final childGroups = context.childItemsByDirectory[directoryKey] ??
          const <String, List<_PendingWebDavScannedItem>>{};
      final seed = scannedItem.metadataSeed;
      final recognition = context.recognitionByResource[resourceId];
      if (directItems.length != 1 || childGroups.isNotEmpty) {
        continue;
      }
      if (seed.itemType.trim().isNotEmpty ||
          seed.seasonNumber != null ||
          seed.episodeNumber != null ||
          recognition?.itemType.trim().toLowerCase() == 'episode' ||
          recognition?.seasonNumber != null ||
          recognition?.episodeNumber != null) {
        continue;
      }
      if (context.movieVersionResourceIds.contains(resourceId)) {
        continue;
      }
      if (seriesRootPlans.containsKey(directoryKey)) {
        // A direct file under a planned root belongs to that root (for
        // example a special or an implicit episode), not to a standalone
        // movie fallback.
        continue;
      }
      if (_hasSeriesAncestor(
        scannedItem,
        context: context,
        seriesRootPlans: seriesRootPlans,
      )) {
        continue;
      }
      resourceIds.add(resourceId);
    }
    return resourceIds;
  }

  bool _hasSeriesAncestor(
    _PendingWebDavScannedItem item, {
    required _StructureInferenceContext context,
    required Map<String, _SeriesRootInferencePlan> seriesRootPlans,
  }) {
    final directories = item.relativeDirectories;
    for (var ancestorLength = 0;
        ancestorLength < directories.length;
        ancestorLength++) {
      final ancestorKey = _segmentsKey(
        directories.take(ancestorLength),
      );
      final childGroups = context.childItemsByDirectory[ancestorKey];
      if (childGroups == null || childGroups.isEmpty) {
        continue;
      }

      final plan = seriesRootPlans[ancestorKey];
      final ancestorSegments = _segmentsFromKey(ancestorKey);
      if (ancestorSegments.isEmpty) {
        // The scan root itself is a library scope, not a title-bearing media
        // directory, when this item enters through a transport wrapper.  A
        // different series directly beside that wrapper must not promote the
        // single movie below it.
        if (directories.isNotEmpty &&
            _isTransportDirectoryLabel(
              directories.first,
              configuredKeywords: context.seriesTitleFilterKeywords,
            )) {
          continue;
        }
        // A scoped scan may itself start at a series directory, so an empty
        // relative root can be a real media root.  Only suppress it when all
        // of its child directories are transport wrappers.
        final isTransportRoot = childGroups.keys.every(
          (childName) => _isTransportDirectoryLabel(
            childName,
            configuredKeywords: context.seriesTitleFilterKeywords,
          ),
        );
        if (isTransportRoot) {
          continue;
        }
      }
      final ancestorTitle = ancestorSegments.isEmpty
          ? ''
          : ancestorSegments.last.trim().toLowerCase();
      final isTransportDirectory = ancestorSegments.isNotEmpty &&
          _isTransportDirectoryLabel(
            ancestorTitle,
            configuredKeywords: context.seriesTitleFilterKeywords,
          );
      // Transport/library wrappers (for example `strm/quark`) are shared by
      // unrelated movies and series.  Episode evidence from a sibling under
      // such a wrapper must never promote a one-file movie directory into a
      // `webdav-series` group.  Only a real, title-bearing ancestor can own
      // descendant series evidence.
      if (isTransportDirectory) {
        continue;
      }
      if (plan != null && !isTransportDirectory) {
        // A non-transport directory with child media directories owns those
        // descendants.  Recognized movie-version resources are excluded
        // before this check; every other unclassified child becomes an
        // implicit season of the parent series.
        return true;
      }

      final descendantItems = childGroups.values.expand((items) => items);
      if (descendantItems.any(
        (descendant) => _hasExplicitSeriesEvidence(
          descendant,
          recognition: context.recognitionByResource[descendant.resourceId],
        ),
      )) {
        return true;
      }

      // Multiple non-version child directories are a useful fallback signal
      // for layouts such as `Show/Disc 1` and `Show/Disc 2` only when their
      // files themselves carry episode/season evidence.  Release/quality
      // directories are deliberately excluded to avoid treating movie
      // versions as seasons.
      if (childGroups.length >= 2) {
        final parentSegments = _segmentsFromKey(ancestorKey);
        final parentTitle = parentSegments.isEmpty ? '' : parentSegments.last;
        final nonVersionGroups = childGroups.entries.where((entry) {
          return !NasMediaRecognizer.matchesMovieVersionFolderLabel(
                entry.key,
              ) &&
              !NasMediaPathPolicy.looksLikeNestedMovieReleaseFolder(
                parentTitle: parentTitle,
                childDirectoryName: entry.key,
              );
        });
        if (nonVersionGroups.length >= 2 &&
            nonVersionGroups.any(
              (entry) => entry.value.any(
                (descendant) => _hasExplicitSeriesEvidence(
                  descendant,
                  recognition:
                      context.recognitionByResource[descendant.resourceId],
                ),
              ),
            )) {
          return true;
        }
      }
    }
    return false;
  }

  bool _isTransportDirectoryLabel(
    String value, {
    required List<String> configuredKeywords,
  }) {
    return NasMediaPathPolicy.isPublicDirectory(
      value,
      configuredKeywords: configuredKeywords,
    );
  }

  bool _hasExplicitSeriesEvidence(
    _PendingWebDavScannedItem item, {
    required NasMediaRecognition? recognition,
  }) {
    final seed = item.metadataSeed;
    final itemType = seed.itemType.trim().toLowerCase();
    if (itemType == 'episode' || itemType == 'series' || itemType == 'season') {
      return true;
    }
    final recognitionType = recognition?.itemType.trim().toLowerCase();
    return recognitionType == 'episode' ||
        recognitionType == 'series' ||
        recognitionType == 'season' ||
        seed.seasonNumber != null ||
        seed.episodeNumber != null ||
        recognition?.seasonNumber != null ||
        recognition?.episodeNumber != null;
  }

  Map<String, _SeriesRootInferencePlan> _buildSeriesRootPlans(
    _StructureInferenceContext context,
  ) {
    final seriesRootPlans = <String, _SeriesRootInferencePlan>{};
    final candidateDirectoryKeys = <String>{
      ...context.filesByDirectory.keys,
      ...context.childVideoCountsByDirectory.keys,
    };
    for (final directoryKey in candidateDirectoryKeys) {
      final directorySegments = _segmentsFromKey(directoryKey);
      if (directorySegments.isNotEmpty &&
          _isTransportDirectoryLabel(
            directorySegments.last,
            configuredKeywords: context.seriesTitleFilterKeywords,
          )) {
        continue;
      }
      final childGroups = context.childItemsByDirectory[directoryKey] ??
          const <String, List<_PendingWebDavScannedItem>>{};
      final promoteAllChildDirectories = directorySegments.isNotEmpty ||
          !childGroups.keys.every(
            (childName) => _isTransportDirectoryLabel(
              childName,
              configuredKeywords: context.seriesTitleFilterKeywords,
            ),
          );
      final plan = _buildSeriesRootPlan(
        directoryKey: directoryKey,
        filesByDirectory: context.filesByDirectory,
        childItemsByDirectory: context.childItemsByDirectory,
        recognitionByResource: context.recognitionByResource,
        specialEpisodeKeywords: context.specialEpisodeKeywords,
        promoteAllChildDirectories: promoteAllChildDirectories,
      );
      if (plan == null) {
        continue;
      }
      seriesRootPlans[directoryKey] = plan;
    }
    return seriesRootPlans;
  }

  Map<String, String> _mapSeriesRootForResource({
    required List<_PendingWebDavScannedItem> items,
    required Map<String, _SeriesRootInferencePlan> seriesRootPlans,
    required Set<String> movieVersionResourceIds,
    required Set<String> singleVideoMovieResourceIds,
  }) {
    final seriesRootForResource = <String, String>{};
    for (final item in items) {
      if (movieVersionResourceIds.contains(item.resourceId)) {
        continue;
      }
      if (singleVideoMovieResourceIds.contains(item.resourceId)) {
        continue;
      }
      String? matchedRootKey;
      for (var length = item.relativeDirectories.length;
          length >= 0;
          length--) {
        final candidateKey =
            _segmentsKey(item.relativeDirectories.take(length));
        if (!seriesRootPlans.containsKey(candidateKey)) {
          continue;
        }
        final preferredAncestorKey = _resolvePreferredAncestorSeriesRoot(
          relativeDirectories: item.relativeDirectories,
          candidateKey: candidateKey,
          seriesRootPlans: seriesRootPlans,
        );
        matchedRootKey = preferredAncestorKey ?? candidateKey;
        seriesRootForResource[item.resourceId] = matchedRootKey;
        break;
      }
    }
    return seriesRootForResource;
  }

  String? _resolvePreferredAncestorSeriesRoot({
    required List<String> relativeDirectories,
    required String candidateKey,
    required Map<String, _SeriesRootInferencePlan> seriesRootPlans,
  }) {
    final candidateSegments = _segmentsFromKey(candidateKey);
    if (candidateSegments.isEmpty) {
      return null;
    }

    for (var ancestorLength = candidateSegments.length - 1;
        ancestorLength >= 0;
        ancestorLength--) {
      if (ancestorLength >= relativeDirectories.length) {
        continue;
      }
      final ancestorKey =
          _segmentsKey(relativeDirectories.take(ancestorLength));
      final ancestorPlan = seriesRootPlans[ancestorKey];
      if (ancestorPlan == null) {
        continue;
      }
      final childDirectoryName = relativeDirectories[ancestorLength];
      if (ancestorPlan.structuralChildDirectories
          .contains(childDirectoryName)) {
        return ancestorKey;
      }
    }
    return null;
  }

  _StructureAssignment _assignItemsToStructure({
    required List<_PendingWebDavScannedItem> items,
    required _StructureInferenceContext context,
    required Map<String, _SeriesRootInferencePlan> seriesRootPlans,
    required Map<String, String> seriesRootForResource,
  }) {
    final nextItems = <_PendingWebDavScannedItem>[];
    final episodeItemsByGroup = <String, List<_PendingWebDavScannedItem>>{};
    final seasonOrderByRoot = <String, List<String>>{};

    for (final item in items) {
      final seriesRootKey = seriesRootForResource[item.resourceId];
      if (seriesRootKey != null) {
        final assignment = _assignSeriesEpisode(
          item: item,
          seriesRootKey: seriesRootKey,
          plan: seriesRootPlans[seriesRootKey]!,
          recognition: context.recognitionByResource[item.resourceId],
          seasonOrderByRoot: seasonOrderByRoot,
          specialEpisodeKeywords: context.specialEpisodeKeywords,
        );
        episodeItemsByGroup
            .putIfAbsent(
                assignment.groupKey, () => <_PendingWebDavScannedItem>[])
            .add(assignment.item);
        nextItems.add(assignment.item);
        continue;
      }

      nextItems.add(_applySingleFileFallback(item, context));
    }

    return _StructureAssignment(
      items: nextItems,
      episodeItemsByGroup: episodeItemsByGroup,
      seasonOrderByRoot: seasonOrderByRoot,
    );
  }

  _AssignedSeriesEpisode _assignSeriesEpisode({
    required _PendingWebDavScannedItem item,
    required String seriesRootKey,
    required _SeriesRootInferencePlan plan,
    required NasMediaRecognition? recognition,
    required Map<String, List<String>> seasonOrderByRoot,
    required List<String> specialEpisodeKeywords,
  }) {
    final seed = item.metadataSeed;
    final explicitSeasonNumber = seed.seasonNumber ?? recognition?.seasonNumber;
    final rootDepth = _segmentsFromKey(seriesRootKey).length;
    final isRootDirectFile = item.relativeDirectories.length == rootDepth;
    final childDirectoryName =
        isRootDirectFile ? '' : item.relativeDirectories[rootDepth];
    final collapseChildDirectoryToRoot = !isRootDirectFile &&
        plan.collapseChildDirectoriesToRoot.contains(childDirectoryName);
    final relativeDirectoriesAfterRoot =
        item.relativeDirectories.skip(rootDepth).toList(growable: false);
    final effectiveRelativeDirectoriesAfterRoot =
        collapseChildDirectoryToRoot && relativeDirectoriesAfterRoot.isNotEmpty
            ? relativeDirectoriesAfterRoot.skip(1).toList(growable: false)
            : relativeDirectoriesAfterRoot;
    final effectiveIsRootDirectFile =
        isRootDirectFile || collapseChildDirectoryToRoot;
    final effectiveChildDirectoryName = effectiveIsRootDirectFile ||
            effectiveRelativeDirectoriesAfterRoot.isEmpty
        ? ''
        : effectiveRelativeDirectoriesAfterRoot.first;
    final matchesSpecialEpisodeKeyword = _matchesSpecialEpisodeKeyword(
      item,
      specialEpisodeKeywords: specialEpisodeKeywords,
      directoryNames: relativeDirectoriesAfterRoot,
    );
    final hintedSeasonNumber = matchesSpecialEpisodeKeyword
        ? 0
        : effectiveIsRootDirectFile
            ? null
            : plan.seasonNumberByChildDirectory[effectiveChildDirectoryName];
    final derivedSeasonNumber = matchesSpecialEpisodeKeyword
        ? 0
        : effectiveIsRootDirectFile
            ? collapseChildDirectoryToRoot
                ? 1
                : plan.rootItemsAsSpecials
                    ? 0
                    : 1
            : hintedSeasonNumber;
    final resolvedExplicitSeasonNumber =
        matchesSpecialEpisodeKeyword ? 0 : explicitSeasonNumber;
    final seasonGroupKey = resolvedExplicitSeasonNumber != null
        ? _buildExplicitSeasonGroupKey(resolvedExplicitSeasonNumber)
        : effectiveIsRootDirectFile
            ? (collapseChildDirectoryToRoot
                ? _implicitSeasonGroupKey
                : plan.rootItemsAsSpecials
                    ? _directSeasonGroupKey
                    : _implicitSeasonGroupKey)
            : hintedSeasonNumber != null
                ? _buildExplicitSeasonGroupKey(hintedSeasonNumber)
                : effectiveChildDirectoryName;

    final seasonOrder = seasonOrderByRoot.putIfAbsent(
      seriesRootKey,
      () => <String>[],
    );
    if (!seasonOrder.contains(seasonGroupKey)) {
      seasonOrder.add(seasonGroupKey);
    }

    final nextSeed = seed.copyWith(
      itemType: 'episode',
      seasonNumber: resolvedExplicitSeasonNumber ?? derivedSeasonNumber,
    );
    final nextItem = item.copyWith(metadataSeed: nextSeed);

    return _AssignedSeriesEpisode(
      item: nextItem,
      groupKey: '$seriesRootKey::$seasonGroupKey',
    );
  }

  _PendingWebDavScannedItem _applySingleFileFallback(
    _PendingWebDavScannedItem item,
    _StructureInferenceContext context,
  ) {
    final seed = item.metadataSeed;
    final recognition = context.recognitionByResource[item.resourceId];
    if (context.movieVersionResourceIds.contains(item.resourceId)) {
      final recognizedTitle = _movieVersionParentTitle(item) ??
          (recognition?.parentTitle.trim().isNotEmpty == true
              ? recognition!.parentTitle.trim()
              : recognition?.title.trim() ?? '');
      return item.copyWith(
        metadataSeed: seed.copyWith(
          title: recognizedTitle.isNotEmpty ? recognizedTitle : seed.title,
          durationLabel: seed.durationLabel.trim().isEmpty ||
                  seed.durationLabel.trim() == '剧集'
              ? '文件'
              : seed.durationLabel,
          itemType: 'movie',
        ),
      );
    }
    final explicitSeasonNumber = seed.seasonNumber ?? recognition?.seasonNumber;
    final explicitEpisodeNumber =
        seed.episodeNumber ?? recognition?.episodeNumber;
    final parentDirectoryKey = _segmentsKey(item.relativeDirectories);
    final directVideoCount =
        context.filesByDirectory[parentDirectoryKey]?.length ?? 0;
    final childDirectoryCount =
        context.childVideoCountsByDirectory[parentDirectoryKey]?.length ?? 0;
    final matchesSpecialEpisodeKeyword = _matchesSpecialEpisodeKeyword(
      item,
      specialEpisodeKeywords: context.specialEpisodeKeywords,
      directoryNames: item.relativeDirectories,
    );

    if (seed.itemType.trim().isNotEmpty ||
        directVideoCount != 1 ||
        childDirectoryCount != 0) {
      return item;
    }

    final resolvedItemType = matchesSpecialEpisodeKeyword ||
            explicitEpisodeNumber != null ||
            explicitSeasonNumber != null
        ? 'episode'
        : 'movie';

    return item.copyWith(
      metadataSeed: seed.copyWith(
        itemType: resolvedItemType,
        seasonNumber: matchesSpecialEpisodeKeyword ? 0 : explicitSeasonNumber,
        episodeNumber: explicitEpisodeNumber ??
            (matchesSpecialEpisodeKeyword && resolvedItemType == 'episode'
                ? 1
                : null),
      ),
    );
  }

  String? _movieVersionParentTitle(_PendingWebDavScannedItem item) {
    final directories = item.relativeDirectories;
    for (var index = 1; index < directories.length; index++) {
      if (!NasMediaRecognizer.matchesMovieVersionFolderLabel(
            directories[index],
          ) &&
          !NasMediaPathPolicy.looksLikeNestedMovieReleaseFolder(
            parentTitle: directories[index - 1],
            childDirectoryName: directories[index],
          )) {
        continue;
      }
      final parentTitle = directories[index - 1].trim();
      if (parentTitle.isNotEmpty) {
        return parentTitle;
      }
    }
    return null;
  }

  Map<String, WebDavMetadataSeed> _resolveEpisodeOverrides({
    required _StructureInferenceContext context,
    required Map<String, List<_PendingWebDavScannedItem>> episodeItemsByGroup,
    required Map<String, List<String>> seasonOrderByRoot,
  }) {
    final seasonNumberByGroup = _resolveSeasonNumberByGroup(seasonOrderByRoot);
    final episodeOverrides = <String, WebDavMetadataSeed>{};

    for (final entry in episodeItemsByGroup.entries) {
      final seasonNumber = seasonNumberByGroup[entry.key];
      final leadingEpisodeNumbers = _resolveGroupedLeadingEpisodeNumbers(
        items: entry.value,
        recognitionByResource: context.recognitionByResource,
      );
      final orderedEpisodes = _orderEpisodeItemsForGroup(
        items: entry.value,
        recognitionByResource: context.recognitionByResource,
        leadingEpisodeNumbers: leadingEpisodeNumbers,
      );
      final groupHasExplicitEpisodeNumber = orderedEpisodes.any((item) {
        final recognition = context.recognitionByResource[item.resourceId];
        return (item.metadataSeed.episodeNumber ??
                recognition?.episodeNumber ??
                leadingEpisodeNumbers[item.resourceId]) !=
            null;
      });
      for (var index = 0; index < orderedEpisodes.length; index++) {
        final item = orderedEpisodes[index];
        final recognition = context.recognitionByResource[item.resourceId];
        final explicitSeasonNumber =
            item.metadataSeed.seasonNumber ?? recognition?.seasonNumber;
        final explicitEpisodeNumber = item.metadataSeed.episodeNumber ??
            recognition?.episodeNumber ??
            leadingEpisodeNumbers[item.resourceId];
        final isDirectSeasonGroup =
            entry.key.endsWith('::$_directSeasonGroupKey');
        final isImplicitSeasonGroup =
            entry.key.endsWith('::$_implicitSeasonGroupKey');
        final resolvedSeasonNumber = explicitSeasonNumber ??
            seasonNumber ??
            (isDirectSeasonGroup
                ? 0
                : isImplicitSeasonGroup
                    ? 1
                    : 1);
        final resolvedEpisodeNumber = explicitEpisodeNumber ??
            ((resolvedSeasonNumber == 0 || !groupHasExplicitEpisodeNumber)
                ? index + 1
                : null);
        episodeOverrides[item.resourceId] = item.metadataSeed.copyWith(
          seasonNumber: resolvedSeasonNumber,
          episodeNumber: resolvedEpisodeNumber,
        );
      }
    }
    return episodeOverrides;
  }

  List<_PendingWebDavScannedItem> _orderEpisodeItemsForGroup({
    required List<_PendingWebDavScannedItem> items,
    required Map<String, NasMediaRecognition> recognitionByResource,
    required Map<String, int> leadingEpisodeNumbers,
  }) {
    final hasExplicitEpisodeNumber = items.any((item) {
      final recognition = recognitionByResource[item.resourceId];
      return (item.metadataSeed.episodeNumber ??
              recognition?.episodeNumber ??
              leadingEpisodeNumbers[item.resourceId]) !=
          null;
    });
    if (!hasExplicitEpisodeNumber) {
      final datedItems = <_EpisodeDateOrderEntry>[];
      for (final item in items) {
        final parsedDate = _parseEpisodeDateFromFileName(item.fileName);
        if (parsedDate == null) {
          datedItems.clear();
          break;
        }
        datedItems.add(
          _EpisodeDateOrderEntry(
            item: item,
            date: parsedDate,
          ),
        );
      }
      if (datedItems.length == items.length && datedItems.length >= 2) {
        datedItems.sort((left, right) {
          final dateCompare = left.date.compareTo(right.date);
          if (dateCompare != 0) {
            return dateCompare;
          }
          final nameCompare = left.item.fileName.toLowerCase().compareTo(
                right.item.fileName.toLowerCase(),
              );
          if (nameCompare != 0) {
            return nameCompare;
          }
          return left.item.actualAddress.toLowerCase().compareTo(
                right.item.actualAddress.toLowerCase(),
              );
        });

        return datedItems.map((entry) => entry.item).toList(growable: false);
      }
    }

    final orderedEpisodes = [...items]..sort((left, right) {
        final leftRecognition = recognitionByResource[left.resourceId];
        final rightRecognition = recognitionByResource[right.resourceId];
        final leftEpisodeNumber = left.metadataSeed.episodeNumber ??
            leftRecognition?.episodeNumber ??
            leadingEpisodeNumbers[left.resourceId];
        final rightEpisodeNumber = right.metadataSeed.episodeNumber ??
            rightRecognition?.episodeNumber ??
            leadingEpisodeNumbers[right.resourceId];
        if (leftEpisodeNumber != null || rightEpisodeNumber != null) {
          if (leftEpisodeNumber == null) {
            return 1;
          }
          if (rightEpisodeNumber == null) {
            return -1;
          }
          final episodeComparison =
              leftEpisodeNumber.compareTo(rightEpisodeNumber);
          if (episodeComparison != 0) {
            return episodeComparison;
          }
        }
        return left.actualAddress.toLowerCase().compareTo(
              right.actualAddress.toLowerCase(),
            );
      });
    return orderedEpisodes;
  }

  Map<String, int> _resolveGroupedLeadingEpisodeNumbers({
    required List<_PendingWebDavScannedItem> items,
    required Map<String, NasMediaRecognition> recognitionByResource,
  }) {
    final episodeNumbers = <String, int>{};
    for (final item in items) {
      final recognition = recognitionByResource[item.resourceId];
      final explicitEpisodeNumber =
          item.metadataSeed.episodeNumber ?? recognition?.episodeNumber;
      if (explicitEpisodeNumber != null) {
        continue;
      }
      final leadingEpisodeNumber = _parseGroupedLeadingEpisodeNumber(
        item.fileName,
      );
      if (leadingEpisodeNumber == null) {
        return const <String, int>{};
      }
      episodeNumbers[item.resourceId] = leadingEpisodeNumber;
    }
    return episodeNumbers;
  }

  int? _parseGroupedLeadingEpisodeNumber(String value) {
    final match = RegExp(
      r'^\s*0*(\d{1,3})(?:[ ._\-、]+)(?=\S)',
      caseSensitive: false,
    ).firstMatch(value.trim());
    final episodeNumber = int.tryParse(match?.group(1) ?? '');
    if (episodeNumber == null || episodeNumber <= 0) {
      return null;
    }
    return episodeNumber;
  }

  Map<String, int> _resolveSeasonNumberByGroup(
    Map<String, List<String>> seasonOrderByRoot,
  ) {
    final seasonNumberByGroup = <String, int>{};
    for (final entry in seasonOrderByRoot.entries) {
      if (entry.value.contains(_directSeasonGroupKey)) {
        seasonNumberByGroup['${entry.key}::$_directSeasonGroupKey'] = 0;
      }
      if (entry.value.contains(_implicitSeasonGroupKey)) {
        seasonNumberByGroup['${entry.key}::$_implicitSeasonGroupKey'] = 1;
      }
      final orderedGroups = entry.value
          .where(
            (group) =>
                group != _directSeasonGroupKey &&
                group != _implicitSeasonGroupKey,
          )
          .toList(growable: false)
        ..sort((left, right) {
          final leftExplicit = _parseExplicitSeasonGroupKey(left);
          final rightExplicit = _parseExplicitSeasonGroupKey(right);
          if (leftExplicit != null || rightExplicit != null) {
            if (leftExplicit == null) {
              return 1;
            }
            if (rightExplicit == null) {
              return -1;
            }
            return leftExplicit.compareTo(rightExplicit);
          }
          return left.toLowerCase().compareTo(right.toLowerCase());
        });
      var nextFallbackSeasonNumber =
          entry.value.contains(_implicitSeasonGroupKey) ? 2 : 1;
      for (final group in orderedGroups) {
        final explicitSeasonNumber = _parseExplicitSeasonGroupKey(group);
        final resolvedSeasonNumber =
            explicitSeasonNumber ?? nextFallbackSeasonNumber;
        seasonNumberByGroup['${entry.key}::$group'] = resolvedSeasonNumber;
        if (explicitSeasonNumber == null) {
          nextFallbackSeasonNumber += 1;
        }
      }
    }
    return seasonNumberByGroup;
  }

  _SeriesRootInferencePlan? _buildSeriesRootPlan({
    required String directoryKey,
    required Map<String, List<_PendingWebDavScannedItem>> filesByDirectory,
    required Map<String, Map<String, List<_PendingWebDavScannedItem>>>
        childItemsByDirectory,
    required Map<String, NasMediaRecognition> recognitionByResource,
    required List<String> specialEpisodeKeywords,
    required bool promoteAllChildDirectories,
  }) {
    final directItems = filesByDirectory[directoryKey] ?? const [];
    final childGroups = childItemsByDirectory[directoryKey] ??
        const <String, List<_PendingWebDavScannedItem>>{};
    if (directItems.isEmpty && childGroups.isEmpty) {
      return null;
    }

    final seasonHintsByChildDirectory = <String, _SeasonDirectoryHint>{};
    // Every child media directory belongs to this root.  Explicit season
    // hints refine the season number, while an unrecognized child remains an
    // implicit season instead of becoming a deeper standalone series root.
    final structuralChildDirectories =
        promoteAllChildDirectories ? <String>{...childGroups.keys} : <String>{};
    final collapseChildDirectoriesToRoot = <String>{};
    for (final entry in childGroups.entries) {
      final hint = _resolveSeasonDirectoryHint(
        parentDirectoryKey: directoryKey,
        childDirectoryName: entry.key,
        items: entry.value,
        siblingDirectoryNames: childGroups.keys.toList(growable: false),
        recognitionByResource: recognitionByResource,
        specialEpisodeKeywords: specialEpisodeKeywords,
      );
      if (hint != null) {
        seasonHintsByChildDirectory[entry.key] = hint;
        structuralChildDirectories.add(entry.key);
      }
      if (_isFlatWrapperChildDirectory(
        directoryKey: directoryKey,
        childDirectoryName: entry.key,
        items: entry.value,
      )) {
        structuralChildDirectories.add(entry.key);
        collapseChildDirectoriesToRoot.add(entry.key);
      }
    }

    final hasImplicitRootEpisodes =
        childGroups.isEmpty && directItems.length >= 2;
    if (hasImplicitRootEpisodes) {
      return const _SeriesRootInferencePlan(
        rootItemsAsSpecials: false,
        seasonNumberByChildDirectory: <String, int?>{},
      );
    }

    if (childGroups.isEmpty) {
      return null;
    }

    return _SeriesRootInferencePlan(
      rootItemsAsSpecials: directItems.isNotEmpty,
      seasonNumberByChildDirectory: {
        for (final childDirectoryName in childGroups.keys)
          childDirectoryName:
              seasonHintsByChildDirectory[childDirectoryName]?.seasonNumber,
      },
      structuralChildDirectories: structuralChildDirectories,
      collapseChildDirectoriesToRoot: collapseChildDirectoriesToRoot,
    );
  }

  _SeasonDirectoryHint? _resolveSeasonDirectoryHint({
    required String parentDirectoryKey,
    required String childDirectoryName,
    required List<_PendingWebDavScannedItem> items,
    required List<String> siblingDirectoryNames,
    required Map<String, NasMediaRecognition> recognitionByResource,
    required List<String> specialEpisodeKeywords,
  }) {
    if (items.isEmpty) {
      return null;
    }

    if (_matchesAnySpecialEpisodeKeyword(
      [childDirectoryName],
      specialEpisodeKeywords: specialEpisodeKeywords,
    )) {
      return const _SeasonDirectoryHint(seasonNumber: 0);
    }

    final explicitSeasonNumber = _parseSeasonNumberFromDirectoryName(
      childDirectoryName,
    );
    if (explicitSeasonNumber != null) {
      return _SeasonDirectoryHint(seasonNumber: explicitSeasonNumber);
    }

    if (_looksLikeNumericSeasonDirectory(
      childDirectoryName,
      siblingDirectoryNames: siblingDirectoryNames,
    )) {
      final seasonNumber = _parseLeadingNumericSeasonNumber(childDirectoryName);

      return _SeasonDirectoryHint(
        seasonNumber: seasonNumber,
      );
    }

    if (_looksLikeYearGroupingDirectory(
      childDirectoryName,
      siblingDirectoryNames: siblingDirectoryNames,
    )) {
      return const _SeasonDirectoryHint(seasonNumber: null);
    }

    final childDirectoryDepth = _segmentsFromKey(parentDirectoryKey).length + 1;
    final explicitSeasonNumbers = items
        .where(
          (item) => item.relativeDirectories.length == childDirectoryDepth,
        )
        .map(
          (item) =>
              item.metadataSeed.seasonNumber ??
              recognitionByResource[item.resourceId]?.seasonNumber,
        )
        .whereType<int>()
        .toSet();
    if (explicitSeasonNumbers.length == 1) {
      return _SeasonDirectoryHint(seasonNumber: explicitSeasonNumbers.first);
    }

    return null;
  }

  int? _parseSeasonNumberFromDirectoryName(String value) {
    return parseSeasonNumberFromFolderLabel(value);
  }

  int? _parseLeadingNumericSeasonNumber(String value) {
    return parseLeadingNumericSeasonNumber(value);
  }

  bool _isFlatWrapperChildDirectory({
    required String directoryKey,
    required String childDirectoryName,
    required List<_PendingWebDavScannedItem> items,
  }) {
    if (!NasMediaRecognizer.matchesWrapperFolderLabel(childDirectoryName)) {
      return false;
    }
    final rootDepth = _segmentsFromKey(directoryKey).length;
    return items
        .every((item) => item.relativeDirectories.length == rootDepth + 1);
  }

  DateTime? _parseEpisodeDateFromFileName(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return null;
    }

    for (final pattern in const [
      r'(?<!\d)(\d{4})[ ._\-](0?[1-9]|1[0-2])[ ._\-](0?[1-9]|[12]\d|3[01])(?!\d)',
      r'(?<!\d)(\d{4})年\s*(0?[1-9]|1[0-2])月\s*(0?[1-9]|[12]\d|3[01])日?(?!\d)',
      r'(?<!\d)(\d{4})(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])(?!\d)',
    ]) {
      final match =
          RegExp(pattern, caseSensitive: false).firstMatch(normalized);
      final parsedDate = _tryBuildEpisodeDate(
        yearText: match?.group(1),
        monthText: match?.group(2),
        dayText: match?.group(3),
      );
      if (parsedDate != null) {
        return parsedDate;
      }
    }
    return null;
  }

  DateTime? _tryBuildEpisodeDate({
    required String? yearText,
    required String? monthText,
    required String? dayText,
  }) {
    final year = int.tryParse(yearText ?? '');
    final month = int.tryParse(monthText ?? '');
    final day = int.tryParse(dayText ?? '');
    if (year == null || month == null || day == null) {
      return null;
    }
    final parsedDate = DateTime.utc(year, month, day);
    if (parsedDate.year != year ||
        parsedDate.month != month ||
        parsedDate.day != day) {
      return null;
    }
    return parsedDate;
  }

  bool _looksLikeNumericSeasonDirectory(
    String value, {
    required List<String> siblingDirectoryNames,
  }) {
    final seasonNumber = _parseLeadingNumericSeasonNumber(value);
    if (seasonNumber == null) {
      return false;
    }
    final numericSiblingCount = siblingDirectoryNames
        .where((name) => _parseLeadingNumericSeasonNumber(name) != null)
        .length;
    return numericSiblingCount >= 2;
  }

  bool _looksLikeYearGroupingDirectory(
    String value, {
    required List<String> siblingDirectoryNames,
  }) {
    if (!looksLikeYearGroupingFolderLabel(value)) {
      return false;
    }
    final yearSiblingCount =
        siblingDirectoryNames.where(looksLikeYearGroupingFolderLabel).length;
    return yearSiblingCount >= 2;
  }

  bool _matchesSpecialEpisodeKeyword(
    _PendingWebDavScannedItem item, {
    required List<String> specialEpisodeKeywords,
    Iterable<String> directoryNames = const <String>[],
  }) {
    return _matchesSpecialCategoryKeyword(
      item,
      keywords: specialEpisodeKeywords,
      directoryNames: directoryNames,
    );
  }

  bool _matchesSpecialCategoryKeyword(
    _PendingWebDavScannedItem item, {
    required List<String> keywords,
    Iterable<String> directoryNames = const <String>[],
  }) {
    if (keywords.isEmpty) {
      return false;
    }
    return _matchesAnySpecialEpisodeKeyword(
      [
        item.fileName,
        _stripFileExtension(item.fileName),
        item.metadataSeed.title,
        ...directoryNames,
      ],
      specialEpisodeKeywords: keywords,
    );
  }

  bool _matchesAnySpecialEpisodeKeyword(
    Iterable<String> rawValues, {
    required List<String> specialEpisodeKeywords,
  }) {
    return MediaNaming.matchesAnyKeyword(
      rawValues,
      keywords: specialEpisodeKeywords,
    );
  }

  String _stripFileExtension(String fileName) {
    final trimmed = fileName.trim();
    final lastDot = trimmed.lastIndexOf('.');
    if (lastDot <= 0) {
      return trimmed;
    }
    return trimmed.substring(0, lastDot);
  }

  String _buildExplicitSeasonGroupKey(int seasonNumber) {
    return '__season__:$seasonNumber';
  }

  int? _parseExplicitSeasonGroupKey(String value) {
    if (!value.startsWith('__season__:')) {
      return null;
    }
    return int.tryParse(value.substring('__season__:'.length));
  }

  String _segmentsKey(Iterable<String> segments) {
    return segments
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .join('/');
  }

  List<String> _segmentsFromKey(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      return const [];
    }
    return trimmed
        .split('/')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
  }
}

class _StructureInferenceContext {
  const _StructureInferenceContext({
    required this.filesByDirectory,
    required this.childVideoCountsByDirectory,
    required this.childItemsByDirectory,
    required this.recognitionByResource,
    required this.movieVersionResourceIds,
    required this.specialEpisodeKeywords,
    required this.seriesTitleFilterKeywords,
  });

  final Map<String, List<_PendingWebDavScannedItem>> filesByDirectory;
  final Map<String, Map<String, int>> childVideoCountsByDirectory;
  final Map<String, Map<String, List<_PendingWebDavScannedItem>>>
      childItemsByDirectory;
  final Map<String, NasMediaRecognition> recognitionByResource;
  final Set<String> movieVersionResourceIds;
  final List<String> specialEpisodeKeywords;
  final List<String> seriesTitleFilterKeywords;
}

class _StructureAssignment {
  const _StructureAssignment({
    required this.items,
    required this.episodeItemsByGroup,
    required this.seasonOrderByRoot,
  });

  final List<_PendingWebDavScannedItem> items;
  final Map<String, List<_PendingWebDavScannedItem>> episodeItemsByGroup;
  final Map<String, List<String>> seasonOrderByRoot;
}

class _AssignedSeriesEpisode {
  const _AssignedSeriesEpisode({
    required this.item,
    required this.groupKey,
  });

  final _PendingWebDavScannedItem item;
  final String groupKey;
}

class _EpisodeDateOrderEntry {
  const _EpisodeDateOrderEntry({
    required this.item,
    required this.date,
  });

  final _PendingWebDavScannedItem item;
  final DateTime date;
}
