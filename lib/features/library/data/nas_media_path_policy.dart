import 'package:starflow/features/library/data/season_folder_label_parser.dart';
import 'package:starflow/features/library/domain/media_naming.dart';
import 'package:starflow/features/library/domain/nas_media_recognition.dart';

class NasMediaPathContext {
  const NasMediaPathContext({
    required this.sectionSegments,
    required this.resourceSegments,
    required this.relativeDirectories,
  });

  final List<String> sectionSegments;
  final List<String> resourceSegments;
  final List<String> relativeDirectories;
}

class NasSeriesRootResolution {
  const NasSeriesRootResolution({
    required this.title,
    required this.rootSegments,
    required this.pathContext,
    required this.hasPublicBoundary,
  });

  final String title;
  final List<String> rootSegments;
  final NasMediaPathContext pathContext;
  final bool hasPublicBoundary;

  static NasSeriesRootResolution empty(NasMediaPathContext context) {
    return NasSeriesRootResolution(
      title: '',
      rootSegments: const [],
      pathContext: context,
      hasPublicBoundary: false,
    );
  }
}

class NasMediaPathPolicy {
  const NasMediaPathPolicy._();

  static const Set<String> defaultPublicDirectoryLabels = <String>{
    'dav',
    'media',
    'movies',
    'movie',
    'nas',
    'quark',
    'strm',
    'tv',
    'video',
    'videos',
    'webdav',
  };

  static NasMediaPathContext resolvePathContext({
    required String resourcePath,
    required String sectionId,
  }) {
    final resourceSegments = pathSegments(uriPath(resourcePath));
    final sectionSegments = pathSegments(uriPath(sectionId));
    var commonLength = 0;
    while (commonLength < sectionSegments.length &&
        commonLength < resourceSegments.length &&
        sectionSegments[commonLength] == resourceSegments[commonLength]) {
      commonLength += 1;
    }
    final relativeDirectories = resourceSegments.length <= commonLength + 1
        ? const <String>[]
        : resourceSegments.sublist(
            commonLength,
            resourceSegments.length - 1,
          );
    return NasMediaPathContext(
      sectionSegments: sectionSegments,
      resourceSegments: resourceSegments,
      relativeDirectories: relativeDirectories,
    );
  }

  static String uriPath(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.path.isNotEmpty) {
      return uri.path;
    }
    return trimmed;
  }

  static List<String> pathSegments(String value) {
    return value
        .split('/')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .map((segment) {
      try {
        return Uri.decodeComponent(segment);
      } catch (_) {
        return segment;
      }
    }).toList(growable: false);
  }

  static String cleanTitleLabel(String value) {
    return stripEmbeddedExternalIdTags(value)
        .replaceAll(RegExp(r'[_\.]+'), ' ')
        .replaceAll(RegExp(r'[【\[\(].*?[】\]\)]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String cleanDirectoryTitle(String value) {
    return stripEmbeddedExternalIdTags(value)
        .replaceAll(RegExp(r'[_\.]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String normalizePathToken(String value) {
    return value.trim().toLowerCase().replaceAll(
          RegExp(r'[\s\-_.·:：/\\|()（）\[\]【】{}《》]+'),
          '',
        );
  }

  static bool matchesConfiguredBoundary(
    String rawValue, {
    required List<String> configuredKeywords,
  }) {
    if (configuredKeywords.isEmpty) {
      return false;
    }
    final cleanedValue = cleanTitleLabel(rawValue);
    final haystacks = <String>{
      rawValue.trim().toLowerCase(),
      cleanedValue.trim().toLowerCase(),
    }..removeWhere((value) => value.isEmpty);
    return configuredKeywords.any(
      (keyword) => haystacks.any((value) => value.contains(keyword)),
    );
  }

  static bool isPublicDirectory(
    String value, {
    List<String> configuredKeywords = const [],
  }) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return true;
    }
    final cleaned = cleanTitleLabel(trimmed);
    return matchesConfiguredBoundary(
          trimmed,
          configuredKeywords: configuredKeywords,
        ) ||
        NasMediaRecognizer.isGenericLibraryFolderLabel(cleaned) ||
        defaultPublicDirectoryLabels.contains(cleaned.toLowerCase());
  }

  static String? firstLibraryDirectoryTitle({
    required String resourcePath,
    required String sectionId,
    List<String> configuredKeywords = const [],
  }) {
    final context = resolvePathContext(
      resourcePath: resourcePath,
      sectionId: sectionId,
    );
    for (final directory in context.relativeDirectories) {
      if (isPublicDirectory(
        directory,
        configuredKeywords: configuredKeywords,
      )) {
        continue;
      }
      final title = cleanDirectoryTitle(directory);
      if (title.isNotEmpty) {
        return title;
      }
    }
    return null;
  }

  static NasSeriesRootResolution resolveSeriesRoot({
    required String resourcePath,
    required String sectionId,
    required String fileFallbackTitle,
    required bool seriesLike,
    List<String> configuredKeywords = const [],
  }) {
    final context = resolvePathContext(
      resourcePath: resourcePath,
      sectionId: sectionId,
    );
    if (!seriesLike || context.resourceSegments.isEmpty) {
      return NasSeriesRootResolution.empty(context);
    }

    final directories = context.relativeDirectories;
    final sectionRoot = context.sectionSegments.isEmpty
        ? ''
        : context.sectionSegments.last.trim();
    final sectionIsPublic = sectionRoot.isNotEmpty &&
        isPublicDirectory(
          sectionRoot,
          configuredKeywords: configuredKeywords,
        );
    if (directories.isEmpty) {
      final fallback = sectionIsPublic
          ? cleanTitleLabel(fileFallbackTitle)
          : cleanTitleLabel(sectionRoot);
      return NasSeriesRootResolution(
        title: fallback,
        rootSegments:
            fallback.isEmpty || sectionIsPublic ? const [] : [sectionRoot],
        pathContext: context,
        hasPublicBoundary: sectionIsPublic,
      );
    }

    var lastBoundaryIndex = -1;
    for (var index = 0; index < directories.length; index++) {
      if (isPublicDirectory(
        directories[index],
        configuredKeywords: configuredKeywords,
      )) {
        lastBoundaryIndex = index;
      }
    }
    final firstCandidateIndex = lastBoundaryIndex + 1;
    for (var index = firstCandidateIndex; index < directories.length; index++) {
      final rawDirectory = directories[index].trim();
      if (rawDirectory.isEmpty ||
          isPublicDirectory(
            rawDirectory,
            configuredKeywords: configuredKeywords,
          )) {
        continue;
      }
      final directChildOfBoundary = index == firstCandidateIndex &&
          (lastBoundaryIndex >= 0 || sectionIsPublic);
      final seriesParent = index > 0 ? directories[index - 1] : sectionRoot;
      if (_shouldSkipSeriesRootDirectory(
        rawDirectory,
        directChildOfBoundary: directChildOfBoundary,
        seriesParent: seriesParent,
      )) {
        continue;
      }
      final title = cleanTitleLabel(rawDirectory);
      if (title.isEmpty) {
        continue;
      }
      return NasSeriesRootResolution(
        title: title,
        rootSegments: [rawDirectory],
        pathContext: context,
        hasPublicBoundary: lastBoundaryIndex >= 0 || sectionIsPublic,
      );
    }

    final hitRelativeBoundary = lastBoundaryIndex >= 0;
    final fallback = hitRelativeBoundary || sectionIsPublic
        ? cleanTitleLabel(fileFallbackTitle)
        : cleanTitleLabel(sectionRoot);
    return NasSeriesRootResolution(
      title: fallback,
      rootSegments: fallback.isEmpty || hitRelativeBoundary || sectionIsPublic
          ? const []
          : [sectionRoot],
      pathContext: context,
      hasPublicBoundary: hitRelativeBoundary || sectionIsPublic,
    );
  }

  static bool _shouldSkipSeriesRootDirectory(
    String rawDirectory, {
    required bool directChildOfBoundary,
    required String seriesParent,
  }) {
    if (NasMediaRecognizer.matchesHashNumberedEpisodeFolder(
      rawDirectory,
      seriesParent: seriesParent,
    )) {
      return true;
    }
    if (!directChildOfBoundary &&
        seriesParent.trim().isNotEmpty &&
        looksLikeYearGroupingFolderLabel(rawDirectory)) {
      return true;
    }
    if (looksLikeSeasonFolderLabel(rawDirectory)) {
      final canUseCompositeSeasonAsRoot = directChildOfBoundary &&
          !looksLikeStrictSeasonFolderLabel(rawDirectory);
      if (!canUseCompositeSeasonAsRoot) {
        return true;
      }
    }
    return NasMediaRecognizer.matchesWrapperFolderLabel(rawDirectory);
  }

  static bool looksLikeNestedMovieReleaseFolder({
    required String parentTitle,
    required String childDirectoryName,
  }) {
    if (parentTitle.trim().isEmpty ||
        NasMediaRecognizer.isGenericLibraryFolderLabel(parentTitle) ||
        looksLikeSeasonFolderLabel(childDirectoryName)) {
      return false;
    }
    final normalizedParent = normalizePathToken(parentTitle);
    final normalizedChild = normalizePathToken(childDirectoryName);
    if (normalizedParent.isEmpty ||
        normalizedChild == normalizedParent ||
        !normalizedChild.startsWith(normalizedParent)) {
      return false;
    }
    final suffix = normalizedChild.substring(normalizedParent.length);
    final yearMatch = RegExp(r'^(?:19\d{2}|20\d{2})').firstMatch(suffix);
    final remainder =
        yearMatch == null ? suffix : suffix.substring(yearMatch.end);
    return remainder.isEmpty ||
        NasMediaRecognizer.matchesMovieVersionFolderLabel(remainder) ||
        _containsMovieReleaseDescriptor(remainder);
  }

  static bool _containsMovieReleaseDescriptor(String value) {
    const descriptorKeywords = <String>[
      '国语',
      '粤语',
      '英语',
      '日语',
      '韩语',
      '中字',
      '字幕',
      '双语',
      '简繁',
      '外挂',
      '内封',
      '蓝光',
      '原盘',
      '高码',
      'hdr',
      '4k',
      '2160p',
      '1080p',
      'web',
    ];
    return descriptorKeywords.any(value.contains);
  }
}
