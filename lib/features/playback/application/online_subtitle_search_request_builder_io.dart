import 'dart:io';
import 'dart:typed_data';

import 'package:starflow/features/playback/application/subtitle_language_preferences.dart';
import 'package:starflow/features/playback/domain/online_subtitle_structured_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';

Future<OnlineSubtitleSearchRequest> buildOnlineSubtitleSearchRequestForTarget({
  required PlaybackTarget target,
  String query = '',
  String title = '',
  String originalTitle = '',
  String imdbId = '',
  String tmdbId = '',
  List<String> languages = const <String>[],
}) async {
  final resolvedFilePath = await _resolveReadableLocalFilePath([
    target.actualAddress,
    target.streamUrl,
  ]);
  final fileHash = resolvedFilePath.isEmpty
      ? ''
      : await _computeOpenSubtitlesHash(File(resolvedFilePath));
  final effectiveLanguages = resolveEffectiveSubtitleSearchLanguages(languages);
  return OnlineSubtitleSearchRequest.fromPlaybackTarget(
    target,
    query: query.trim().isNotEmpty
        ? query.trim()
        : buildSubtitleSearchQuery(target),
    originalTitle: originalTitle,
    imdbId: imdbId,
    tmdbId: tmdbId,
    filePath: resolvedFilePath,
    fileHash: fileHash,
    languages: effectiveLanguages,
    context: {
      if (title.trim().isNotEmpty) 'display_title': title.trim(),
    },
  );
}

Future<OnlineSubtitleSearchRequest> buildOnlineSubtitleSearchRequestForRoute(
  SubtitleSearchRequest request, {
  List<String> languages = const <String>[],
}) async {
  final resolvedFilePath =
      await _resolveReadableLocalFilePath([request.filePath]);
  final fileHash = resolvedFilePath.isEmpty
      ? ''
      : await _computeOpenSubtitlesHash(File(resolvedFilePath));
  final effectiveLanguages = resolveEffectiveSubtitleSearchLanguages(languages);
  return OnlineSubtitleSearchRequest(
    query: request.query,
    title: request.title,
    originalTitle: request.originalTitle,
    year: request.year,
    imdbId: request.imdbId,
    tmdbId: request.tmdbId,
    seasonNumber: request.seasonNumber,
    episodeNumber: request.episodeNumber,
    filePath: resolvedFilePath,
    fileHash: fileHash,
    languages: effectiveLanguages,
  );
}

Future<String> _resolveReadableLocalFilePath(
    Iterable<String> candidates) async {
  for (final candidate in candidates) {
    final resolved = _tryNormalizeLocalFilePath(candidate);
    if (resolved.isEmpty) {
      continue;
    }
    final file = File(resolved);
    if (await file.exists()) {
      return file.path;
    }
  }
  return '';
}

String _tryNormalizeLocalFilePath(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  if (_looksLikeWindowsAbsolutePath(trimmed) ||
      trimmed.startsWith('/') ||
      trimmed.startsWith(r'\\')) {
    return trimmed;
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null) {
    return '';
  }
  if (uri.scheme == 'file') {
    try {
      return uri.toFilePath(windows: Platform.isWindows);
    } catch (_) {
      return '';
    }
  }
  if (uri.hasScheme) {
    return '';
  }
  return trimmed;
}

bool _looksLikeWindowsAbsolutePath(String value) {
  return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value);
}

Future<String> _computeOpenSubtitlesHash(File file) async {
  RandomAccessFile? raf;
  try {
    raf = await file.open();
    final length = await raf.length();
    const chunkSize = 64 * 1024;
    if (length < chunkSize * 2) {
      return '';
    }
    var hash = length & 0xFFFFFFFFFFFFFFFF;
    final firstChunk = await raf.read(chunkSize);
    await raf.setPosition(length - chunkSize);
    final lastChunk = await raf.read(chunkSize);
    hash = _accumulateOpenSubtitlesHash(hash, firstChunk);
    hash = _accumulateOpenSubtitlesHash(hash, lastChunk);
    final normalized = hash & 0xFFFFFFFFFFFFFFFF;
    return normalized.toRadixString(16).padLeft(16, '0');
  } catch (_) {
    return '';
  } finally {
    await raf?.close();
  }
}

int _accumulateOpenSubtitlesHash(int seed, List<int> bytes) {
  var hash = seed & 0xFFFFFFFFFFFFFFFF;
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  for (var offset = 0; offset + 8 <= bytes.length; offset += 8) {
    final value = data.getUint64(offset, Endian.little);
    hash = (hash + value) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash;
}
