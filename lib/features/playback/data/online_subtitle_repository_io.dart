import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:starflow/core/network/starflow_http_client.dart';
import 'package:starflow/features/playback/data/online_subtitle_repository.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';

OnlineSubtitleRepository createOnlineSubtitleRepository(Ref ref) {
  return AssrtSubtitleRepository(ref.read(starflowHttpClientProvider));
}

class AssrtSubtitleRepository implements OnlineSubtitleRepository {
  AssrtSubtitleRepository(this._client);

  static const _searchMarker =
      '<div onmouseover="addclass(this,\'subitem_hover\')" onmouseout="redclass(this,\'subitem_hover\')" class="subitem"';

  final http.Client _client;
  Future<Directory>? _cacheDirectoryFuture;

  @override
  Future<List<SubtitleSearchResult>> search(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return const [];
    }

    final uri = Uri.https('assrt.net', '/sub/', {
      'searchword': normalizedQuery,
      'sort': 'rank',
    });
    final response = await _client.get(uri, headers: const {
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    });
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('字幕搜索失败：HTTP ${response.statusCode}');
    }

    return parseAssrtSearchHtml(response.body);
  }

  @override
  Future<SubtitleDownloadResult> download(SubtitleSearchResult result) async {
    final normalizedUrl = result.downloadUrl.trim();
    if (normalizedUrl.isEmpty) {
      throw StateError('字幕下载地址为空');
    }

    final baseDirectory = await _cacheDirectory();
    final bucketDirectory = Directory(
      p.join(baseDirectory.path, _stableHash(normalizedUrl)),
    );
    if (!await bucketDirectory.exists()) {
      await bucketDirectory.create(recursive: true);
    }

    final existingExtracted = await _findBestExistingSubtitleFile(
      bucketDirectory,
      packageName: result.packageName,
      version: result.version,
    );
    if (existingExtracted != null) {
      return SubtitleDownloadResult(
        cachedPath: bucketDirectory.path,
        displayName: p.basenameWithoutExtension(existingExtracted.path),
        subtitleFilePath: existingExtracted.path,
      );
    }

    final response = await _client.get(Uri.parse(normalizedUrl), headers: const {
      'Accept': '*/*',
      'Referer': 'https://assrt.net/',
    });
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('字幕下载失败：HTTP ${response.statusCode}');
    }

    final normalizedPackageName = _sanitizeFileName(
      result.packageName.trim().isEmpty ? 'subtitle.bin' : result.packageName,
    );
    final archivePath = p.join(bucketDirectory.path, normalizedPackageName);
    final archiveFile = File(archivePath);
    await archiveFile.writeAsBytes(response.bodyBytes, flush: true);

    switch (result.packageKind) {
      case SubtitlePackageKind.subtitleFile:
        return SubtitleDownloadResult(
          cachedPath: archiveFile.path,
          displayName: p.basenameWithoutExtension(archiveFile.path),
          subtitleFilePath: archiveFile.path,
        );
      case SubtitlePackageKind.zipArchive:
        final extracted = await _extractBestSubtitleFromZip(
          archiveFile: archiveFile,
          bucketDirectory: bucketDirectory,
          version: result.version,
          packageName: result.packageName,
        );
        return SubtitleDownloadResult(
          cachedPath: bucketDirectory.path,
          displayName: p.basenameWithoutExtension(extracted.path),
          subtitleFilePath: extracted.path,
        );
      case SubtitlePackageKind.rarArchive:
      case SubtitlePackageKind.unsupported:
        return SubtitleDownloadResult(
          cachedPath: archiveFile.path,
          displayName: p.basenameWithoutExtension(archiveFile.path),
        );
    }
  }

  @visibleForTesting
  static List<SubtitleSearchResult> parseAssrtSearchHtml(String html) {
    final normalized = html.trim();
    if (normalized.isEmpty || !normalized.contains(_searchMarker)) {
      return const [];
    }

    final segments = normalized.split(_searchMarker);
    final results = <SubtitleSearchResult>[];
    for (final rawSegment in segments.skip(1)) {
      final segment = rawSegment.trim();
      final titleMatch = RegExp(
        r'<a class="introtitle"[^>]*title="([^"]+)"[^>]*href="([^"]+)"',
        dotAll: true,
      ).firstMatch(segment);
      final downloadMatch = RegExp(
        r"location\.href='([^']+)'",
        dotAll: true,
      ).firstMatch(segment);
      if (titleMatch == null || downloadMatch == null) {
        continue;
      }

      final title = _decodeHtmlText(titleMatch.group(1) ?? '');
      final detailUrl = _absoluteAssrtUrl(titleMatch.group(2) ?? '');
      final downloadUrl = _absoluteAssrtUrl(downloadMatch.group(1) ?? '');
      final version = _extractAssrtField(segment, label: '版本');
      final formatLabel = _extractAssrtField(segment, label: '格式');
      final languageLabel = _extractAssrtField(segment, label: '语言');
      final sourceLabel = _extractAssrtField(segment, label: '来源');
      final publishDateLabel = _extractAssrtField(segment, label: '日期');
      final downloadCount = int.tryParse(
            RegExp(r'下载次数：\s*(\d+)').firstMatch(segment)?.group(1) ?? '',
          ) ??
          0;
      final ratingValue = RegExp(
        r'用户评分(\d+)分',
      ).firstMatch(segment)?.group(1);
      final ratingCount = int.tryParse(
            RegExp(r'\((\d+)人评分\)').firstMatch(segment)?.group(1) ?? '',
          ) ??
          0;
      final ratingLabel = ratingValue == null
          ? ''
          : '评分 ${ratingValue.trim()}${ratingCount > 0 ? ' · $ratingCount 人' : ''}';
      final packageName = _extractPackageName(downloadUrl);
      final packageKind = _resolvePackageKind(packageName);
      final id = RegExp(r'/download/(\d+)/').firstMatch(downloadUrl)?.group(1) ??
          _stableHash(downloadUrl);

      results.add(
        SubtitleSearchResult(
          id: id,
          providerLabel: 'ASSRT',
          title: title,
          version: version,
          formatLabel: formatLabel,
          languageLabel: languageLabel,
          sourceLabel: sourceLabel,
          publishDateLabel: publishDateLabel,
          downloadCount: downloadCount,
          ratingLabel: ratingLabel,
          downloadUrl: downloadUrl,
          detailUrl: detailUrl,
          packageName: packageName,
          packageKind: packageKind,
        ),
      );
    }

    results.sort((left, right) {
      final supportOrder =
          _packageKindSortValue(left.packageKind).compareTo(
        _packageKindSortValue(right.packageKind),
      );
      if (supportOrder != 0) {
        return supportOrder;
      }
      final ratingOrder = _ratingScore(right.ratingLabel)
          .compareTo(_ratingScore(left.ratingLabel));
      if (ratingOrder != 0) {
        return ratingOrder;
      }
      return right.downloadCount.compareTo(left.downloadCount);
    });
    return results;
  }

  static String _extractAssrtField(
    String segment, {
    required String label,
  }) {
    final match = RegExp(
      '$label：\\s*(.*?)</span>',
      dotAll: true,
    ).firstMatch(segment);
    if (match == null) {
      return '';
    }
    return _normalizeWhitespace(_decodeHtmlText(match.group(1) ?? ''));
  }

  static int _packageKindSortValue(SubtitlePackageKind kind) {
    return switch (kind) {
      SubtitlePackageKind.subtitleFile => 0,
      SubtitlePackageKind.zipArchive => 1,
      SubtitlePackageKind.rarArchive => 2,
      SubtitlePackageKind.unsupported => 3,
    };
  }

  static int _ratingScore(String label) {
    final match = RegExp(r'评分\s*(\d+)').firstMatch(label);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  Future<File?> _findBestExistingSubtitleFile(
    Directory bucketDirectory, {
    required String packageName,
    required String version,
  }) async {
    if (!await bucketDirectory.exists()) {
      return null;
    }
    final candidates = <File>[];
    await for (final entity in bucketDirectory.list()) {
      if (entity is! File) {
        continue;
      }
      if (!_isSubtitleFileName(entity.path)) {
        continue;
      }
      candidates.add(entity);
    }
    if (candidates.isEmpty) {
      return null;
    }
    candidates.sort(
      (left, right) => _subtitleCandidateScore(
        fileName: p.basename(right.path),
        packageName: packageName,
        version: version,
      ).compareTo(
        _subtitleCandidateScore(
          fileName: p.basename(left.path),
          packageName: packageName,
          version: version,
        ),
      ),
    );
    return candidates.first;
  }

  Future<File> _extractBestSubtitleFromZip({
    required File archiveFile,
    required Directory bucketDirectory,
    required String version,
    required String packageName,
  }) async {
    final archive = ZipDecoder().decodeBytes(
      await archiveFile.readAsBytes(),
      verify: true,
    );
    final subtitleEntries = archive.files
        .where(
          (file) => file.isFile && _isSubtitleFileName(file.name),
        )
        .toList(growable: false);
    if (subtitleEntries.isEmpty) {
      throw StateError('压缩包里没有可用字幕文件');
    }
    subtitleEntries.sort(
      (left, right) => _subtitleCandidateScore(
        fileName: right.name,
        packageName: packageName,
        version: version,
      ).compareTo(
        _subtitleCandidateScore(
          fileName: left.name,
          packageName: packageName,
          version: version,
        ),
      ),
    );

    final selected = subtitleEntries.first;
    final extension = p.extension(selected.name).trim();
    final outputFile = File(
      p.join(
        bucketDirectory.path,
        '${_sanitizeFileName(p.basenameWithoutExtension(packageName))}${extension.isEmpty ? '.srt' : extension}',
      ),
    );
    final content = selected.content;
    final bytes = content is List<int>
        ? content
        : utf8.encode('$content');
    await outputFile.writeAsBytes(bytes, flush: true);
    return outputFile;
  }

  Future<Directory> _cacheDirectory() {
    return _cacheDirectoryFuture ??= () async {
      final baseDirectory = await getApplicationSupportDirectory();
      final directory = Directory(
        p.join(baseDirectory.path, 'starflow-subtitle-cache'),
      );
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return directory;
    }();
  }
}

String _absoluteAssrtUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.hasScheme) {
    return trimmed;
  }
  return 'https://assrt.net$trimmed';
}

String _extractPackageName(String downloadUrl) {
  final uri = Uri.tryParse(downloadUrl);
  final segments = uri?.pathSegments ?? const <String>[];
  if (segments.isEmpty) {
    return 'subtitle.bin';
  }
  return Uri.decodeComponent(segments.last);
}

SubtitlePackageKind _resolvePackageKind(String packageName) {
  final extension = p.extension(packageName).toLowerCase();
  return switch (extension) {
    '.srt' || '.ass' || '.ssa' || '.vtt' => SubtitlePackageKind.subtitleFile,
    '.zip' => SubtitlePackageKind.zipArchive,
    '.rar' => SubtitlePackageKind.rarArchive,
    _ => SubtitlePackageKind.unsupported,
  };
}

bool _isSubtitleFileName(String fileName) {
  final extension = p.extension(fileName).toLowerCase();
  return extension == '.srt' ||
      extension == '.ass' ||
      extension == '.ssa' ||
      extension == '.vtt';
}

int _subtitleCandidateScore({
  required String fileName,
  required String packageName,
  required String version,
}) {
  final normalized = _normalizeCandidateText(fileName);
  final normalizedPackageName = _normalizeCandidateText(packageName);
  final normalizedVersion = _normalizeCandidateText(version);
  var score = 0;
  final extension = p.extension(fileName).toLowerCase();
  score += switch (extension) {
    '.ass' => 520,
    '.ssa' => 500,
    '.srt' => 480,
    '.vtt' => 420,
    _ => 0,
  };

  if (normalizedPackageName.isNotEmpty &&
      normalized.contains(normalizedPackageName)) {
    score += 180;
  }
  if (normalizedVersion.isNotEmpty && normalized.contains(normalizedVersion)) {
    score += 140;
  }

  const preferredTokens = <String>[
    '中英',
    '双语',
    '简中',
    '简体',
    '繁中',
    '繁体',
    'chs',
    'cht',
    'zh',
  ];
  for (final token in preferredTokens) {
    if (normalized.contains(_normalizeCandidateText(token))) {
      score += 40;
    }
  }

  const deprioritizedTokens = <String>[
    'commentary',
    'sdh',
    'signs',
    'forced',
  ];
  for (final token in deprioritizedTokens) {
    if (normalized.contains(token)) {
      score -= 25;
    }
  }

  score -= p.basename(fileName).length ~/ 18;
  return score;
}

String _normalizeCandidateText(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(
        RegExp(r'[\s\-_.,:;!?/\\|()\[\]{}<>《》【】"“”·]+'),
        '',
      );
}

String _sanitizeFileName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return 'subtitle';
  }
  return trimmed.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]+'), '_');
}

String _decodeHtmlText(String value) {
  return value
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&#x27;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}

String _normalizeWhitespace(String value) {
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _stableHash(String value) {
  var hash = 0xcbf29ce484222325;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
  }
  return hash.toRadixString(16);
}
