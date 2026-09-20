import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:starflow/core/network/bounded_http_request.dart';
import 'package:starflow/features/playback/application/subtitle_content_decoder.dart';
import 'package:starflow/features/playback/application/subtitle_language_preferences.dart';
import 'package:starflow/features/playback/domain/online_subtitle_structured_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/playback/domain/subtitle_operation.dart';

/// Shared on-demand download, validation and UTF-8 normalization path.
class SubtitleValidationPipeline {
  SubtitleValidationPipeline(
    this._client, {
    Future<Directory> Function()? cacheDirectoryProvider,
  }) : _cacheDirectoryProvider =
            cacheDirectoryProvider ?? _defaultCacheDirectory;

  final http.Client _client;
  final Future<Directory> Function() _cacheDirectoryProvider;

  Future<List<ValidatedSubtitleCandidate>> validateHits(
      Iterable<ProviderSubtitleHit> hits,
      {int maxValidated = 0,
      SubtitleOperation? operation}) async {
    final results = <ValidatedSubtitleCandidate>[];
    var validated = 0;
    try {
      operation?.throwIfCancelled();
      for (final hit in hits) {
        if (maxValidated > 0 && validated >= maxValidated) break;
        final result = await validateHit(hit, operation: operation);
        results.add(result);
        if (result.canApply) validated++;
      }
      operation?.throwIfCancelled();
      return results;
    } catch (_) {
      // No caller owns the earlier outputs if this batch cannot be returned.
      await Future.wait(results.where((result) => result.canApply).map(
          (result) => discardSubtitleDownload(result.cachedPath)));
      rethrow;
    }
  }

  Future<ValidatedSubtitleCandidate> validateHit(
    ProviderSubtitleHit hit, {
    List<String> preferredLanguages = const [],
    String referer = '',
    SubtitleOperation? operation,
  }) async {
    operation?.throwIfCancelled();
    if (hit.downloadUrl.trim().isEmpty ||
        hit.packageKind == SubtitlePackageKind.rarArchive ||
        hit.packageKind == SubtitlePackageKind.unsupported) {
      return ValidatedSubtitleCandidate(
          hit: hit,
          status: SubtitleValidationStatus.skipped,
          failureReason: '缺少下载地址或字幕包格式不受支持');
    }
    Directory? bucket;
    try {
      final bytes = await downloadSubtitleBytes(_client, hit.downloadUrl,
          referer: referer, operation: operation);
      operation?.throwIfCancelled();
      final languages =
          resolveEffectiveSubtitleSearchLanguages(preferredLanguages);
      final processed = await compute(
          _processSubtitle,
          _SubtitleInput(
            bytes,
            hit,
            languages,
            PlatformDispatcher.instance.locale.toLanguageTag(),
          ));
      operation?.throwIfCancelled();
      final root = await _cacheDirectoryProvider();
      operation?.throwIfCancelled();
      await root.create(recursive: true);
      operation?.throwIfCancelled();
      bucket = await root.createTemp('download-');
      operation?.throwIfCancelled();
      final output =
          File(p.join(bucket.path, 'subtitle.${processed.extension}'));
      await output.writeAsString(processed.text, encoding: utf8, flush: true);
      operation?.throwIfCancelled();
      return ValidatedSubtitleCandidate(
          hit: hit,
          status: SubtitleValidationStatus.validated,
          cachedPath: bucket.path,
          subtitleFilePath: output.path,
          displayName: p.basenameWithoutExtension(processed.name),
          detectedFiles: [output.path]);
    } catch (error) {
      if (bucket != null) await discardSubtitleDownload(bucket.path);
      operation?.throwIfCancelled();
      return ValidatedSubtitleCandidate(
          hit: hit,
          status: SubtitleValidationStatus.failed,
          failureReason: '$error');
    }
  }
}

Future<Uint8List> downloadSubtitleBytes(
  http.Client client,
  String url, {
  String referer = '',
  SubtitleOperation? operation,
}) async {
  operation?.throwIfCancelled();
  final uri = Uri.parse(url);
  if (!['https', 'http'].contains(uri.scheme) || uri.host.isEmpty) {
    throw const SubtitleContentException('字幕下载地址无效');
  }
  late final http.Response response;
  try {
    response = await sendBoundedRequest(client, 'GET', uri,
        cancel: operation?.whenCancelled,
        timeout: const Duration(seconds: 30),
        maxBytes: maxSubtitleBytes,
        headers: {
          'Accept': '*/*',
          'User-Agent': 'Mozilla/5.0',
          if (referer.isNotEmpty) 'Referer': referer,
        });
  } on http.ClientException catch (error) {
    operation?.throwIfCancelled();
    if (error.message == 'Response exceeds byte limit') {
      throw const SubtitleContentException('字幕下载超过 16 MiB 限制');
    }
    rethrow;
  }
  operation?.throwIfCancelled();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw StateError('字幕下载失败：HTTP ${response.statusCode}');
  }
  return response.bodyBytes;
}

Future<void> discardSubtitleDownload(String path) async {
  final directory = Directory(path);
  try {
    if (await directory.exists()) await directory.delete(recursive: true);
  } on FileSystemException {
    // A concurrent cache clear may already have removed the bucket.
    if (await directory.exists()) rethrow;
  }
}

class _SubtitleInput {
  const _SubtitleInput(this.bytes, this.hit, this.languages, this.locale);
  final Uint8List bytes;
  final ProviderSubtitleHit hit;
  final List<String> languages;
  final String locale;
}

class _ProcessedSubtitle {
  const _ProcessedSubtitle(this.text, this.extension, this.name);
  final String text;
  final String extension;
  final String name;
}

_ProcessedSubtitle _processSubtitle(_SubtitleInput input) {
  final bytes = input.bytes;
  if (isSubtitleZipBytes(bytes)) {
    final archive = decodeBoundedSubtitleArchive(bytes);
    final candidates = archive.files
        .where((entry) =>
            entry.isFile &&
            !isExplicitSubtitleEpisodeMismatch(entry.name,
                seasonNumber: input.hit.seasonNumber,
                episodeNumber: input.hit.episodeNumber) &&
            ['.srt', '.ass', '.ssa', '.vtt']
                .contains(p.extension(entry.name).toLowerCase()))
        .toList();
    final localeParts = input.locale.split('-');
    final locale = Locale(
        localeParts.first, localeParts.length > 1 ? localeParts.last : null);
    int score(String name) =>
        scoreSubtitleEpisodeMatch(name,
            seasonNumber: input.hit.seasonNumber,
            episodeNumber: input.hit.episodeNumber) +
        scorePreferredSubtitleText(name,
            configuredLanguages: input.languages, systemLocale: locale);
    candidates.sort((a, b) {
      final ranked = score(b.name).compareTo(score(a.name));
      return ranked != 0 ? ranked : a.name.compareTo(b.name);
    });
    for (final candidate in candidates) {
      final content = readBoundedSubtitleEntry(candidate);
      try {
        final text = decodeSubtitleBytes(content);
        return _ProcessedSubtitle(
            text, detectSubtitleFormat(text), candidate.name);
      } on SubtitleContentException {
        continue;
      }
    }
    throw const SubtitleContentException('压缩包内没有有效文本字幕');
  }
  if (isExplicitSubtitleEpisodeMismatch(input.hit.packageName,
      seasonNumber: input.hit.seasonNumber,
      episodeNumber: input.hit.episodeNumber)) {
    throw const SubtitleContentException('字幕文件与目标季集不匹配');
  }
  final text = decodeSubtitleBytes(bytes);
  return _ProcessedSubtitle(
      text, detectSubtitleFormat(text), input.hit.packageName);
}

Future<Directory> _defaultCacheDirectory() async => Directory(p.join(
    (await getTemporaryDirectory()).path, 'starflow', 'online_subtitles'));
