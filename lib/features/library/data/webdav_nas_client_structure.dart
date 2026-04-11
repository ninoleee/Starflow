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
  final rootSegments = rootUri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  final fileSegments = fileUri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);

  var index = 0;
  while (index < rootSegments.length &&
      index < fileSegments.length &&
      rootSegments[index] == fileSegments[index]) {
    index += 1;
  }
  if (index >= fileSegments.length) {
    return const [];
  }
  final relativeSegments = fileSegments.skip(index).toList(growable: false);
  if (relativeSegments.length <= 1) {
    return const [];
  }
  return relativeSegments
      .take(relativeSegments.length - 1)
      .map(_decodePathSegment)
      .toList(growable: false);
}

String _decodePathSegment(String raw) {
  try {
    return Uri.decodeComponent(raw);
  } catch (_) {
    return raw;
  }
}

class _ExternalScanStructureModule {
  List<_PendingWebDavScannedItem> apply(
    List<_PendingWebDavScannedItem> items, {
    required MediaSourceConfig source,
  }) {
    if (items.isEmpty) {
      return items;
    }
    final filteredItems = _filterExtraItems(
      items,
      source: source,
    );
    if (filteredItems.isEmpty) {
      webDavTrace(
        'structure.done',
        fields: {
          'resultCount': 0,
          'episodes': 0,
          'movies': 0,
          'filteredExtras': items.length,
        },
      );
      return const [];
    }
    webDavTrace(
      'structure.start',
      fields: {
        'itemCount': filteredItems.length,
        'filteredExtras': items.length - filteredItems.length,
      },
    );

    final context = _buildStructureContext(
      filteredItems,
      source: source,
    );
    final seriesRootPlans = _buildSeriesRootPlans(context);
    final seriesRootForResource = _mapSeriesRootForResource(
      items: filteredItems,
      seriesRootPlans: seriesRootPlans,
    );
    final assignment = _assignItemsToStructure(
      items: filteredItems,
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
    webDavTrace(
      'structure.done',
      fields: {
        'resultCount': resolvedItems.length,
        'episodes': resolvedItems
            .where((item) => item.metadataSeed.itemType == 'episode')
            .length,
        'movies': resolvedItems
            .where((item) => item.metadataSeed.itemType == 'movie')
            .length,
        'filteredExtras': items.length - filteredItems.length,
      },
    );
    return resolvedItems;
  }

  List<_PendingWebDavScannedItem> _filterExtraItems(
    List<_PendingWebDavScannedItem> items, {
    required MediaSourceConfig source,
  }) {
    final extraKeywords = source.normalizedWebDavExtraKeywords;
    if (extraKeywords.isEmpty) {
      return items;
    }
    final keptItems = <_PendingWebDavScannedItem>[];
    for (final item in items) {
      if (_matchesSpecialCategoryKeyword(
        item,
        keywords: extraKeywords,
        directoryNames: item.relativeDirectories,
      )) {
        webDavTrace(
          'structure.filterExtra',
          fields: {
            'path': item.actualAddress,
            'fileName': item.fileName,
            'relativeDirs': item.relativeDirectories,
          },
        );
        continue;
      }
      keptItems.add(item);
    }
    return keptItems;
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
    final explicitEpisodeCountByDirectory = <String, int>{};

    final seriesTitleFilterKeywords =
        source.normalizedWebDavSeriesTitleFilterKeywords;
    final specialEpisodeKeywords =
        source.normalizedWebDavSpecialEpisodeKeywords;
    final extraKeywords = source.normalizedWebDavExtraKeywords;
    for (final item in items) {
      final directoryKey = _segmentsKey(item.relativeDirectories);
      filesByDirectory.putIfAbsent(directoryKey, () => []).add(item);
      final recognition = NasMediaRecognizer.recognize(
        item.actualAddress,
        seriesTitleFilterKeywords: seriesTitleFilterKeywords,
      );
      recognitionByResource[item.resourceId] = recognition;
      if (_hasExplicitEpisodeCue(item, recognition)) {
        explicitEpisodeCountByDirectory[directoryKey] =
            (explicitEpisodeCountByDirectory[directoryKey] ?? 0) + 1;
      }
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

    for (final entry in filesByDirectory.entries) {
      final childDirectoryNames =
          childItemsByDirectory[entry.key]?.keys.toList(growable: false) ??
              const <String>[];
      webDavTrace(
        'structure.context.directory',
        fields: {
          'directory': entry.key,
          'directItems': entry.value.length,
          'childDirs': childDirectoryNames,
        },
      );
    }

    return _StructureInferenceContext(
      filesByDirectory: filesByDirectory,
      childVideoCountsByDirectory: childVideoCountsByDirectory,
      childItemsByDirectory: childItemsByDirectory,
      recognitionByResource: recognitionByResource,
      explicitEpisodeCountByDirectory: explicitEpisodeCountByDirectory,
      specialEpisodeKeywords: specialEpisodeKeywords,
      extraKeywords: extraKeywords,
    );
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
      final plan = _buildSeriesRootPlan(
        directoryKey: directoryKey,
        filesByDirectory: context.filesByDirectory,
        childItemsByDirectory: context.childItemsByDirectory,
        recognitionByResource: context.recognitionByResource,
        explicitEpisodeCountByDirectory:
            context.explicitEpisodeCountByDirectory,
        specialEpisodeKeywords: context.specialEpisodeKeywords,
      );
      if (plan == null) {
        continue;
      }
      seriesRootPlans[directoryKey] = plan;
      webDavTrace(
        'structure.seriesRoot',
        fields: {
          'directory': directoryKey,
          'rootItemsAsSpecials': plan.rootItemsAsSpecials,
          'seasonDirs': plan.seasonNumberByChildDirectory,
        },
      );
    }
    return seriesRootPlans;
  }

  Map<String, String> _mapSeriesRootForResource({
    required List<_PendingWebDavScannedItem> items,
    required Map<String, _SeriesRootInferencePlan> seriesRootPlans,
  }) {
    final seriesRootForResource = <String, String>{};
    for (final item in items) {
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
      webDavTrace(
        matchedRootKey == null
            ? 'structure.rootMapping.unassigned'
            : 'structure.rootMapping.assigned',
        fields: {
          'path': item.actualAddress,
          'relativeDirs': item.relativeDirectories,
          'resourceId': item.resourceId,
          'seriesRoot': matchedRootKey,
        },
      );
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
      final hintedSeasonNumber =
          ancestorPlan.seasonNumberByChildDirectory[childDirectoryName];
      if (hintedSeasonNumber != null) {
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
    final explicitEpisodeNumber =
        seed.episodeNumber ?? recognition?.episodeNumber;
    final rootDepth = _segmentsFromKey(seriesRootKey).length;
    final isRootDirectFile = item.relativeDirectories.length == rootDepth;
    final childDirectoryName =
        isRootDirectFile ? '' : item.relativeDirectories[rootDepth];
    final relativeDirectoriesAfterRoot =
        item.relativeDirectories.skip(rootDepth).toList(growable: false);
    final matchesSpecialEpisodeKeyword = _matchesSpecialEpisodeKeyword(
      item,
      specialEpisodeKeywords: specialEpisodeKeywords,
      directoryNames: relativeDirectoriesAfterRoot,
    );
    final hintedSeasonNumber = matchesSpecialEpisodeKeyword
        ? 0
        : isRootDirectFile
            ? null
            : plan.seasonNumberByChildDirectory[childDirectoryName];
    final derivedSeasonNumber = matchesSpecialEpisodeKeyword
        ? 0
        : isRootDirectFile
            ? plan.rootItemsAsSpecials
                ? 0
                : 1
            : hintedSeasonNumber;
    final resolvedExplicitSeasonNumber =
        matchesSpecialEpisodeKeyword ? 0 : explicitSeasonNumber;
    final seasonGroupKey = resolvedExplicitSeasonNumber != null
        ? _buildExplicitSeasonGroupKey(resolvedExplicitSeasonNumber)
        : isRootDirectFile
            ? (plan.rootItemsAsSpecials
                ? _directSeasonGroupKey
                : _implicitSeasonGroupKey)
            : hintedSeasonNumber != null
                ? _buildExplicitSeasonGroupKey(hintedSeasonNumber)
                : childDirectoryName;

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
    webDavTrace(
      'structure.assignSeriesEpisode',
      fields: {
        'path': item.actualAddress,
        'seriesRoot': seriesRootKey,
        'seasonGroup': seasonGroupKey,
        'season': nextSeed.seasonNumber,
        'episode': explicitEpisodeNumber,
        'title': nextSeed.title,
        'specialKeyword': matchesSpecialEpisodeKeyword,
      },
    );
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
    webDavTrace(
      'structure.singleFileFallback',
      fields: {
        'path': item.actualAddress,
        'resolvedItemType': resolvedItemType,
        'season': matchesSpecialEpisodeKeyword ? 0 : explicitSeasonNumber,
        'episode': explicitEpisodeNumber,
        'specialKeyword': matchesSpecialEpisodeKeyword,
      },
    );
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

  Map<String, WebDavMetadataSeed> _resolveEpisodeOverrides({
    required _StructureInferenceContext context,
    required Map<String, List<_PendingWebDavScannedItem>> episodeItemsByGroup,
    required Map<String, List<String>> seasonOrderByRoot,
  }) {
    final seasonNumberByGroup = _resolveSeasonNumberByGroup(seasonOrderByRoot);
    final episodeOverrides = <String, WebDavMetadataSeed>{};

    for (final entry in episodeItemsByGroup.entries) {
      final seasonNumber = seasonNumberByGroup[entry.key];
      final orderedEpisodes = _orderEpisodeItemsForGroup(
        items: entry.value,
        recognitionByResource: context.recognitionByResource,
      );
      for (var index = 0; index < orderedEpisodes.length; index++) {
        final item = orderedEpisodes[index];
        final recognition = context.recognitionByResource[item.resourceId];
        final explicitSeasonNumber =
            item.metadataSeed.seasonNumber ?? recognition?.seasonNumber;
        final explicitEpisodeNumber =
            item.metadataSeed.episodeNumber ?? recognition?.episodeNumber;
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
        episodeOverrides[item.resourceId] = item.metadataSeed.copyWith(
          seasonNumber: resolvedSeasonNumber,
          episodeNumber: explicitEpisodeNumber ?? index + 1,
        );
      }
    }
    return episodeOverrides;
  }

  List<_PendingWebDavScannedItem> _orderEpisodeItemsForGroup({
    required List<_PendingWebDavScannedItem> items,
    required Map<String, NasMediaRecognition> recognitionByResource,
  }) {
    final hasExplicitEpisodeNumber = items.any((item) {
      final recognition = recognitionByResource[item.resourceId];
      return (item.metadataSeed.episodeNumber ?? recognition?.episodeNumber) !=
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
        webDavTrace(
          'structure.episodeOrder.date',
          fields: {
            'items': datedItems
                .map(
                  (entry) =>
                      '${entry.item.fileName}@${entry.date.toIso8601String()}',
                )
                .toList(growable: false),
          },
        );
        return datedItems.map((entry) => entry.item).toList(growable: false);
      }
    }

    final orderedEpisodes = [...items]
      ..sort((left, right) => left.actualAddress.toLowerCase().compareTo(
            right.actualAddress.toLowerCase(),
          ));
    return orderedEpisodes;
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
      var nextFallbackSeasonNumber = 1;
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
    required Map<String, int> explicitEpisodeCountByDirectory,
    required List<String> specialEpisodeKeywords,
  }) {
    final directItems = filesByDirectory[directoryKey] ?? const [];
    final childGroups = childItemsByDirectory[directoryKey] ??
        const <String, List<_PendingWebDavScannedItem>>{};
    if (directItems.isEmpty && childGroups.isEmpty) {
      webDavTrace(
        'structure.plan.skipEmpty',
        fields: {
          'directory': directoryKey,
        },
      );
      return null;
    }

    final directExplicitEpisodeCount =
        explicitEpisodeCountByDirectory[directoryKey] ?? 0;
    final seasonHintsByChildDirectory = <String, _SeasonDirectoryHint>{};
    for (final entry in childGroups.entries) {
      final hint = _resolveSeasonDirectoryHint(
        childDirectoryName: entry.key,
        items: entry.value,
        siblingDirectoryNames: childGroups.keys.toList(growable: false),
        recognitionByResource: recognitionByResource,
        specialEpisodeKeywords: specialEpisodeKeywords,
      );
      if (hint != null) {
        seasonHintsByChildDirectory[entry.key] = hint;
      }
    }

    final hasImplicitRootEpisodes =
        childGroups.isEmpty && directItems.length >= 2;
    if (hasImplicitRootEpisodes) {
      webDavTrace(
        'structure.plan.implicitSeason',
        fields: {
          'directory': directoryKey,
          'directItems': directItems.length,
          'explicitEpisodes': directExplicitEpisodeCount,
        },
      );
      return const _SeriesRootInferencePlan(
        rootItemsAsSpecials: false,
        seasonNumberByChildDirectory: <String, int?>{},
      );
    }

    if (childGroups.isEmpty) {
      webDavTrace(
        'structure.plan.noSeriesRoot',
        fields: {
          'directory': directoryKey,
          'directItems': directItems.length,
          'childDirs': childGroups.keys.toList(),
          'seasonHints': seasonHintsByChildDirectory,
        },
      );
      return null;
    }

    webDavTrace(
      'structure.plan.seriesRoot',
      fields: {
        'directory': directoryKey,
        'directItems': directItems.length,
        'rootItemsAsSpecials': directItems.isNotEmpty,
        'seasonHints': seasonHintsByChildDirectory,
      },
    );
    return _SeriesRootInferencePlan(
      rootItemsAsSpecials: directItems.isNotEmpty,
      seasonNumberByChildDirectory: {
        for (final childDirectoryName in childGroups.keys)
          childDirectoryName:
              seasonHintsByChildDirectory[childDirectoryName]?.seasonNumber,
      },
    );
  }

  _SeasonDirectoryHint? _resolveSeasonDirectoryHint({
    required String childDirectoryName,
    required List<_PendingWebDavScannedItem> items,
    required List<String> siblingDirectoryNames,
    required Map<String, NasMediaRecognition> recognitionByResource,
    required List<String> specialEpisodeKeywords,
  }) {
    if (items.isEmpty) {
      webDavTrace(
        'structure.seasonHint.empty',
        fields: {
          'directory': childDirectoryName,
        },
      );
      return null;
    }

    if (_matchesAnySpecialEpisodeKeyword(
      [childDirectoryName],
      specialEpisodeKeywords: specialEpisodeKeywords,
    )) {
      webDavTrace(
        'structure.seasonHint.specialKeyword',
        fields: {
          'directory': childDirectoryName,
        },
      );
      return const _SeasonDirectoryHint(seasonNumber: 0);
    }

    final explicitSeasonNumber = _parseSeasonNumberFromDirectoryName(
      childDirectoryName,
    );
    if (explicitSeasonNumber != null) {
      webDavTrace(
        'structure.seasonHint.explicit',
        fields: {
          'directory': childDirectoryName,
          'season': explicitSeasonNumber,
        },
      );
      return _SeasonDirectoryHint(seasonNumber: explicitSeasonNumber);
    }

    if (_looksLikeNumericSeasonDirectory(
      childDirectoryName,
      siblingDirectoryNames: siblingDirectoryNames,
    )) {
      final seasonNumber = _parseLeadingNumericSeasonNumber(childDirectoryName);
      webDavTrace(
        'structure.seasonHint.numeric',
        fields: {
          'directory': childDirectoryName,
          'season': seasonNumber,
          'siblings': siblingDirectoryNames,
        },
      );
      return _SeasonDirectoryHint(
        seasonNumber: seasonNumber,
      );
    }

    final explicitSeasonNumbers = items
        .map(
          (item) =>
              item.metadataSeed.seasonNumber ??
              recognitionByResource[item.resourceId]?.seasonNumber,
        )
        .whereType<int>()
        .toSet();
    if (explicitSeasonNumbers.length == 1) {
      webDavTrace(
        'structure.seasonHint.fromItems',
        fields: {
          'directory': childDirectoryName,
          'season': explicitSeasonNumbers.first,
        },
      );
      return _SeasonDirectoryHint(seasonNumber: explicitSeasonNumbers.first);
    }

    webDavTrace(
      'structure.seasonHint.none',
      fields: {
        'directory': childDirectoryName,
        'itemCount': items.length,
      },
    );
    return null;
  }

  int? _parseSeasonNumberFromDirectoryName(String value) {
    return parseSeasonNumberFromFolderLabel(value);
  }

  int? _parseLeadingNumericSeasonNumber(String value) {
    return parseLeadingNumericSeasonNumber(value);
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

  bool _hasExplicitEpisodeCue(
    _PendingWebDavScannedItem item,
    NasMediaRecognition recognition,
  ) {
    return item.metadataSeed.seasonNumber != null ||
        item.metadataSeed.episodeNumber != null ||
        recognition.seasonNumber != null ||
        recognition.episodeNumber != null ||
        recognition.itemType.trim().toLowerCase() == 'episode';
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
    if (specialEpisodeKeywords.isEmpty) {
      return false;
    }
    final haystacks = <String>{};
    for (final rawValue in rawValues) {
      haystacks.addAll(_keywordMatchForms(rawValue));
    }
    if (haystacks.isEmpty) {
      return false;
    }
    for (final keyword in specialEpisodeKeywords) {
      for (final normalizedKeyword in _keywordMatchForms(keyword)) {
        if (normalizedKeyword.isEmpty) {
          continue;
        }
        if (haystacks.any((haystack) => haystack.contains(normalizedKeyword))) {
          return true;
        }
      }
    }
    return false;
  }

  Set<String> _keywordMatchForms(String rawValue) {
    final values = <String>{};
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return values;
    }
    final lowered = trimmed.toLowerCase();
    values.add(lowered);
    final stripped = stripEmbeddedExternalIdTags(trimmed).trim().toLowerCase();
    if (stripped.isNotEmpty) {
      values.add(stripped);
    }
    final compact = stripped.isNotEmpty ? stripped : lowered;
    values.add(
      compact.replaceAll(
        RegExp(r'[【】\[\]\(\)（）{}<>《》"“”‘’·_.\-\s+&/\\|,:;]+'),
        '',
      ),
    );
    return values..removeWhere((value) => value.isEmpty);
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
    required this.explicitEpisodeCountByDirectory,
    required this.specialEpisodeKeywords,
    required this.extraKeywords,
  });

  final Map<String, List<_PendingWebDavScannedItem>> filesByDirectory;
  final Map<String, Map<String, int>> childVideoCountsByDirectory;
  final Map<String, Map<String, List<_PendingWebDavScannedItem>>>
      childItemsByDirectory;
  final Map<String, NasMediaRecognition> recognitionByResource;
  final Map<String, int> explicitEpisodeCountByDirectory;
  final List<String> specialEpisodeKeywords;
  final List<String> extraKeywords;
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
