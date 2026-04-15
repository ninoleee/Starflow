import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:starflow/core/storage/local_storage_models.dart';
import 'package:starflow/core/network/starflow_http_client.dart';
import 'package:starflow/core/utils/subtitle_search_trace.dart';
import 'package:starflow/features/playback/application/subtitle_language_preferences.dart';
import 'package:starflow/features/playback/data/online_subtitle_repository.dart';
import 'package:starflow/features/playback/data/online_subtitle_provider_protocol.dart';
import 'package:starflow/features/playback/data/online_subtitle_validation_pipeline.dart';
import 'package:starflow/features/playback/domain/online_subtitle_structured_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

OnlineSubtitleRepository createOnlineSubtitleRepository(Ref ref) {
  return AssrtSubtitleRepository(
    ref.read(starflowHttpClientProvider),
    settingsProvider: () => ref.read(appSettingsProvider),
  );
}

class AssrtSubtitleRepository implements OnlineSubtitleRepository {
  AssrtSubtitleRepository(
    this._client, {
    required AppSettings Function() settingsProvider,
  })  : _settingsProvider = settingsProvider,
        _validationPipeline = SubtitleValidationPipeline(_client);

  static const _openSubtitlesApiKey = String.fromEnvironment(
    'STARFLOW_OPENSUBTITLES_API_KEY',
  );

  final http.Client _client;
  final AppSettings Function() _settingsProvider;
  final SubtitleValidationPipeline _validationPipeline;
  Future<Directory>? _cacheDirectoryFuture;

  @override
  Future<List<ValidatedSubtitleCandidate>> searchStructured(
    OnlineSubtitleSearchRequest request, {
    List<OnlineSubtitleSource> sources = const [
      OnlineSubtitleSource.assrt,
      OnlineSubtitleSource.opensubtitles,
      OnlineSubtitleSource.subdl,
    ],
    int maxResults = 0,
    int maxValidated = 0,
  }) async {
    final enabledSources = sources.toSet();
    final providers = _buildStructuredProviders()
        .where((provider) => enabledSources.contains(provider.source))
        .toList(growable: false);
    subtitleSearchTrace(
      'repository.structured.search.start',
      fields: {
        'query': request.normalizedQuery,
        'title': request.normalizedTitle,
        'sources': providers.map((item) => item.source.name).join('/'),
        'plan':
            request.buildQueryPlan().map((item) => item.kind.name).join('/'),
      },
    );
    if (!request.hasStructuredIdentity || providers.isEmpty) {
      subtitleSearchTrace('repository.structured.search.skip-empty-request');
      return const [];
    }

    final hitLists = <List<ProviderSubtitleHit>>[];
    final errors = <String>[];
    for (final provider in providers) {
      try {
        hitLists.add(await provider.search(request));
      } catch (error, stackTrace) {
        errors.add('${provider.providerLabel}: $error');
        subtitleSearchTrace(
          'repository.structured.search.provider-failed',
          fields: {
            'source': provider.source.name,
            'query': request.normalizedQuery,
          },
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    final hits = hitLists.expand((item) => item).toList(growable: false);
    subtitleSearchTrace(
      'repository.structured.search.hits-collected',
      fields: {
        'hits': hits.length,
        'downloadable': hits.where((item) => item.canDownload).length,
        'sample': hits
            .take(3)
            .map((item) => '${item.providerLabel}:${item.title}')
            .join(' | '),
      },
    );
    if (hits.isEmpty && errors.isNotEmpty) {
      throw StateError(errors.join('；'));
    }
    final limitedHits = maxResults > 0 && hits.length > maxResults
        ? hits.take(maxResults).toList(growable: false)
        : hits;
    final candidates = await _validationPipeline.validateHits(
      limitedHits,
      maxValidated: maxValidated,
    );
    subtitleSearchTrace(
      'repository.structured.search.finished',
      fields: {
        'hits': hits.length,
        'processed': candidates.length,
        'validated': candidates
            .where((item) => item.status == SubtitleValidationStatus.validated)
            .length,
        'failed': candidates
            .where((item) => item.status == SubtitleValidationStatus.failed)
            .length,
        'skipped': candidates
            .where((item) => item.status == SubtitleValidationStatus.skipped)
            .length,
        'sources': providers.map((item) => item.source.name).join('/'),
      },
    );
    return candidates;
  }

  List<OnlineSubtitleStructuredProvider> _buildStructuredProviders() {
    final settings = _settingsProvider();
    return <OnlineSubtitleStructuredProvider>[
      AssrtStructuredProvider(
        _client,
        config: AssrtProviderConfig(
          enabled: settings.assrtApiSearchEnabled,
          token: settings.assrtToken,
        ),
      ),
      OpenSubtitlesStructuredProvider(
        _client,
        config: OpenSubtitlesProviderConfig(
          enabled: settings.opensubtitlesEnabled,
          apiKey: _openSubtitlesApiKey,
          username: settings.opensubtitlesUsername,
          password: settings.opensubtitlesPassword,
        ),
      ),
      SubdlStructuredProvider(
        _client,
        config: SubdlProviderConfig(
          enabled: settings.subdlEnabled,
          apiKey: settings.subdlApiKey,
        ),
      ),
    ];
  }

  @override
  Future<SubtitleDownloadResult> download(SubtitleSearchResult result) {
    switch (result.source) {
      case OnlineSubtitleSource.assrt:
        return _downloadAndCacheResult(
          result,
          referer: 'https://assrt.net/',
        );
      case OnlineSubtitleSource.opensubtitles:
      case OnlineSubtitleSource.subdl:
        throw StateError('新结构化字幕源请走预验证后本地应用链路。');
    }
  }

  @override
  Future<LocalStorageCacheSummary> inspectCacheSummary() async {
    final downloadSummary =
        await _inspectDirectorySummary(await _cacheDirectory());
    final validationSummary =
        await _inspectDirectorySummary(await _validationCacheDirectory());
    return LocalStorageCacheSummary(
      type: LocalStorageCacheType.subtitleCache,
      entryCount: downloadSummary.entryCount + validationSummary.entryCount,
      totalBytes: downloadSummary.totalBytes + validationSummary.totalBytes,
    );
  }

  @override
  Future<void> clearCache() async {
    final downloadDirectory = await _cacheDirectory();
    if (await downloadDirectory.exists()) {
      await downloadDirectory.delete(recursive: true);
    }
    final validationDirectory = await _validationCacheDirectory();
    if (await validationDirectory.exists()) {
      await validationDirectory.delete(recursive: true);
    }
    _cacheDirectoryFuture = null;
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

    if (result.packageKind == SubtitlePackageKind.zipArchive) {
      final cachedArchive = await _findExistingPackageFile(
        bucketDirectory,
        packageName: result.packageName,
      );
      if (cachedArchive != null) {
        final extracted = await _extractBestSubtitleFromZip(
          archiveFile: cachedArchive,
          bucketDirectory: bucketDirectory,
          version: result.version,
          packageName: result.packageName,
          preferredLanguages: _settingsProvider().subtitlePreferredLanguages,
          seasonNumber: result.seasonNumber,
          episodeNumber: result.episodeNumber,
        );
        subtitleSearchTrace(
          'repository.download.cache-hit',
          fields: {
            'id': result.id,
            'path': extracted.path,
          },
        );
        return SubtitleDownloadResult(
          cachedPath: bucketDirectory.path,
          displayName: p.basenameWithoutExtension(extracted.path),
          subtitleFilePath: extracted.path,
        );
      }
    }

    final existingExtracted = result.packageKind ==
            SubtitlePackageKind.subtitleFile
        ? await _findExistingSubtitleFileByPackageName(
            bucketDirectory,
            packageName: result.packageName,
          )
        : await _findBestExistingSubtitleFile(
            bucketDirectory,
            packageName: result.packageName,
            version: result.version,
            preferredLanguages: _settingsProvider().subtitlePreferredLanguages,
            seasonNumber: result.seasonNumber,
            episodeNumber: result.episodeNumber,
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
          preferredLanguages: _settingsProvider().subtitlePreferredLanguages,
          seasonNumber: result.seasonNumber,
          episodeNumber: result.episodeNumber,
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

  Future<File?> _findBestExistingSubtitleFile(
    Directory bucketDirectory, {
    required String packageName,
    required String version,
    required List<String> preferredLanguages,
    int? seasonNumber,
    int? episodeNumber,
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
        preferredLanguages: preferredLanguages,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
      ).compareTo(
        _subtitleCandidateScore(
          fileName: p.basename(left.path),
          packageName: packageName,
          version: version,
          preferredLanguages: preferredLanguages,
          seasonNumber: seasonNumber,
          episodeNumber: episodeNumber,
        ),
      ),
    );
    return candidates.first;
  }

  Future<File?> _findExistingSubtitleFileByPackageName(
    Directory bucketDirectory, {
    required String packageName,
  }) async {
    if (!await bucketDirectory.exists()) {
      return null;
    }
    final normalizedName = _sanitizeFileName(packageName);
    if (normalizedName.trim().isEmpty) {
      return null;
    }
    final directFile = File(p.join(bucketDirectory.path, normalizedName));
    if (await directFile.exists()) {
      return directFile;
    }
    return null;
  }

  Future<File?> _findExistingPackageFile(
    Directory bucketDirectory, {
    required String packageName,
  }) async {
    if (!await bucketDirectory.exists()) {
      return null;
    }
    final directFile =
        File(p.join(bucketDirectory.path, _sanitizeFileName(packageName)));
    if (await directFile.exists()) {
      return directFile;
    }
    final packageExtension = p.extension(packageName).toLowerCase();
    await for (final entity in bucketDirectory.list()) {
      if (entity is! File) {
        continue;
      }
      if (packageExtension.isNotEmpty &&
          p.extension(entity.path).toLowerCase() == packageExtension) {
        return entity;
      }
    }
    return null;
  }

  Future<File> _extractBestSubtitleFromZip({
    required File archiveFile,
    required Directory bucketDirectory,
    required String version,
    required String packageName,
    required List<String> preferredLanguages,
    int? seasonNumber,
    int? episodeNumber,
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
        preferredLanguages: preferredLanguages,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
      ).compareTo(
        _subtitleCandidateScore(
          fileName: left.name,
          packageName: packageName,
          version: version,
          preferredLanguages: preferredLanguages,
          seasonNumber: seasonNumber,
          episodeNumber: episodeNumber,
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
      final baseDirectory = await getTemporaryDirectory();
      final directory = Directory(
        p.join(baseDirectory.path, 'starflow', 'downloaded_online_subtitles'),
      );
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return directory;
    }();
  }

  Future<Directory> _validationCacheDirectory() async {
    final root = await getTemporaryDirectory();
    return Directory(
      p.join(root.path, 'starflow', 'validated_online_subtitles'),
    );
  }
}

Future<LocalStorageCacheSummary> _inspectDirectorySummary(
  Directory directory,
) async {
  if (!await directory.exists()) {
    return const LocalStorageCacheSummary(
      type: LocalStorageCacheType.subtitleCache,
      entryCount: 0,
      totalBytes: 0,
    );
  }

  var entryCount = 0;
  var totalBytes = 0;
  await for (final entity
      in directory.list(recursive: true, followLinks: false)) {
    if (entity is! File) {
      continue;
    }
    entryCount += 1;
    totalBytes += await entity.length();
  }

  return LocalStorageCacheSummary(
    type: LocalStorageCacheType.subtitleCache,
    entryCount: entryCount,
    totalBytes: totalBytes,
  );
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
  Iterable<String> preferredLanguages = const <String>[],
  int? seasonNumber,
  int? episodeNumber,
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
  score += scoreSubtitleEpisodeMatch(
    fileName,
    seasonNumber: seasonNumber,
    episodeNumber: episodeNumber,
  );
  score += scorePreferredSubtitleText(
    fileName,
    configuredLanguages: preferredLanguages,
  );

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

  const deprioritizedTokens = <String>['commentary', 'signs', 'forced'];
  for (final token in deprioritizedTokens) {
    if (normalized.contains(token)) {
      score -= 25;
    }
  }

  score -= p.basename(fileName).length ~/ 18;
  return score;
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

String _stableHash(String value) {
  var hash = 0xcbf29ce484222325;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
  }
  return hash.toRadixString(16);
}
