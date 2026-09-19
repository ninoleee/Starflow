import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/playback/application/subtitle_content_decoder.dart';
import 'package:starflow/features/playback/application/subtitle_language_preferences.dart';
import 'package:starflow/features/playback/application/subtitle_render_policy.dart';
import 'package:starflow/features/playback/data/online_subtitle_provider_protocol.dart';
import 'package:starflow/features/playback/data/online_subtitle_repository_io.dart';
import 'package:starflow/features/playback/data/online_subtitle_validation_pipeline.dart';
import 'package:starflow/features/playback/domain/online_subtitle_structured_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

const _srt = '1\n00:00:01,000 --> 00:00:02,000\n中文字幕';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('shared cross-platform language contract', () {
    final rows = jsonDecode(
        File('test/fixtures/subtitle_language_contract.json')
            .readAsStringSync()) as List;
    for (final row in rows) {
      expect(
          scorePreferredSubtitleText(row['text'] as String,
                  configuredLanguages: [row['preference'] as String]) >
              0,
          row['match'],
          reason: '$row');
    }
  });

  test(
      'OpenSubtitles retries authorization once but never retries quota errors',
      () async {
    var logins = 0;
    var downloads = 0;
    var quota = false;
    final provider = OpenSubtitlesStructuredProvider(
        MockClient((request) async {
      if (request.url.path.endsWith('/login')) {
        logins++;
        return http.Response('{"token":"token-$logins"}', 200);
      }
      downloads++;
      if (quota) return http.Response('{}', 406);
      if (downloads == 1) return http.Response('{}', 401);
      return http.Response('{"link":"https://example.com/file.srt"}', 200);
    }),
        config: const OpenSubtitlesProviderConfig(
            enabled: true,
            apiKey: 'retry-key',
            username: 'retry-user',
            password: 'secret'));
    expect(
        await provider.resolveDownloadUrl(1), 'https://example.com/file.srt');
    expect(logins, 2);
    expect(downloads, 2);
    quota = true;
    await expectLater(
        provider.resolveDownloadUrl(1), throwsA(isA<StateError>()));
    expect(downloads, 3);
  });

  test('ZIP cannot bypass output limits with a forged uncompressed size', () {
    final bytes = Uint8List.fromList(ZipEncoder().encode(Archive()
      ..addFile(ArchiveFile(
          'bomb.srt', maxSubtitleBytes + 1, Uint8List(maxSubtitleBytes + 1)))));
    final data = ByteData.sublistView(bytes);
    for (var offset = 0; offset + 46 <= bytes.length; offset++) {
      final signature = data.getUint32(offset, Endian.little);
      if (signature == 0x04034b50) {
        data.setUint32(offset + 22, 1, Endian.little);
      }
      if (signature == 0x02014b50) {
        data.setUint32(offset + 24, 1, Endian.little);
      }
    }
    final archive = decodeBoundedSubtitleArchive(bytes);
    expect(() => readBoundedSubtitleEntry(archive.files.single),
        throwsA(isA<SubtitleContentException>()));
  });

  test(
      'standard language codes match without matching unrelated bilingual titles',
      () {
    for (final language in ['en', 'ja', 'ko', 'fr', 'de', 'es', 'pt', 'ru']) {
      expect(
          scorePreferredSubtitleText(language, configuredLanguages: [language]),
          greaterThan(0));
    }
    expect(scorePreferredSubtitleText('bilingual', configuredLanguages: ['ja']),
        0);
    expect(
        scorePreferredSubtitleText('French', configuredLanguages: ['en']), 0);
    expect(scorePreferredSubtitleText('中英', configuredLanguages: ['en']),
        greaterThan(0));
  });

  test('bitmap rendering is separate from text rendering', () {
    for (final codec in [
      'pgs',
      'hdmv_pgs_subtitle',
      'dvd_subtitle',
      'dvb_subtitle',
      'vobsub',
      'xsub'
    ]) {
      expect(isBitmapSubtitle(codec: codec), isTrue);
    }
    expect(isBitmapSubtitle(image: true), isTrue);
    expect(isBitmapSubtitle(codec: 'ass'), isFalse);
    expect(isBitmapSubtitle(), isFalse);
  });

  test(
      'OpenSubtitles searches metadata only and resolves selected file on demand',
      () async {
    var downloads = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/login')) {
        expect(jsonDecode(request.body)['password'], ' secret ');
        return http.Response(
            jsonEncode(
                {'token': 'token', 'base_url': 'vip-api.opensubtitles.com'}),
            200);
      }
      expect(request.url.host, 'vip-api.opensubtitles.com');
      if (request.url.path == '/api/v1/subtitles') {
        return http.Response(
            jsonEncode({
              'data': List.generate(
                  8,
                  (index) => {
                        'id': '$index',
                        'attributes': {
                          'release': 'Film',
                          'language': 'en',
                          'feature_details': {'movie_name': 'Film'},
                          'files': [
                            {'file_id': index + 1, 'file_name': 'Film.srt'}
                          ],
                        },
                      })
            }),
            200);
      }
      expect(request.url.path, '/api/v1/download');
      expect(jsonDecode(request.body)['file_id'], 4);
      downloads++;
      return http.Response('{"link":"https://example.com/selected.srt"}', 200);
    });
    final provider = OpenSubtitlesStructuredProvider(client,
        config: const OpenSubtitlesProviderConfig(
            enabled: true,
            apiKey: 'regression-key',
            username: 'regression-user',
            password: ' secret '));
    final hits =
        await provider.search(const OnlineSubtitleSearchRequest(title: 'Film'));
    expect(hits, hasLength(8));
    expect(downloads, 0);
    expect(
        hits.every(
            (hit) => hit.canDownload && hit.toSearchResult().canDownload),
        isTrue);
    final serialized =
        SubtitleSearchResult.fromJson(hits[3].toSearchResult().toJson());
    expect(serialized.providerFileId, 4);
    expect(await provider.resolveDownloadUrl(serialized.providerFileId),
        'https://example.com/selected.srt');
    expect(downloads, 1);
  });

  test('SubDL skips unsupported hash queries and resolves relative ZIP URLs',
      () async {
    final client = MockClient((request) async {
      expect(request.url.queryParameters['film_name'], 'Film');
      return http.Response(
          '{"status":true,"subtitles":[{"sd_id":1,"name":"Film.release","url":"/subtitle/42.zip","language":"EN"}]}',
          200);
    });
    final hits = await SubdlStructuredProvider(client,
            config: const SubdlProviderConfig(enabled: true, apiKey: 'key'))
        .search(const OnlineSubtitleSearchRequest(
            title: 'Film', fileHash: '0123456789abcdef'));
    expect(hits.single.downloadUrl, 'https://dl.subdl.com/subtitle/42.zip');
    expect(hits.single.packageKind, SubtitlePackageKind.zipArchive);
  });

  for (final encoding in [gbk, utf16]) {
    test(
        'pipeline normalizes ${encoding.name} and cache clears across repository instances',
        () async {
      final root =
          await Directory.systemTemp.createTemp('subtitle-regression-');
      addTearDown(() => root.delete(recursive: true));
      final client = MockClient(
          (_) async => http.Response.bytes(encoding.encode(_srt), 200));
      AssrtSubtitleRepository repository() => AssrtSubtitleRepository(client,
          settingsProvider: () => AppSettings.fromJson({}),
          temporaryDirectoryProvider: () async => root);
      final download = await repository().download(const SubtitleSearchResult(
        id: 'test',
        source: OnlineSubtitleSource.assrt,
        providerLabel: 'ASSRT',
        title: 'Film',
        version: '',
        formatLabel: '',
        languageLabel: '',
        sourceLabel: '',
        publishDateLabel: '',
        downloadCount: 0,
        ratingLabel: '',
        detailUrl: '',
        downloadUrl: 'https://example.com/subtitle.srt',
        packageName: 'subtitle.srt',
        packageKind: SubtitlePackageKind.subtitleFile,
      ));
      expect(await File(download.subtitleFilePath!).readAsString(), _srt);
      final legacy =
          File('${root.path}/starflow/validated_online_subtitles/old.srt');
      await legacy.parent.create(recursive: true);
      await legacy.writeAsString(_srt);
      final second = repository();
      expect((await second.inspectCacheSummary()).entryCount, 2);
      await second.clearCache();
      expect((await second.inspectCacheSummary()).entryCount, 0);
      expect(await File(download.subtitleFilePath!).exists(), isFalse);
    });
  }

  test('invalid HTML and oversized responses never become playable subtitles',
      () async {
    final root = await Directory.systemTemp.createTemp('subtitle-invalid-');
    addTearDown(() => root.delete(recursive: true));
    final pipeline = SubtitleValidationPipeline(
        MockClient((_) async => http.Response('<html>login</html>', 200)),
        cacheDirectoryProvider: () async => root);
    final result = await pipeline.validateHit(const ProviderSubtitleHit(
      id: 'bad',
      source: OnlineSubtitleSource.assrt,
      providerLabel: 'ASSRT',
      title: 'bad',
      downloadUrl: 'https://example.com/bad.srt',
      packageName: 'bad.srt',
      packageKind: SubtitlePackageKind.subtitleFile,
    ));
    expect(result.status, SubtitleValidationStatus.failed);
    expect(await root.list().isEmpty, isTrue);
    final client = MockClient((_) async =>
        http.Response.bytes(List.filled(maxSubtitleBytes + 1, 0), 200));
    await expectLater(
        downloadSubtitleBytes(client, 'https://example.com/large'),
        throwsA(isA<SubtitleContentException>()));
  });

  test('ZIP selects the requested episode and rejects excessive entry counts',
      () async {
    final archive = Archive();
    archive.addFile(ArchiveFile.string(
        'Show.S01E01.en.srt', _srt.replaceAll('中文字幕', 'EP01')));
    archive.addFile(ArchiveFile.string(
        'Show.S01E02.en.srt', _srt.replaceAll('中文字幕', 'EP02')));
    final root = await Directory.systemTemp.createTemp('subtitle-zip-');
    addTearDown(() => root.delete(recursive: true));
    final pipeline = SubtitleValidationPipeline(
        MockClient((_) async =>
            http.Response.bytes(ZipEncoder().encode(archive), 200)),
        cacheDirectoryProvider: () async => root);
    final result = await pipeline.validateHit(
        const ProviderSubtitleHit(
          id: 'zip',
          source: OnlineSubtitleSource.assrt,
          providerLabel: 'ASSRT',
          title: 'show',
          downloadUrl: 'https://example.com/show.zip',
          packageName: 'show.zip',
          packageKind: SubtitlePackageKind.zipArchive,
          seasonNumber: 1,
          episodeNumber: 2,
        ),
        preferredLanguages: ['en']);
    expect(result.canApply, isTrue, reason: result.failureReason);
    expect(
        await File(result.subtitleFilePath!).readAsString(), endsWith('EP02'));
    for (var i = 0; i < maxSubtitleArchiveEntries; i++) {
      archive.addFile(ArchiveFile('extra-$i.txt', 1, [1]));
    }
    expect(() => decodeBoundedSubtitleArchive(ZipEncoder().encode(archive)),
        throwsA(isA<SubtitleContentException>()));
  });
}
