import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/search/data/smart_strm_webhook_client.dart';
import 'package:starflow/features/search/application/aliyun_to115_workflow.dart';
import 'package:starflow/features/search/application/aliyun_sync_delete_service.dart';
import 'package:starflow/features/search/application/cloud115_save_workflow_service.dart';
import 'package:starflow/features/search/data/aliyun_transfer_client.dart';
import 'package:starflow/features/search/data/cloud115_instant_upload_client.dart';
import 'package:starflow/features/search/data/cloud115_save_client.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/search/domain/cloud_save_feedback.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/search/data/aliyun_transfer_journal.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';

class _MemoryStore extends Fake implements PreferencesStore {
  final values = <String, String>{};
  bool failWrite = false;
  @override
  Future<String?> getString(String key) async => values[key];
  @override
  Future<void> setString(String key, String value) async {
    if (failWrite) throw StateError('disk full');
    values[key] = value;
  }
}

const _config =
    NetworkStorageConfig(aliyunRefreshToken: 'token', cloud115Cookie: 'cookie');
final _hash = 'A' * 40;
AliyunTransferFile _file(String id) => AliyunTransferFile(
    id: id,
    name: '$id.mkv',
    parentId: 'root',
    isDirectory: false,
    size: 4,
    sha1: _hash);

class _Ali extends Fake implements AliyunTransferClient {
  final events = <String>[];
  bool failCleanup = false;
  bool failCopy = false;
  String userId = 'user';
  List<AliyunTransferFile>? tree;
  final parents = <String>[];
  final owned = <String, List<AliyunTransferFile>>{};
  @override
  Future<void> recycleOwned(
      AliyunTransferSession session, String parentId, List<String> ids) async {
    events.add('recycle:$parentId:${ids.join(',')}');
    owned[parentId]?.removeWhere((e) => ids.contains(e.id));
  }

  @override
  Future<List<AliyunTransferFile>> listOwned(
          AliyunTransferSession session, String parentId) async =>
      owned[parentId] ?? [];
  @override
  Future<String> shareToken(AliyunShareLink link) async => 'share';
  @override
  Future<List<AliyunTransferFile>> listSharedTree(
          AliyunShareLink link, String token) async =>
      tree ?? [_file('one'), _file('two')];
  @override
  Future<String> createSaveDirectory(
      AliyunTransferSession session, String parentId, String name) async {
    events.add('mkdir:$parentId');
    return parentId == 'root' ? 'savedRoot' : 'savedChild';
  }

  @override
  Future<AliyunTransferSession> login(String refreshToken,
      {required Future<void> Function(String) persistToken,
      bool open = false}) async {
    await persistToken('rotated');
    return AliyunTransferSession(
        userId: userId,
        accessToken: 'access',
        driveId: 'drive',
        deviceId: 'device',
        signature: 'sig');
  }

  @override
  Future<String> createStagingFolder(
          AliyunTransferSession session, String name) async =>
      'staging';
  @override
  Future<AliyunTransferFile> stageFile(
      AliyunTransferSession session,
      AliyunShareLink link,
      String token,
      String stagingId,
      AliyunTransferFile source) async {
    events.add('stage:${source.id}');
    parents.add(stagingId);
    if (failCopy) throw const QuarkSaveException('copy failed');
    final copy = AliyunTransferFile(
        id: 'copy${source.id}',
        name: source.name,
        parentId: stagingId,
        isDirectory: false,
        size: source.size,
        sha1: source.sha1.isEmpty ? _hash : source.sha1);
    owned.putIfAbsent(stagingId, () => []).add(copy);
    return copy;
  }

  @override
  Future<void> recycleStagedFile(AliyunTransferSession session,
      String stagingId, AliyunTransferFile expected) async {
    events.add('delete:${expected.id}');
    if (failCleanup) throw const QuarkSaveException('cleanup failed');
    expect(expected.parentId, stagingId);
    expect(expected.id.startsWith('copy'), isTrue);
    owned[stagingId]?.removeWhere((f) => f.id == expected.id);
  }
}

class _Upload extends Fake implements Cloud115InstantUploadClient {
  int accountCalls = 0;
  final names = <String>[];
  final targets = <String>[];
  final sha1s = <String>[];
  String? miss;
  String? fail;
  void Function()? onUpload;
  @override
  Future<Cloud115UploadAccount> account(String cookie) async {
    accountCalls++;
    return const Cloud115UploadAccount('1', 'key', 100);
  }

  @override
  Future<bool> upload(
      {required String cookie,
      required Cloud115UploadAccount account,
      required String parentId,
      required String name,
      required int size,
      required String fileSha1,
      required Future<Uint8List> Function(int, int) readRange}) async {
    names.add(name);
    sha1s.add(fileSha1);
    onUpload?.call();
    targets.add(parentId);
    if (fail == name) throw const QuarkSaveException('unconfirmed');
    return miss != name;
  }
}

class _Destination extends Fake implements Cloud115SaveClient {
  final List<String> events;
  _Destination(this.events);
  bool verified = true;
  bool collision = false;
  final owned = <String, List<QuarkFileEntry>>{};
  @override
  Future<List<QuarkFileEntry>> listEntries(
          {required String cookie,
          String parentFid = '0',
          String parentPath = '/'}) async =>
      collision
          ? [
              const QuarkFileEntry(
                  fid: 'existing',
                  name: 'one.mkv',
                  path: '/one.mkv',
                  isDirectory: false,
                  extension: 'mkv'),
            ]
          : owned[parentFid] ?? [];
  @override
  Future<bool> verifyTransferredFile(
      {required String cookie,
      required String parentId,
      required String name,
      required int size,
      required String sha1}) async {
    events.add('verify:$name');
    return verified;
  }
}

class _Post extends Fake implements Cloud115SaveWorkflowService {
  int calls = 0;
  NetworkStorageConfig? usedConfig;
  @override
  Future<String> finishSavedResult(
      {required Cloud115SaveResult result,
      required NetworkStorageConfig config,
      CloudSaveProgressCallback? onProgress,
      void Function(String)? onBackgroundRefreshFailure}) async {
    calls++;
    usedConfig = config;
    return 'saved ${result.savedCount}';
  }
}

void main() {
  late _Ali ali;
  late _Upload upload;
  late _Destination dest;
  late _Post post;
  late AliyunTo115Workflow workflow;
  setUp(() {
    ali = _Ali();
    upload = _Upload();
    dest = _Destination(ali.events);
    post = _Post();
    workflow = AliyunTo115Workflow(
        aliyun: ali,
        upload: upload,
        destination: dest,
        postprocessing: post,
        persistToken: (previous, next) async {
          expect(previous, 'token');
          expect(next, 'rotated');
        });
  });
  Future<String> run({bool delete = true}) => workflow.save(
      shareUrl: 'https://alipan.com/s/abc',
      password: '',
      config: _config,
      saveFolderName: '',
      deleteAliyunCopies: delete);

  AliyunTransferJournal enableJournal(_MemoryStore store) {
    final journal = AliyunTransferJournal(preferences: store);
    workflow = AliyunTo115Workflow(
        aliyun: ali,
        upload: upload,
        destination: dest,
        postprocessing: post,
        journal: journal,
        persistToken: (_, __) async {});
    return journal;
  }

  test('shared file without list SHA1 uploads using the owned copy hash',
      () async {
    ali.tree = [_file('one').withSha1('')];
    await run();
    expect(ali.events, contains('stage:one'));
    expect(upload.names, ['one.mkv']);
    expect(upload.sha1s, [_hash]);
  });

  test('hashless shared entries resume using the persisted owned copy SHA1',
      () async {
    final store = _MemoryStore();
    final journal = enableJournal(store);
    ali.tree = [_file('one').withSha1('')];
    upload.miss = 'one.mkv';
    await expectLater(run(), throwsA(isA<QuarkSaveException>()));
    final id = (await journal.list()).single['id'] as String;
    upload.miss = null;
    enableJournal(store);
    await workflow.resume(id, _config);
    expect(ali.events.where((e) => e.startsWith('stage:')), ['stage:one']);
    expect(
        ali.events.where((e) => e.startsWith('delete:')), ['delete:copyone']);
    expect(upload.sha1s, [_hash, _hash]);
  });

  test('hashless entries can recover an uncertain upload only if target exists',
      () async {
    final journal = enableJournal(_MemoryStore());
    ali.tree = [_file('one').withSha1('')];
    upload.fail = 'one.mkv';
    await expectLater(run(), throwsA(isA<QuarkSaveException>()));
    final id = (await journal.list()).single['id'] as String;
    upload.fail = null;
    await expectLater(
        workflow.resume(id, _config),
        throwsA(isA<QuarkSaveException>()
            .having((e) => e.message, 'message', contains('未重复提交'))));
    expect(upload.names, ['one.mkv']);
    dest.owned['0'] = [
      const QuarkFileEntry(
          fid: 'one',
          name: 'one.mkv',
          path: '/one.mkv',
          isDirectory: false,
          extension: 'mkv')
    ];
    await workflow.resume(id, _config);
    expect(upload.names, ['one.mkv']);
    expect(
        ali.events.where((e) => e.startsWith('delete:')), ['delete:copyone']);
  });

  test('hashless cleanup-only reuses receipts even after copies were cleaned',
      () async {
    final journal = enableJournal(_MemoryStore());
    ali.tree = [_file('one').withSha1('')];
    await run(delete: false);
    final id = (await journal.list()).single['id'] as String;
    dest.owned['0'] = [
      const QuarkFileEntry(
          fid: 'one',
          name: 'one.mkv',
          path: '/one.mkv',
          isDirectory: false,
          extension: 'mkv')
    ];
    await workflow.resume(id, _config, cleanupOnly: true);
    await workflow.resume(id, _config, cleanupOnly: true);
    expect(upload.names, ['one.mkv']);
    expect(ali.events.where((e) => e.startsWith('stage:')), ['stage:one']);
    expect(
        ali.events.where((e) => e.startsWith('delete:')), ['delete:copyone']);
    expect(post.calls, 1);
  });

  for (final change in ['hash', 'parent', 'size']) {
    test('hashless resume refuses invalid persisted copy $change', () async {
      final journal = enableJournal(_MemoryStore());
      ali.tree = [_file('one').withSha1('')];
      upload.miss = 'one.mkv';
      await expectLater(run(), throwsA(isA<QuarkSaveException>()));
      final record = (await journal.list()).single;
      final copy = ((record['files'] as Map)['one'] as Map)['copy'] as Map;
      switch (change) {
        case 'hash':
          copy['content_hash'] = '';
        case 'parent':
          copy['parent_file_id'] = 'other';
        case 'size':
          copy['size'] = 8;
      }
      await journal.put(record);
      await expectLater(workflow.resume(record['id'] as String, _config),
          throwsA(isA<QuarkSaveException>()));
      expect(upload.names, ['one.mkv']);
      expect(ali.events.where((e) => e.startsWith('delete:')), isEmpty);
    });
  }

  test('persisted resume reuses copies and verifies destination before cleanup',
      () async {
    final store = _MemoryStore();
    final journal = enableJournal(store);
    upload.miss = 'two.mkv';
    await expectLater(run(), throwsA(isA<QuarkSaveException>()));
    final record = (await journal.list()).single;
    expect(record['stage'], '待恢复');
    expect(ali.events.where((e) => e.startsWith('delete:')), isEmpty);
    upload.miss = null;
    dest.owned['0'] = [
      const QuarkFileEntry(
          fid: 'one',
          name: 'one.mkv',
          path: '/one.mkv',
          isDirectory: false,
          extension: 'mkv')
    ];
    enableJournal(store);
    await workflow.resume(record['id'] as String, _config);
    expect(ali.events.where((e) => e.startsWith('stage:')).length, 2);
    expect(ali.events.where((e) => e.startsWith('delete:')).length, 2);
    expect((await journal.list()).single['stage'], '已完成');
    expect(store.values.values.single, isNot(contains('cloud115Cookie')));
    expect(store.values.values.single, isNot(contains('aliyunRefreshToken')));
  });

  test('recovery refuses different accounts before touching staged files',
      () async {
    final journal = enableJournal(_MemoryStore());
    upload.miss = 'two.mkv';
    await expectLater(run(), throwsA(isA<QuarkSaveException>()));
    ali.userId = 'other';
    final id = (await journal.list()).single['id'] as String;
    final count = ali.events.length;
    await expectLater(
        workflow.resume(id, _config), throwsA(isA<QuarkSaveException>()));
    expect(ali.events.length, count);
  });

  test(
      'uncertain copy intent is never replayed and disk failure prevents mutations',
      () async {
    final store = _MemoryStore();
    final journal = enableJournal(store);
    ali.failCopy = true;
    await expectLater(run(), throwsA(isA<QuarkSaveException>()));
    ali.failCopy = false;
    final id = (await journal.list()).single['id'] as String;
    await expectLater(
        workflow.resume(id, _config), throwsA(isA<QuarkSaveException>()));
    expect(ali.events.where((e) => e.startsWith('stage:')).length, 1);
    store.failWrite = true;
    await expectLater(run(), throwsA(anything));
    expect(ali.events.where((e) => e.startsWith('stage:')).length, 1);
    expect(workflow.isRunning, isFalse);
  });

  test('cleanup-only verifies whole batch and never uploads or copies',
      () async {
    final journal = enableJournal(_MemoryStore());
    await run(delete: false);
    final id = (await journal.list()).single['id'] as String;
    dest.owned['0'] = [
      for (final name in ['one', 'two'])
        QuarkFileEntry(
            fid: name,
            name: '$name.mkv',
            path: '/$name.mkv',
            isDirectory: false,
            extension: 'mkv')
    ];
    dest.verified = false;
    await expectLater(workflow.resume(id, _config, cleanupOnly: true),
        throwsA(isA<QuarkSaveException>()));
    expect(ali.events.where((e) => e.startsWith('delete:')), isEmpty);
    dest.verified = true;
    await workflow.resume(id, _config, cleanupOnly: true);
    expect(ali.events.where((e) => e.startsWith('stage:')).length, 2);
    expect(upload.names.length, 2);
    expect(ali.events.where((e) => e.startsWith('delete:')).length, 2);
    expect(post.calls, 1);
  });

  test(
      'stop finishes current request then preserves copies without further mutations',
      () async {
    final journal = enableJournal(_MemoryStore());
    upload.onUpload = workflow.requestStop;
    await expectLater(run(), throwsA(isA<QuarkSaveException>()));
    expect(upload.names.length, 1);
    expect(ali.events.where((e) => e.startsWith('stage:')).length, 1);
    expect(ali.events.where((e) => e.startsWith('delete:')), isEmpty);
    expect((await journal.list()).single['stage'], '已停止');
    expect(workflow.isRunning, isFalse);
  });

  test(
      'transfer inherits destination common rules and suppresses a second rename pass',
      () async {
    ali.tree = [
      AliyunTransferFile(
          id: 'one',
          name: 'one#?.mkv',
          parentId: 'root',
          isDirectory: false,
          size: 4,
          sha1: _hash)
    ];
    await workflow.save(
        shareUrl: 'https://alipan.com/s/abc',
        password: '',
        config: _config.copyWith(
            commonSanitizeSavedNamesEnabled: true,
            commonSanitizedNameCharacters: '#'),
        saveFolderName: '');
    expect(upload.names, ['one?.mkv']);
    expect(post.usedConfig!.effective115NameCharacters, isEmpty);
    expect(post.usedConfig!.commonSanitizeSavedNamesEnabled, isFalse);
  });

  test('Aliyun save and update preview share inherited rules', () async {
    ali.tree = [
      AliyunTransferFile(
          id: 'one',
          name: 'one#.mkv',
          parentId: 'root',
          isDirectory: false,
          size: 4,
          sha1: _hash)
    ];
    ali.owned['root'] = [_file('one')];
    final config = _config.copyWith(
        commonSanitizeSavedNamesEnabled: true,
        commonSanitizedNameCharacters: '#');
    final preview = await workflow.preview(
        shareUrl: 'https://alipan.com/s/abc',
        password: '',
        config: config,
        saveFolderName: '');
    expect(preview.missingVideos, isEmpty);
    final result = await workflow.saveToAliyun(
        shareUrl: 'https://alipan.com/s/abc',
        password: '',
        config: config,
        saveFolderName: '');
    expect(result, contains('略过 1 个'));
    expect(ali.events, isEmpty);
  });

  test('115 transfer uses common name settings and destination folder/task',
      () async {
    ali.tree = [
      AliyunTransferFile(
          id: 'one',
          name: 'one#?.mkv',
          parentId: 'root',
          isDirectory: false,
          size: 4,
          sha1: _hash)
    ];
    await workflow.save(
        shareUrl: 'https://alipan.com/s/abc',
        password: '',
        config: _config.copyWith(
            aliyunSaveFolderId: 'aliFolder',
            cloud115SaveFolderId: '123',
            commonSanitizeSavedNamesEnabled: true,
            commonSanitizedNameCharacters: '#',
            aliyunSmartStrmTaskName: 'ali',
            cloud115SmartStrmTaskName: '115'),
        saveFolderName: '');
    expect(upload.names, ['one?.mkv']);
    expect(upload.targets, ['123']);
    expect(post.usedConfig!.cloud115SmartStrmTaskName, '115');
    expect(post.usedConfig!.cloud115SanitizeSavedNamesEnabled, isFalse);
  });

  for (final to115 in [false, true]) {
    test('preview reads only the selected destination: $to115', () async {
      ali.tree = [
        const AliyunTransferFile(
            id: 'season', name: 'Season', parentId: 'root', isDirectory: true),
        AliyunTransferFile(
            id: 'one',
            name: 'one.mkv',
            parentId: 'season',
            isDirectory: false,
            size: 4,
            sha1: _hash,
            path: const ['Season']),
      ];
      ali.owned['aliRoot'] = [
        const AliyunTransferFile(
            id: 'localSeason',
            name: 'Season',
            parentId: 'aliRoot',
            isDirectory: true)
      ];
      ali.owned['localSeason'] = [_file('one')];
      dest.owned['123'] = [
        const QuarkFileEntry(
            fid: '234',
            name: 'Season',
            path: '/Season',
            isDirectory: true,
            extension: '')
      ];
      dest.owned['234'] = [
        const QuarkFileEntry(
            fid: '345',
            name: 'one.mkv',
            path: '/Season/one.mkv',
            isDirectory: false,
            extension: 'mkv')
      ];
      final preview = await workflow.preview(
          shareUrl: 'https://alipan.com/s/abc',
          password: '',
          config: _config.copyWith(
              aliyunTo115Enabled: to115,
              aliyunSaveFolderId: 'aliRoot',
              aliyunSaveFolderPath: '/Ali',
              cloud115SaveFolderId: '123',
              cloud115SaveFolderPath: '/115'),
          saveFolderName: to115 ? '115' : 'Ali');
      expect(preview.targetFolderPath, to115 ? '/115' : '/Ali');
      expect(preview.onlineEntries.map((e) => e.relativePath),
          ['Season', 'Season/one.mkv']);
      expect(preview.missingVideos, isEmpty);
      expect(ali.events, isEmpty);
    });
  }

  test(
      'standalone skips identical files and refuses different same-name content',
      () async {
    ali.tree = [_file('one')];
    ali.owned['root'] = [_file('one')];
    final result = await workflow.saveToAliyun(
        shareUrl: 'https://alipan.com/s/abc',
        password: '',
        config: _config,
        saveFolderName: '');
    expect(result, contains('略过 1 个'));
    expect(ali.events, isEmpty);
    ali.owned['root'] = [
      AliyunTransferFile(
          id: 'old',
          name: 'one.mkv',
          parentId: 'root',
          isDirectory: false,
          size: 8,
          sha1: _hash)
    ];
    await expectLater(
        workflow.saveToAliyun(
            shareUrl: 'https://alipan.com/s/abc',
            password: '',
            config: _config,
            saveFolderName: ''),
        throwsA(isA<QuarkSaveException>()));
    expect(ali.events, isEmpty);
  });

  group('Aliyun sync deletion', () {
    const scope = NetworkStorageWebDavDirectory(
        sourceId: 'nas', directoryId: 'https://dav.test/ali');
    final config = _config.copyWith(
        syncDeleteAliyunEnabled: true,
        syncDeleteAliyunWebDavDirectories: [scope]);
    Future<AliyunDeletePlan?> prepare(NetworkStorageConfig c, String path) =>
        AliyunSyncDeleteService(workflow)
            .prepare(config: c, sourceId: 'nas', resourcePath: path);

    test('disabled in transfer mode; outside scopes never connects', () async {
      expect(
          await prepare(config.copyWith(aliyunTo115Enabled: true),
              'https://dav.test/ali/one.strm'),
          isNull);
      expect(await prepare(config, 'https://dav.test/other/one.strm'), isNull);
    });
    test(
        'missing scope, root deletion and overlapping destinations are rejected',
        () async {
      for (final c in [
        config.copyWith(syncDeleteAliyunWebDavDirectories: []),
        config.copyWith(
            syncDelete115Enabled: true, syncDelete115WebDavDirectories: [scope])
      ]) {
        await expectLater(prepare(c, 'https://dav.test/ali/one.strm'),
            throwsA(isA<QuarkSaveException>()));
      }
      await expectLater(prepare(config, 'https://dav.test/ali'),
          throwsA(isA<QuarkSaveException>()));
    });
    test('maps STRM to a unique video and rejects ambiguous extensions',
        () async {
      ali.owned['root'] = [_file('one')];
      final plan = await prepare(config, 'https://dav.test/ali/one.strm');
      expect(plan!.entry.id, 'one');
      ali.owned['root']!.add(AliyunTransferFile(
          id: 'other',
          name: 'one.mp4',
          parentId: 'root',
          isDirectory: false,
          size: 4,
          sha1: _hash));
      await expectLater(prepare(config, 'https://dav.test/ali/one.strm'),
          throwsA(isA<QuarkSaveException>()));
    });
    test('changed identity blocks deletion', () async {
      ali.owned['root'] = [_file('one')];
      final service = AliyunSyncDeleteService(workflow);
      final plan = await prepare(config, 'https://dav.test/ali/one.strm');
      ali.owned['root'] = [];
      await expectLater(
          service.execute(plan!), throwsA(isA<QuarkSaveException>()));
    });
    test('confirmed plan recycles only the matched file', () async {
      ali.owned['root'] = [_file('one'), _file('two')];
      final plan = await prepare(config, 'https://dav.test/ali/one.strm');
      await AliyunSyncDeleteService(workflow).execute(plan!);
      expect(ali.events, ['recycle:root:one']);
      expect(ali.owned['root']!.single.id, 'two');
    });
  });

  test(
      'standalone Aliyun save preserves nested structure without 115 or cleanup',
      () async {
    ali.tree = [
      const AliyunTransferFile(
          id: 'folder', name: 'Season', parentId: 'root', isDirectory: true),
      AliyunTransferFile(
          id: 'one',
          name: 'one.mkv',
          parentId: 'folder',
          isDirectory: false,
          size: 4,
          sha1: _hash,
          path: const ['Season']),
    ];
    final result = await workflow.saveToAliyun(
        shareUrl: 'https://alipan.com/s/abc',
        password: '',
        config: _config.copyWith(cloud115Cookie: ''),
        saveFolderName: 'Show');
    expect(result, contains('已保存到阿里'));
    expect(result, contains('/Show'));
    expect(ali.parents, ['savedChild']);
    expect(upload.accountCalls, 0);
    expect(ali.events, ['mkdir:root', 'mkdir:savedRoot', 'stage:one']);
    expect(post.calls, 0);
  });

  test('standalone postprocessing uses Aliyun task and shared refresh settings',
      () async {
    final refreshed = <String>[];
    final smartStrm = <String>[];
    final standalone = AliyunTo115Workflow(
        aliyun: ali,
        upload: upload,
        destination: dest,
        postprocessing: Cloud115SaveWorkflowService(dest, (ids, delay) async {
          refreshed.addAll(ids);
          expect(delay, 3);
        }, smartStrm: SmartStrmWebhookClient(MockClient((request) async {
          smartStrm.add(request.body);
          return http.Response('{"success":true}', 200);
        }))),
        persistToken: (_, __) async {});
    await standalone.saveToAliyun(
        shareUrl: 'https://alipan.com/s/abc',
        password: '',
        config: _config.copyWith(
            aliyunSmartStrmTaskName: 'ali-task',
            cloud115SmartStrmTaskName: '115-task',
            smartStrmWebhookUrl: 'https://strm.test/webhook',
            refreshMediaSourceIds: ['nas'],
            refreshDelaySeconds: 3),
        saveFolderName: 'Show');
    await Future<void>.delayed(Duration.zero);
    expect(smartStrm.single, contains('ali-task'));
    expect(smartStrm.single, isNot(contains('115-task')));
    expect(refreshed, ['nas']);
    expect(upload.accountCalls, 0);
  });

  test('standalone save failure retains files without any deletion', () async {
    ali.failCopy = true;
    await expectLater(
        workflow.saveToAliyun(
            shareUrl: 'https://alipan.com/s/abc',
            password: '',
            config: _config,
            saveFolderName: 'Show'),
        throwsA(isA<QuarkSaveException>()));
    expect(ali.events.where((e) => e.startsWith('delete:')), isEmpty);
    expect(post.calls, 0);
  });

  test('only deletes staged IDs after every destination is verified twice',
      () async {
    final result = await run();
    expect(result, contains('已移入回收站 2 个'));
    expect(ali.events, [
      'stage:one',
      'verify:one.mkv',
      'stage:two',
      'verify:two.mkv',
      'verify:one.mkv',
      'verify:two.mkv',
      'delete:copyone',
      'delete:copytwo'
    ]);
    expect(post.calls, 1);
  });
  test('retains copies when cleanup is not opted into', () async {
    await run(delete: false);
    expect(ali.events.where((e) => e.startsWith('delete')), isEmpty);
  });
  test(
      'partial instant miss retains ALL staged copies and skips postprocessing',
      () async {
    upload.miss = 'two.mkv';
    await expectLater(run(), throwsA(isA<QuarkSaveException>()));
    expect(ali.events.where((e) => e.startsWith('delete')), isEmpty);
    expect(post.calls, 0);
  });
  test('ambiguous second upload never cleans first copy', () async {
    upload.fail = 'two.mkv';
    await expectLater(run(), throwsA(isA<QuarkSaveException>()));
    expect(ali.events.where((e) => e.startsWith('delete')), isEmpty);
  });
  test('unverified destination prevents cleanup', () async {
    dest.verified = false;
    await expectLater(run(), throwsA(isA<QuarkSaveException>()));
    expect(ali.events.where((e) => e.startsWith('delete')), isEmpty);
  });
  test('different same-name file is not overwritten', () async {
    dest.collision = true;
    dest.verified = false;
    await expectLater(run(), throwsA(isA<QuarkSaveException>()));
    expect(ali.events.where((e) => e.startsWith('stage')), isEmpty);
  });
  test('cleanup failure is a warning, does not retry deletion', () async {
    ali.failCleanup = true;
    final result = await run();
    expect(result, contains('清理未全部确认'));
    expect(ali.events.where((e) => e.startsWith('delete')).length, 1);
    expect(post.calls, 1);
  });
}
