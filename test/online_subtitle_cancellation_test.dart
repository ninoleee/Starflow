import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/playback/data/online_subtitle_provider_protocol.dart';
import 'package:starflow/features/playback/data/online_subtitle_repository_io.dart';
import 'package:starflow/features/playback/data/online_subtitle_validation_pipeline.dart';
import 'package:starflow/features/playback/domain/online_subtitle_structured_models.dart';
import 'package:starflow/features/playback/domain/subtitle_operation.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

const _hit = ProviderSubtitleHit(
    id: 'file',
    source: OnlineSubtitleSource.assrt,
    providerLabel: 'ASSRT',
    title: 'Show',
    downloadUrl: 'https://example.com/show.srt',
    packageName: 'Show.srt',
    packageKind: SubtitlePackageKind.subtitleFile);
const _srt = '1\n00:00:01,000 --> 00:00:02,000\nSubtitle';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cancel interrupts a stalled body and keeps the shared client open',
      () async {
    final client = _StalledClient();
    final operation = SubtitleOperation();
    final pending =
        downloadSubtitleBytes(client, _hit.downloadUrl, operation: operation);
    final check =
        expectLater(pending, throwsA(isA<SubtitleOperationCancelled>()));
    await client.started.future;
    operation.cancel();
    await check.timeout(const Duration(seconds: 2));
    await client.aborted.future.timeout(const Duration(seconds: 2));
    expect(client.bodyCancelled, isTrue);
    expect(client.closed, isFalse);
    client.close();
  });

  test('provider cancellation interrupts headers without another query',
      () async {
    final client = _StalledClient(stallHeaders: true);
    final operation = SubtitleOperation();
    final pending = AssrtStructuredProvider(client,
            config: const AssrtProviderConfig(enabled: true, token: 'token'),
            operation: operation)
        .search(const OnlineSubtitleSearchRequest(title: 'Show'));
    final check =
        expectLater(pending, throwsA(isA<http.RequestAbortedException>()));
    await client.started.future;
    operation.cancel();
    await check.timeout(const Duration(seconds: 2));
    expect(client.requests, 1);
    expect(client.closed, isFalse);
    // A transport ignoring abort must still have its late body cancelled.
    client.headers.complete(http.StreamedResponse(client.body.stream, 200));
    await Future<void>.delayed(Duration.zero);
    expect(client.bodyCancelled, isTrue);
    client.close();
  });

  test('cancellation after decode does not create an unaccepted bucket',
      () async {
    final root = await Directory.systemTemp.createTemp('subtitle-cancel-');
    addTearDown(() => root.delete(recursive: true));
    final entered = Completer<void>();
    final directory = Completer<Directory>();
    final operation = SubtitleOperation();
    final pipeline = SubtitleValidationPipeline(
        MockClient((_) async => http.Response(_srt, 200)),
        cacheDirectoryProvider: () {
      entered.complete();
      return directory.future;
    });
    final pending = pipeline.validateHit(_hit, operation: operation);
    final check =
        expectLater(pending, throwsA(isA<SubtitleOperationCancelled>()));
    await entered.future;
    operation.cancel();
    directory.complete(root);
    await check;
    expect(await root.list().isEmpty, isTrue);
  });

  test('cancelled download never starts network or decode', () async {
    var calls = 0;
    final operation = SubtitleOperation()..cancel();
    final pipeline = SubtitleValidationPipeline(MockClient((_) async {
      calls++;
      return http.Response(_srt, 200);
    }));
    await expectLater(pipeline.validateHit(_hit, operation: operation),
        throwsA(isA<SubtitleOperationCancelled>()));
    expect(calls, 0);
  });

  test('cancellation during bucket creation deletes the late bucket', () async {
    final root = await Directory.systemTemp.createTemp('subtitle-late-bucket-');
    addTearDown(() => root.delete(recursive: true));
    final operation = SubtitleOperation();
    final pipeline = SubtitleValidationPipeline(
        MockClient((_) async => http.Response(_srt, 200)),
        cacheDirectoryProvider: () async =>
            _CancelOnCreateTemp(root, operation));
    await expectLater(pipeline.validateHit(_hit, operation: operation),
        throwsA(isA<SubtitleOperationCancelled>()));
    expect(await root.list().isEmpty, isTrue);
  });

  test('discard is idempotent and preserves another accepted download',
      () async {
    final root = await Directory.systemTemp.createTemp('subtitle-discard-');
    addTearDown(() => root.delete(recursive: true));
    final repository = AssrtSubtitleRepository(
        MockClient((_) async => http.Response(_srt, 200)),
        settingsProvider: () => AppSettings.fromJson({}),
        temporaryDirectoryProvider: () async => root);
    final discarded = await repository.download(_hit.toSearchResult());
    final accepted = await repository.download(_hit.toSearchResult());
    await discarded.discard!();
    await discarded.discard!();
    expect(await Directory(discarded.cachedPath).exists(), isFalse);
    expect(await File(accepted.subtitleFilePath!).readAsString(), _srt);
  });

  test('OpenSubtitles cancellation does not poison another in-flight login',
      () async {
    final stalled = _StalledClient();
    final operation = SubtitleOperation();
    const config = OpenSubtitlesProviderConfig(
        enabled: true,
        apiKey: 'cancel-isolation',
        username: 'cancel-isolation',
        password: 'test');
    final pending = OpenSubtitlesStructuredProvider(stalled,
            config: config, operation: operation)
        .resolveDownloadUrl(1);
    final check =
        expectLater(pending, throwsA(isA<http.RequestAbortedException>()));
    await stalled.started.future;
    final other = OpenSubtitlesStructuredProvider(
        MockClient((request) async => http.Response(
            jsonEncode(request.url.path.endsWith('/login')
                ? {'token': 'ready'}
                : {'link': 'https://example.com/accepted.srt'}),
            200)),
        config: config);
    operation.cancel();
    expect(
        await other.resolveDownloadUrl(2), 'https://example.com/accepted.srt');
    await check;
    stalled.close();
  });
}

class _CancelOnCreateTemp implements Directory {
  _CancelOnCreateTemp(this.inner, this.operation);
  final Directory inner;
  final SubtitleOperation operation;

  @override
  Future<Directory> create({bool recursive = false}) =>
      inner.create(recursive: recursive);

  @override
  Future<Directory> createTemp([String? prefix]) async {
    final bucket = await inner.createTemp(prefix);
    operation.cancel();
    return bucket;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StalledClient extends http.BaseClient {
  _StalledClient({this.stallHeaders = false}) {
    body = StreamController<List<int>>(onCancel: () => bodyCancelled = true);
  }
  final bool stallHeaders;
  final started = Completer<void>();
  final aborted = Completer<void>();
  final headers = Completer<http.StreamedResponse>();
  late final StreamController<List<int>> body;
  bool closed = false;
  bool bodyCancelled = false;
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    expect(request, isA<http.Abortable>());
    unawaited((request as http.Abortable).abortTrigger!.then((_) {
      if (!aborted.isCompleted) aborted.complete();
    }));
    started.complete();
    if (stallHeaders) return headers.future;
    return http.StreamedResponse(body.stream, 200);
  }

  @override
  void close() {
    closed = true;
    unawaited(body.close());
  }
}
