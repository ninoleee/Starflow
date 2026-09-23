import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/media_detail_page.dart';
import 'package:starflow/features/search/application/cloud115_save_workflow_service.dart';
import 'package:starflow/features/search/application/quark_save_workflow_service.dart';
import 'package:starflow/features/search/data/cloud115_save_client.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/search/data/search_preferences_repository.dart';
import 'package:starflow/features/search/data/smart_strm_webhook_client.dart';
import 'package:starflow/features/search/domain/cloud_save_feedback.dart';
import 'package:starflow/features/search/domain/favorite_sync_document.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

const _target = MediaDetailTarget(
    title: 'Show',
    posterUrl: '',
    overview: '',
    itemType: 'movie',
    searchQuery: 'Show');
const _favorite = SearchResult(
    id: '115',
    title: 'Show',
    posterUrl: '',
    providerId: 'online',
    providerName: 'Online',
    quality: '',
    sizeLabel: '',
    seeders: 0,
    summary: '',
    resourceUrl: 'https://115.com/s/abc',
    password: 'abcd',
    favoriteFolderName: 'Show',
    metadataMediaType: 'movie');

http.Response _response(Object value) => http.Response.bytes(
      utf8.encode(jsonEncode(value)),
      200,
      headers: {'content-type': 'application/json'},
    );

class _Harness {
  _Harness(
      {this.drive = CloudSaveDrive.cloud115,
      this.mixed = false,
      this.noUpdates = false,
      this.missingCookie = false,
      this.tv = false,
      this.delayCheck = false,
      this.delaySave = false,
      this.unconfirmedSave = false,
      this.saveFails = false});

  final CloudSaveDrive drive;
  final bool mixed;
  final bool noUpdates;
  final bool missingCookie;
  final bool tv;
  final bool delayCheck;
  final bool delaySave;
  final bool unconfirmedSave;
  final bool saveFails;
  final pendingCheck = Completer<http.Response>();
  final pendingSave = Completer<void>();
  final navigator = GlobalKey<NavigatorState>();
  final reads = <CloudSaveDrive>[];
  final saves = <CloudSaveDrive>[];
  final strmTasks = <Map>[];
  final refreshes = <String>[];
  bool saved = false;

  String get saveLabel =>
      drive == CloudSaveDrive.cloud115 ? '保存到 115' : '保存到夸克';

  http.Response shareResponse(CloudSaveDrive provider) {
    final is115 = provider == CloudSaveDrive.cloud115;
    return _response(is115
        ? {
            'state': true,
            'data': {
              'count': 2,
              'list': [
                {'fid': '1', 'n': 'E01.mkv'},
                {'fid': '2', 'n': 'E02.mkv'},
              ]
            }
          }
        : {
            'code': 0,
            'metadata': {'_total': 2},
            'data': {
              'list': [
                {
                  'fid': '1',
                  'file_name': 'E01.mkv',
                  'share_fid_token': 'token-1'
                },
                {
                  'fid': '2',
                  'file_name': 'E02.mkv',
                  'share_fid_token': 'token-2'
                },
              ]
            }
          });
  }

  Future<http.Response> request(
      http.Request request, CloudSaveDrive provider) async {
    final is115 = provider == CloudSaveDrive.cloud115;
    expect(request.headers['cookie'], is115 ? '115-cookie' : 'quark-cookie');
    final path = request.url.path;
    if (path.endsWith('/token')) {
      expect(request.method, 'POST');
      expect((jsonDecode(request.body) as Map)['passcode'], 'abcd');
      return _response({
        'code': 0,
        'data': {'stoken': 'token'}
      });
    }
    if (path == '/share/snap' || path.endsWith('/detail')) {
      expect(request.method, 'GET');
      reads.add(provider);
      if (is115) expect(request.url.queryParameters['receive_code'], 'abcd');
      if (delayCheck && reads.length == 1) return pendingCheck.future;
      return shareResponse(provider);
    }
    if (path == '/files' || path.endsWith('/sort')) {
      expect(request.method, 'GET');
      expect(request.url.queryParameters[is115 ? 'cid' : 'pdir_fid'], '42');
      return _response(is115
          ? {
              'state': true,
              'count': saved || noUpdates ? 2 : 1,
              'data': [
                {'fid': '101', 'n': 'E01.mkv'},
                if (saved || noUpdates) {'fid': '102', 'n': 'E02.mkv'},
              ],
            }
          : {
              'code': 0,
              'data': {
                'list': [
                  {'fid': '101', 'file_name': 'E01.mkv'},
                  if (saved || noUpdates)
                    {'fid': '102', 'file_name': 'E02.mkv'},
                ]
              }
            });
    }
    expect(request.method, 'POST');
    expect(
        path, is115 ? '/share/receive' : '/1/clouddrive/share/sharepage/save');
    final body = is115
        ? Uri.splitQueryString(request.body)
        : jsonDecode(request.body) as Map;
    expect(body[is115 ? 'cid' : 'to_pdir_fid'], '42');
    expect(body[is115 ? 'file_id' : 'fid_list'], is115 ? '2' : ['2']);
    if (is115) expect(body['receive_code'], 'abcd');
    saves.add(provider);
    if (delaySave) await pendingSave.future;
    if (unconfirmedSave) throw StateError('unknown transfer outcome');
    if (saveFails) return http.Response('blocked', 405);
    saved = true;
    return _response(is115 ? {'state': true} : {'code': 0});
  }

  Future<void> pump(WidgetTester tester) async {
    final favorites = [
      if (drive == CloudSaveDrive.cloud115 || mixed) _favorite,
      if (drive == CloudSaveDrive.quark || mixed)
        SearchResult.fromJson({
          ..._favorite.toJson(),
          'id': 'quark',
          'resourceUrl': 'https://pan.quark.cn/s/abc'
        }),
    ];
    var favoriteDocument = FavoriteSyncDocument();
    for (final favorite in favorites) {
      favoriteDocument = favoriteDocument.setFavorite(
        searchResultFavoriteKey(favorite),
        favorite,
      );
    }
    SharedPreferences.setMockInitialValues({
      SearchPreferencesRepository.favoriteResultsPreferenceKey:
          favoriteDocument.encode(),
    });
    final store = SharedPreferencesStore(await SharedPreferences.getInstance());
    final preferences = SearchPreferencesRepository(preferences: store);
    final cache = LocalStorageCacheRepository(preferences: store);
    addTearDown(preferences.dispose);
    addTearDown(cache.dispose);
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client115 = Cloud115SaveClient(
        MockClient((r) => request(r, CloudSaveDrive.cloud115)));
    final quark =
        QuarkSaveClient(MockClient((r) => request(r, CloudSaveDrive.quark)));
    final strm = SmartStrmWebhookClient(MockClient((request) async {
      expect(request.headers.containsKey('cookie'), isFalse);
      final body = jsonDecode(request.body) as Map;
      expect(body['event'], 'a_task');
      strmTasks.add(body['task'] as Map);
      return _response({'success': true});
    }));
    Future<void> refresh(List<String> ids, int delay, String path) async {
      expect(ids, ['nas']);
      expect(delay, 5);
      refreshes.add(path);
    }

    final quarkWorkflow = QuarkSaveWorkflowService(
      saveShareLink: quark.saveShareLink,
      sanitizeSavedNames: quark.sanitizeSavedEntries,
      triggerSmartStrm: strm.triggerTask,
      resolveRefreshSourceIds: (
              {required networkStorage, required includeConfiguredSources}) =>
          networkStorage.refreshMediaSourceIds,
      refreshSelectedSources: (
              {required sourceIds,
              required delaySeconds,
              required invalidateWebDavDirectoryCache}) =>
          refresh(sourceIds, delaySeconds, '/quark/Show'),
    );
    final settings = AppSettings.fromJson({
      'mediaSources': const [],
      'searchProviders': const [],
      'homeModules': const [],
      'doubanAccount': const {'enabled': false},
      'tmdbMetadataMatchEnabled': false,
      'wmdbMetadataMatchEnabled': false,
      'imdbRatingMatchEnabled': false,
      'detailAutoLibraryMatchEnabled': false,
    }).copyWith(
        networkStorage: NetworkStorageConfig(
      cloud115Cookie:
          !missingCookie && (mixed || drive == CloudSaveDrive.cloud115)
              ? '115-cookie'
              : '',
      quarkCookie: mixed || (!missingCookie && drive == CloudSaveDrive.quark)
          ? 'quark-cookie'
          : '',
      cloud115SaveFolderId: '42',
      cloud115SaveFolderPath: '/115/Show',
      quarkSaveFolderId: '42',
      quarkSaveFolderPath: '/quark/Show',
      smartStrmWebhookUrl: 'https://strm.test/webhook',
      cloud115SmartStrmTaskName: '115-task',
      smartStrmTaskName: 'quark-task',
      smartStrmDelaySeconds: 3,
      refreshMediaSourceIds: ['nas'],
      refreshDelaySeconds: 5,
    ));
    await tester.pumpWidget(ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => tv),
          appSettingsProvider.overrideWithValue(settings),
          enrichedDetailTargetProvider.overrideWith((ref, target) => target),
          localStorageCacheRepositoryProvider.overrideWithValue(cache),
          searchPreferencesRepositoryProvider.overrideWithValue(preferences),
          cloud115SaveClientProvider.overrideWithValue(client115),
          quarkSaveClientProvider.overrideWithValue(quark),
          cloud115SaveWorkflowProvider.overrideWithValue(
              Cloud115SaveWorkflowService(client115, (ids, delay) async {
            refresh(ids, delay, '/115/Show');
          }, smartStrm: strm)),
          quarkSaveWorkflowServiceProvider.overrideWithValue(quarkWorkflow),
        ],
        child: MaterialApp(
            navigatorKey: navigator,
            theme: ThemeData.dark(),
            home: const MediaDetailPage(target: _target))));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
  }

  Future<void> check(WidgetTester tester) async {
    await tester.scrollUntilVisible(find.text('检查更新'), 250,
        scrollable: find.byType(Scrollable).first);
    if (tv) {
      final action = find.byWidgetPredicate((widget) =>
          widget is TvFocusableAction &&
          widget.focusId == 'detail:resource:check-online-update');
      tester
          .widget<FocusableActionDetector>(find
              .descendant(
                  of: action, matching: find.byType(FocusableActionDetector))
              .first)
          .focusNode!
          .requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    } else {
      await tester.tap(find.text('检查更新'));
    }
    await tester.pumpAndSettle();
  }
}

void main() {
  for (final drive in CloudSaveDrive.values) {
    testWidgets(
        '$drive only writes after confirmation, then uses its STRM task',
        (tester) async {
      final harness = _Harness(drive: drive);
      await harness.pump(tester);
      await harness.check(tester);
      expect(find.text('发现更新'), findsOneWidget);
      expect(tester.widget<SelectableText>(find.byType(SelectableText)).data,
          contains('E02.mkv'));
      expect(harness.saves, isEmpty);
      expect(harness.strmTasks, isEmpty);
      expect(harness.refreshes, isEmpty);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(harness.saves, isEmpty);
      await harness.check(tester);
      await tester.tap(find.text(harness.saveLabel));
      await tester.pumpAndSettle();
      expect(harness.saves, [drive]);
      expect(harness.strmTasks, [
        {
          'name': drive == CloudSaveDrive.cloud115 ? '115-task' : 'quark-task',
          'storage_path':
              drive == CloudSaveDrive.cloud115 ? '/115/Show' : '/quark/Show',
        }
      ]);
      expect(harness.refreshes,
          [drive == CloudSaveDrive.cloud115 ? '/115/Show' : '/quark/Show']);
      expect(find.textContaining('保存 1 个，略过 1 个'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('mixed favorites require source selection before any requests',
      (tester) async {
    final harness = _Harness(mixed: true);
    await harness.pump(tester);
    await harness.check(tester);
    expect(find.text('选择更新来源'), findsOneWidget);
    expect(harness.reads, isEmpty);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(harness.reads, isEmpty);
    await harness.check(tester);
    await tester.tap(find.text('115 · Show'));
    await tester.pumpAndSettle();
    expect(harness.reads, [CloudSaveDrive.cloud115]);
    expect(find.text('保存到 115'), findsOneWidget);
    expect(find.text('保存到夸克'), findsNothing);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing 115 cookie cannot borrow Quark credentials',
      (tester) async {
    final harness = _Harness(mixed: true, missingCookie: true);
    await harness.pump(tester);
    await harness.check(tester);
    expect(find.text('未配置此网盘 Cookie'), findsOneWidget);
    await tester.tap(find.text('115 · Show'));
    await tester.pumpAndSettle();
    expect(find.textContaining('配置115 Cookie'), findsOneWidget);
    expect(harness.reads, isEmpty);
    expect(harness.saves, isEmpty);
  });

  testWidgets('no matching cookie hides the update action', (tester) async {
    final harness = _Harness(missingCookie: true);
    await harness.pump(tester);
    expect(find.text('检查更新'), findsNothing);
    expect(harness.reads, isEmpty);
  });

  testWidgets('no new videos has no save action', (tester) async {
    final harness = _Harness(noUpdates: true);
    await harness.pump(tester);
    await harness.check(tester);
    expect(find.text('保存到 115'), findsNothing);
    expect(tester.widget<SelectableText>(find.byType(SelectableText)).data,
        contains('没有更新。'));
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(harness.saves, isEmpty);
  });

  testWidgets('check failure is an error, never a no-update dialog',
      (tester) async {
    final harness = _Harness(delayCheck: true);
    harness.pendingCheck.complete(http.Response('blocked', 405));
    await harness.pump(tester);
    await harness.check(tester);
    expect(find.textContaining('HTTP 405'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(harness.saves, isEmpty);
  });

  testWidgets('save failure does not trigger downstream tasks', (tester) async {
    final harness = _Harness(saveFails: true);
    await harness.pump(tester);
    await harness.check(tester);
    await tester.tap(find.text(harness.saveLabel));
    await tester.pumpAndSettle();
    expect(harness.saves, [CloudSaveDrive.cloud115]);
    expect(harness.strmTasks, isEmpty);
    expect(harness.refreshes, isEmpty);
    expect(find.textContaining('HTTP 405'), findsOneWidget);
  });

  testWidgets('unconfirmed 115 save preserves the warning without retry',
      (tester) async {
    final harness = _Harness(unconfirmedSave: true);
    await harness.pump(tester);
    await harness.check(tester);
    await tester.tap(find.text(harness.saveLabel));
    await tester.pumpAndSettle();
    expect(harness.saves, [CloudSaveDrive.cloud115]);
    expect(harness.strmTasks, isEmpty);
    expect(harness.refreshes, isEmpty);
    expect(find.textContaining('当前批次结果未确认，请先检查网盘再重试'), findsOneWidget);
    expect(find.textContaining('unknown transfer outcome'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'duplicate clicks share one check and detached pages ignore its response',
      (tester) async {
    final harness = _Harness(delayCheck: true);
    await harness.pump(tester);
    await tester.scrollUntilVisible(find.text('检查更新'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('检查更新'));
    await tester.tap(find.text('检查更新'));
    await tester.pump();
    expect(harness.reads, [CloudSaveDrive.cloud115]);
    await tester.pumpWidget(const SizedBox());
    harness.pendingCheck
        .complete(harness.shareResponse(CloudSaveDrive.cloud115));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(harness.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV update dialog supports keyboard confirmation',
      (tester) async {
    final harness = _Harness(tv: true);
    await harness.pump(tester);
    await harness.check(tester);
    expect(find.text('保存到 115'), findsOneWidget);
    expect(
        FocusManager.instance.primaryFocus?.debugLabel, 'detail-update-save');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(harness.saves, [CloudSaveDrive.cloud115]);
    expect(harness.strmTasks.single['name'], '115-task');
    expect(tester.takeException(), isNull);
  });

  testWidgets('covered detail pages do not show a late check dialog',
      (tester) async {
    final harness = _Harness(delayCheck: true);
    await harness.pump(tester);
    await tester.scrollUntilVisible(find.text('检查更新'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('检查更新'));
    await tester.pump();
    unawaited(harness.navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Other page')))));
    await tester.pumpAndSettle();
    harness.pendingCheck
        .complete(harness.shareResponse(CloudSaveDrive.cloud115));
    await tester.pumpAndSettle();
    expect(find.text('Other page'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(harness.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('returning during a save cannot start another update',
      (tester) async {
    final harness = _Harness(delaySave: true);
    await harness.pump(tester);
    await harness.check(tester);
    await tester.tap(find.text(harness.saveLabel));
    await tester.pumpAndSettle();
    expect(harness.saves, [CloudSaveDrive.cloud115]);
    unawaited(harness.navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Other page')))));
    await tester.pumpAndSettle();
    harness.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    final previousReads = harness.reads.length;
    await harness.check(tester);
    expect(harness.reads.length, previousReads);
    expect(harness.saves, [CloudSaveDrive.cloud115]);
    expect(find.byType(AlertDialog), findsNothing);
    harness.pendingSave.complete();
    await tester.pumpAndSettle();
    expect(harness.strmTasks.single['name'], '115-task');
    expect(tester.takeException(), isNull);
  });
}
