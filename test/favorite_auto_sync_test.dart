import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/search/application/favorite_auto_sync.dart';
import 'package:starflow/features/search/application/search_favorite_metadata_service.dart';
import 'package:starflow/features/search/data/search_preferences_repository.dart';
import 'package:starflow/features/search/domain/favorite_sync_document.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/search/presentation/search_page.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/data/app_settings_repository.dart';
import 'package:starflow/features/settings/data/webdav_sync_service.dart';

SearchResult favorite(String id) => SearchResult(
    id: id,
    title: id,
    posterUrl: '',
    providerId: 'test',
    providerName: 'Test',
    quality: '',
    sizeLabel: '',
    seeders: 0,
    summary: '',
    resourceUrl: 'https://example.com/$id');
String key(String id) => searchResultFavoriteKey(favorite(id));
FavoriteSyncDocument document(String id) =>
    FavoriteSyncDocument().setFavorite(key(id), favorite(id));
FavoriteSyncDocument documentWithFavorites(List<SearchResult> items) {
  var result = FavoriteSyncDocument();
  for (final item in items) {
    result = result.setFavorite(searchResultFavoriteKey(item), item);
  }
  return result;
}

class MemoryStore implements PreferencesStore {
  final values = <String, Object>{};
  @override
  Future<String?> getString(String key) async => values[key] as String?;
  @override
  Future<List<String>?> getStringList(String key) async =>
      values[key] as List<String>?;
  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> setStringList(String key, List<String> value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}

class SyncPreferences extends WebDavSyncPreferences {
  WebDavSyncConfig config = const WebDavSyncConfig(
      url: 'https://example.com/dav/', autoFavorites: true);
  @override
  Future<WebDavSyncConfig> load() async => config;
}

class Server {
  FavoriteSyncDocument? remoteDocument;
  final deviceFiles = <String, FavoriteSyncDocument>{};
  final compactDevicePaths = <String>{};
  final putPaths = <String>[];
  final putBodies = <String>[];
  FavoriteSyncDocument? get remote => remoteDocument == null &&
          deviceFiles.isEmpty
      ? null
      : (remoteDocument ?? FavoriteSyncDocument()).mergeAll(deviceFiles.values);
  set remote(FavoriteSyncDocument? value) => remoteDocument = value;
  int reads = 0;
  int writes = 0;
  bool offline = false;
  bool etag = true;
  int requests = 0;
  Completer<void>? hold;
  Completer<void>? holdWrite;
  Future<http.Response> respond(http.Request request) async {
    requests++;
    expectSync(request.url.path, isNot(contains('starflow-sync.json')));
    if (offline) throw http.ClientException('offline');
    if (request.method == 'MKCOL') return http.Response('', 201);
    if (request.method == 'PROPFIND') {
      expectSync(request.url.path.endsWith('/'), isTrue);
      final files =
          request.headers['Depth'] == '1' ? deviceFiles.keys.map((path) => '''
<d:response><d:href>${htmlEscape.convert(path)}</d:href><d:propstat>
<d:prop><d:resourcetype/></d:prop><d:status>HTTP/1.1 200 OK</d:status>
</d:propstat></d:response>''').join() : '';
      return http.Response('''<d:multistatus xmlns:d="DAV:"><d:response>
<d:href>${htmlEscape.convert(request.url.path)}</d:href><d:propstat>
<d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop>
<d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>$files</d:multistatus>''',
          207);
    }
    if (request.method == 'GET') {
      reads++;
      await hold?.future;
      final document = deviceFiles[request.url.path] ?? remoteDocument;
      if (document == null) return http.Response('', 404);
      return http.Response.bytes(
          utf8.encode(document.encode(
              forSync: compactDevicePaths.contains(request.url.path))),
          200,
          headers: {if (etag) 'etag': '"version"'});
    }
    expectSync(request.method, 'PUT');
    expectSync(request.body, isNot(contains('schemaVersion')));
    expectSync(request.url.pathSegments.last,
        matches(r'^starflow-favorites-[a-f0-9]{32}\.json$'));
    putPaths.add(request.url.path);
    putBodies.add(request.body);
    await holdWrite?.future;
    expectSync(request.headers['If-None-Match'], isNull);
    expectSync(request.headers['If-Match'], isNull);
    deviceFiles[request.url.path] = FavoriteSyncDocument.decode(request.body);
    compactDevicePaths.add(request.url.path);
    writes++;
    return http.Response('', 204);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'application settings adapter loads connection without startup sync',
      (tester) async {
    final store = MemoryStore();
    store.values['starflow.settings.v3'] = jsonEncode(
      SeedData.defaultSettings
          .copyWith(
              webDavSync: const WebDavSyncConfig(
            url: 'https://example.com/dav/',
            autoFavorites: true,
          ))
          .toJson(),
    );
    final server = Server();
    final container = ProviderContainer(overrides: [
      appSettingsRepositoryProvider
          .overrideWithValue(LocalAppSettingsRepository(preferences: store)),
      webDavSyncServiceProvider
          .overrideWithValue(WebDavSyncService(MockClient(server.respond))),
      searchPreferencesRepositoryProvider
          .overrideWithValue(SearchPreferencesRepository(preferences: store)),
    ]);
    addTearDown(container.dispose);
    final sync = container.read(favoriteAutoSyncProvider);
    sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(server.requests, 0);
    await sync.onFavoritesPageEntered();
    expect(server.reads, 1);
    await container
        .read(webDavSyncPreferencesProvider)
        .save(const WebDavSyncConfig(
          url: 'https://new.example.com/dav/',
          autoFavorites: true,
        ));
    await tester.pump();
    await sync.onFavoritesPageEntered();
    expect(server.reads, 1);
  });

  Future<void> tick(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
  }

  test(
      'device identity is stable, local to each installation and survives clear',
      () async {
    final store = MemoryStore();
    final repo = SearchPreferencesRepository(preferences: store);
    final other = SearchPreferencesRepository(preferences: MemoryStore());
    addTearDown(repo.dispose);
    addTearDown(other.dispose);
    final ids = await Future.wait(
        List.generate(4, (_) => repo.loadFavoriteSyncDeviceId()));
    expect(ids.toSet().length, 1);
    expect(ids.first, matches(r'^[a-f0-9]{32}$'));
    expect(await other.loadFavoriteSyncDeviceId(), isNot(ids.first));
    await repo.setFavorite(key('local'), favorite('local'));
    expect((await repo.loadFavoriteSyncDocument()).encode(),
        isNot(contains(ids.first)));
    await repo.clear();
    final restarted = SearchPreferencesRepository(preferences: store);
    addTearDown(restarted.dispose);
    expect(await restarted.loadFavoriteSyncDeviceId(), ids.first);
  });

  test(
      'invalid local device identity is regenerated without affecting favorites',
      () async {
    final store = MemoryStore();
    store.values[SearchPreferencesRepository
        .favoriteSyncDeviceIdPreferenceKey] = '../escape';
    final repo = SearchPreferencesRepository(preferences: store);
    addTearDown(repo.dispose);
    await repo.setFavorite(key('local'), favorite('local'));
    expect(await repo.loadFavoriteSyncDeviceId(), matches(r'^[a-f0-9]{32}$'));
    expect((await repo.loadFavoriteResults()).single.id, 'local');
  });

  test('multi-device capacity is checked after applying all deletion records',
      () {
    final full =
        documentWithFavorites(List.generate(200, (i) => favorite('$i')));
    final extra = document('extra');
    final deletion = document('0').setFavorite(key('0'), null);
    final merged = FavoriteSyncDocument().mergeAll([full, extra, deletion]);
    expect(merged.favorites.length, 200);
    expect(merged.entries[key('0')]!.deleted, isTrue);
    expect(FavoriteSyncDocument().mergeAll([deletion, extra, full]).encode(),
        merged.encode());
    expect(
        () => FavoriteSyncDocument().mergeAll([full, extra]), throwsStateError);
  });

  test('merge is commutative, idempotent and preserves both offline additions',
      () {
    final a = document('a');
    final b = document('b');
    expect(a.merge(b).favorites.map((e) => e.id).toSet(), {'a', 'b'});
    expect(a.merge(b).encode(), b.merge(a).encode());
    expect(a.merge(a).encode(), a.encode());
  });

  test('deletion beats stale data and artwork, explicit re-add works', () {
    final base = document('a');
    final deleted = base.setFavorite(key('a'), null);
    final artwork =
        base.setFavorite(key('a'), favorite('a').copyWith(posterUrl: 'poster'));
    expect(deleted.merge(artwork).favorites, isEmpty);
    expect(artwork.merge(deleted).favorites, isEmpty);
    final restored = deleted.setFavorite(key('a'), favorite('a'));
    expect(restored.merge(deleted).favorites.single.id, 'a');
    final roundtrip = FavoriteSyncDocument.decode(deleted.encode());
    expect(roundtrip.merge(base).favorites, isEmpty);
  });

  test('artwork does not reorder favorites and invalid documents are rejected',
      () {
    final base = document('a').setFavorite(key('b'), favorite('b'));
    final enriched =
        base.setFavorite(key('a'), favorite('a').copyWith(posterUrl: 'poster'));
    expect(enriched.favorites.map((e) => e.id), ['b', 'a']);
    final json = jsonDecode(base.encode()) as Map<String, dynamic>;
    (json['entries'] as List).add((json['entries'] as List).first);
    expect(() => FavoriteSyncDocument.decode(jsonEncode(json)),
        throwsFormatException);
    expect(() => FavoriteSyncDocument.decode('{broken'), throwsFormatException);
  });

  test('corrupt local storage cannot be silently replaced by sync or edits',
      () async {
    final store = MemoryStore();
    store.values[SearchPreferencesRepository.favoriteResultsPreferenceKey] =
        '{broken';
    final repo = SearchPreferencesRepository(preferences: store);
    addTearDown(repo.dispose);
    expect(await repo.loadFavoriteResults(), isEmpty);
    await expectLater(repo.loadFavoriteSyncDocument(), throwsFormatException);
    await expectLater(repo.mergeFavoriteSyncDocument(document('remote')),
        throwsFormatException);
    await expectLater(
        repo.setFavorite(key('new'), favorite('new')), throwsFormatException);
    expect(
        store.values[SearchPreferencesRepository.favoriteResultsPreferenceKey],
        '{broken');
  });

  test('repository serializes merge with edits', () async {
    final store = MemoryStore();
    final repo = SearchPreferencesRepository(preferences: store);
    addTearDown(repo.dispose);
    await repo.mergeFavoriteSyncDocument(document('a'));
    expect((await repo.loadFavoriteResults()).single.id, 'a');
    await Future.wait([
      repo.mergeFavoriteSyncDocument(document('b')),
      repo.setFavorite(key('a'), null),
      repo.updateFavoritePoster(favorite('a').copyWith(posterUrl: 'late')),
    ]);
    final restarted = SearchPreferencesRepository(preferences: store);
    addTearDown(restarted.dispose);
    await restarted.mergeFavoriteSyncDocument(document('a'));
    expect((await restarted.loadFavoriteResults()).map((e) => e.id), ['b']);
    await restarted.mergeFavoriteSyncDocument(document('obsolete'),
        shouldApply: () => false);
    expect((await restarted.loadFavoriteResults()).map((e) => e.id), ['b']);
    await restarted.clear();
    await restarted.mergeFavoriteSyncDocument(document('b'));
    expect(await restarted.loadFavoriteResults(), isEmpty);
  });

  testWidgets(
      'compact verified upload keeps local presentation without artwork uploads',
      (tester) async {
    final server = Server();
    final store = MemoryStore();
    final repo = SearchPreferencesRepository(preferences: store);
    final prefs = SyncPreferences();
    final result = SearchResult.fromJson({
      ...favorite('local').toJson(),
      'summary': 'A local-only cached description',
      'imageUrls': ['https://images.example.com/one.jpg'],
      'password': '1234',
      'favoriteFolderName': 'Saved folder',
    });
    await repo.setFavorite(key('local'), result);
    final original = await repo.loadFavoriteSyncDocument();
    final sync = FavoriteAutoSync(
        repository: repo,
        preferences: prefs,
        service: WebDavSyncService(MockClient(server.respond)));
    addTearDown(sync.dispose);
    addTearDown(repo.dispose);
    addTearDown(prefs.dispose);
    sync.start();
    sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tick(tester);
    expect(server.requests, 0);
    await sync.onFavoritesPageEntered();
    expect(sync.lastSuccess, isNotNull);
    expect(server.writes, 1);
    expect(server.putBodies.single, original.encodeForSync());
    expect(server.putBodies.single, isNot(contains('summary')));
    expect(server.putBodies.single, isNot(contains('imageUrls')));
    expect((await repo.loadFavoriteResults()).single.toJson(), result.toJson());

    final reads = server.reads;
    final enriched = result.copyWith(
        posterUrl: 'https://images.example.com/poster.jpg',
        posterHeaders: {'Authorization': 'image-only-secret'});
    await repo.updateFavoritePoster(enriched);
    await tester.pump(const Duration(hours: 1));
    expect(server.reads, reads);
    await sync.synchronize(manual: true);
    expect(server.writes, 1);
    final afterArtwork = await repo.loadFavoriteSyncDocument();
    expect(afterArtwork.encodeForSync(), original.encodeForSync());
    expect(afterArtwork.favorites.single.toJson(), enriched.toJson());

    final otherPath = prefs.config
        .favoriteDeviceFileUri('abcdef0123456789abcdef0123456789')
        .path;
    final remote = server.remote!;
    server.deviceFiles[otherPath] = remote.setFavorite(key('local'),
        remote.favorites.single.copyWith(title: 'New title', password: ''));
    server.compactDevicePaths.add(otherPath);
    await sync.synchronize(manual: true);
    expect(server.writes, 2);
    final updated = (await repo.loadFavoriteResults()).single;
    expect(updated.title, 'New title');
    expect(updated.password, isEmpty);
    expect(updated.summary, result.summary);
    expect(updated.posterUrl, enriched.posterUrl);
    expect(updated.posterHeaders, enriched.posterHeaders);
    expect(updated.imageUrls, result.imageUrls);
    expect(server.putBodies.last, isNot(contains('image-only-secret')));
  });

  testWidgets(
      'startup is silent and only the first page entry syncs, membership events remain active',
      (tester) async {
    final server = Server()..remote = document('remote');
    final repo = SearchPreferencesRepository(preferences: MemoryStore());
    final prefs = SyncPreferences();
    final sync = FavoriteAutoSync(
        repository: repo,
        preferences: prefs,
        service: WebDavSyncService(MockClient(server.respond)));
    sync.start();
    sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tick(tester);
    expect(server.requests, 0);
    expect(await repo.loadFavoriteResults(), isEmpty);
    await sync.onFavoritesPageEntered();
    expect((await repo.loadFavoriteResults()).single.id, 'remote');
    final initialReads = server.reads;
    await sync.onFavoritesPageEntered();
    await tester.pump(const Duration(hours: 1));
    expect(server.reads, initialReads);
    await repo.setFavorite(key('local'), favorite('local'));
    await tester.pump();
    expect(server.remote!.favorites.length, 2);
    final reads = server.reads;
    await repo
        .updateFavoritePoster(favorite('local').copyWith(posterUrl: 'poster'));
    await repo.setFavorite(
        key('local'), favorite('local').copyWith(title: 'renamed'));
    await repo.mergeFavoriteSyncDocument(document('merged'));
    await tester.pump(const Duration(hours: 1));
    expect(server.reads, reads);
    await sync.reload();
    await sync.onFavoritesPageEntered();
    await tester.pump();
    expect(server.reads, reads);
    sync.didChangeAppLifecycleState(AppLifecycleState.paused);
    final pausedReads = server.reads;
    await repo.setFavorite(key('background'), favorite('background'));
    await tester.pump(const Duration(minutes: 10));
    expect(server.reads, pausedReads);
    sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tick(tester);
    expect(server.reads, pausedReads);
    await sync.synchronize();
    expect(server.remote!.favorites.length, 4);
    await repo.setFavorite(key('local'), null);
    await tester.pump();
    expect(server.remote!.favorites.length, 3);
    final afterDelete = server.reads;
    await repo.setFavorite(key('local'), null);
    await tester.pump(const Duration(hours: 1));
    expect(server.reads, afterDelete);
    sync.dispose();
    repo.dispose();
    prefs.dispose();
  });

  testWidgets(
      'edits made during request survive and follow up without extra device files',
      (tester) async {
    final server = Server()..remote = document('remote');
    final repo = SearchPreferencesRepository(preferences: MemoryStore());
    final prefs = SyncPreferences();
    await repo.setFavorite(key('local'), favorite('local'));
    final sync = FavoriteAutoSync(
        repository: repo,
        preferences: prefs,
        service: WebDavSyncService(MockClient(server.respond)));
    server.hold = Completer<void>();
    sync.start();
    sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
    unawaited(sync.onFavoritesPageEntered());
    await tick(tester);
    await repo.setFavorite(key('during'), favorite('during'));
    server.hold!.complete();
    await tester.pump();
    expect(server.deviceFiles.length, 1);
    expect(server.writes, 1);
    expect(sync.status, '收藏已同步');
    expect(server.remote!.favorites.map((e) => e.id).toSet(),
        {'remote', 'local', 'during'});
    expect((await repo.loadFavoriteResults()).length, 3);
    sync.dispose();
    repo.dispose();
    prefs.dispose();
  });

  testWidgets(
      'offline failures do not retry until a new event or manual action',
      (tester) async {
    final server = Server()..offline = true;
    final repo = SearchPreferencesRepository(preferences: MemoryStore());
    final prefs = SyncPreferences();
    await repo.setFavorite(key('local'), favorite('local'));
    final sync = FavoriteAutoSync(
        repository: repo,
        preferences: prefs,
        service: WebDavSyncService(MockClient(server.respond)));
    sync.start();
    sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tick(tester);
    expect(server.requests, 0);
    await sync.onFavoritesPageEntered();
    expect(sync.status, contains('失败'));
    expect((await repo.loadFavoriteResults()).length, 1);
    final requests = server.requests;
    server.offline = false;
    await sync.onFavoritesPageEntered();
    await tester.pump(const Duration(hours: 24));
    expect(server.requests, requests);
    await sync.synchronize(manual: true);
    expect(server.remote!.favorites.single.id, 'local');
    server.etag = false;
    await repo.setFavorite(key('second'), favorite('second'));
    await tester.pump();
    expect(sync.status, '收藏已同步');
    expect(server.remote!.favorites.length, 2);
    expect((await repo.loadFavoriteResults()).length, 2);
    final completedRequests = server.requests;
    await tester.pump(const Duration(hours: 24));
    expect(server.requests, completedRequests);
    sync.dispose();
    repo.dispose();
    prefs.dispose();
  });

  testWidgets(
      'two devices write concurrently without ETags or overwriting each other',
      (tester) async {
    final server = Server()
      ..etag = false
      ..holdWrite = Completer<void>();
    final repoA = SearchPreferencesRepository(preferences: MemoryStore());
    final repoB = SearchPreferencesRepository(preferences: MemoryStore());
    final prefsA = SyncPreferences();
    final prefsB = SyncPreferences();
    final service = WebDavSyncService(MockClient(server.respond));
    final a = FavoriteAutoSync(
        repository: repoA, preferences: prefsA, service: service);
    final b = FavoriteAutoSync(
        repository: repoB, preferences: prefsB, service: service);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    addTearDown(repoA.dispose);
    addTearDown(repoB.dispose);
    addTearDown(prefsA.dispose);
    addTearDown(prefsB.dispose);
    await repoA.setFavorite(key('a'), favorite('a'));
    await repoB.setFavorite(key('b'), favorite('b'));
    a.start();
    b.start();
    a.didChangeAppLifecycleState(AppLifecycleState.resumed);
    b.didChangeAppLifecycleState(AppLifecycleState.resumed);
    final first =
        Future.wait([a.onFavoritesPageEntered(), b.onFavoritesPageEntered()]);
    await tick(tester);
    expect(server.putPaths.toSet().length, 2);
    server.holdWrite!.complete();
    await first;
    expect(a.status, '收藏已同步');
    expect(b.status, '收藏已同步');
    expect(server.deviceFiles.length, 2);
    expect(server.remote!.favorites.map((e) => e.id).toSet(), {'a', 'b'});
    await Future.wait(
        [a.synchronize(manual: true), b.synchronize(manual: true)]);
    expect((await repoA.loadFavoriteResults()).map((e) => e.id).toSet(),
        {'a', 'b'});
    expect((await repoB.loadFavoriteResults()).map((e) => e.id).toSet(),
        {'a', 'b'});
    final writes = server.writes;
    await Future.wait(
        [a.synchronize(manual: true), b.synchronize(manual: true)]);
    expect(server.writes, writes);
    b.didChangeAppLifecycleState(AppLifecycleState.paused);
    await repoA.setFavorite(key('b'), null);
    await tester.pump();
    await repoB.setFavorite(key('offline'), favorite('offline'));
    b.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await b.synchronize(manual: true);
    await a.synchronize(manual: true);
    expect((await repoA.loadFavoriteResults()).map((e) => e.id).toSet(),
        {'a', 'offline'});
    expect((await repoB.loadFavoriteResults()).map((e) => e.id).toSet(),
        {'a', 'offline'});
    await repoB.setFavorite(key('b'), favorite('b'));
    await tester.pump();
    await a.synchronize(manual: true);
    expect((await repoA.loadFavoriteResults()).map((e) => e.id).toSet(),
        {'a', 'b', 'offline'});
    expect(server.deviceFiles.length, 2);
    final requests = server.requests;
    await tester.pump(const Duration(hours: 24));
    await a.onFavoritesPageEntered();
    await b.onFavoritesPageEntered();
    expect(server.requests, requests);
  });

  testWidgets(
      'device file imports another device read only and syncs deletions and clear',
      (tester) async {
    final server = Server()
      ..remote = document('remote').merge(document('remove'))
      ..etag = false;
    final repo = SearchPreferencesRepository(preferences: MemoryStore());
    final prefs = SyncPreferences();
    await repo.mergeFavoriteSyncDocument(server.remote!);
    await repo.setFavorite(key('remove'), null);
    await repo.setFavorite(key('local'), favorite('local'));
    final sync = FavoriteAutoSync(
        repository: repo,
        preferences: prefs,
        service: WebDavSyncService(MockClient(server.respond)));
    addTearDown(sync.dispose);
    addTearDown(repo.dispose);
    addTearDown(prefs.dispose);
    sync.start();
    sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tick(tester);
    expect(server.requests, 0);
    await sync.onFavoritesPageEntered();
    expect(sync.status, '收藏已同步');
    expect(sync.lastSuccess, isNotNull);
    expect(server.writes, 1);
    expect(server.deviceFiles.length, 1);
    expect(server.remoteDocument!.favorites.map((e) => e.id).toSet(),
        {'remote', 'remove'});
    expect(
        server.remote!.favorites.map((e) => e.id).toSet(), {'remote', 'local'});
    expect(server.remote!.entries[key('remove')]!.deleted, isTrue);
    expect((await repo.loadFavoriteResults()).map((e) => e.id).toSet(),
        {'remote', 'local'});
    await repo.setFavorite(key('local'), null);
    await tester.pump();
    expect(server.remote!.favorites.map((e) => e.id).toSet(), {'remote'});
    await repo.clear();
    await tester.pump();
    expect(server.remote!.favorites, isEmpty);
    expect(await repo.loadFavoriteResults(), isEmpty);
    expect(sync.status, '收藏已同步');
    final requests = server.requests;
    await tester.pump(const Duration(hours: 24));
    await sync.onFavoritesPageEntered();
    expect(server.requests, requests);
  });

  for (final etag in [true, false]) {
    testWidgets(
        'failed readback preserves local changes without reporting success: ETag=$etag',
        (tester) async {
      final stale = document('remote');
      final server = Server()
        ..remote = stale
        ..etag = etag;
      final repo = SearchPreferencesRepository(preferences: MemoryStore());
      final prefs = SyncPreferences();
      await repo.setFavorite(key('local'), favorite('local'));
      var requests = 0;
      final sync = FavoriteAutoSync(
          repository: repo,
          preferences: prefs,
          service: WebDavSyncService(MockClient((request) async {
            requests++;
            if (request.method == 'GET' && server.writes > 0) {
              return http.Response(stale.encode(), 200);
            }
            return server.respond(request);
          })));
      addTearDown(sync.dispose);
      addTearDown(repo.dispose);
      addTearDown(prefs.dispose);
      sync.start();
      sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await sync.onFavoritesPageEntered();
      expect(server.writes, 1);
      expect(sync.status, contains('未通过读回验证'));
      expect(sync.status, contains('本地收藏已保留'));
      expect(sync.lastSuccess, isNull);
      expect((await repo.loadFavoriteResults()).single.id, 'local');
      final failedRequests = requests;
      await tester.pump(const Duration(hours: 24));
      await sync.onFavoritesPageEntered();
      expect(requests, failedRequests);
    });
  }

  for (final cancelBy in ['background', 'configChange']) {
    testWidgets('device sync stops before PUT after $cancelBy during reads',
        (tester) async {
      final server = Server()
        ..remote = document('remote')
        ..etag = false;
      final repo = SearchPreferencesRepository(preferences: MemoryStore());
      final prefs = SyncPreferences();
      await repo.setFavorite(key('local'), favorite('local'));
      final holdPreflight = Completer<void>();
      var holdFirstRead = true;
      final sync = FavoriteAutoSync(
          repository: repo,
          preferences: prefs,
          service: WebDavSyncService(MockClient((request) async {
            if (request.method == 'GET' && holdFirstRead) {
              holdFirstRead = false;
              await holdPreflight.future;
            }
            return server.respond(request);
          })));
      addTearDown(sync.dispose);
      addTearDown(repo.dispose);
      addTearDown(prefs.dispose);
      sync.start();
      sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
      final pending = sync.onFavoritesPageEntered();
      await tick(tester);
      expect(sync.running, isTrue);
      expect(server.reads, 0);
      expect(server.requests, 1);
      if (cancelBy == 'background') {
        sync.didChangeAppLifecycleState(AppLifecycleState.paused);
      } else {
        prefs.config = const WebDavSyncConfig(
            url: 'https://other.example.com/', autoFavorites: true);
        await sync.reload();
      }
      holdPreflight.complete();
      await pending;
      expect(server.writes, 0);
      expect(server.remote!.favorites.single.id, 'remote');
      expect((await repo.loadFavoriteResults()).single.id, 'local');
      expect(sync.lastSuccess, isNull);
      final requests = server.requests;
      sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump(const Duration(hours: 24));
      await sync.onFavoritesPageEntered();
      expect(server.requests, requests);
    });
  }

  testWidgets(
      'failed directory verification preserves favorites without timed retries',
      (tester) async {
    final requests = <String>[];
    final repo = SearchPreferencesRepository(preferences: MemoryStore());
    final prefs = SyncPreferences();
    await repo.setFavorite(key('local'), favorite('local'));
    final sync = FavoriteAutoSync(
        repository: repo,
        preferences: prefs,
        service: WebDavSyncService(MockClient((request) async {
          requests.add(request.method);
          return http.Response('', request.method == 'MKCOL' ? 201 : 404);
        })));
    addTearDown(sync.dispose);
    addTearDown(repo.dispose);
    addTearDown(prefs.dispose);
    sync.start();
    sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tick(tester);
    expect(requests, isEmpty);
    await sync.onFavoritesPageEntered();
    expect(requests, ['PROPFIND', 'MKCOL', 'PROPFIND']);
    expect(sync.status, contains('创建同步目录后仍无法访问'));
    expect(sync.status, contains('本地收藏已保留'));
    expect(sync.lastSuccess, isNull);
    expect((await repo.loadFavoriteResults()).single.id, 'local');
    await sync.onFavoritesPageEntered();
    await tester.pump(const Duration(hours: 24));
    expect(requests, ['PROPFIND', 'MKCOL', 'PROPFIND']);
    await sync.synchronize(manual: true);
    expect(requests,
        ['PROPFIND', 'MKCOL', 'PROPFIND', 'PROPFIND', 'MKCOL', 'PROPFIND']);
  });

  testWidgets(
      'disabled mode and changed destination do not apply stale remote data',
      (tester) async {
    final server = Server()
      ..remote = document('remote')
      ..hold = Completer<void>();
    final repo = SearchPreferencesRepository(preferences: MemoryStore());
    final prefs = SyncPreferences();
    final sync = FavoriteAutoSync(
        repository: repo,
        preferences: prefs,
        service: WebDavSyncService(MockClient(server.respond)));
    sync.start();
    sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
    unawaited(sync.onFavoritesPageEntered());
    await tick(tester);
    prefs.config = const WebDavSyncConfig(url: 'https://other.example.com');
    await sync.reload();
    server.hold!.complete();
    await tester.pump();
    expect(await repo.loadFavoriteResults(), isEmpty);
    expect(server.writes, 0);
    final reads = server.reads;
    await tester.pump(const Duration(minutes: 10));
    expect(server.reads, reads);
    sync.dispose();
    repo.dispose();
    prefs.dispose();
  });

  testWidgets('deleting during upload survives and is sent on the next pass',
      (tester) async {
    final server = Server()..holdWrite = Completer<void>();
    final repo = SearchPreferencesRepository(preferences: MemoryStore());
    final prefs = SyncPreferences();
    await repo.setFavorite(key('local'), favorite('local'));
    final sync = FavoriteAutoSync(
        repository: repo,
        preferences: prefs,
        service: WebDavSyncService(MockClient(server.respond)));
    sync.start();
    sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
    unawaited(sync.onFavoritesPageEntered());
    await tick(tester);
    expect(sync.running, isTrue);
    await repo.setFavorite(key('local'), null);
    server.holdWrite!.complete();
    await tester.pump();
    expect(await repo.loadFavoriteResults(), isEmpty);
    expect(server.remote!.favorites, isEmpty);
    final requests = server.requests;
    await tester.pump(const Duration(hours: 1));
    expect(server.requests, requests);
    sync.dispose();
    repo.dispose();
    prefs.dispose();
  });

  testWidgets(
      'manual sync works with automatic sync off and does not enable it',
      (tester) async {
    final server = Server();
    final repo = SearchPreferencesRepository(preferences: MemoryStore());
    final prefs = SyncPreferences()
      ..config = const WebDavSyncConfig(url: 'https://example.com/dav/');
    final sync = FavoriteAutoSync(
        repository: repo,
        preferences: prefs,
        service: WebDavSyncService(MockClient(server.respond)));
    sync.start();
    sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tick(tester);
    await repo.setFavorite(key('local'), favorite('local'));
    await tester.pump(const Duration(hours: 1));
    expect(server.requests, 0);
    await sync.synchronize(manual: true);
    expect(server.remote!.favorites.single.id, 'local');
    expect(sync.enabled, isFalse);
    sync.dispose();
    repo.dispose();
    prefs.dispose();
  });

  testWidgets(
      'first entry stays consumed across config reload and resets on app restart',
      (tester) async {
    final server = Server();
    final repo = SearchPreferencesRepository(preferences: MemoryStore());
    final prefs = SyncPreferences()
      ..config = const WebDavSyncConfig(url: 'https://example.com/dav/');
    final service = WebDavSyncService(MockClient(server.respond));
    final sync = FavoriteAutoSync(
        repository: repo, preferences: prefs, service: service);
    sync.start();
    sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await sync.onFavoritesPageEntered();
    expect(server.requests, 0);
    prefs.config = const WebDavSyncConfig(
        url: 'https://example.com/dav/', autoFavorites: true);
    await sync.reload();
    await sync.onFavoritesPageEntered();
    expect(server.requests, 0);
    await sync.synchronize(manual: true);
    expect(server.reads, 1);
    sync.dispose();

    final restarted = FavoriteAutoSync(
        repository: repo, preferences: prefs, service: service);
    restarted.start();
    restarted.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tick(tester);
    expect(server.reads, 1);
    await Future.wait([
      restarted.onFavoritesPageEntered(),
      restarted.onFavoritesPageEntered(),
    ]);
    expect(server.reads, 2);
    restarted.dispose();
    repo.dispose();
    prefs.dispose();
  });

  for (final succeeds in [true, false]) {
    for (final moveAway in [false, true]) {
      testWidgets(
          'TV manual sync keeps ${moveAway ? 'list' : 'button'} focus after ${succeeds ? 'success' : 'failure'}',
          (tester) async {
        await tester.binding.setSurfaceSize(const Size(1920, 1080));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final server = Server();
        final repo = SearchPreferencesRepository(preferences: MemoryStore());
        final prefs = SyncPreferences()
          ..config = const WebDavSyncConfig(url: 'https://example.com/dav/');
        await repo.setFavorite(key('local'), favorite('local'));
        final sync = FavoriteAutoSync(
            repository: repo,
            preferences: prefs,
            service: WebDavSyncService(MockClient(server.respond)));
        sync.start();
        addTearDown(sync.dispose);
        addTearDown(repo.dispose);
        addTearDown(prefs.dispose);
        var menuRequests = 0;
        await tester.pumpWidget(ProviderScope(
          overrides: [
            isTelevisionProvider.overrideWith((ref) => true),
            appSettingsProvider.overrideWithValue(SeedData.defaultSettings),
            searchFavoriteMetadataServiceProvider
                .overrideWithValue(const SearchFavoriteMetadataService()),
            searchPreferencesRepositoryProvider.overrideWithValue(repo),
            favoriteAutoSyncProvider.overrideWithValue(sync),
          ],
          child: MaterialApp(
              home: TvMenuButtonScope(
            onMenuButtonPressed: () => menuRequests++,
            child: const SearchPage(favoritesOnly: true),
          )),
        ));
        await tester.pumpAndSettle();
        final syncAction = find.byWidgetPredicate((widget) =>
            widget is TvFocusableAction && widget.focusId == 'favorites:sync');
        final syncNode =
            tester.widget<TvFocusableAction>(syncAction).focusNode!;
        final button = find.byWidgetPredicate((widget) =>
            widget is StarflowIconButton && widget.focusId == 'favorites:sync');
        syncNode.requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus?.debugLabel,
            contains('search:result:local'));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(syncNode.hasPrimaryFocus, isTrue);
        final rect = tester.getRect(button);
        server.hold = Completer<void>();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pump();
        await tester.pump();
        expect(sync.running, isTrue);
        expect(syncNode.hasPrimaryFocus, isTrue);
        expect(tester.getRect(button), rect);
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(server.reads, 1);
        if (moveAway) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
          expect(FocusManager.instance.primaryFocus?.debugLabel,
              contains('search:result:local'));
        }
        final expectedFocus = FocusManager.instance.primaryFocus;
        if (succeeds) {
          server.hold!.complete();
        } else {
          server.hold!.completeError(http.ClientException('offline'));
        }
        await tester.pumpAndSettle();
        expect(sync.running, isFalse);
        expect(FocusManager.instance.primaryFocus, same(expectedFocus));
        expect(server.reads, succeeds ? 2 : 1);
        if (moveAway) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await tester.pumpAndSettle();
          expect(syncNode.hasPrimaryFocus, isTrue);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
        await tester.pumpAndSettle();
        expect(menuRequests, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  for (final size in [
    const Size(390, 844),
    const Size(1280, 800),
    const Size(1920, 1080)
  ]) {
    testWidgets('compact favorites omit empty descriptions and labels at $size',
        (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = SearchPreferencesRepository(preferences: MemoryStore());
      final prefs = SyncPreferences()
        ..config = const WebDavSyncConfig(url: 'https://example.com/dav/');
      final server = Server();
      final sync = FavoriteAutoSync(
          repository: repo,
          preferences: prefs,
          service: WebDavSyncService(MockClient(server.respond)));
      addTearDown(sync.dispose);
      addTearDown(repo.dispose);
      addTearDown(prefs.dispose);
      await repo.mergeFavoriteSyncDocument(
          FavoriteSyncDocument.decode(document('local').encodeForSync()));
      sync.start();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => size.width == 1920),
          appSettingsProvider.overrideWithValue(SeedData.defaultSettings),
          searchFavoriteMetadataServiceProvider
              .overrideWithValue(const SearchFavoriteMetadataService()),
          searchPreferencesRepositoryProvider.overrideWithValue(repo),
          favoriteAutoSyncProvider.overrideWithValue(sync),
        ],
        child: const MaterialApp(home: SearchPage(favoritesOnly: true)),
      ));
      await tester.pumpAndSettle();
      expect(find.text('local'), findsWidgets);
      expect(find.text('Test'), findsWidgets);
      expect(find.text(''), findsNothing);
      expect(find.byTooltip('手动同步收藏'), findsOneWidget);
      expect(server.requests, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'first favorites entry and top-right manual sync button at $size',
        (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final server = Server();
      final repo = SearchPreferencesRepository(preferences: MemoryStore());
      final prefs = SyncPreferences();
      final sync = FavoriteAutoSync(
          repository: repo,
          preferences: prefs,
          service: WebDavSyncService(MockClient(server.respond)));
      sync.start();
      sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tick(tester);
      final startupReads = server.reads;
      expect(startupReads, 0);
      final visible = ValueNotifier(false);
      final pageRevision = ValueNotifier(0);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => size.width == 1920),
          appSettingsProvider.overrideWithValue(SeedData.defaultSettings),
          searchPreferencesRepositoryProvider.overrideWithValue(repo),
          favoriteAutoSyncProvider.overrideWithValue(sync),
        ],
        child: MaterialApp(
            home: ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (context, enabled, child) =>
              TickerMode(enabled: enabled, child: child!),
          child: ValueListenableBuilder<int>(
            valueListenable: pageRevision,
            builder: (context, revision, child) => SearchPage(
              key: ValueKey(revision),
              favoritesOnly: true,
            ),
          ),
        )),
      ));
      await tester.pumpAndSettle();
      expect(server.reads, startupReads);
      visible.value = true;
      await tester.pumpAndSettle();
      expect(server.reads, startupReads + 1);
      final buttonFinder = find.byWidgetPredicate((widget) =>
          widget is StarflowIconButton && widget.focusId == 'favorites:sync');
      final initialRect = tester.getRect(buttonFinder);
      final titleRect = tester.getRect(find.text('收藏'));
      expect(initialRect.left, greaterThan(titleRect.right));
      expect(initialRect.right, lessThanOrEqualTo(size.width));
      expect(initialRect.top, lessThan(100));
      expect(find.byTooltip('手动同步收藏'), findsOneWidget);
      server.hold = Completer<void>();
      FocusNode? syncNode;
      if (size.width == 1920) {
        final action = find.byWidgetPredicate((widget) =>
            widget is TvFocusableAction && widget.focusId == 'favorites:sync');
        syncNode = tester.widget<TvFocusableAction>(action).focusNode!;
        syncNode.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
      } else {
        tester.widget<StarflowIconButton>(buttonFinder).onPressed!();
      }
      await tester.pump();
      await tester.pump();
      expect(sync.running, isTrue);
      if (syncNode != null) expect(syncNode.hasPrimaryFocus, isTrue);
      expect(tester.widget<StarflowIconButton>(buttonFinder).onPressed, isNull);
      expect(tester.getRect(buttonFinder), initialRect);
      server.hold!.complete();
      await tester.pumpAndSettle();
      if (syncNode != null) expect(syncNode.hasPrimaryFocus, isTrue);
      expect(server.reads, startupReads + 2);
      expect(find.text('收藏已同步'), findsOneWidget);
      final reads = server.reads;
      await tester.pump(const Duration(hours: 1));
      expect(server.reads, reads);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(server.reads, reads);
      visible.value = false;
      await tester.pumpAndSettle();
      visible.value = true;
      await tester.pumpAndSettle();
      expect(server.reads, reads);
      pageRevision.value++;
      await tester.pumpAndSettle();
      expect(server.reads, reads);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      sync.dispose();
      repo.dispose();
      prefs.dispose();
      visible.dispose();
      pageRevision.dispose();
    });
  }
}
