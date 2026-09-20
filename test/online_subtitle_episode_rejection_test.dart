import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/playback/data/online_subtitle_provider_protocol.dart';
import 'package:starflow/features/playback/data/online_subtitle_validation_pipeline.dart';
import 'package:starflow/features/playback/domain/online_subtitle_structured_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';

const _srt = '1\n00:00:01,000 --> 00:00:02,000\nSubtitle';
const _request = OnlineSubtitleSearchRequest(
    title: 'Show', seasonNumber: 1, episodeNumber: 2);
const _hit = ProviderSubtitleHit(
    id: 'zip',
    source: OnlineSubtitleSource.assrt,
    providerLabel: 'ASSRT',
    title: 'Show',
    downloadUrl: 'https://example.com/show.zip',
    packageName: 'Show.zip',
    packageKind: SubtitlePackageKind.zipArchive,
    seasonNumber: 1,
    episodeNumber: 2);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('explicit mismatch is distinct from unknown or matching identity', () {
    for (final name in [
      'Show.S01E01.srt',
      'Show.1x01.srt',
      'Show_第1季第1集.srt',
      'Show_E01.srt',
      'Show.S02.E02.srt'
    ]) {
      expect(
          isExplicitSubtitleEpisodeMismatch(name,
              seasonNumber: 1, episodeNumber: 2),
          isTrue,
          reason: name);
    }
    for (final name in [
      'Show.S01E02.srt',
      'Show_1x02.srt',
      'Show_第1季第2集.srt',
      'Show_E02.srt',
      'Show.en.srt'
    ]) {
      expect(
          isExplicitSubtitleEpisodeMismatch(name,
              seasonNumber: 1, episodeNumber: 2),
          isFalse,
          reason: name);
    }
    expect(isExplicitSubtitleEpisodeMismatch('Show.S01E01.srt'), isFalse);
    expect(
        isExplicitSubtitleEpisodeMismatch('Show.S00E01.srt',
            seasonNumber: 0, episodeNumber: 2),
        isTrue);
  });

  for (final unknownFallback in [false, true]) {
    test('ZIP missing target, unknown fallback=$unknownFallback', () async {
      final archive = Archive()
        ..addFile(ArchiveFile.string('Show.S01E01.chs.srt', _srt));
      if (unknownFallback) {
        archive.addFile(ArchiveFile.string('Show.en.srt', _srt));
      }
      final root = await Directory.systemTemp.createTemp('subtitle-episode-');
      addTearDown(() => root.delete(recursive: true));
      final pipeline = SubtitleValidationPipeline(
          MockClient((_) async =>
              http.Response.bytes(ZipEncoder().encode(archive), 200)),
          cacheDirectoryProvider: () async => root);
      final result = await pipeline.validateHit(_hit);
      expect(result.canApply, unknownFallback);
      if (unknownFallback) {
        expect(result.displayName, 'Show.en');
      } else {
        expect(await root.list().isEmpty, isTrue);
      }
    });

    test('ASSRT missing target, unknown fallback=$unknownFallback', () async {
      final client = MockClient((request) async => http.Response(
          jsonEncode({
            'status': 0,
            'sub': request.url.path.endsWith('/search')
                ? {
                    'subs': [
                      {'id': 1, 'native_name': 'Show'}
                    ]
                  }
                : {
                    'id': 1,
                    'filename': 'Show.zip',
                    'url': 'https://example.com/bundle.zip',
                    'filelist': [
                      {
                        'f': 'Show.S01E01.srt',
                        'url': 'https://example.com/wrong'
                      },
                      if (unknownFallback)
                        {
                          'f': 'Show.en.srt',
                          'url': 'https://example.com/unknown'
                        },
                    ]
                  }
          }),
          200));
      final hits = await AssrtStructuredProvider(client,
              config: const AssrtProviderConfig(enabled: true, token: 'token'))
          .search(_request);
      if (unknownFallback) {
        expect(hits.single.packageName, 'Show.en.srt');
      } else {
        expect(hits, isEmpty);
      }
    });
  }

  test('ASSRT direct fallback rejects an explicit wrong episode', () async {
    final client = MockClient((request) async => http.Response(
        jsonEncode({
          'status': 0,
          'sub': request.url.path.endsWith('/search')
              ? {
                  'subs': [
                    {'id': 1, 'native_name': 'Show'}
                  ]
                }
              : {
                  'id': 1,
                  'filename': 'Show.S01E01.srt',
                  'url': 'https://example.com/wrong.srt'
                },
        }),
        200));
    expect(
        await AssrtStructuredProvider(client,
                config:
                    const AssrtProviderConfig(enabled: true, token: 'token'))
            .search(_request),
        isEmpty);
  });
}
