part of 'webdav_nas_client.dart';

extension _WebDavNasClientStructure on WebDavNasClient {
  List<_PendingWebDavScannedItem> _applyDirectoryStructureInference(
    List<_PendingWebDavScannedItem> items,
  ) {
    if (items.isEmpty) {
      return items;
    }
    webDavTrace(
      'structure.start',
      fields: {
        'itemCount': items.length,
      },
    );

    final filesByDirectory = <String, List<_PendingWebDavScannedItem>>{};
    final childVideoCountsByDirectory = <String, Map<String, int>>{};
    final childItemsByDirectory =
        <String, Map<String, List<_PendingWebDavScannedItem>>>{};
    final recognitionByResource = <String, NasMediaRecognition>{};
    final explicitEpisodeCountByDirectory = <String, int>{};
    for (final item in items) {
      final directoryKey = _segmentsKey(item.relativeDirectories);
      filesByDirectory.putIfAbsent(directoryKey, () => []).add(item);
      final recognition = NasMediaRecognizer.recognize(item.actualAddress);
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

    final seriesRootPlans = <String, _SeriesRootInferencePlan>{};
    final candidateDirectoryKeys = <String>{
      ...filesByDirectory.keys,
      ...childVideoCountsByDirectory.keys,
    };
    for (final directoryKey in candidateDirectoryKeys) {
      final plan = _buildSeriesRootPlan(
        directoryKey: directoryKey,
        filesByDirectory: filesByDirectory,
        childItemsByDirectory: childItemsByDirectory,
        recognitionByResource: recognitionByResource,
        explicitEpisodeCountByDirectory: explicitEpisodeCountByDirectory,
      );
      if (plan != null) {
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
    }

    final seriesRootForResource = <String, String>{};
    for (final item in items) {
      for (var length = 0;
          length <= item.relativeDirectories.length;
          length++) {
        final candidateKey =
            _segmentsKey(item.relativeDirectories.take(length));
        if (seriesRootPlans.containsKey(candidateKey)) {
          seriesRootForResource[item.resourceId] = candidateKey;
          break;
        }
      }
    }

    final nextItems = <_PendingWebDavScannedItem>[];
    final episodeItemsByGroup = <String, List<_PendingWebDavScannedItem>>{};
    final seasonOrderByRoot = <String, List<String>>{};

    for (final item in items) {
      final seriesRootKey = seriesRootForResource[item.resourceId];
      final seed = item.metadataSeed;
      final recognition = recognitionByResource[item.resourceId];
      final explicitSeasonNumber =
          seed.seasonNumber ?? recognition?.seasonNumber;
      final explicitEpisodeNumber =
          seed.episodeNumber ?? recognition?.episodeNumber;
      if (seriesRootKey != null) {
        final plan = seriesRootPlans[seriesRootKey]!;
        final rootDepth = _segmentsFromKey(seriesRootKey).length;
        final isRootDirectFile = item.relativeDirectories.length == rootDepth;
        final childDirectoryName =
            isRootDirectFile ? '' : item.relativeDirectories[rootDepth];
        final derivedSeasonNumber = isRootDirectFile
            ? plan.rootItemsAsSpecials
                ? 0
                : 1
            : plan.seasonNumberByChildDirectory[childDirectoryName];
        final seasonGroupKey = explicitSeasonNumber != null
            ? _buildExplicitSeasonGroupKey(explicitSeasonNumber)
            : isRootDirectFile
                ? (plan.rootItemsAsSpecials
                    ? _directSeasonGroupKey
                    : _implicitSeasonGroupKey)
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
          seasonNumber: explicitSeasonNumber ?? derivedSeasonNumber,
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
          },
        );
        episodeItemsByGroup
            .putIfAbsent('$seriesRootKey::$seasonGroupKey', () => [])
            .add(nextItem);
        nextItems.add(nextItem);
        continue;
      }

      final parentDirectoryKey = _segmentsKey(item.relativeDirectories);
      final directVideoCount =
          filesByDirectory[parentDirectoryKey]?.length ?? 0;
      final childDirectoryCount =
          childVideoCountsByDirectory[parentDirectoryKey]?.length ?? 0;
      if (seed.itemType.trim().isEmpty &&
          directVideoCount == 1 &&
          childDirectoryCount == 0) {
        final resolvedItemType =
            explicitEpisodeNumber != null || explicitSeasonNumber != null
                ? 'episode'
                : 'movie';
        webDavTrace(
          'structure.singleFileFallback',
          fields: {
            'path': item.actualAddress,
            'resolvedItemType': resolvedItemType,
            'season': explicitSeasonNumber,
            'episode': explicitEpisodeNumber,
          },
        );
        nextItems.add(
          item.copyWith(
            metadataSeed: seed.copyWith(
              itemType: resolvedItemType,
              seasonNumber: explicitSeasonNumber,
              episodeNumber: explicitEpisodeNumber,
            ),
          ),
        );
      } else {
        nextItems.add(item);
      }
    }

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

    final episodeOverrides = <String, WebDavMetadataSeed>{};
    for (final entry in episodeItemsByGroup.entries) {
      final seasonNumber = seasonNumberByGroup[entry.key];
      final orderedEpisodes = [...entry.value]..sort(
          (left, right) => left.actualAddress.toLowerCase().compareTo(
                right.actualAddress.toLowerCase(),
              ),
        );
      for (var index = 0; index < orderedEpisodes.length; index++) {
        final item = orderedEpisodes[index];
        final recognition = recognitionByResource[item.resourceId];
        final explicitSeasonNumber =
            item.metadataSeed.seasonNumber ?? recognition?.seasonNumber;
        final explicitEpisodeNumber =
            item.metadataSeed.episodeNumber ?? recognition?.episodeNumber;
        final specialGroupSuffix = '::$_directSeasonGroupKey';
        final implicitGroupSuffix = '::$_implicitSeasonGroupKey';
        final isDirectSeasonGroup = entry.key.endsWith(specialGroupSuffix);
        final isImplicitSeasonGroup = entry.key.endsWith(implicitGroupSuffix);
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

    final resolvedItems = nextItems
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
      },
    );
    return resolvedItems;
  }

  _SeriesRootInferencePlan? _buildSeriesRootPlan({
    required String directoryKey,
    required Map<String, List<_PendingWebDavScannedItem>> filesByDirectory,
    required Map<String, Map<String, List<_PendingWebDavScannedItem>>>
        childItemsByDirectory,
    required Map<String, NasMediaRecognition> recognitionByResource,
    required Map<String, int> explicitEpisodeCountByDirectory,
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
      );
      if (hint != null) {
        seasonHintsByChildDirectory[entry.key] = hint;
      }
    }

    final hasImplicitRootEpisodes = childGroups.isEmpty &&
        directItems.length >= 2 &&
        (directExplicitEpisodeCount >= 2 ||
            _looksLikeImplicitRootEpisodeBatch(directItems));
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

    final validSeasonHints =
        seasonHintsByChildDirectory.values.toList(growable: false);
    final hasSeasonDirectories = validSeasonHints.length >= 2 ||
        (validSeasonHints.length == 1 &&
            (directItems.isNotEmpty ||
                childGroups.length == 1 ||
                childGroups.values.first.length >= 2));
    if (!hasSeasonDirectories) {
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
        for (final entry in seasonHintsByChildDirectory.entries)
          entry.key: entry.value.seasonNumber,
      },
    );
  }

  _SeasonDirectoryHint? _resolveSeasonDirectoryHint({
    required String childDirectoryName,
    required List<_PendingWebDavScannedItem> items,
    required List<String> siblingDirectoryNames,
    required Map<String, NasMediaRecognition> recognitionByResource,
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
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return null;
    }
    for (final pattern in const [
      r'(?:^|[ ._\-])s(\d{1,2})(?:$|[ ._\-])',
      r'season[ ._\-]?(\d{1,2})',
      r'第(\d{1,2})季',
    ]) {
      final match =
          RegExp(pattern, caseSensitive: false).firstMatch(normalized);
      final seasonNumber = int.tryParse(match?.group(1) ?? '');
      if (seasonNumber != null && seasonNumber > 0) {
        return seasonNumber;
      }
    }
    return null;
  }

  int? _parseLeadingNumericSeasonNumber(String value) {
    final match = RegExp(r'^\s*(\d{1,2})(?:[ ._\-]|$)').firstMatch(value);
    final seasonNumber = int.tryParse(match?.group(1) ?? '');
    if (seasonNumber == null || seasonNumber <= 0) {
      return null;
    }
    return seasonNumber;
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

  bool _looksLikeImplicitRootEpisodeBatch(
    List<_PendingWebDavScannedItem> items,
  ) {
    if (items.length < 2) {
      return false;
    }
    final numberedItems = items
        .where(
          (item) => _parseBareEpisodeNumberFromPath(item.actualAddress) != null,
        )
        .length;
    return numberedItems == items.length;
  }

  int? _parseBareEpisodeNumberFromPath(String actualAddress) {
    final rawName = actualAddress.split('/').last.trim();
    if (rawName.isEmpty) {
      return null;
    }
    final fileName = _decodePathSegment(rawName);
    var baseName = fileName.replaceFirst(RegExp(r'\.[^.]+$'), '');
    baseName = baseName.replaceFirst(
      RegExp(r'\.\((mp4|mkv|avi|mov|ts|m2ts|strm)\)$', caseSensitive: false),
      '',
    );
    final match = RegExp(
      r'^\s*(?:ep(?:isode)?\s*)?0*(\d{1,3})(.*)$',
      caseSensitive: false,
    ).firstMatch(baseName);
    if (match == null) {
      return null;
    }
    final episodeNumber = int.tryParse(match.group(1) ?? '');
    if (episodeNumber == null || episodeNumber <= 0) {
      return null;
    }
    final remainder = (match.group(2) ?? '')
        .replaceAll(
          RegExp(
            r'\b(?:4k|8k|2160p|1080p|720p|480p|hdr|dv|uhd|sd|hd|hevc|h265|h264|x265|x264|aac|ddp|dd|atmos|remux|webdl|web-dl|webrip|bluray|bdrip|proper|repack|mp4|mkv|avi|mov|ts|m2ts)\b',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'[\s._\-\[\]\(\)]+'), '');
    return remainder.isEmpty ? episodeNumber : null;
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
