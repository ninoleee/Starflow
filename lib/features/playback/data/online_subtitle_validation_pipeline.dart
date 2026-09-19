import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:starflow/features/playback/application/subtitle_content_decoder.dart';
import 'package:starflow/features/playback/application/subtitle_language_preferences.dart';
import 'package:starflow/features/playback/domain/online_subtitle_structured_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';

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
      {int maxValidated = 0}) async {
    final results = <ValidatedSubtitleCandidate>[];
    var validated = 0;
    for (final hit in hits) {
      if (maxValidated > 0 && validated >= maxValidated) break;
      final result = await validateHit(hit);
      results.add(result);
      if (result.canApply) validated++;
    }
    return results;
  }

  Future<ValidatedSubtitleCandidate> validateHit(
    ProviderSubtitleHit hit, {
    List<String> preferredLanguages = const [],
    String referer = '',
  }) async {
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
          referer: referer);
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
      final root = await _cacheDirectoryProvider();
      await root.create(recursive: true);
      bucket = await root.createTemp('download-');
      final output =
          File(p.join(bucket.path, 'subtitle.${processed.extension}'));
      await output.writeAsString(processed.text, encoding: utf8, flush: true);
      return ValidatedSubtitleCandidate(
          hit: hit,
          status: SubtitleValidationStatus.validated,
          cachedPath: bucket.path,
          subtitleFilePath: output.path,
          displayName: p.basenameWithoutExtension(processed.name),
          detectedFiles: [output.path]);
    } catch (error) {
      if (bucket != null && await bucket.exists()) {
        await bucket.delete(recursive: true);
      }
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
}) async {
  final uri = Uri.parse(url);
  if (!['https', 'http'].contains(uri.scheme) || uri.host.isEmpty) {
    throw const SubtitleContentException('字幕下载地址无效');
  }
  final deadline = Stopwatch()..start();
  const timeout = Duration(seconds: 30);
  final response = await client
      .send(http.Request('GET', uri)
        ..headers.addAll({
          'Accept': '*/*',
          'User-Agent': 'Mozilla/5.0',
          if (referer.isNotEmpty) 'Referer': referer,
        }))
      .timeout(timeout);
  final iterator = StreamIterator(response.stream);
  try {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('字幕下载失败：HTTP ${response.statusCode}');
    }
    if ((response.contentLength ?? 0) > maxSubtitleBytes) {
      throw const SubtitleContentException('字幕下载超过 16 MiB 限制');
    }
    final bytes = BytesBuilder(copy: false);
    while (true) {
      final remaining = timeout - deadline.elapsed;
      if (remaining <= Duration.zero) throw TimeoutException('字幕下载超时');
      if (!await iterator.moveNext().timeout(remaining)) break;
      if (bytes.length + iterator.current.length > maxSubtitleBytes) {
        throw const SubtitleContentException('字幕下载超过 16 MiB 限制');
      }
      bytes.add(iterator.current);
    }
    return bytes.takeBytes();
  } finally {
    await iterator.cancel();
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
  final text = decodeSubtitleBytes(bytes);
  return _ProcessedSubtitle(
      text, detectSubtitleFormat(text), input.hit.packageName);
}

Future<Directory> _defaultCacheDirectory() async => Directory(p.join(
    (await getTemporaryDirectory()).path, 'starflow', 'online_subtitles'));
