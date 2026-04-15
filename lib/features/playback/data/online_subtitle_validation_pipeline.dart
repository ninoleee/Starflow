import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:starflow/core/utils/subtitle_search_trace.dart';
import 'package:starflow/features/playback/application/subtitle_language_preferences.dart';
import 'package:starflow/features/playback/domain/online_subtitle_structured_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';

class SubtitleValidationPipeline {
  static const _defaultValidationConcurrency = 4;

  SubtitleValidationPipeline(
    this._client, {
    Future<Directory> Function()? cacheDirectoryProvider,
  }) : _cacheDirectoryProvider =
            cacheDirectoryProvider ?? _defaultValidationCacheDirectory;

  final http.Client _client;
  final Future<Directory> Function() _cacheDirectoryProvider;

  Future<List<ValidatedSubtitleCandidate>> validateHits(
    Iterable<ProviderSubtitleHit> hits, {
    int maxValidated = 0,
  }) async {
    final hitList = hits.toList(growable: false);
    final workerCount = _resolveValidationWorkerCount(
      hitCount: hitList.length,
      maxValidated: maxValidated,
    );
    subtitleSearchTrace(
      'repository.structured.validation.batch-start',
      fields: {
        'totalHits': hitList.length,
        'maxValidated': maxValidated,
        'workers': workerCount,
        'sources': hitList.map((item) => item.source.name).toSet().join('/'),
      },
    );
    if (hitList.isEmpty) {
      subtitleSearchTrace(
        'repository.structured.validation.batch-finished',
        fields: {
          'processed': 0,
          'validated': 0,
          'failed': 0,
          'skipped': 0,
        },
      );
      return const [];
    }
    final indexedResults = <_IndexedValidatedSubtitleCandidate>[];
    var validatedCount = 0;
    var nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        if (maxValidated > 0 && validatedCount >= maxValidated) {
          return;
        }
        if (nextIndex >= hitList.length) {
          return;
        }
        final currentIndex = nextIndex;
        nextIndex += 1;
        final validated = await validateHit(hitList[currentIndex]);
        indexedResults.add(
          _IndexedValidatedSubtitleCandidate(
            index: currentIndex,
            candidate: validated,
          ),
        );
        if (validated.status == SubtitleValidationStatus.validated) {
          validatedCount += 1;
        }
      }
    }

    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );
    indexedResults.sort((left, right) => left.index.compareTo(right.index));
    final results =
        indexedResults.map((item) => item.candidate).toList(growable: false);
    final effectiveResults = maxValidated > 0
        ? _truncateAfterValidated(results, maxValidated: maxValidated)
        : results;
    subtitleSearchTrace(
      'repository.structured.validation.batch-finished',
      fields: {
        'processed': effectiveResults.length,
        'validated': effectiveResults
            .where((item) => item.status == SubtitleValidationStatus.validated)
            .length,
        'failed': effectiveResults
            .where((item) => item.status == SubtitleValidationStatus.failed)
            .length,
        'skipped': effectiveResults
            .where((item) => item.status == SubtitleValidationStatus.skipped)
            .length,
      },
    );
    return effectiveResults;
  }

  int _resolveValidationWorkerCount({
    required int hitCount,
    required int maxValidated,
  }) {
    if (hitCount <= 1) {
      return hitCount;
    }
    final target = maxValidated > 0
        ? maxValidated.clamp(1, _defaultValidationConcurrency)
        : _defaultValidationConcurrency;
    return hitCount.clamp(1, target);
  }

  List<ValidatedSubtitleCandidate> _truncateAfterValidated(
    List<ValidatedSubtitleCandidate> results, {
    required int maxValidated,
  }) {
    if (maxValidated <= 0) {
      return results;
    }
    final truncated = <ValidatedSubtitleCandidate>[];
    var validatedCount = 0;
    for (final result in results) {
      truncated.add(result);
      if (result.status == SubtitleValidationStatus.validated) {
        validatedCount += 1;
        if (validatedCount >= maxValidated) {
          break;
        }
      }
    }
    return truncated;
  }

  Future<ValidatedSubtitleCandidate> validateHit(
      ProviderSubtitleHit hit) async {
    subtitleSearchTrace(
      'repository.structured.validation.hit-start',
      fields: {
        'source': hit.source.name,
        'id': hit.id,
        'title': hit.title,
        'packageKind': hit.packageKind.name,
        'downloadUrl': hit.downloadUrl,
      },
    );
    if (!hit.canDownload) {
      final result = ValidatedSubtitleCandidate(
        hit: hit,
        status: SubtitleValidationStatus.skipped,
        failureReason: '字幕源未提供可直下地址',
      );
      _traceValidationOutcome(hit, result);
      return result;
    }

    if (hit.packageKind == SubtitlePackageKind.rarArchive ||
        hit.packageKind == SubtitlePackageKind.unsupported) {
      final result = ValidatedSubtitleCandidate(
        hit: hit,
        status: SubtitleValidationStatus.skipped,
        failureReason: '暂不支持该字幕包类型',
      );
      _traceValidationOutcome(hit, result);
      return result;
    }

    try {
      final cacheDirectory = await _cacheDirectory();
      final bucket =
          Directory(p.join(cacheDirectory.path, _operationBucketKey(hit)));
      if (!await bucket.exists()) {
        await bucket.create(recursive: true);
      }

      final response = await _client.get(
        Uri.parse(hit.downloadUrl),
        headers: const {'Accept': '*/*', 'User-Agent': 'Mozilla/5.0'},
      );
      subtitleSearchTrace(
        'repository.structured.validation.http-response',
        fields: {
          'source': hit.source.name,
          'id': hit.id,
          'status': response.statusCode,
          'bytes': response.bodyBytes.length,
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final result = ValidatedSubtitleCandidate(
          hit: hit,
          status: SubtitleValidationStatus.failed,
          failureReason: 'HTTP ${response.statusCode}',
        );
        _traceValidationOutcome(hit, result);
        return result;
      }

      final packagePath =
          p.join(bucket.path, _sanitizeFileName(hit.packageName));
      final packageFile = File(packagePath);
      await packageFile.writeAsBytes(response.bodyBytes, flush: true);
      subtitleSearchTrace(
        'repository.structured.validation.package-cached',
        fields: {
          'source': hit.source.name,
          'id': hit.id,
          'packagePath': packagePath,
          'packageKind': hit.packageKind.name,
        },
      );

      switch (hit.packageKind) {
        case SubtitlePackageKind.subtitleFile:
          final result = ValidatedSubtitleCandidate(
            hit: hit,
            status: SubtitleValidationStatus.validated,
            cachedPath: packageFile.path,
            subtitleFilePath: packageFile.path,
            displayName: p.basenameWithoutExtension(packageFile.path),
            detectedFiles: [packageFile.path],
          );
          _traceValidationOutcome(hit, result);
          return result;
        case SubtitlePackageKind.zipArchive:
          final extracted = await _extractBestSubtitleFromZip(
            packageFile,
            bucket,
            version: hit.version,
            packageName: hit.packageName,
            seasonNumber: hit.seasonNumber,
            episodeNumber: hit.episodeNumber,
          );
          if (extracted == null) {
            final result = ValidatedSubtitleCandidate(
              hit: hit,
              status: SubtitleValidationStatus.failed,
              cachedPath: bucket.path,
              failureReason: 'ZIP 内未找到受支持字幕文件',
            );
            _traceValidationOutcome(hit, result);
            return result;
          }
          final result = ValidatedSubtitleCandidate(
            hit: hit,
            status: SubtitleValidationStatus.validated,
            cachedPath: bucket.path,
            subtitleFilePath: extracted.path,
            displayName: p.basenameWithoutExtension(extracted.path),
            detectedFiles: [extracted.path],
          );
          subtitleSearchTrace(
            'repository.structured.validation.zip-extracted',
            fields: {
              'source': hit.source.name,
              'id': hit.id,
              'subtitleFilePath': extracted.path,
            },
          );
          _traceValidationOutcome(hit, result);
          return result;
        case SubtitlePackageKind.rarArchive:
        case SubtitlePackageKind.unsupported:
          final result = ValidatedSubtitleCandidate(
            hit: hit,
            status: SubtitleValidationStatus.skipped,
            cachedPath: packageFile.path,
            failureReason: '暂不支持该字幕包类型',
          );
          _traceValidationOutcome(hit, result);
          return result;
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
      final result = ValidatedSubtitleCandidate(
        hit: hit,
        status: SubtitleValidationStatus.failed,
        failureReason: '$error',
      );
      _traceValidationOutcome(hit, result);
      return result;
    }
  }

  Future<Directory> _cacheDirectory() {
    return _cacheDirectoryProvider();
  }
}

class _IndexedValidatedSubtitleCandidate {
  const _IndexedValidatedSubtitleCandidate({
    required this.index,
    required this.candidate,
  });

  final int index;
  final ValidatedSubtitleCandidate candidate;
}

Future<Directory> _defaultValidationCacheDirectory() async {
  final root = await getTemporaryDirectory();
  final directory = Directory(
    p.join(root.path, 'starflow', 'validated_online_subtitles'),
  );
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
  return directory;
}

void _traceValidationOutcome(
  ProviderSubtitleHit hit,
  ValidatedSubtitleCandidate result,
) {
  subtitleSearchTrace(
    'repository.structured.validation.hit-finished',
    fields: {
      'source': hit.source.name,
      'id': hit.id,
      'status': result.status.name,
      'canApply': result.canApply,
      'failureReason': result.failureReason,
      'subtitleFilePath': result.subtitleFilePath ?? '',
    },
  );
}

Future<File?> _extractBestSubtitleFromZip(
  File archiveFile,
  Directory bucket, {
  required String version,
  required String packageName,
  int? seasonNumber,
  int? episodeNumber,
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
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    ).compareTo(
      _subtitleCandidateScore(
        fileName: left.name,
        packageName: packageName,
        version: version,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
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
  int? seasonNumber,
  int? episodeNumber,
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
  score += scoreSubtitleEpisodeMatch(
    fileName,
    seasonNumber: seasonNumber,
    episodeNumber: episodeNumber,
  );
  score += scorePreferredSubtitleText(fileName);
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

String _operationBucketKey(ProviderSubtitleHit hit) {
  final fingerprint = [
    hit.source.name,
    hit.id.trim(),
    hit.downloadUrl.trim(),
    hit.packageName.trim(),
    hit.version.trim(),
    '${hit.seasonNumber ?? ''}',
    '${hit.episodeNumber ?? ''}',
  ].join('|');
  return '${DateTime.now().microsecondsSinceEpoch}-${_stableHash(fingerprint)}';
}
