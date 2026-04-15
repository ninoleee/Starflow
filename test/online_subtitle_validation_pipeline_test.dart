import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/playback/data/online_subtitle_validation_pipeline.dart';
import 'package:starflow/features/playback/domain/online_subtitle_structured_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'validation cache isolates subtitle files with the same result id but different download urls',
      () async {
    final cacheRoot = await Directory.systemTemp.createTemp(
      'starflow-subtitle-validation-test-',
    );
    addTearDown(() async {
      if (await cacheRoot.exists()) {
        await cacheRoot.delete(recursive: true);
      }
    });

    final client = MockClient((request) async {
      if (request.url.toString().contains('episode-1')) {
        return http.Response('EP01', 200);
      }
      if (request.url.toString().contains('episode-2')) {
        return http.Response('EP02', 200);
      }
      return http.Response('not-found', 404);
    });

    final pipeline = SubtitleValidationPipeline(
      client,
      cacheDirectoryProvider: () async => cacheRoot,
    );

    final first = await pipeline.validateHit(
      const ProviderSubtitleHit(
        id: 'assrt:shared-id',
        source: OnlineSubtitleSource.assrt,
        providerLabel: 'ASSRT',
        title: '示例剧集',
        downloadUrl: 'https://example.com/episode-1.ass',
        packageName: 'shared-package.ass',
        packageKind: SubtitlePackageKind.subtitleFile,
        seasonNumber: 1,
        episodeNumber: 1,
      ),
    );
    final second = await pipeline.validateHit(
      const ProviderSubtitleHit(
        id: 'assrt:shared-id',
        source: OnlineSubtitleSource.assrt,
        providerLabel: 'ASSRT',
        title: '示例剧集',
        downloadUrl: 'https://example.com/episode-2.ass',
        packageName: 'shared-package.ass',
        packageKind: SubtitlePackageKind.subtitleFile,
        seasonNumber: 1,
        episodeNumber: 2,
      ),
    );

    expect(first.canApply, isTrue);
    expect(second.canApply, isTrue);
    expect(first.subtitleFilePath, isNot(equals(second.subtitleFilePath)));
    expect(
      await File(first.subtitleFilePath!).readAsString(),
      equals('EP01'),
    );
    expect(
      await File(second.subtitleFilePath!).readAsString(),
      equals('EP02'),
    );
  });
}
