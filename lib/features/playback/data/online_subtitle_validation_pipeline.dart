import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:starflow/core/utils/subtitle_search_trace.dart';
import 'package:starflow/features/playback/domain/online_subtitle_structured_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';

class SubtitleValidationPipeline {
  SubtitleValidationPipeline(this._client);

  final http.Client _client;
  Future<Directory>? _cacheDirectoryFuture;

  Future<List<ValidatedSubtitleCandidate>> validateHits(
    Iterable<ProviderSubtitleHit> hits, {
    int maxValidated = 0,
  }) async {
    final results = <ValidatedSubtitleCandidate>[];
    for (final hit in hits) {
      final validated = await validateHit(hit);
      if (validated.status == SubtitleValidationStatus.validated) {
        results.add(validated);
        if (maxValidated > 0 && results.length >= maxValidated) {
          break;
        }
      }
    }
    return results;
  }

  Future<ValidatedSubtitleCandidate> validateHit(ProviderSubtitleHit hit) async {
    if (!hit.canDownload) {
      return ValidatedSubtitleCandidate(
        hit: hit,
        status: SubtitleValidationStatus.skipped,
        failureReason: '字幕源未提供可直下地址',
      );
    }

    if (hit.packageKind == SubtitlePackageKind.rarArchive ||
        hit.packageKind == SubtitlePackageKind.unsupported) {
      return ValidatedSubtitleCandidate(
        hit: hit,
        status: SubtitleValidationStatus.skipped,
        failureReason: '暂不支持该字幕包类型',
      );
    }

    try {
      final cacheDirectory = await _cacheDirectory();
      final bucket = Directory(p.join(cacheDirectory.path, _stableHash(hit.id)));
      if (!await bucket.exists()) {
        await bucket.create(recursive: true);
      }

      final existing = await _findExistingSubtitle(bucket);
      if (existing != null) {
        return ValidatedSubtitleCandidate(
          hit: hit,
          status: SubtitleValidationStatus.validated,
          cachedPath: bucket.path,
          subtitleFilePath: existing.path,
          displayName: p.basenameWithoutExtension(existing.path),
          detectedFiles: [existing.path],
        );
      }

      final response = await _client.get(
        Uri.parse(hit.downloadUrl),
        headers: const {'Accept': '*/*', 'User-Agent': 'Mozilla/5.0'},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ValidatedSubtitleCandidate(
          hit: hit,
          status: SubtitleValidationStatus.failed,
          failureReason: 'HTTP ${response.statusCode}',
        );
      }

      final packagePath = p.join(bucket.path, _sanitizeFileName(hit.packageName));
      final packageFile = File(packagePath);
      await packageFile.writeAsBytes(response.bodyBytes, flush: true);

      switch (hit.packageKind) {
        case SubtitlePackageKind.subtitleFile:
          return ValidatedSubtitleCandidate(
            hit: hit,
            status: SubtitleValidationStatus.validated,
            cachedPath: packageFile.path,
            subtitleFilePath: packageFile.path,
            displayName: p.basenameWithoutExtension(packageFile.path),
            detectedFiles: [packageFile.path],
          );
        case SubtitlePackageKind.zipArchive:
          final extracted = await _extractBestSubtitleFromZip(
            packageFile,
            bucket,
            version: hit.version,
            packageName: hit.packageName,
          );
          if (extracted == null) {
            return ValidatedSubtitleCandidate(
              hit: hit,
              status: SubtitleValidationStatus.failed,
              cachedPath: bucket.path,
              failureReason: 'ZIP 内未找到受支持字幕文件',
            );
          }
          return ValidatedSubtitleCandidate(
            hit: hit,
            status: SubtitleValidationStatus.validated,
            cachedPath: bucket.path,
            subtitleFilePath: extracted.path,
            displayName: p.basenameWithoutExtension(extracted.path),
            detectedFiles: [extracted.path],
          );
        case SubtitlePackageKind.rarArchive:
        case SubtitlePackageKind.unsupported:
          return ValidatedSubtitleCandidate(
            hit: hit,
            status: SubtitleValidationStatus.skipped,
            cachedPath: packageFile.path,
            failureReason: '暂不支持该字幕包类型',
          );
      }
    } catch (error, stackTrace) {
      subtitleSearchTrace(
        'repository.structured.validation.failed',
        fields: {
          'source': hit.source.name,
          'id': hit.id,
        },
        error: error,
        stackTrace: stackTrace,
      );
      return ValidatedSubtitleCandidate(
        hit: hit,
        status: SubtitleValidationStatus.failed,
        failureReason: '$error',
      );
    }
  }

  Future<Directory> _cacheDirectory() {
    return _cacheDirectoryFuture ??= () async {
      final root = await getTemporaryDirectory();
      final directory = Directory(
        p.join(root.path, 'starflow', 'validated_online_subtitles'),
      );
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return directory;
    }();
  }
}

Future<File?> _findExistingSubtitle(Directory bucket) async {
  if (!await bucket.exists()) {
    return null;
  }
  final entities = await bucket.list().toList();
  final files = entities.whereType<File>().where((file) {
    final extension = p.extension(file.path).toLowerCase();
    return extension == '.srt' ||
        extension == '.ass' ||
        extension == '.ssa' ||
        extension == '.vtt';
  }).toList(growable: false);
  if (files.isEmpty) {
    return null;
  }
  files.sort((left, right) => left.path.length.compareTo(right.path.length));
  return files.first;
}

Future<File?> _extractBestSubtitleFromZip(
  File archiveFile,
  Directory bucket, {
  required String version,
  required String packageName,
}) async {
  final archive = ZipDecoder().decodeBytes(await archiveFile.readAsBytes());
  final candidates = archive.files.where((entry) {
    if (!entry.isFile) {
      return false;
    }
    final extension = p.extension(entry.name).toLowerCase();
    return extension == '.srt' ||
        extension == '.ass' ||
        extension == '.ssa' ||
        extension == '.vtt';
  }).toList(growable: false);
  if (candidates.isEmpty) {
    return null;
  }

  candidates.sort((left, right) {
    return _subtitleCandidateScore(
      fileName: right.name,
      packageName: packageName,
      version: version,
    ).compareTo(
      _subtitleCandidateScore(
        fileName: left.name,
        packageName: packageName,
        version: version,
      ),
    );
  });

  final best = candidates.first;
  final output = File(
    p.join(bucket.path, _sanitizeFileName(p.basename(best.name))),
  );
  final content = best.content as List<int>;
  await output.writeAsBytes(content, flush: true);
  return output;
}

int _subtitleCandidateScore({
  required String fileName,
  required String packageName,
  required String version,
}) {
  final normalized = _normalizeToken(fileName);
  final normalizedPackageName = _normalizeToken(packageName);
  final normalizedVersion = _normalizeToken(version);
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
  for (final token in const ['中英', '双语', '简中', '繁中', 'chs', 'cht']) {
    if (normalized.contains(_normalizeToken(token))) {
      score += 32;
    }
  }
  return score - p.basename(fileName).length ~/ 18;
}

String _normalizeToken(String value) {
  return value.trim().toLowerCase().replaceAll(
        RegExp(r'[\s\-_.,:;!?/\\|()\[\]{}<>《》【】"“”·]+'),
        '',
      );
}

String _sanitizeFileName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return 'subtitle.bin';
  }
  return trimmed.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]+'), '_');
}

String _stableHash(String value) {
  var hash = 0xcbf29ce484222325;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
  }
  return hash.toRadixString(16);
}
