import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/library/data/fntv_api_client.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';
import 'package:starflow/features/library/data/media_repository.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_target_resolver.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/settings/application/media_source_cache_lifecycle.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/data/app_settings_repository.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/media_source_editor_page.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_text_input_field.dart';

const _source = MediaSourceConfig(
  id: 'fntv',
  name: 'FNTV',
  kind: MediaSourceKind.fntv,
  endpoint: 'https://nas.example.com',
  enabled: true,
  username: 'alice',
  password: ' p ',
  userId: 'user',
  accessToken: 'token',
  featuredSectionIds: ['movies'],
);

http.Response _ok(Object? data) =>
    http.Response(jsonEncode({'code': 0, 'data': data}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('missing FNTV parent removes only its stale detail relation', () async {
    final client = FntvApiClient(MockClient((request) async {
      expect(request.url.path, '/v/api/v1/item/deleted-guid');
      return http.Response(jsonEncode({'code': -6, 'msg': 'Not Found'}), 200);
    }));
    final container = ProviderContainer(overrides: [
      appSettingsProvider.overrideWithValue(
        SeedData.defaultSettings.copyWith(mediaSources: [_source]),
      ),
      fntvApiClientProvider.overrideWithValue(client),
    ]);
    addTearDown(container.dispose);
    final cache = container.read(localStorageCacheRepositoryProvider);
    const old = MediaDetailTarget(
      title: '半泽直树', posterUrl: '', overview: '',
      sourceId: 'fntv', sourceKind: MediaSourceKind.fntv,
      itemId: 'deleted-guid', itemType: 'series',
    );
    final other = old.copyWith(title: 'Other show', itemId: 'other-guid');
    for (final target in [old, other]) {
      await cache.saveDetailTarget(seedTarget: target, resolvedTarget: target,
          libraryMatchChoices: [target]);
    }
    await expectLater(
      container.read(mediaRepositoryProvider).fetchChildren(
        sourceId: 'fntv', parentId: 'deleted-guid',
      ),
      throwsA(isA<FntvApiException>().having((e) => e.isMissingItem, 'missing', true)),
    );
    final state = await cache.loadDetailState(old);
    expect(state?.target.itemId ?? '', isNot('deleted-guid'));
    expect(state?.libraryMatchChoices ?? [], isEmpty);
    expect((await cache.loadDetailTarget(other))?.itemId, 'other-guid');
  });

  test(
      'repository uses FNTV, caches sections and keeps cache on failed refresh',
      () async {
    var failRefresh = false;
    var requests = 0;
    final client = FntvApiClient(MockClient((request) async {
      requests++;
      if (failRefresh) return http.Response('', 503);
      if (request.url.path.endsWith('/item/refresh')) {
        return _ok(true);
      }
      if (request.url.path.endsWith('/mediadb/list')) {
        return _ok([
          {'guid': 'movies', 'title': 'Movies', 'category': 'Movie'}
        ]);
      }
      expect(request.url.path, '/v/api/v1/item/list');
      return _ok({
        'total': 1,
        'list': [
          {
            'guid': 'movie',
            'title': 'Example Movie',
            'type': 'Movie',
            'poster': '/covers/movie.jpg',
            'ancestor_guid': 'movies',
          }
        ]
      });
    }));
    final settings = SeedData.defaultSettings.copyWith(mediaSources: [_source]);
    final container = ProviderContainer(overrides: [
      appSettingsProvider.overrideWithValue(settings),
      fntvApiClientProvider.overrideWithValue(client),
    ]);
    addTearDown(container.dispose);
    final repository = container.read(mediaRepositoryProvider);
    await repository.refreshSource(sourceId: _source.id);
    final requestCount = requests;
    expect((await repository.fetchCollections(sourceId: _source.id)).single.id,
        'movies');
    final items = await repository.fetchLibrary(sourceId: _source.id);
    expect(items.single.sourceKind, MediaSourceKind.fntv);
    expect(items.single.posterHeaders['Authorization'], 'token');
    expect(
        await repository.fetchLibrary(
            sourceId: _source.id, sectionId: 'unselected'),
        isEmpty);
    expect(
        (await repository.loadLibraryMatchItems(
                source: _source, titles: ['Example Movie']))
            .single
            .id,
        'movie');
    expect(requests, requestCount);
    failRefresh = true;
    await expectLater(repository.refreshSource(sourceId: _source.id),
        throwsA(isA<FntvApiException>()));
    expect((await repository.fetchLibrary(sourceId: _source.id)).single.id,
        'movie');
  });

  test('failed server refresh request does not block local library refresh',
      () async {
    final paths = <String>[];
    final client = FntvApiClient(MockClient((request) async {
      paths.add(request.url.path);
      if (request.url.path.endsWith('/item/refresh')) {
        return http.Response('', 503);
      }
      if (request.url.path.endsWith('/mediadb/list')) {
        return _ok([
          {'guid': 'movies', 'title': 'Movies', 'category': 'Movie'}
        ]);
      }
      expect(request.url.path, '/v/api/v1/item/list');
      return _ok({
        'total': 1,
        'list': [
          {
            'guid': 'movie',
            'title': 'Example Movie',
            'type': 'Movie',
            'ancestor_guid': 'movies',
          }
        ]
      });
    }));
    final container = ProviderContainer(overrides: [
      appSettingsProvider.overrideWithValue(
          SeedData.defaultSettings.copyWith(mediaSources: [_source])),
      fntvApiClientProvider.overrideWithValue(client),
    ]);
    addTearDown(container.dispose);
    final repository = container.read(mediaRepositoryProvider);

    await repository.refreshSource(sourceId: _source.id);

    expect(paths.first, '/v/api/v1/item/refresh');
    expect(paths, contains('/v/api/v1/item/list'));
    expect((await repository.fetchLibrary(sourceId: _source.id)).single.id,
        'movie');
  });

  test('playback startup re-resolves saved external URL through FNTV',
      () async {
    final client = FntvApiClient(MockClient((request) async {
      if (request.url.path.endsWith('/play/info')) {
        return _ok({'media_guid': 'file'});
      }
      expect(request.url.path, '/v/api/v1/stream');
      final body = jsonDecode(request.body) as Map;
      if (body['ip'] !=
              md5.convert(utf8.encode(_source.accessToken)).toString() ||
          body['header'] is! Map ||
          (body['header'] as Map)['User-Agent'] is! List) {
        return http.Response(jsonEncode({'code': -1}), 200);
      }
      return _ok({
        'file_stream': {'guid': 'file', 'can_play': 1}
      });
    }));
    final container = ProviderContainer(overrides: [
      appSettingsProvider.overrideWithValue(
          SeedData.defaultSettings.copyWith(mediaSources: [_source])),
      fntvApiClientProvider.overrideWithValue(client),
    ]);
    addTearDown(container.dispose);
    final resolved = await PlaybackTargetResolver(read: container.read)
        .resolve(const PlaybackTarget(
      title: 'Movie',
      sourceId: 'fntv',
      sourceName: 'FNTV',
      sourceKind: MediaSourceKind.fntv,
      itemId: 'movie',
      streamUrl: 'https://expired.example.com/old',
      headers: {'Cookie': 'old'},
    ));
    expect(resolved.streamUrl,
        'https://nas.example.com/v/api/v1/media/range/file');
    expect(resolved.headers['Cookie'], 'Trim-MC-token=token');
  });

  for (final tv in [false, true]) {
    testWidgets(
        'FNTV editor logs in, autosaves and invalidates changed credentials (TV=$tv)',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final draft = _source.copyWith(accessToken: '', userId: '');
      final repository =
          _Settings(SeedData.defaultSettings.copyWith(mediaSources: [draft]));
      final client = FntvApiClient(MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          expect(jsonDecode(request.body)['password'], ' p ');
          return _ok({'token': 'new-token'});
        }
        if (request.url.path.endsWith('/user/info')) {
          return _ok({'guid': 'user', 'username': 'alice'});
        }
        return _ok([
          {'guid': 'movies', 'title': 'Movies', 'category': 'Movie'}
        ]);
      }));
      await tester.pumpWidget(ProviderScope(overrides: [
        appSettingsRepositoryProvider.overrideWithValue(repository),
        fntvApiClientProvider.overrideWithValue(client),
        mediaSourceCacheLifecycleProvider.overrideWithValue(_CacheLifecycle()),
        isTelevisionProvider.overrideWith((ref) async => tv),
      ], child: MaterialApp(home: MediaSourceEditorPage(initial: draft))));
      await tester.pumpAndSettle();
      expect(find.text('飞牛影视 用户名'), findsWidgets);
      expect(find.text('Access Token / API Key'), findsNothing);
      await tester.ensureVisible(find.text('测试登录'));
      await _activate(tester, find.text('测试登录'), tv: tv);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(repository.settings.mediaSources.single.accessToken, 'new-token');
      await tester.ensureVisible(find.text('选择分区').last);
      await _activate(tester, find.text('选择分区').last, tv: tv);
      await tester.pumpAndSettle();
      expect(find.text('Movies'), findsOneWidget);
      final field = tester
          .widgetList<SettingsTextInputField>(
              find.byType(SettingsTextInputField))
          .firstWhere((field) => field.labelText == '飞牛影视 用户名');
      field.controller.text = 'other';
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(repository.settings.mediaSources.single.hasActiveSession, false);
      expect(
          repository.settings.mediaSources.single.featuredSectionIds, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('FNTV login completion cannot overwrite a changed endpoint',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final pending = Completer<http.Response>();
    final draft = _source.copyWith(accessToken: '', userId: '');
    final repository =
        _Settings(SeedData.defaultSettings.copyWith(mediaSources: [draft]));
    await tester.pumpWidget(ProviderScope(overrides: [
      appSettingsRepositoryProvider.overrideWithValue(repository),
      mediaSourceCacheLifecycleProvider.overrideWithValue(_CacheLifecycle()),
      isTelevisionProvider.overrideWith((ref) async => false),
      fntvApiClientProvider
          .overrideWithValue(FntvApiClient(MockClient((request) async {
        if (request.url.path.endsWith('/login')) return pending.future;
        return _ok({'guid': 'user', 'username': 'alice'});
      }))),
    ], child: MaterialApp(home: MediaSourceEditorPage(initial: draft))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('测试登录'));
    await tester.tap(find.text('测试登录'));
    await tester.pump();
    tester
        .widgetList<SettingsTextInputField>(find.byType(SettingsTextInputField))
        .firstWhere((field) => field.labelText == 'Endpoint')
        .controller
        .text = 'https://new.example.com';
    pending.complete(_ok({'token': 'old-server-token'}));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(repository.settings.mediaSources.single.endpoint,
        'https://new.example.com');
    expect(repository.settings.mediaSources.single.hasActiveSession, false);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _activate(WidgetTester tester, Finder finder,
    {required bool tv}) async {
  if (!tv) {
    await tester.tap(finder);
    return;
  }
  Focus.of(tester.element(finder)).requestFocus();
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
}

class _Settings implements AppSettingsRepository {
  _Settings(this.settings);
  AppSettings settings;
  @override
  Future<AppSettings> load() async => settings;
  @override
  Future<void> save(AppSettings settings) async {
    this.settings = settings;
  }
}

class _CacheLifecycle implements MediaSourceCacheLifecycle {
  @override
  Future<void> clearSource(String sourceId) async {}
  @override
  Future<void> clearAllIndexes() async {}
  @override
  Future<void> reconcileSources(List<MediaSourceConfig> sources) async {}
}
