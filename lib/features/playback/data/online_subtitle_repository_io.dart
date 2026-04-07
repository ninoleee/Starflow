import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:starflow/core/network/starflow_http_client.dart';
import 'package:starflow/core/utils/subtitle_search_trace.dart';
import 'package:starflow/features/playback/data/online_subtitle_repository.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';

OnlineSubtitleRepository createOnlineSubtitleRepository(Ref ref) {
  return AssrtSubtitleRepository(ref.read(starflowHttpClientProvider));
}

class AssrtSubtitleRepository implements OnlineSubtitleRepository {
  AssrtSubtitleRepository(this._client);

  static const _assrtSearchMarker =
      '<div onmouseover="addclass(this,\'subitem_hover\')" onmouseout="redclass(this,\'subitem_hover\')" class="subitem"';
  static const _subhdSearchMarker =
      '<div class="bg-white shadow-sm rounded-3 mb-4">';

  final http.Client _client;
  Future<Directory>? _cacheDirectoryFuture;

  @override
  Future<List<SubtitleSearchResult>> search(
    String query, {
    List<OnlineSubtitleSource> sources = const [OnlineSubtitleSource.assrt],
    int maxResults = 0,
  }) async {
    final normalizedQuery = query.trim();
    subtitleSearchTrace(
      'repository.search.start',
      fields: {
        'query': normalizedQuery,
        'sources': sources.map((item) => item.name).join('/'),
        'maxResults': maxResults,
      },
    );
    if (normalizedQuery.isEmpty) {
      subtitleSearchTrace('repository.search.skip-empty-query');
      return const [];
    }

    final enabledSources = sources.toSet();
    if (enabledSources.isEmpty) {
      subtitleSearchTrace('repository.search.skip-empty-sources');
      return const [];
    }

    final results = <SubtitleSearchResult>[];
    final errors = <String>[];

    if (enabledSources.contains(OnlineSubtitleSource.assrt)) {
      try {
        final assrtResults = await _searchSourceWithFallback(
          normalizedQuery,
          source: OnlineSubtitleSource.assrt,
          searcher: _searchAssrt,
        );
        results.addAll(assrtResults);
        subtitleSearchTrace(
          'repository.search.source-finished',
          fields: {
            'source': OnlineSubtitleSource.assrt.name,
            'count': assrtResults.length,
            'downloadable': assrtResults.where((item) => item.canDownload).length,
            'autoLoadable':
                assrtResults.where((item) => item.canAutoLoad).length,
            'sample': _sampleResultTitles(assrtResults),
          },
        );
      } catch (error, stackTrace) {
        errors.add('ASSRT: $error');
        subtitleSearchTrace(
          'repository.search.source-failed',
          fields: {
            'source': OnlineSubtitleSource.assrt.name,
            'query': normalizedQuery,
          },
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    if (enabledSources.contains(OnlineSubtitleSource.subhd)) {
      try {
        final subhdResults = await _searchSourceWithFallback(
          normalizedQuery,
          source: OnlineSubtitleSource.subhd,
          searcher: _searchSubhd,
        );
        results.addAll(subhdResults);
        subtitleSearchTrace(
          'repository.search.source-finished',
          fields: {
            'source': OnlineSubtitleSource.subhd.name,
            'count': subhdResults.length,
            'downloadable': subhdResults.where((item) => item.canDownload).length,
            'autoLoadable':
                subhdResults.where((item) => item.canAutoLoad).length,
            'sample': _sampleResultTitles(subhdResults),
          },
        );
      } catch (error, stackTrace) {
        errors.add('SubHD: $error');
        subtitleSearchTrace(
          'repository.search.source-failed',
          fields: {
            'source': OnlineSubtitleSource.subhd.name,
            'query': normalizedQuery,
          },
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    if (enabledSources.contains(OnlineSubtitleSource.yify)) {
      try {
        final yifyResults = await _searchSourceWithFallback(
          normalizedQuery,
          source: OnlineSubtitleSource.yify,
          searcher: _searchYify,
        );
        results.addAll(yifyResults);
        subtitleSearchTrace(
          'repository.search.source-finished',
          fields: {
            'source': OnlineSubtitleSource.yify.name,
            'count': yifyResults.length,
            'downloadable': yifyResults.where((item) => item.canDownload).length,
            'autoLoadable':
                yifyResults.where((item) => item.canAutoLoad).length,
            'sample': _sampleResultTitles(yifyResults),
          },
        );
      } catch (error, stackTrace) {
        errors.add('YIFY: $error');
        subtitleSearchTrace(
          'repository.search.source-failed',
          fields: {
            'source': OnlineSubtitleSource.yify.name,
            'query': normalizedQuery,
          },
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    if (results.isEmpty && errors.isNotEmpty) {
      subtitleSearchTrace(
        'repository.search.failed',
        fields: {
          'query': normalizedQuery,
          'errors': errors.join('；'),
        },
      );
      throw StateError(errors.join('；'));
    }

    results.sort(_compareSearchResults);
    final limitedResults = maxResults > 0 && results.length > maxResults
        ? results.take(maxResults).toList(growable: false)
        : results;
    subtitleSearchTrace(
      'repository.search.finished',
      fields: {
        'query': normalizedQuery,
        'total': results.length,
        'returned': limitedResults.length,
        'downloadable': limitedResults.where((item) => item.canDownload).length,
        'autoLoadable':
            limitedResults.where((item) => item.canAutoLoad).length,
        'sample': _sampleResultTitles(limitedResults),
      },
    );
    return limitedResults;
  }

  Future<List<SubtitleSearchResult>> _searchSourceWithFallback(
    String query, {
    required OnlineSubtitleSource source,
    required Future<List<SubtitleSearchResult>> Function(String query) searcher,
  }) async {
    final variants = buildSubtitleSearchQueryVariants(query);
    if (variants.isEmpty) {
      return const [];
    }

    Object? lastError;
    StackTrace? lastStackTrace;
    List<SubtitleSearchResult> lastResults = const [];

    for (var index = 0; index < variants.length; index++) {
      final variant = variants[index];
      final isFallback = index > 0;
      if (isFallback) {
        subtitleSearchTrace(
          'repository.search.fallback-query',
          fields: {
            'source': source.name,
            'originalQuery': query,
            'fallbackQuery': variant,
            'attempt': index + 1,
          },
        );
      }

      try {
        final variantResults = await searcher(variant);
        lastResults = variantResults;
        if (variantResults.isNotEmpty || index == variants.length - 1) {
          if (isFallback) {
            subtitleSearchTrace(
              'repository.search.fallback-result',
              fields: {
                'source': source.name,
                'fallbackQuery': variant,
                'count': variantResults.length,
                'sample': _sampleResultTitles(variantResults),
              },
            );
          }
          return variantResults;
        }
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        if (index == variants.length - 1) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        subtitleSearchTrace(
          isFallback
              ? 'repository.search.fallback-query-failed'
              : 'repository.search.primary-query-failed',
          fields: {
            'source': source.name,
            'query': variant,
            'originalQuery': query,
          },
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    if (lastError != null && lastStackTrace != null) {
      Error.throwWithStackTrace(lastError, lastStackTrace);
    }
    return lastResults;
  }

  Future<List<SubtitleSearchResult>> _searchAssrt(String query) async {
    final uri = Uri.https('assrt.net', '/sub/', {
      'searchword': query,
      'sort': 'rank',
    });
    subtitleSearchTrace(
      'repository.assrt.request',
      fields: {
        'query': query,
        'uri': uri,
      },
    );
    final response = await _client.get(uri, headers: const {
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    });
    final body = _readResponseBody(response);
    subtitleSearchTrace(
      'repository.assrt.response',
      fields: {
        'status': response.statusCode,
        'bytes': response.bodyBytes.length,
        'marker': body.contains(_assrtSearchMarker),
        'snippet': _responseSnippet(body),
      },
    );
    if (isAssrtErrorResponse(response.statusCode, body)) {
      subtitleSearchTrace(
        'repository.assrt.error-page',
        fields: {
          'query': query,
          'status': response.statusCode,
          'snippet': _responseSnippet(body),
        },
      );
      throw StateError('ASSRT 当前返回错误页，暂时无法搜索字幕，请改用其他字幕源重试');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('字幕搜索失败：HTTP ${response.statusCode}');
    }
    final results = parseAssrtSearchHtml(body);
    subtitleSearchTrace(
      'repository.assrt.parsed',
      fields: {
        'query': query,
        'count': results.length,
        'sample': _sampleResultTitles(results),
      },
    );
    return results;
  }

  Future<List<SubtitleSearchResult>> _searchSubhd(String query) async {
    final uri = Uri.parse(
      'https://subhd.tv/search/${Uri.encodeComponent(query)}',
    );
    subtitleSearchTrace(
      'repository.subhd.request',
      fields: {
        'query': query,
        'uri': uri,
      },
    );
    final response = await _client.get(uri, headers: const {
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'User-Agent': 'Mozilla/5.0',
    });
    final body = _readResponseBody(response);
    subtitleSearchTrace(
      'repository.subhd.response',
      fields: {
        'status': response.statusCode,
        'bytes': response.bodyBytes.length,
        'marker': body.contains(_subhdSearchMarker),
        'snippet': _responseSnippet(body),
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('字幕搜索失败：HTTP ${response.statusCode}');
    }
    final results = parseSubhdSearchHtml(body);
    subtitleSearchTrace(
      'repository.subhd.parsed',
      fields: {
        'query': query,
        'count': results.length,
        'downloadable': results.where((item) => item.canDownload).length,
        'autoLoadable': results.where((item) => item.canAutoLoad).length,
        'sample': _sampleResultTitles(results),
      },
    );
    return results;
  }

  Future<List<SubtitleSearchResult>> _searchYify(String query) async {
    if (_looksLikeEpisodeQuery(query)) {
      subtitleSearchTrace(
        'repository.yify.skip-episode-query',
        fields: {'query': query},
      );
      return const [];
    }

    final ajaxUri = Uri.https('www.yifysubtitles.ch', '/ajax/search/', {
      'mov': query,
    });
    subtitleSearchTrace(
      'repository.yify.ajax-request',
      fields: {
        'query': query,
        'uri': ajaxUri,
      },
    );
    final ajaxResponse = await _client.get(ajaxUri, headers: const {
      'Accept': 'application/json, text/plain, */*',
      'User-Agent': 'Mozilla/5.0',
      'X-Requested-With': 'XMLHttpRequest',
    });
    final ajaxBody = _readResponseBody(ajaxResponse);
    subtitleSearchTrace(
      'repository.yify.ajax-response',
      fields: {
        'status': ajaxResponse.statusCode,
        'bytes': ajaxResponse.bodyBytes.length,
        'snippet': _responseSnippet(ajaxBody),
      },
    );
    if (ajaxResponse.statusCode < 200 || ajaxResponse.statusCode >= 300) {
      throw StateError('字幕搜索失败：HTTP ${ajaxResponse.statusCode}');
    }

    final decoded = jsonDecode(ajaxBody);
    if (decoded is! List) {
      subtitleSearchTrace(
        'repository.yify.ajax-invalid-payload',
        fields: {
          'query': query,
          'runtimeType': decoded.runtimeType,
        },
      );
      return const [];
    }

    final candidates = decoded
        .whereType<Map>()
        .map(
          (item) => _YifyMovieCandidate(
            title: (item['movie'] as String? ?? '').trim(),
            imdbId: (item['imdb'] as String? ?? '').trim(),
          ),
        )
        .where(
          (item) => item.title.isNotEmpty && item.imdbId.trim().isNotEmpty,
        )
        .toList(growable: false);
    if (candidates.isEmpty) {
      subtitleSearchTrace(
        'repository.yify.no-candidates',
        fields: {'query': query},
      );
      return const [];
    }
    subtitleSearchTrace(
      'repository.yify.candidates',
      fields: {
        'query': query,
        'count': candidates.length,
        'sample': candidates.take(3).map((item) => item.title).join(' | '),
      },
    );

    final sortedCandidates = candidates.toList()
      ..sort(
        (left, right) => _scoreYifyCandidate(right, query).compareTo(
          _scoreYifyCandidate(left, query),
        ),
      );

    final results = <SubtitleSearchResult>[];
    for (final candidate in sortedCandidates.take(3)) {
      try {
        final detailUri = Uri.https(
          'www.yifysubtitles.ch',
          '/movie-imdb/${candidate.imdbId}',
        );
        subtitleSearchTrace(
          'repository.yify.detail-request',
          fields: {
            'query': query,
            'imdbId': candidate.imdbId,
            'title': candidate.title,
            'uri': detailUri,
          },
        );
        final detailResponse = await _client.get(detailUri, headers: const {
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'User-Agent': 'Mozilla/5.0',
        });
        if (detailResponse.statusCode < 200 ||
            detailResponse.statusCode >= 300) {
          subtitleSearchTrace(
            'repository.yify.detail-non-200',
            fields: {
              'imdbId': candidate.imdbId,
              'status': detailResponse.statusCode,
            },
          );
          continue;
        }
        final detailBody = _readResponseBody(detailResponse);
        final parsed = parseYifyMoviePageHtml(
          detailBody,
          imdbId: candidate.imdbId,
        ).take(12).toList(growable: false);
        subtitleSearchTrace(
          'repository.yify.detail-parsed',
          fields: {
            'imdbId': candidate.imdbId,
            'count': parsed.length,
            'sample': _sampleResultTitles(parsed),
          },
        );
        results.addAll(
          parsed,
        );
      } catch (error, stackTrace) {
        subtitleSearchTrace(
          'repository.yify.detail-failed',
          fields: {
            'query': query,
            'imdbId': candidate.imdbId,
            'title': candidate.title,
          },
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    results.sort(_compareSearchResults);
    subtitleSearchTrace(
      'repository.yify.finished',
      fields: {
        'query': query,
        'count': results.length,
        'sample': _sampleResultTitles(results),
      },
    );
    return results;
  }

  @override
  Future<SubtitleDownloadResult> download(SubtitleSearchResult result) {
    switch (result.source) {
      case OnlineSubtitleSource.assrt:
        return _downloadAndCacheResult(
          result,
          referer: 'https://assrt.net/',
        );
      case OnlineSubtitleSource.subhd:
        throw StateError('SubHD 当前暂不支持应用内直接下载字幕。');
      case OnlineSubtitleSource.yify:
        return _downloadAndCacheResult(
          result,
          referer: result.detailUrl.trim().isEmpty
              ? 'https://www.yifysubtitles.ch/'
              : result.detailUrl.trim(),
        );
    }
  }

  Future<SubtitleDownloadResult> _downloadAndCacheResult(
    SubtitleSearchResult result, {
    required String referer,
  }) async {
    final normalizedUrl = result.downloadUrl.trim();
    subtitleSearchTrace(
      'repository.download.start',
      fields: {
        'id': result.id,
        'source': result.source.name,
        'packageKind': result.packageKind.name,
        'downloadUrl': normalizedUrl,
      },
    );
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
      subtitleSearchTrace(
        'repository.download.cache-hit',
        fields: {
          'id': result.id,
          'path': existingExtracted.path,
        },
      );
      return SubtitleDownloadResult(
        cachedPath: bucketDirectory.path,
        displayName: p.basenameWithoutExtension(existingExtracted.path),
        subtitleFilePath: existingExtracted.path,
      );
    }

    final response = await _client.get(
      Uri.parse(normalizedUrl),
      headers: {
        'Accept': '*/*',
        if (referer.trim().isNotEmpty) 'Referer': referer.trim(),
        'User-Agent': 'Mozilla/5.0',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('字幕下载失败：HTTP ${response.statusCode}');
    }
    subtitleSearchTrace(
      'repository.download.response',
      fields: {
        'id': result.id,
        'status': response.statusCode,
        'bytes': response.bodyBytes.length,
      },
    );

    final normalizedPackageName = _sanitizeFileName(
      result.packageName.trim().isEmpty ? 'subtitle.bin' : result.packageName,
    );
    final archivePath = p.join(bucketDirectory.path, normalizedPackageName);
    final archiveFile = File(archivePath);
    await archiveFile.writeAsBytes(response.bodyBytes, flush: true);

    switch (result.packageKind) {
      case SubtitlePackageKind.subtitleFile:
        subtitleSearchTrace(
          'repository.download.finished',
          fields: {
            'id': result.id,
            'subtitleFilePath': archiveFile.path,
          },
        );
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
        subtitleSearchTrace(
          'repository.download.finished',
          fields: {
            'id': result.id,
            'subtitleFilePath': extracted.path,
          },
        );
        return SubtitleDownloadResult(
          cachedPath: bucketDirectory.path,
          displayName: p.basenameWithoutExtension(extracted.path),
          subtitleFilePath: extracted.path,
        );
      case SubtitlePackageKind.rarArchive:
      case SubtitlePackageKind.unsupported:
        subtitleSearchTrace(
          'repository.download.finished',
          fields: {
            'id': result.id,
            'cachedPath': archiveFile.path,
            'applyable': false,
          },
        );
        return SubtitleDownloadResult(
          cachedPath: archiveFile.path,
          displayName: p.basenameWithoutExtension(archiveFile.path),
        );
    }
  }

  @visibleForTesting
  static List<SubtitleSearchResult> parseAssrtSearchHtml(String html) {
    final normalized = html.trim();
    if (normalized.isEmpty || !normalized.contains(_assrtSearchMarker)) {
      return const [];
    }

    final segments = normalized.split(_assrtSearchMarker);
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
      final detailUrl =
          _absoluteUrl('https://assrt.net/', titleMatch.group(2) ?? '');
      final downloadUrl = _absoluteUrl(
        'https://assrt.net/',
        downloadMatch.group(1) ?? '',
      );
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
      final id =
          RegExp(r'/download/(\d+)/').firstMatch(downloadUrl)?.group(1) ??
              _stableHash(downloadUrl);

      results.add(
        SubtitleSearchResult(
          id: id,
          source: OnlineSubtitleSource.assrt,
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

    results.sort(_compareSearchResults);
    return results;
  }

  @visibleForTesting
  static List<SubtitleSearchResult> parseSubhdSearchHtml(String html) {
    final normalized = html.trim();
    if (normalized.isEmpty || !normalized.contains(_subhdSearchMarker)) {
      return const [];
    }

    final segments = normalized.split(_subhdSearchMarker);
    final results = <SubtitleSearchResult>[];
    for (final rawSegment in segments.skip(1)) {
      final segment = rawSegment.trim();
      final titleMatch = RegExp(
        r"""<a class="link-dark align-middle" href=['"]([^'"]+)['"]>(.*?)</a>""",
        dotAll: true,
      ).firstMatch(segment);
      if (titleMatch == null) {
        continue;
      }

      final detailUrl =
          _absoluteUrl('https://subhd.tv/', titleMatch.group(1) ?? '');
      final id = RegExp(r'/a/([^/?#]+)').firstMatch(detailUrl)?.group(1) ??
          _stableHash(detailUrl);
      final title = _normalizeWhitespace(
        _decodeHtmlTextWithBreaks(titleMatch.group(2) ?? ''),
      );
      final version = _normalizeWhitespace(
        _decodeHtmlTextWithBreaks(
          RegExp(
                r'<div class="view-text text-secondary">.*?<a [^>]*>(.*?)</a>',
                dotAll: true,
              ).firstMatch(segment)?.group(1) ??
              '',
        ),
      );
      final languageLabel = RegExp(
        r'<span class="p-1 fw-bold">(.*?)</span>',
        dotAll: true,
      )
          .allMatches(segment)
          .map(
            (match) => _normalizeWhitespace(
              _decodeHtmlText(match.group(1) ?? ''),
            ),
          )
          .where((item) => item.isNotEmpty)
          .toSet()
          .join(' / ');
      final formatLabel = _normalizeWhitespace(
        _decodeHtmlText(
          RegExp(
                r'<span class="p-1 text-secondary">(.*?)</span>',
                dotAll: true,
              ).firstMatch(segment)?.group(1) ??
              '',
        ),
      );
      final typeLabel = _normalizeWhitespace(
        _decodeHtmlText(
          RegExp(
                r'<span class="rounded p-1 me-1 text-white"[^>]*>(.*?)</span>',
                dotAll: true,
              ).firstMatch(segment)?.group(1) ??
              '',
        ),
      );
      final statsBlock = RegExp(
        r'<div class="pt-2 text-secondary f12">(.*?)</div>',
        dotAll: true,
      ).firstMatch(segment)?.group(1);
      final statValues = statsBlock == null
          ? const <String>[]
          : RegExp(
              r'<span[^>]*>(.*?)</span>',
              dotAll: true,
            )
              .allMatches(statsBlock)
              .map(
                (match) => _normalizeWhitespace(
                  _decodeHtmlText(match.group(1) ?? ''),
                ),
              )
              .where((item) => item.isNotEmpty)
              .toList(growable: false);
      final downloadCount =
          statValues.length > 1 ? _parseLooseInt(statValues[1]) : 0;
      final publishDateLabel = statValues.isNotEmpty ? statValues.last : '';
      final publisher = _normalizeWhitespace(
        _decodeHtmlText(
          RegExp(
                r'发布人\s*<a[^>]*>(.*?)</a>',
                dotAll: true,
              ).firstMatch(segment)?.group(1) ??
              '',
        ),
      );
      final extension = _defaultSubtitleExtension(formatLabel);
      final packageName =
          extension.isEmpty ? 'subhd-$id.bin' : 'subhd-$id$extension';
      final packageKind = _resolvePackageKind(packageName);

      results.add(
        SubtitleSearchResult(
          id: 'subhd:$id',
          source: OnlineSubtitleSource.subhd,
          providerLabel: 'SubHD',
          title: title,
          version: version,
          formatLabel: formatLabel,
          languageLabel: languageLabel,
          sourceLabel: publisher,
          publishDateLabel: publishDateLabel,
          downloadCount: downloadCount,
          ratingLabel: typeLabel,
          downloadUrl: '',
          detailUrl: detailUrl,
          packageName: packageName,
          packageKind: packageKind,
        ),
      );
    }

    results.sort(_compareSearchResults);
    return results;
  }

  @visibleForTesting
  static List<SubtitleSearchResult> parseYifyMoviePageHtml(
    String html, {
    required String imdbId,
  }) {
    final normalized = html.trim();
    if (normalized.isEmpty || !normalized.contains('<tr data-id=')) {
      return const [];
    }

    final movieTitle = _normalizeWhitespace(
      _decodeHtmlTextWithBreaks(
        RegExp(
              r'<h2 class="movie-main-title">(.*?)</h2>',
              dotAll: true,
            ).firstMatch(normalized)?.group(1) ??
            RegExp(r'<h2>(.*?)</h2>', dotAll: true)
                .firstMatch(normalized)
                ?.group(1) ??
            '',
      ),
    );
    final publishYear = _normalizeWhitespace(
      _decodeHtmlText(
        RegExp(
              r'<div class="movie-year">(.*?)</div>',
              dotAll: true,
            ).firstMatch(normalized)?.group(1) ??
            '',
      ),
    );

    final results = <SubtitleSearchResult>[];
    final matches = RegExp(
      r'<tr data-id="(\d+)">(.*?)</tr>',
      dotAll: true,
    ).allMatches(normalized);

    for (final match in matches) {
      final rowId = match.group(1) ?? '';
      final segment = match.group(2) ?? '';
      final detailPath = RegExp(
        r'<a href="([^"]*?/subtitles/[^"]+)">',
        dotAll: true,
      ).firstMatch(segment)?.group(1);
      if (detailPath == null || detailPath.trim().isEmpty) {
        continue;
      }

      final detailUrl = _absoluteUrl(
        'https://www.yifysubtitles.ch/',
        detailPath,
      );
      final slug = Uri.parse(detailUrl).pathSegments.isEmpty
          ? rowId
          : Uri.parse(detailUrl).pathSegments.last;
      final releaseLines = _decodeHtmlTextWithBreaks(
        RegExp(
              r'<a href="[^"]*?/subtitles/[^"]+">(.*?)</a>',
              dotAll: true,
            ).firstMatch(segment)?.group(1) ??
            '',
      )
          .split('\n')
          .map(_normalizeWhitespace)
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
      var version = releaseLines.isEmpty ? '' : releaseLines.first;
      if (version.toLowerCase().startsWith('subtitle ')) {
        version = version.substring('subtitle '.length).trim();
      }

      final languageLabel = _normalizeWhitespace(
        _decodeHtmlText(
          RegExp(
                r'<span class="sub-lang">(.*?)</span>',
                dotAll: true,
              ).firstMatch(segment)?.group(1) ??
              '',
        ),
      );
      final uploader = _normalizeWhitespace(
        _decodeHtmlText(
          RegExp(
                r'<td class="uploader-cell"><a [^>]*>(.*?)</a></td>',
                dotAll: true,
              ).firstMatch(segment)?.group(1) ??
              '',
        ),
      );
      final ratingValue = _parseLooseInt(
        RegExp(
              r'<td class="rating-cell">.*?<(?:p class="rating"|span class="label(?: [^"]*)?")>([^<]+)</',
              dotAll: true,
            ).firstMatch(segment)?.group(1) ??
            '',
      );
      final downloadUrl = 'https://www.yifysubtitles.ch/subtitle/$slug.zip';
      final title =
          publishYear.isEmpty ? movieTitle : '$movieTitle ($publishYear)';

      results.add(
        SubtitleSearchResult(
          id: 'yify:$rowId',
          source: OnlineSubtitleSource.yify,
          providerLabel: 'YIFY',
          title: title,
          version: version,
          formatLabel: '',
          languageLabel: languageLabel,
          sourceLabel: uploader,
          publishDateLabel: '',
          downloadCount: 0,
          ratingLabel: ratingValue > 0 ? '评分 $ratingValue' : '',
          downloadUrl: downloadUrl,
          detailUrl: detailUrl,
          packageName: '$slug.zip',
          packageKind: SubtitlePackageKind.zipArchive,
        ),
      );
    }

    results.sort(_compareSearchResults);
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
    final bytes = List<int>.from(content);
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

String _sampleResultTitles(List<SubtitleSearchResult> results) {
  if (results.isEmpty) {
    return '';
  }
  return results
      .take(3)
      .map((item) => '${item.providerLabel}:${item.title}')
      .join(' | ');
}

String _responseSnippet(String body) {
  final normalized = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length <= 180) {
    return normalized;
  }
  return '${normalized.substring(0, 177)}...';
}

class _YifyMovieCandidate {
  const _YifyMovieCandidate({
    required this.title,
    required this.imdbId,
  });

  final String title;
  final String imdbId;
}

int _compareSearchResults(
  SubtitleSearchResult left,
  SubtitleSearchResult right,
) {
  final downloadOrder = _compareBoolTrueFirst(
    left.canDownload,
    right.canDownload,
  );
  if (downloadOrder != 0) {
    return downloadOrder;
  }

  final autoLoadOrder = _compareBoolTrueFirst(
    left.canAutoLoad,
    right.canAutoLoad,
  );
  if (autoLoadOrder != 0) {
    return autoLoadOrder;
  }

  final packageOrder = _packageKindSortValue(left.packageKind).compareTo(
    _packageKindSortValue(right.packageKind),
  );
  if (packageOrder != 0) {
    return packageOrder;
  }

  final languageOrder = _subtitleLanguageScore(right.languageLabel).compareTo(
    _subtitleLanguageScore(left.languageLabel),
  );
  if (languageOrder != 0) {
    return languageOrder;
  }

  final ratingOrder = _ratingScore(right.ratingLabel).compareTo(
    _ratingScore(left.ratingLabel),
  );
  if (ratingOrder != 0) {
    return ratingOrder;
  }

  final downloadCountOrder = right.downloadCount.compareTo(left.downloadCount);
  if (downloadCountOrder != 0) {
    return downloadCountOrder;
  }

  return left.providerLabel.compareTo(right.providerLabel);
}

int _compareBoolTrueFirst(bool left, bool right) {
  if (left == right) {
    return 0;
  }
  return left ? -1 : 1;
}

int _packageKindSortValue(SubtitlePackageKind kind) {
  return switch (kind) {
    SubtitlePackageKind.subtitleFile => 0,
    SubtitlePackageKind.zipArchive => 1,
    SubtitlePackageKind.rarArchive => 2,
    SubtitlePackageKind.unsupported => 3,
  };
}

int _subtitleLanguageScore(String label) {
  final normalized = label.trim().toLowerCase();
  if (normalized.isEmpty) {
    return 0;
  }

  var score = 0;
  if (normalized.contains('双语') ||
      normalized.contains('中英') ||
      normalized.contains('bilingual')) {
    score += 6;
  }
  if (normalized.contains('简体') ||
      normalized.contains('繁体') ||
      normalized.contains('中文') ||
      normalized.contains('chinese') ||
      normalized.contains('chs') ||
      normalized.contains('cht')) {
    score += 5;
  }
  if (normalized.contains('英语') || normalized.contains('english')) {
    score += 2;
  }
  return score;
}

int _ratingScore(String label) {
  final match = RegExp(r'评分\s*(\d+)').firstMatch(label);
  if (match != null) {
    return int.tryParse(match.group(1) ?? '') ?? 0;
  }
  if (label.contains('官方')) {
    return 8;
  }
  if (label.contains('转载精修')) {
    return 6;
  }
  return 0;
}

int _scoreYifyCandidate(_YifyMovieCandidate candidate, String query) {
  final normalizedTitle = _normalizeCandidateText(candidate.title);
  final normalizedQuery = _normalizeCandidateText(query);
  var score = 0;
  if (normalizedTitle.isEmpty || normalizedQuery.isEmpty) {
    return score;
  }
  if (normalizedTitle.contains(normalizedQuery)) {
    score += 360;
  }
  if (normalizedQuery.contains(normalizedTitle)) {
    score += 200;
  }

  final queryTokens = query
      .split(RegExp(r'[\s:._-]+'))
      .map(_normalizeCandidateText)
      .where((item) => item.isNotEmpty)
      .toSet();
  for (final token in queryTokens) {
    if (normalizedTitle.contains(token)) {
      score += 28;
    }
  }
  score -= candidate.title.length ~/ 16;
  return score;
}

bool _looksLikeEpisodeQuery(String query) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) {
    return false;
  }
  return RegExp(
    r'\bs\d{1,2}e\d{1,2}\b|season\s*\d+\s*episode\s*\d+|第\s*\d+\s*季|第\s*\d+\s*集',
    caseSensitive: false,
  ).hasMatch(normalized);
}

@visibleForTesting
List<String> buildSubtitleSearchQueryVariants(String query) {
  final normalized = _normalizeWhitespace(query);
  if (normalized.isEmpty) {
    return const [];
  }

  final variants = <String>[];
  final pending = <String>[normalized];
  final seen = <String>{};

  while (pending.isNotEmpty) {
    final current = pending.removeAt(0);
    if (!seen.add(current)) {
      continue;
    }
    variants.add(current);

    final withoutEpisode = _stripTrailingEpisodeToken(current);
    if (withoutEpisode.isNotEmpty && !seen.contains(withoutEpisode)) {
      pending.add(withoutEpisode);
    }

    final withoutYear = _stripTrailingYearToken(current);
    if (withoutYear.isNotEmpty && !seen.contains(withoutYear)) {
      pending.add(withoutYear);
    }
  }
  return variants;
}

@visibleForTesting
bool isAssrtErrorResponse(int statusCode, String body) {
  final normalized = body.trim();
  if (statusCode >= 400) {
    return true;
  }
  if (normalized.isEmpty) {
    return false;
  }
  return normalized.contains('java.money.noMoneyException') ||
      normalized.contains('请您通过Email报告指向此页面的网址') ||
      normalized.contains('啊呀');
}

String _readResponseBody(http.Response response) {
  try {
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  } catch (_) {
    return response.body;
  }
}

String _absoluteUrl(String baseUrl, String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.hasScheme) {
    return trimmed;
  }
  return Uri.parse(baseUrl).resolve(trimmed).toString();
}

String _extractPackageName(String downloadUrl) {
  final uri = Uri.tryParse(downloadUrl);
  final segments = uri?.pathSegments ?? const <String>[];
  if (segments.isEmpty) {
    return 'subtitle.bin';
  }
  final rawName = segments.last.trim();
  if (rawName.isEmpty) {
    return 'subtitle.bin';
  }
  try {
    return Uri.decodeComponent(rawName);
  } on ArgumentError catch (error, stackTrace) {
    subtitleSearchTrace(
      'repository.package-name.decode-fallback',
      fields: {
        'downloadUrl': downloadUrl,
        'rawName': rawName,
      },
      error: error,
      stackTrace: stackTrace,
    );
    return rawName;
  }
}

String _defaultSubtitleExtension(String formatLabel) {
  final normalized = formatLabel.trim().toLowerCase();
  if (normalized.contains('ssa')) {
    return '.ssa';
  }
  if (normalized.contains('ass')) {
    return '.ass';
  }
  if (normalized.contains('srt')) {
    return '.srt';
  }
  if (normalized.contains('vtt')) {
    return '.vtt';
  }
  if (normalized.contains('sup')) {
    return '.sup';
  }
  return '';
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

int _parseLooseInt(String value) {
  final match = RegExp(r'(\d+)').firstMatch(value);
  return int.tryParse(match?.group(1) ?? '') ?? 0;
}

String _stripTrailingEpisodeToken(String query) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  return _normalizeWhitespace(
    trimmed.replaceFirst(
      RegExp(
        r'\s*(?:s\d{1,2}e\d{1,2}|season\s*\d+\s*episode\s*\d+|第\s*\d+\s*季\s*第\s*\d+\s*集|第\s*\d+\s*集)\s*$',
        caseSensitive: false,
      ),
      '',
    ),
  );
}

String _stripTrailingYearToken(String query) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  return _normalizeWhitespace(
    trimmed.replaceFirst(RegExp(r'\s+(?:19|20)\d{2}\s*$'), ''),
  );
}

String _normalizeCandidateText(String value) {
  return value.trim().toLowerCase().replaceAll(
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
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&#x27;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}

String _decodeHtmlTextWithBreaks(String value) {
  return value
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
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
