const String kCloudUnsafeUrlNameCharacters = '#%?';

String normalizeCloudDirectoryPath(String raw) {
  final path = raw.trim().replaceAll('\\', '/');
  if (path.isEmpty || path == '/') return '/';
  final absolute = path.startsWith('/') ? path : '/$path';
  final normalized = absolute.replaceFirst(RegExp(r'/+$'), '');
  return normalized.isEmpty ? '/' : normalized;
}

String sanitizeCloudDirectoryName(String raw) {
  final name = raw
      .replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return name == '.' || name == '..' ? '' : name;
}

String sanitizeCloudNameForUrl(String raw,
    {String characters = kCloudUnsafeUrlNameCharacters}) {
  final unsafe = characters.runes
      .map(String.fromCharCode)
      .where((character) => character.trim().isNotEmpty)
      .toSet();
  if (unsafe.isEmpty) return raw;
  final name = raw.runes
      .map(String.fromCharCode)
      .where((character) => !unsafe.contains(character))
      .join()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return name == '.' || name == '..' ? '' : name;
}

String sanitizeCloudSavedEntryName(String raw,
    {required bool isDirectory, required String characters}) {
  final dot = raw.lastIndexOf('.');
  if (isDirectory || dot <= 0 || dot == raw.length - 1) {
    return sanitizeCloudNameForUrl(raw, characters: characters);
  }
  final stem =
      sanitizeCloudNameForUrl(raw.substring(0, dot), characters: characters);
  return stem.isEmpty ? '' : '$stem${raw.substring(dot)}';
}

String cloudSaveNameKey(String raw,
    {String characters = '', bool? isDirectory}) {
  final sanitized = characters.trim().isEmpty
      ? raw
      : isDirectory == null
          ? sanitizeCloudNameForUrl(raw, characters: characters)
          : sanitizeCloudSavedEntryName(raw,
              isDirectory: isDirectory, characters: characters);
  // A name that cannot be cleaned is left unchanged by the rename stage.
  return (sanitized.isEmpty ? raw : sanitized).trim().toLowerCase();
}

String cloudChildPath(String parent, String name) =>
    '${normalizeCloudDirectoryPath(parent) == '/' ? '' : normalizeCloudDirectoryPath(parent)}/$name';

bool cloudSaveNeedsChild(String parentPath, String name) =>
    name.isNotEmpty &&
    cloudSaveNameKey(sanitizeCloudDirectoryName(
            normalizeCloudDirectoryPath(parentPath).split('/').last)) !=
        cloudSaveNameKey(name);

String resolveCloudSaveFolderPath(String parentPath, String saveFolderName) {
  final name = sanitizeCloudDirectoryName(saveFolderName);
  return cloudSaveNeedsChild(parentPath, name)
      ? cloudChildPath(parentPath, name)
      : normalizeCloudDirectoryPath(parentPath);
}

abstract interface class CloudSaveEntry {
  String get fid;
  String get name;
  bool get isDirectory;
}

const Set<String> cloudVideoExtensions = {
  'mp4',
  'm4v',
  'mov',
  'mkv',
  'avi',
  'ts',
  'webm',
  'flv',
  'wmv',
  'mpg',
  'mpeg',
  'm2ts',
  'iso',
  'strm',
};

class CloudSavePreviewEntry {
  const CloudSavePreviewEntry({
    required this.name,
    required this.relativePath,
    required this.isDirectory,
  });
  final String name;
  final String relativePath;
  final bool isDirectory;
  bool get isVideo =>
      !isDirectory &&
      name.lastIndexOf('.') > 0 &&
      cloudVideoExtensions.contains(name.split('.').last.trim().toLowerCase());

  String comparisonKey(String characters) {
    final segments = relativePath.split('/');
    return [
      for (var index = 0; index < segments.length; index++)
        cloudSaveNameKey(segments[index],
            characters: characters,
            isDirectory: index < segments.length - 1 || isDirectory),
    ].join('/');
  }
}

class CloudSavePreview {
  const CloudSavePreview({
    required this.targetFolderPath,
    required this.localFolderExists,
    required this.onlineEntries,
    required this.localEntries,
    this.sanitizedNameCharacters = '',
    this.deduplicate = true,
  });
  final String targetFolderPath;
  final bool localFolderExists;
  final List<CloudSavePreviewEntry> onlineEntries;
  final List<CloudSavePreviewEntry> localEntries;
  final String sanitizedNameCharacters;
  final bool deduplicate;

  List<CloudSavePreviewEntry> get missingVideos {
    if (!deduplicate) {
      return onlineEntries
          .where((entry) => entry.isVideo)
          .toList(growable: false);
    }
    final localKeys = localEntries
        .where((entry) => !entry.isDirectory)
        .map((entry) => entry.comparisonKey(sanitizedNameCharacters))
        .toSet();
    return onlineEntries
        .where((entry) =>
            entry.isVideo &&
            !localKeys.contains(entry.comparisonKey(sanitizedNameCharacters)))
        .toList(growable: false);
  }
}

class CloudSaveException implements Exception {
  const CloudSaveException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CloudSavedEntry {
  const CloudSavedEntry({
    required this.parentFid,
    required this.name,
    this.isDirectory,
    this.previousFids = const {},
    this.expectedChildren,
  });

  final String parentFid;
  final String name;
  final bool? isDirectory;
  final Set<String> previousFids;
  final List<CloudCopyEntry>? expectedChildren;
}

class CloudCopyEntry {
  const CloudCopyEntry(
      {required this.name,
      required this.isDirectory,
      this.children = const []});
  final String name;
  final bool isDirectory;
  final List<CloudCopyEntry> children;
}

class CloudNameSanitizeResult {
  const CloudNameSanitizeResult({
    this.renamedCount = 0,
    this.listedDirectoryCount = 0,
    this.failedNames = const [],
  });
  final int renamedCount;
  final int listedDirectoryCount;
  final List<String> failedNames;
  bool get changedAnything => renamedCount > 0;
  bool get completed => failedNames.isEmpty;
}
