import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:starflow/features/live_tv/application/live_playback_controller.dart';
import 'package:starflow/features/live_tv/data/live_backup.dart';
import 'package:starflow/features/live_tv/data/live_repository.dart';
import 'package:starflow/features/live_tv/data/live_playlist_parser.dart';
import 'package:starflow/features/live_tv/domain/live_models.dart';
import 'package:starflow/features/playback/application/active_playback_cleanup.dart';
import 'package:starflow/core/network/network_proxy_config.dart';

Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));
String playlist(String name, {String epg = '', String group = 'News'}) =>
    '#EXTM3U url-tvg="$epg"\n#EXTINF:-1 tvg-id="stable" group-title="$group",$name\nhttps://a.test/live';
const source = LiveSource(id: 's', name: 'Source', url: 'https://a.test/list');
const channel = LiveChannel(
    id: 'c',
    sourceId: 's',
    name: 'Channel',
    lines: [LiveLine('https://a.test/live')]);
int sequence = 0;
LiveRepository repository([http.Client? client]) {
  final r = LiveRepository(
      openDatabase: () =>
          databaseFactoryMemory.openDatabase('review-${sequence++}'),
      client: client ?? MockClient((_) async => http.Response('<tv/>', 200)));
  addTearDown(r.dispose);
  return r;
}

void main() {
  test(
      'local reimport invalidates changed discovered EPG but preserves override TTL',
      () async {
    final requests = <String>[];
    final r = repository(MockClient((request) async {
      requests.add(request.url.toString());
      return http.Response('<tv/>', 200);
    }));
    const local = LiveSource(id: 's', name: 'Local');
    await r.saveSource(local,
        imported: bytes(playlist('A', epg: 'https://a.test/a.xml')));
    await r.refreshDue();
    await r.saveSource(local,
        imported: bytes(playlist('B', epg: 'https://a.test/b.xml')));
    expect((await r.load()).sources.single.epgUpdatedAt, 0);
    await r.refreshDue();
    expect(requests, ['https://a.test/a.xml', 'https://a.test/b.xml']);
    const override = LiveSource(
        id: 's', name: 'Local', epgUrl: 'https://a.test/override.xml');
    await r.saveSource(override);
    await r.refreshDue();
    final updatedAt = (await r.load()).sources.single.epgUpdatedAt;
    await r.saveSource(override,
        imported: bytes(playlist('C', epg: 'https://a.test/c.xml')));
    await r.refreshDue();
    expect((await r.load()).sources.single.epgUpdatedAt, updatedAt);
    expect(requests, [
      'https://a.test/a.xml',
      'https://a.test/b.xml',
      'https://a.test/override.xml'
    ]);
  });

  test('late refresh failure after restore is discarded with its old epoch',
      () async {
    final started = Completer<void>();
    final response = Completer<http.Response>();
    final r = repository(MockClient((_) {
      started.complete();
      return response.future;
    }));
    await r.saveSource(source, imported: bytes(playlist('Saved')));
    final backup = await r.exportBackup();
    final refresh = r.refresh('s');
    await started.future;
    await r.importBackup(backup, LiveBackupImportMode.replace);
    response.complete(http.Response('failed', 503));
    await refresh;
    expect(await r.exportBackup(), backup);
  });

  test('MPV cancellation during prior disposal prevents player creation',
      () async {
    final engine = PreparingMpvEngine();
    final opening = engine.open(channel.lines.single, 1, (_, __) {});
    final rejected = expectLater(opening, throwsA(isA<LiveOpenCancelled>()));
    var acknowledged = false;
    final cancellation = engine.cancelOpen().then((_) => acknowledged = true);
    await Future<void>.delayed(Duration.zero);
    expect(acknowledged, isFalse);
    expect(engine.player, isNull);
    engine.preparation.complete();
    await rejected;
    await cancellation;
    expect(acknowledged, isTrue);
    expect(engine.player, isNull);
    expect(engine.video, isNull);
    await engine.dispose();
  });

  test(
      'discovery follows A to B, override wins, clearing override restores discovery',
      () async {
    var discovered = 'https://a.test/a.xml';
    final requests = <String>[];
    final r = repository(MockClient((request) async {
      requests.add(request.url.toString());
      return http.Response(
          request.url.path == '/list'
              ? playlist('A', epg: discovered)
              : '<tv/>',
          200);
    }));
    await r.saveSource(source);
    await r.refresh('s');
    expect((await r.load()).sources.single.epgUrl, '');
    discovered = 'https://a.test/b.xml';
    await r.refresh('s');
    expect(requests.last, discovered);
    await r.saveSource(LiveSource.fromJson(
        {...source.toJson(), 'epgUrl': 'https://a.test/user.xml'}));
    await r.refresh('s');
    expect(requests.last, 'https://a.test/user.xml');
    await r.saveSource(source);
    await r.refresh('s');
    expect(requests.last, discovered);
    expect((await r.load()).sources.single.discoveredEpgUrl, discovered);
  });

  test('local playlist age is not part of remote EPG TTL after restart',
      () async {
    var downloads = 0;
    final r = repository(MockClient((_) async {
      downloads++;
      return http.Response('<tv/>', 200);
    }));
    await r.saveSource(
        const LiveSource(
            id: 's', name: 'Local', epgUrl: 'https://a.test/guide'),
        imported: bytes(playlist('A')));
    await r.refresh('s');
    final db = await r.database;
    final store = stringMapStoreFactory.store('sources');
    final old = (await store.record('s').get(db))!;
    await store.record('s').put(db, {...old, 'updatedAt': 1});
    final restored = repository(MockClient((_) async {
      downloads++;
      return http.Response('<tv/>', 200);
    }));
    await restored.importBackup(
        await r.exportBackup(), LiveBackupImportMode.replace);
    await restored.refreshDue();
    expect(downloads, 1);
    final current = (await store.record('s').get(db))!;
    await store.record('s').put(db, {...current, 'epgUpdatedAt': 0});
    await restored.importBackup(
        await r.exportBackup(), LiveBackupImportMode.replace);
    await restored.refreshDue();
    expect(downloads, 2);
  });

  test(
      'stable tvg-id survives rename and regroup; duplicate identities remain distinct',
      () async {
    final a = parseLivePlaylist(playlist('A'), 's').channels.single;
    final b =
        parseLivePlaylist(playlist('B', group: 'Other'), 's').channels.single;
    expect(a.id, b.id);
    final ambiguous =
        parseLivePlaylist('${playlist('A')}\n${playlist('B')}', 's');
    expect(ambiguous.channels.map((c) => c.id).toSet(), hasLength(2));
    final r = repository();
    await r.saveSource(source, imported: bytes(playlist('A')));
    await r.preference(
        a.id, {'favorite': true, 'hidden': true, 'order': 3, 'name': 'Custom'});
    await r.remember(a.id, 0);
    await r.saveSource(source, imported: bytes(playlist('B', group: 'Other')));
    final snap = await r.load();
    expect(snap.channels.single.id, a.id);
    expect(snap.preference(snap.channels.single).favorite, isTrue);
    expect(snap.lastChannel, a.id);
  });

  test(
      'legacy channel ID migrates one-to-one but never merges ambiguous shared EPG',
      () async {
    final r = repository();
    await r.saveSource(source);
    final db = await r.database;
    final channels = stringMapStoreFactory.store('channels');
    final old = {
      ...parseLivePlaylist(playlist('Old'), 's').channels.single.toJson(),
      'id': 'legacy'
    }..remove('identity');
    await channels.record('legacy').put(db, old);
    await r.preference('legacy', {'favorite': true});
    await r.remember('legacy', 0);
    await r.saveSource(source, imported: bytes(playlist('New')));
    final stableId = (await r.load()).channels.single.id;
    expect(stableId, isNot('legacy'));
    expect((await r.load()).preferences[stableId]!.favorite, isTrue);
    expect((await r.load()).lastChannel, stableId);
    await channels
        .record('other')
        .put(db, {...old, 'id': 'other', 'name': 'Other'});
    await r.saveSource(source, imported: bytes(playlist('Newest')));
    expect((await r.load()).channels.single.id, isNot('legacy'));
  });

  test(
      'versioned backup retains IDs, credentials, historical preferences and caches',
      () async {
    final r = repository();
    await r.saveSource(source,
        imported: bytes('${playlist('A')}|User-Agent=secret'));
    final id = (await r.load()).channels.single.id;
    await r.preference(id, {
      'favorite': true,
      'hidden': true,
      'order': 8,
      'group': 'Mine',
      'epgId': 'mapped'
    });
    await r.remember(id, 0);
    await r.setEngine('exo');
    final encoded = await r.exportBackup();
    final copy = repository();
    await copy.importBackup(encoded, LiveBackupImportMode.replace);
    expect(jsonDecode(utf8.decode(await copy.exportBackup())),
        jsonDecode(utf8.decode(encoded)));
    expect(
        (await copy.load()).channels.single.lines.single.headers['User-Agent'],
        'secret');
    await copy.removeSource('s');
    expect((await copy.load()).preferences, isEmpty);
  });

  test(
      'backup merge keeps existing source and preferences, replace replaces, invalid is atomic',
      () async {
    final a = repository(), b = repository();
    await a.saveSource(source, imported: bytes(playlist('Imported')));
    await b.saveSource(source, imported: bytes(playlist('Existing')));
    await b.setEngine('exo');
    final backup = await a.exportBackup();
    await b.importBackup(backup, LiveBackupImportMode.merge);
    expect((await b.load()).channels.single.name, 'Existing');
    expect((await b.load()).engine, 'exo');
    final invalid = jsonDecode(utf8.decode(backup)) as Map<String, dynamic>;
    invalid['version'] = 99;
    await expectLater(
        b.importBackup(
            bytes(jsonEncode(invalid)), LiveBackupImportMode.replace),
        throwsFormatException);
    expect((await b.load()).channels.single.name, 'Existing');
    await b.importBackup(backup, LiveBackupImportMode.replace);
    expect((await b.load()).channels.single.name, 'Imported');
  });

  test('inflight refresh cannot overwrite a restored source', () async {
    final gate = Completer<http.Response>();
    final started = Completer<void>();
    final r = repository(MockClient((_) {
      started.complete();
      return gate.future;
    }));
    await r.saveSource(source, imported: bytes(playlist('Saved')));
    final backup = await r.exportBackup();
    final refresh = r.refresh('s');
    await started.future;
    await r.importBackup(backup, LiveBackupImportMode.replace);
    gate.complete(http.Response(playlist('Late'), 200));
    await refresh;
    expect((await r.load()).channels.single.name, 'Saved');
  });

  testWidgets(
      'never-settling open is cancelled before retry and close drains only acknowledgement',
      (tester) async {
    final engine = CancelEngine()..blockOpen = true;
    final c = LivePlaybackController(engine: engine, onReady: (_, __) async {});
    c.select(channel);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    await tester.pump(livePlaybackTimeout);
    expect(engine.cancellations, 1);
    expect(c.status, 'retrying');
    expect(engine.active, 0);
    engine.blockOpen = false;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 180));
    expect(engine.opens, 2);
    expect(engine.maxActive, 1);
    await c.close();
    c.dispose();
    expect(engine.active, 0);
  });

  testWidgets(
      'cancel acknowledgement is a barrier even when old open settles early',
      (tester) async {
    final engine = CancelEngine()..blockOpen = true;
    engine.cancelGate = Completer<void>();
    final c = LivePlaybackController(engine: engine, onReady: (_, __) async {});
    c.select(channel);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    c.select(channel);
    await tester.pump(const Duration(milliseconds: 180));
    expect(engine.opens, 1);
    engine.pendingOpen.complete();
    await tester.pump();
    expect(engine.opens, 1);
    engine.blockOpen = false;
    engine.cancelGate!.complete();
    await tester.pump();
    expect(engine.opens, 2);
    expect(engine.maxActive, 1);
    await c.close();
    c.dispose();
  });

  testWidgets('global cleanup cancels a never-settling open', (tester) async {
    final engine = CancelEngine()..blockOpen = true;
    final c = LivePlaybackController(engine: engine, onReady: (_, __) async {});
    c.select(channel);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    final cleanup = ActivePlaybackCleanupCoordinator.cleanupAll(reason: 'test');
    await tester.pump();
    await cleanup;
    expect(engine.active, 0);
    expect(engine.cancellations, 1);
    c.dispose();
  });

  testWidgets('close waits for native cancellation acknowledgement, not open',
      (tester) async {
    final engine = CancelEngine()..blockOpen = true;
    engine.cancelGate = Completer<void>();
    final c = LivePlaybackController(engine: engine, onReady: (_, __) async {});
    c.select(channel);
    await tester.pump(const Duration(milliseconds: 180));
    var closed = false;
    final closing = c.close().then((_) => closed = true);
    await tester.pump(const Duration(minutes: 1));
    expect(closed, isFalse);
    expect(engine.active, 1);
    expect(engine.cancellations, 1);
    engine.cancelGate!.complete();
    await tester.pump();
    await closing;
    expect(engine.pendingOpen.isCompleted, isFalse);
    expect(engine.active, 0);
    expect(closed, isTrue);
    c.dispose();
  });

  testWidgets(
      'pause and suppression stop watchdog; old audio generation cannot select',
      (tester) async {
    final engine = CancelEngine();
    final c = LivePlaybackController(engine: engine, onReady: (_, __) async {});
    c.select(channel);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    final old = c.generation;
      for (final pause in ['paused:3', 'paused:2', 'suppressed:1']) {
        engine.emit(pause);
        engine.emit('buffering');
        engine.emit('progress');
        engine.emit('error');
        engine.emit('ended');
        await tester.pump(const Duration(minutes: 1));
        expect(c.status, 'paused');
        expect(c.pauseReason, pause);
        expect(c.retries, 0);
        engine.emit('resumed');
        expect(c.pauseReason, isEmpty);
      }
    engine.emit('error');
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 180));
    await c.selectAudio(old, '0:1');
    expect(engine.selections, isEmpty);
    await c.selectAudio(c.generation, '0:1');
    expect(engine.selections, ['0:1']);
    await c.close();
    c.dispose();
  });

  testWidgets('session mute is applied before either replacement engine opens',
      (tester) async {
    for (var i = 0; i < 2; i++) {
      final engine = CancelEngine();
      final c = LivePlaybackController(
          engine: engine, muted: true, onReady: (_, __) async {});
      c.select(channel);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      expect(engine.openVolumes, [0]);
      await c.close();
      c.dispose();
    }
  });
}

class CancelEngine implements CancellableLiveEngine {
  bool blockOpen = false;
  int active = 0, maxActive = 0, opens = 0, cancellations = 0;
  double volume = 1;
  final openVolumes = <double>[];
  final selections = <String>[];
  final pendingOpen = Completer<void>();
  Completer<void>? cancelGate;
  void Function(String) emit = (_) {};
  @override
  Future<void> open(
      LiveLine line, int generation, void Function(int, String) onState) {
    emit = (state) => onState(generation, state);
    opens++;
    active++;
    if (active > maxActive) maxActive = active;
    openVolumes.add(volume);
    return blockOpen ? pendingOpen.future : Future.value();
  }

  @override
  Future<void> cancelOpen() async {
    cancellations++;
    await cancelGate?.future;
    active = 0;
  }

  @override
  Future<void> stop() async {
    active = 0;
  }

  @override
  Future<void> dispose() async {
    active = 0;
  }

  @override
  Future<void> setVolume(double value) async {
    volume = value;
  }

  @override
  Future<List<(String, String)>> audioTracks() async => [('0:1', 'Audio')];
  @override
  Future<void> selectAudio(String id) async {
    selections.add(id);
  }
}

class PreparingMpvEngine extends MpvLiveEngine {
  PreparingMpvEngine() : super(const NetworkProxyConfig());
  final preparation = Completer<void>();

  @override
  Future<void> stop() => preparation.future;
}
