import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/search/application/cloud115_save_workflow_service.dart';
import 'package:starflow/features/search/application/quark_save_workflow_service.dart';
import 'package:starflow/features/search/application/search_favorite_metadata_service.dart';
import 'package:starflow/features/search/data/cloud115_save_client.dart';
import 'package:starflow/features/search/data/search_repository.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/search/data/search_preferences_repository.dart';
import 'package:starflow/features/search/data/smart_strm_webhook_client.dart';
import 'package:starflow/features/search/domain/cloud_save_feedback.dart';
import 'package:starflow/features/search/domain/favorite_sync_document.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/search/presentation/search_page.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

const _result = SearchResult(
  id: '115-save',
  title: 'Test Movie',
  posterUrl: '',
  providerId: 'online',
  providerName: 'Online',
  quality: '',
  sizeLabel: '',
  seeders: 0,
  summary: '',
  resourceUrl: 'https://115.com/s/abc',
  password: 'abcd',
  favoriteFolderName: 'Favorite Movie',
);

http.Response _response(Object value) => http.Response.bytes(
      utf8.encode(jsonEncode(value)),
      200,
      headers: {'content-type': 'application/json'},
    );

class _SaveHarness {
  _SaveHarness({this.drive = CloudSaveDrive.cloud115});

  final CloudSaveDrive drive;
  final save = Completer<http.Response>();
  final strm = Completer<http.Response>();
  final refresh = Completer<void>();
  int saveRequests = 0;
  int refreshRequests = 0;

  bool get is115 => drive == CloudSaveDrive.cloud115;
  String get saveTooltip => is115 ? '保存到 115' : '保存到夸克';
  String get summary =>
      '已提交到${is115 ? ' 115' : '夸克'}，保存 1 个，略过 0 个，STRM 已延迟 3 秒触发，5 秒后刷新媒体源';

  void completeSave({bool success = true}) {
    save.complete(_response(is115
        ? {'state': success, if (!success) 'error': 'request denied'}
        : {
            'code': success ? 0 : 1,
            if (!success) 'message': 'request denied'
          }));
  }

  Future<void> pump(WidgetTester tester, {required bool favorites}) async {
    final result = _result.copyWith(
        resourceUrl: is115
            ? 'https://115.com/s/abc'
            : 'https://pan.quark.cn/s/abc${favorites ? '?pwd=abcd' : ''}');
    SharedPreferences.setMockInitialValues({
      if (favorites)
        SearchPreferencesRepository.favoriteResultsPreferenceKey:
            FavoriteSyncDocument()
                .setFavorite(searchResultFavoriteKey(result), result)
                .encode(),
    });
    final preferences = SearchPreferencesRepository(
      preferences:
          SharedPreferencesStore(await SharedPreferences.getInstance()),
    );
    addTearDown(preferences.dispose);
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = Cloud115SaveClient(MockClient((request) {
      if (request.url.path == '/files') {
        expect(request.method, 'GET');
        return Future.value(_response({'state': true, 'count': 0, 'data': []}));
      }
      if (request.url.path == '/files/add') {
        expect(request.method, 'POST');
        final body = Uri.splitQueryString(request.body);
        expect(body['pid'], '0');
        expect(body['cname'], favorites ? 'Favorite Movie' : 'Movie');
        return Future.value(_response({'state': true, 'cid': '42'}));
      }
      if (request.url.path == '/share/receive') {
        expect(request.method, 'POST');
        saveRequests++;
        expect(Uri.splitQueryString(request.body)['receive_code'], 'abcd');
        expect(Uri.splitQueryString(request.body)['cid'], '42');
        return save.future;
      }
      return Future.value(_response({
        'state': true,
        'data': {
          'count': 1,
          'list': [
            {'fid': '1', 'n': 'Movie.mkv'}
          ],
        },
      }));
    }));
    final quark = QuarkSaveClient(MockClient((request) {
      if (request.url.path.endsWith('/token')) {
        expect((jsonDecode(request.body) as Map)['passcode'], 'abcd');
        return Future.value(_response({
          'code': 0,
          'data': {'stoken': 'test'},
        }));
      }
      if (request.url.path.endsWith('/detail')) {
        return Future.value(_response({
          'code': 0,
          'data': {
            'list': [
              {
                'fid': '1',
                'file_name': 'Movie.mkv',
                'share_fid_token': 'token-1',
              },
            ],
          },
          'metadata': {'_total': 1},
        }));
      }
      if (request.url.path.endsWith('/sort')) {
        return Future.value(_response({
          'code': 0,
          'data': {'list': []},
        }));
      }
      if (request.url.path == '/1/clouddrive/file') {
        final body = jsonDecode(request.body) as Map;
        expect(body['pdir_fid'], '0');
        expect(body['file_name'], favorites ? 'Favorite Movie' : 'Movie');
        return Future.value(_response({
          'code': 0,
          'data': {'fid': '42'},
        }));
      }
      expect(request.url.path, '/1/clouddrive/share/sharepage/save');
      expect((jsonDecode(request.body) as Map)['to_pdir_fid'], '42');
      saveRequests++;
      return save.future;
    }));
    Future<void> refreshSources(List<String> ids, int delay) {
      expect(ids, ['nas']);
      expect(delay, 5);
      refreshRequests++;
      return refresh.future;
    }

    final smartStrm = SmartStrmWebhookClient(MockClient((request) {
      final body = jsonDecode(request.body) as Map;
      expect(body['task']['storage_path'],
          favorites ? '/Favorite Movie' : '/Movie');
      return strm.future;
    }));
    final workflow = Cloud115SaveWorkflowService(client, refreshSources,
        smartStrm: smartStrm);
    final quarkWorkflow = QuarkSaveWorkflowService(
      saveShareLink: quark.saveShareLink,
      sanitizeSavedNames: quark.sanitizeSavedEntries,
      triggerSmartStrm: smartStrm.triggerTask,
      resolveRefreshSourceIds: ({
        required NetworkStorageConfig networkStorage,
        required bool includeConfiguredSources,
      }) {
        expect(includeConfiguredSources, isTrue);
        return networkStorage.refreshMediaSourceIds;
      },
      refreshSelectedSources: ({
        required List<String> sourceIds,
        required int delaySeconds,
        required bool invalidateWebDavDirectoryCache,
      }) {
        expect(invalidateWebDavDirectoryCache, isTrue);
        return refreshSources(sourceIds, delaySeconds);
      },
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        isTelevisionProvider.overrideWith((ref) => false),
        searchRepositoryProvider.overrideWithValue(_Repository(result)),
        searchPreferencesRepositoryProvider.overrideWithValue(preferences),
        searchFavoriteMetadataServiceProvider.overrideWithValue(
          const SearchFavoriteMetadataService(),
        ),
        cloud115SaveClientProvider.overrideWithValue(client),
        cloud115SaveWorkflowProvider.overrideWithValue(workflow),
        quarkSaveClientProvider.overrideWithValue(quark),
        quarkSaveWorkflowServiceProvider.overrideWithValue(quarkWorkflow),
        appSettingsProvider.overrideWithValue(const AppSettings(
          mediaSources: [],
          searchProviders: [
            SearchProviderConfig(
              id: 'online',
              name: 'Online',
              kind: SearchProviderKind.panSou,
              endpoint: 'https://online.test',
              enabled: true,
              allowedCloudTypes: ['quark', '115'],
            ),
          ],
          doubanAccount: DoubanAccountConfig(enabled: false),
          homeModules: [],
          networkStorage: NetworkStorageConfig(
            cloud115Cookie: 'test',
            quarkCookie: 'test',
            smartStrmWebhookUrl: 'https://strm.test/webhook',
            cloud115SmartStrmTaskName: '115-task',
            smartStrmTaskName: 'quark-task',
            smartStrmDelaySeconds: 3,
            refreshMediaSourceIds: ['nas'],
            refreshDelaySeconds: 5,
          ),
        )),
      ],
      child: MaterialApp(
          home: SearchPage(
        initialQuery: favorites ? null : 'Movie',
        favoritesOnly: favorites,
      )),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(saveTooltip));
    await tester.pumpAndSettle();
    expect(find.text(drive.savingMessage), findsOneWidget);
  }
}

void main() {
  for (final drive in CloudSaveDrive.values) {
    for (final favorites in [false, true]) {
      testWidgets(
          '$drive progress and background refresh, favorites=$favorites',
          (tester) async {
        final harness = _SaveHarness(drive: drive);
        await harness.pump(tester, favorites: favorites);
        await tester.tap(find.byTooltip(harness.saveTooltip));
        await tester.pump();
        expect(harness.saveRequests, 1);
        harness.completeSave();
        await tester.pumpAndSettle();
        expect(find.text(drive.savingMessage), findsOneWidget);
        expect(find.textContaining('STRM 触发中'), findsNothing);
        harness.strm.complete(_response({'success': true}));
        await tester.pumpAndSettle();
        expect(find.text(drive.savingMessage), findsNothing);
        expect(find.textContaining('保存目录：'), findsNothing);
        expect(find.text(harness.summary), findsOneWidget);
        expect(find.textContaining('STRM 已延迟 3 秒触发'), findsOneWidget);
        expect(find.textContaining('5 秒后刷新媒体源'), findsOneWidget);
        expect(harness.refreshRequests, 1);
        expect(harness.refresh.isCompleted, isFalse);
        harness.refresh.completeError(StateError('refresh failed'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(find.text(drive.refreshFailureMessage), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    for (final stage in ['save', 'strm']) {
      testWidgets('$drive $stage failure closes progress', (tester) async {
        final harness = _SaveHarness(drive: drive);
        await harness.pump(tester, favorites: false);
        if (stage == 'save') {
          harness.completeSave(success: false);
        } else {
          harness.completeSave();
          await tester.pumpAndSettle();
          harness.strm.complete(http.Response('error', 500));
        }
        await tester.pumpAndSettle();
        expect(find.text(drive.savingMessage), findsNothing);
        expect(find.text('已保存 1 个，STRM 触发中...'), findsNothing);
        expect(
            find.textContaining(
                stage == 'save' ? 'request denied' : 'STRM 触发失败'),
            findsOneWidget);
        expect(harness.refreshRequests, stage == 'strm' ? 1 : 0);
        harness.refresh.complete();
        expect(tester.takeException(), isNull);
      });

      testWidgets(
          'leaving during $drive $stage closes progress and ignores late UI updates',
          (tester) async {
        final harness = _SaveHarness(drive: drive);
        await harness.pump(tester, favorites: false);
        if (stage == 'strm') {
          harness.completeSave();
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox());
        if (stage == 'save') harness.completeSave();
        harness.strm.complete(_response({'success': true}));
        harness.refresh.complete();
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

class _Repository implements SearchRepository {
  _Repository(this.result);
  final SearchResult result;

  @override
  Future<SearchFetchResult> searchOnline(String query,
          {required SearchProviderConfig provider}) async =>
      SearchFetchResult(items: [result], filteredCount: 0);

  @override
  Future<SearchFetchResult> searchLocal(String query,
          {String? sourceId, String? sectionId, int limit = 60}) async =>
      SearchFetchResult(items: const [], filteredCount: 0);
}
