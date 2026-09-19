import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/data/media_server_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/subtitle_content_decoder.dart';
import 'package:starflow/features/playback/data/native_fntv_service.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

class _Client extends Fake implements MediaServerClient {
  Future<List<int>> Function() download = () async => [];
  int calls = 0;

  @override
  Future<List<int>> downloadExternalSubtitleBytes({
    required MediaSourceConfig source,
    required String subtitleId,
  }) {
    calls++;
    return download();
  }
}

void main() {
  const source = MediaSourceConfig(
    id: 'nas',
    name: 'NAS',
    kind: MediaSourceKind.fntv,
    endpoint: 'https://nas.example',
    enabled: true,
  );
  const target = PlaybackTarget(
    title: 'Movie',
    sourceId: 'nas',
    sourceName: 'NAS',
    sourceKind: MediaSourceKind.fntv,
    streamUrl: '',
    subtitleStreams: [
      PlaybackSubtitleStream(id: 'sub', title: 'zh.srt', isExternal: true)
    ],
  );
  const srt = '1\n00:00:01,000 --> 00:00:02,000\n中文字幕\n';
  late Directory root;
  late _Client client;
  late NativeFntvService service;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('native-fntv-test-');
    client = _Client();
    service = NativeFntvService(
        client: client, source: source, temporaryDirectory: () async => root);
  });
  tearDown(() async {
    await service.close();
    await root.delete(recursive: true);
  });

  for (final encoding in [utf8, utf16, gbk]) {
    test('normalizes ${encoding.name} to cached UTF-8 and cleans on close',
        () async {
      client.download = () async => encoding.encode(srt);
      final result = await service.downloadSubtitle(target, 'sub');
      final file = File(result['path'] as String);
      expect(await file.readAsString(), srt);
      expect(file.path, endsWith('.srt'));
      await service.close();
      expect(await file.exists(), isFalse);
    });
  }
  test('downloads selected ZIP entry without extracting archive paths',
      () async {
    client.download = () async => ZipEncoder().encode(Archive()
      ..addFile(ArchiveFile.string('../en.srt', 'not selected'))
      ..addFile(ArchiveFile.bytes('../zh.srt', gbk.encode(srt))));
    final result = await service.downloadSubtitle(target, 'sub');
    expect(await File(result['path'] as String).readAsString(), srt);
    expect(await File('${root.path}/zh.srt').exists(), isFalse);
  });
  test('rejects invalid, empty and bitmap-only archives', () async {
    for (final bytes in [
      <int>[],
      utf8.encode('<html>error</html>'),
      ZipEncoder()
          .encode(Archive()..addFile(ArchiveFile.bytes('sub.sup', [1, 2])))
    ]) {
      client.download = () async => bytes;
      await expectLater(service.downloadSubtitle(target, 'sub'),
          throwsA(isA<SubtitleContentException>()));
    }
    expect(await root.list().isEmpty, isTrue);
  });
  test('rejects bitmap stream and another source before download', () async {
    await expectLater(
        service.downloadSubtitle(
            target.copyWith(subtitleStreams: const [
              PlaybackSubtitleStream(id: 'sub', isExternal: true, codec: 'pgs'),
            ]),
            'sub'),
        throwsA(isA<SubtitleContentException>()));
    await expectLater(
        service.downloadSubtitle(target.copyWith(sourceId: 'other'), 'sub'),
        throwsStateError);
    expect(client.calls, 0);
  });
  test('closing during download prevents late cached files', () async {
    final pending = Completer<List<int>>();
    client.download = () => pending.future;
    final result = service.downloadSubtitle(target, 'sub');
    await service.close();
    pending.complete(utf8.encode(srt));
    await expectLater(result, throwsStateError);
    expect(await root.list().isEmpty, isTrue);
  });
}
