import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:starflow/core/network/starflow_http_client.dart';
import 'package:starflow/core/storage/local_storage_models.dart';
import 'package:starflow/features/playback/data/online_subtitle_provider_protocol.dart';
import 'package:starflow/features/playback/data/online_subtitle_repository.dart';
import 'package:starflow/features/playback/data/online_subtitle_validation_pipeline.dart';
import 'package:starflow/features/playback/domain/online_subtitle_structured_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

OnlineSubtitleRepository createOnlineSubtitleRepository(Ref ref) =>
    AssrtSubtitleRepository(ref.read(starflowHttpClientProvider),
        settingsProvider: () => ref.read(appSettingsProvider));

class AssrtSubtitleRepository implements OnlineSubtitleRepository {
  AssrtSubtitleRepository(
    this._client, {
    required AppSettings Function() settingsProvider,
    Future<Directory> Function()? temporaryDirectoryProvider,
  })  : _settingsProvider = settingsProvider,
        _temporaryDirectoryProvider =
            temporaryDirectoryProvider ?? getTemporaryDirectory;

  static const _openSubtitlesApiKey =
      String.fromEnvironment('STARFLOW_OPENSUBTITLES_API_KEY');
  final http.Client _client;
  final AppSettings Function() _settingsProvider;
  final Future<Directory> Function() _temporaryDirectoryProvider;

  OpenSubtitlesStructuredProvider _openSubtitlesProvider() {
    final settings = _settingsProvider();
    return OpenSubtitlesStructuredProvider(_client,
        config: OpenSubtitlesProviderConfig(
          enabled: settings.opensubtitlesEnabled,
          apiKey: _openSubtitlesApiKey,
          username: settings.opensubtitlesUsername,
          password: settings.opensubtitlesPassword,
        ));
  }

  @override
  Future<List<ValidatedSubtitleCandidate>> searchStructured(
    OnlineSubtitleSearchRequest request, {
    List<OnlineSubtitleSource> sources = const [
      OnlineSubtitleSource.assrt,
      OnlineSubtitleSource.opensubtitles,
      OnlineSubtitleSource.subdl
    ],
    int maxResults = 0,
    int maxValidated = 0,
  }) async {
    if (!request.hasStructuredIdentity) return const [];
    final settings = _settingsProvider();
    final providers = <OnlineSubtitleStructuredProvider>[
      AssrtStructuredProvider(_client,
          config: AssrtProviderConfig(
              enabled: settings.assrtApiSearchEnabled,
              token: settings.assrtToken)),
      _openSubtitlesProvider(),
      SubdlStructuredProvider(_client,
          config: SubdlProviderConfig(
              enabled: settings.subdlEnabled, apiKey: settings.subdlApiKey)),
    ].where((provider) => sources.contains(provider.source));
    final errors = <String>[];
    final batches = await Future.wait(providers.map((provider) async {
      try {
        return await provider
            .search(request)
            .timeout(const Duration(seconds: 30));
      } catch (error) {
        errors.add('${provider.providerLabel}: $error');
        return <ProviderSubtitleHit>[];
      }
    }));
    final hits = batches.expand((batch) => batch).toList();
    if (hits.isEmpty && errors.isNotEmpty) throw StateError(errors.join('；'));
    var limit = hits.length;
    if (maxResults > 0 && maxResults < limit) limit = maxResults;
    // Retain the persisted setting key while treating it as a result limit.
    if (maxValidated > 0 && maxValidated < limit) limit = maxValidated;
    return hits
        .take(limit)
        .map((hit) => ValidatedSubtitleCandidate(
              hit: hit,
              status: SubtitleValidationStatus.skipped,
              failureReason: '搜索阶段不预下载，点选后再下载并加载',
            ))
        .toList(growable: false);
  }

  @override
  Future<SubtitleDownloadResult> download(SubtitleSearchResult result) async {
    final url = result.source == OnlineSubtitleSource.opensubtitles &&
            result.providerFileId > 0
        ? await _openSubtitlesProvider()
            .resolveDownloadUrl(result.providerFileId)
            .timeout(const Duration(seconds: 30))
        : result.downloadUrl;
    await _pruneExpiredCache();
    final pipeline =
        SubtitleValidationPipeline(_client, cacheDirectoryProvider: _cacheRoot);
    final validated = await pipeline.validateHit(
        ProviderSubtitleHit(
          id: result.id,
          source: result.source,
          providerLabel: result.providerLabel,
          title: result.title,
          downloadUrl: url,
          packageName: result.packageName,
          packageKind: result.packageKind,
          version: result.version,
          seasonNumber: result.seasonNumber,
          episodeNumber: result.episodeNumber,
        ),
        preferredLanguages: _settingsProvider().subtitlePreferredLanguages,
        referer: result.source == OnlineSubtitleSource.assrt
            ? 'https://assrt.net/'
            : '');
    if (!validated.canApply) throw StateError(validated.failureReason);
    return validated.toDownloadResult();
  }

  Future<Directory> _cacheRoot() async => Directory(p.join(
      (await _temporaryDirectoryProvider()).path,
      'starflow',
      'online_subtitles'));

  Future<List<Directory>> _cacheRoots() async {
    final root = await _temporaryDirectoryProvider();
    return [
      Directory(p.join(root.path, 'starflow', 'online_subtitles')),
      Directory(p.join(root.path, 'starflow', 'validated_online_subtitles')),
      // Legacy native shifted files. New native playback owns its own copies.
      Directory(p.join(root.path, 'native_subtitles')),
    ];
  }

  DateTime? _lastCachePrune;

  Future<void> _pruneExpiredCache() async {
    final now = DateTime.now();
    if (_lastCachePrune != null &&
        now.difference(_lastCachePrune!) < const Duration(hours: 1)) {
      return;
    }
    _lastCachePrune = now;
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    for (final root in await _cacheRoots()) {
      try {
        if (!await root.exists()) continue;
        await for (final entry in root.list(followLinks: false)) {
          if ((await entry.stat()).modified.isBefore(cutoff)) {
            await entry.delete(recursive: true);
          }
        }
      } on FileSystemException {
        // Retention is best effort while other engines inspect or clear cache.
      }
    }
  }

  @override
  Future<LocalStorageCacheSummary> inspectCacheSummary() async {
    var count = 0;
    var bytes = 0;
    for (final root in await _cacheRoots()) {
      try {
        if (!await root.exists()) continue;
        await for (final entry
            in root.list(recursive: true, followLinks: false)) {
          if (entry is File) {
            try {
              bytes += await entry.length();
              count++;
            } on FileSystemException {
              // A second Flutter engine may have removed this file.
            }
          }
        }
      } on FileSystemException {
        // Cache inspection is a snapshot across independent engines.
      }
    }
    return LocalStorageCacheSummary(
        type: LocalStorageCacheType.subtitleCache,
        entryCount: count,
        totalBytes: bytes);
  }

  @override
  Future<void> clearCache() async {
    for (final root in await _cacheRoots()) {
      try {
        if (await root.exists()) await root.delete(recursive: true);
      } on FileSystemException {
        if (await root.exists()) rethrow;
      }
    }
  }
}
