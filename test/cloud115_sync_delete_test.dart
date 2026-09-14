import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/search/application/cloud115_sync_delete_service.dart';
import 'package:starflow/features/search/data/cloud115_save_client.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

const scope = NetworkStorageWebDavDirectory(
    sourceId: 'nas', directoryId: 'https://nas.test/strm/115');
const config = NetworkStorageConfig(
    cloud115Cookie: 'cookie',
    cloud115SaveFolderId: '10',
    syncDelete115Enabled: true,
    syncDelete115WebDavDirectories: [scope]);

void main() {
  test('configuration preserves independent deletion settings', () {
    final restored = NetworkStorageConfig.fromJson(
        config.copyWith(syncDeleteQuarkEnabled: true).toJson());
    expect(restored.syncDelete115Enabled, isTrue);
    expect(restored.syncDelete115WebDavDirectories.single.directoryId,
        scope.directoryId);
    expect(
        restored.copyWith(syncDeleteQuarkEnabled: false).syncDelete115Enabled,
        isTrue);
    expect(NetworkStorageConfig.fromJson({}).syncDelete115Enabled, isFalse);
  });
  test('scope matching respects authority and path segment boundaries', () {
    expect(
        cloud115RelativeDeletePath(
            'https://nas.test/strm/115/Movie/a.strm', scope.directoryId),
        ['Movie', 'a.strm']);
    for (final path in [
      'https://other.test/strm/115/Movie',
      'https://nas.test/strm/115-old/Movie',
      'https://nas.test/strm/115/%2e%2e/Movie',
      'https://nas.test/strm/115/a%2fb'
    ]) {
      expect(cloud115RelativeDeletePath(path, scope.directoryId), isNull);
    }
  });
  test('resolves a single episode and posts only its id to recycle deletion',
      () async {
    final requests = <http.Request>[];
    var deleted = false;
    final client = Cloud115SaveClient(MockClient((request) async {
      requests.add(request);
      if (request.method == 'POST') {
        expect(request.url.path, '/rb/delete');
        expect(
            Uri.splitQueryString(request.body), {'pid': '20', 'fid[0]': '30'});
        deleted = true;
        return http.Response('{"state":true}', 200);
      }
      if (deleted) {
        expect(request.url.queryParameters['cid'], '20');
        return http.Response('{"state":true,"count":0,"data":[]}', 200);
      }
      final root = request.url.queryParameters['cid'] == '10';
      return http.Response(
          jsonEncode({
            'state': true,
            'count': 1,
            'data': [
              root ? {'cid': '20', 'n': 'Show'} : {'fid': '30', 'n': 'E01.mkv'}
            ]
          }),
          200);
    }));
    final service = Cloud115SyncDeleteService(client);
    final plan = await service.prepare(
        config: config,
        sourceId: 'nas',
        resourcePath: '${scope.directoryId}/Show/E01.strm');
    expect(plan!.entry.fid, '30');
    expect(requests.every((r) => r.method == 'GET'), isTrue);
    await service.execute(plan);
    expect(requests.length, 4);
  });
  for (final outcome in ['still-exists', 'read-failed']) {
    test('delete confirmation fails without retrying the write: $outcome',
        () async {
      var writes = 0;
      final client = Cloud115SaveClient(MockClient((request) async {
        if (request.method == 'POST') {
          writes++;
          return http.Response('{"state":true}', 200);
        }
        if (outcome == 'read-failed') return http.Response('', 503);
        return http.Response(
            '{"state":true,"count":1,"data":[{"cid":"20","n":"Show"}]}', 200);
      }));
      await expectLater(
        Cloud115SyncDeleteService(client).execute(const Cloud115DeletePlan(
          cookie: 'cookie',
          parentId: '10',
          entry: QuarkFileEntry(
              fid: '20', name: 'Show', path: '/Show', isDirectory: true),
        )),
        throwsA(isA<QuarkSaveException>()),
      );
      expect(writes, 1);
    });
  }
  test('wrong source and disabled configuration never access the drive',
      () async {
    final service = Cloud115SyncDeleteService(Cloud115SaveClient(
        MockClient((_) async => fail('No network expected'))));
    expect(
        await service.prepare(
            config: config,
            sourceId: 'other',
            resourcePath: '${scope.directoryId}/Movie'),
        isNull);
    expect(
        await service.prepare(
            config: config.copyWith(syncDelete115Enabled: false),
            sourceId: 'nas',
            resourcePath: '${scope.directoryId}/Movie'),
        isNull);
    await expectLater(
        service.prepare(
            config: config, sourceId: 'nas', resourcePath: scope.directoryId),
        throwsA(isA<QuarkSaveException>()));
    await expectLater(
        service.prepare(
            config: config.copyWith(
                syncDeleteQuarkEnabled: true,
                syncDeleteQuarkWebDavDirectories: [scope]),
            sourceId: 'nas',
            resourcePath: '${scope.directoryId}/Movie'),
        throwsA(isA<QuarkSaveException>()));
  });
  for (final directories in [
    <NetworkStorageWebDavDirectory>[],
    [
      const NetworkStorageWebDavDirectory(sourceId: 'nas', directoryId: ' '),
      const NetworkStorageWebDavDirectory(
          sourceId: ' ', directoryId: 'https://nas.test/strm/115'),
    ],
  ]) {
    test('enabled deletion requires a configured scope: ${directories.length}',
        () async {
      final service = Cloud115SyncDeleteService(Cloud115SaveClient(
          MockClient((_) async => fail('No network expected'))));
      final incomplete =
          config.copyWith(syncDelete115WebDavDirectories: directories);
      await expectLater(
        service.prepare(
          config: incomplete,
          sourceId: 'nas',
          resourcePath: '${scope.directoryId}/Movie',
        ),
        throwsA(isA<QuarkSaveException>().having(
          (error) => error.toString(),
          'message',
          contains('未选择 WebDAV 删除监听目录'),
        )),
      );
      expect(
        await service.prepare(
          config: incomplete.copyWith(syncDelete115Enabled: false),
          sourceId: 'nas',
          resourcePath: '${scope.directoryId}/Movie',
        ),
        isNull,
      );
    });
  }
  test('configured scopes still leave unrelated resources outside deletion',
      () async {
    final service = Cloud115SyncDeleteService(Cloud115SaveClient(
        MockClient((_) async => fail('No network expected'))));
    expect(
      await service.prepare(
        config: config,
        sourceId: 'nas',
        resourcePath: 'https://nas.test/strm/other/Movie',
      ),
      isNull,
    );
  });
  for (final rows in [
    <Map<String, String>>[],
    [
      {'fid': '30', 'n': 'E01.mkv'},
      {'fid': '31', 'n': 'E01.mp4'}
    ]
  ]) {
    test('missing or ambiguous target aborts before deletion: ${rows.length}',
        () async {
      final service = Cloud115SyncDeleteService(
          Cloud115SaveClient(MockClient((request) async {
        expect(request.method, 'GET');
        return http.Response(
            jsonEncode({'state': true, 'count': rows.length, 'data': rows}),
            200);
      })));
      await expectLater(
          service.prepare(
              config: config,
              sourceId: 'nas',
              resourcePath: '${scope.directoryId}/E01.strm'),
          throwsA(isA<QuarkSaveException>()));
    });
  }
  test('delete rejects root and current directory without requests', () async {
    final client = Cloud115SaveClient(
        MockClient((_) async => fail('No request expected')));
    for (final id in ['0', '10', '', 'bad']) {
      await expectLater(
          client.deleteEntries(cookie: 'cookie', parentId: '10', fids: [id]),
          throwsA(isA<QuarkSaveException>()));
    }
  });
}
