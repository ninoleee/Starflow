import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:starflow/features/live_tv/application/live_playback_controller.dart';
import 'package:starflow/features/live_tv/data/live_epg_parser.dart';
import 'package:starflow/features/live_tv/data/live_playlist_parser.dart';
import 'package:starflow/features/live_tv/data/live_repository.dart';
import 'package:starflow/features/live_tv/domain/live_models.dart';

const _m3u = '''#EXTM3U x-tvg-url="guide.xml"
#EXTINF:-1 tvg-id="cctv1" tvg-logo="logo.png" group-title="新闻,综合",综合频道
#EXTVLCOPT:http-user-agent=Starflow
one.m3u8
#EXTINF:-1 tvg-id="cctv1" group-title="新闻,综合",综合频道
https://example.test/two.ts|Referer=https%3A%2F%2Fexample.test
''';
const _source = LiveSource(
    id: 'source', name: 'Test', url: 'https://example.test/list.m3u');
const _aptvPlaylist = '''#EXTM3U
#EXT-X-APTV-PREVIEW: FALSE
#EXT-X-APTV-LATENCY: FALSE
#EXTINF:-1 tvg-id="news" group-title="News",News Channel
https://example.test/news.m3u8
''';
LiveChannel _channel(String id) =>
    LiveChannel(id: id, sourceId: 'source', name: id, lines: [
      LiveLine('https://example.test/$id'),
      LiveLine('https://example.test/$id/backup')
    ]);

void main() {
  test('APTV channel-list metadata is not an HLS manifest', () {
    final parsed = parseLivePlaylist(
        _aptvPlaylist.replaceFirst(
            '#EXTM3U', '#EXTM3U x-tvg-url="https://example.test/epg.xml.gz"'),
        's');
    expect(parsed.channels.single.name, 'News Channel');
    expect(parsed.channels.single.group, 'News');
    expect(parsed.channels.single.epgId, 'news');
    expect(parsed.epgUrl, 'https://example.test/epg.xml.gz');
  });
  test('real HLS tags remain rejected even alongside APTV metadata', () {
    for (final tag in [
      '#EXT-X-TARGETDURATION:6',
      '#EXT-X-STREAM-INF:BANDWIDTH=1280000',
      '#EXT-X-MEDIA:TYPE=AUDIO',
      '#EXT-X-VERSION:7',
      '#EXT-X-ENDLIST',
      '#EXT-X-PART:DURATION=0.5,URI="part.ts"',
      '#EXT-X-KEY:METHOD=AES-128,URI="key"',
    ]) {
      expect(() => parseLivePlaylist('\uFEFF$_aptvPlaylist\n  $tag', 's'),
          throwsFormatException,
          reason: tag);
    }
  });
  test('M3U quoted commas, relative addresses, headers and multiple lines', () {
    final result = parseLivePlaylist(_m3u, 'source', baseUrl: _source.url);
    expect(result.epgUrl, 'https://example.test/guide.xml');
    expect(result.channels, hasLength(1));
    final c = result.channels.single;
    expect(c.name, '综合频道');
    expect(c.group, '新闻,综合');
    expect(c.lines, hasLength(2));
    expect(c.lines.first.url, 'https://example.test/one.m3u8');
    expect(c.lines.first.headers['User-Agent'], 'Starflow');
    expect(c.lines.last.headers['Referer'], 'https://example.test');
    expect(c.lines.last.headers.containsKey('User-Agent'), false);
    expect(c.logo, 'https://example.test/logo.png');
  });
  test('TXT groups, duplicate removal, URL query commas and backup syntax', () {
    final result = parseLivePlaylist(
        '新闻,#genre#\n频道,http://a.test/live?a=1,2#https://b.test/live\n频道,http://a.test/live?a=1,2',
        's');
    expect(result.channels.single.group, '新闻');
    expect(result.channels.single.lines, hasLength(2));
    expect(result.channels.single.lines.first.url, contains('a=1,2'));
  });
  test('identity survives token changes and remains source isolated', () {
    final a = parseLivePlaylist('频道,http://a.test/live?token=one', 's')
        .channels
        .single;
    final b = parseLivePlaylist('频道,http://a.test/live?token=two', 's')
        .channels
        .single;
    final c = parseLivePlaylist('频道,http://a.test/live?token=one', 'other')
        .channels
        .single;
    expect(a.id, b.id);
    expect(a.id, isNot(c.id));
  });
  test('HLS media manifests, empty lists and unsafe transports rejected', () {
    for (final input in [
      '#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXTINF:6,\nhttp://a.test/1.ts',
      '<html>login</html>',
      '频道,file:///etc/passwd'
    ]) {
      expect(() => parseLivePlaylist(input, 's'), throwsFormatException);
    }
  });
  test('XMLTV timezone, current interval, retention and logo mapping', () {
    final now = DateTime.utc(2026, 9, 20, 12);
    final result = parseLiveEpg(
        '''<tv><channel id="a"><icon src="https://a.test/a.png"/></channel>
      <programme channel="a" start="20260920193000 +0800" stop="20260920203000 +0800"><title>新闻</title></programme>
      <programme channel="a" start="20260901000000 +0000" stop="20260901010000 +0000"><title>过期</title></programme></tv>''',
        now: now);
    expect(result.programmes, hasLength(1));
    expect(result.programmes.single.contains(now), true);
    expect(
        result.programmes.single.contains(result.programmes.single.end), false);
    expect(result.logos['a'], 'https://a.test/a.png');
    expect(parseXmltvTime('20260920080000 -0400'), now);
    expect(parseXmltvTime('20260230080000 +0000'), isNull);
    expect(() => parseLiveEpg('<!DOCTYPE tv><tv/>'), throwsFormatException);
  });

  group('repository', () {
    late LiveRepository repository;
    var status = 200;
    var body = '频道,http://a.test/live?token=one';
    var count = 0;
    setUp(() {
      status = 200;
      count = 0;
      body = '频道,http://a.test/live?token=one';
      repository = LiveRepository(
          openDatabase: () => databaseFactoryMemory
              .openDatabase('live-${DateTime.now().microsecondsSinceEpoch}'),
          client: MockClient((_) async {
            count++;
            return http.Response.bytes(utf8.encode(body), status);
          }));
    });
    tearDown(() => repository.dispose());
    test('APTV subscriptions and local imports populate visible channels',
        () async {
      body = _aptvPlaylist;
      await repository.saveSource(_source);
      await repository.refresh(_source.id);
      expect((await repository.load()).visible().single.name, 'News Channel');
      await repository.saveSource(const LiveSource(id: 'local', name: 'Local'),
          imported: Uint8List.fromList(utf8.encode(_aptvPlaylist)));
      expect((await repository.load()).visible(), hasLength(2));
    });
    test(
        'refresh preserves preferences, failures retain cache, delete cleans source',
        () async {
      await repository.saveSource(_source);
      await repository.refresh('source');
      final id = (await repository.load()).channels.single.id;
      await repository.preference(id, {'favorite': true, 'name': '我的台'});
      await repository.remember(id, 0);
      body = '频道,http://a.test/live?token=two';
      await repository.refresh('source');
      var snapshot = await repository.load();
      expect(snapshot.channels.single.id, id);
      expect(snapshot.name(snapshot.channels.single), '我的台');
      expect(snapshot.preferences[id]!.favorite, true);
      expect(snapshot.lastChannel, id);
      status = 500;
      await expectLater(repository.refresh('source'), throwsStateError);
      snapshot = await repository.load();
      expect(snapshot.channels.single.lines.single.url, endsWith('two'));
      await repository.removeSource('source');
      snapshot = await repository.load();
      expect(snapshot.sources, isEmpty);
      expect(snapshot.channels, isEmpty);
      expect(snapshot.preferences, isEmpty);
      expect(snapshot.lastChannel, isEmpty);
    });
    test('invalid imports do not replace a good playlist', () async {
      await repository.saveSource(_source,
          imported: Uint8List.fromList(utf8.encode(body)));
      await expectLater(
          repository.saveSource(_source,
              imported: Uint8List.fromList(utf8.encode('<html>bad</html>'))),
          throwsFormatException);
      expect((await repository.load()).channels, hasLength(1));
    });
    test('refreshDue observes TTL and coalesces refresh requests', () async {
      await repository.saveSource(_source);
      await Future.wait(
          [repository.refresh('source'), repository.refresh('source')]);
      expect(count, 1);
      await repository.refreshDue();
      expect(count, 1);
    });
    test('serial preference mutations merge instead of losing fields',
        () async {
      await repository.saveSource(_source,
          imported: Uint8List.fromList(utf8.encode(body)));
      final id = (await repository.load()).channels.single.id;
      await Future.wait([
        repository.preference(id, {'favorite': true}),
        repository.preference(id, {'hidden': true})
      ]);
      final p = (await repository.load()).preferences[id]!;
      expect(p.favorite, true);
      expect(p.hidden, true);
    });
    test('source deletion rejects an in-flight response', () async {
      repository.dispose();
      final response = Completer<http.Response>();
      repository = LiveRepository(
          openDatabase: () => databaseFactoryMemory.openDatabase('late'),
          client: MockClient((_) => response.future));
      await repository.saveSource(_source);
      final refresh = repository.refresh('source');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await repository.removeSource('source');
      response.complete(http.Response.bytes(utf8.encode(body), 200));
      await refresh;
      expect((await repository.load()).channels, isEmpty);
    });
  });

  test(
      'compressed EPG refresh, current programme lookup and corrupt-cache retention',
      () async {
    final now = DateTime.now().toUtc();
    String stamp(DateTime d) =>
        '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}${d.hour.toString().padLeft(2, '0')}${d.minute.toString().padLeft(2, '0')}${d.second.toString().padLeft(2, '0')} +0000';
    final xml =
        '<tv><channel id="c"><icon src="https://example.test/logo.png"/></channel><programme channel="c" start="${stamp(now.subtract(const Duration(minutes: 10)))}" stop="${stamp(now.add(const Duration(minutes: 30)))}"><title>Now</title></programme></tv>';
    var bytes = const GZipEncoder().encode(utf8.encode(xml));
    final repository = LiveRepository(
        openDatabase: () => databaseFactoryMemory.openDatabase('gzip'),
        client: MockClient((request) async => request.url.path.endsWith('.gz')
            ? http.Response.bytes(bytes, 200)
            : http.Response.bytes(
                utf8.encode(
                    '#EXTM3U\n#EXTINF:-1 tvg-id="c",Channel\nhttps://example.test/live'),
                200)));
    addTearDown(repository.dispose);
    await repository.saveSource(const LiveSource(
        id: 's',
        name: 'Guide',
        url: 'https://example.test/list',
        epgUrl: 'https://example.test/guide.gz'));
    await repository.refresh('s');
    expect((await repository.guide('s', 'c')).single.title, 'Now');
    expect((await repository.nowNext())['s|c']!.single.title, 'Now');
    expect(
        (await repository.load()).channels.single.logo, endsWith('logo.png'));
    bytes = Uint8List.fromList(bytes)..[bytes.length - 8] ^= 255;
    await expectLater(repository.refresh('s'), throwsFormatException);
    expect((await repository.guide('s', 'c')).single.title, 'Now');
    expect(
        (await repository.load()).channels.single.logo, endsWith('logo.png'));
  });

  testWidgets('rapid switch opens only latest target and ignores stale events',
      (tester) async {
    final engine = _FakeEngine();
    final remembered = <String>[];
    final c = LivePlaybackController(
        engine: engine, onReady: (id, _) async => remembered.add(id));
    c.select(_channel('a'));
    c.select(_channel('b'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(engine.opened, ['https://example.test/b']);
    final oldGeneration = c.generation;
    engine.event(oldGeneration, 'progress');
    expect(remembered, ['b']);
    c.select(_channel('c'));
    engine.event(oldGeneration, 'error');
    expect(c.retries, 0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(engine.opened.last, 'https://example.test/c');
    await c.close();
    c.dispose();
  });
  testWidgets('retry budget is finite and manual selection resets it',
      (tester) async {
    final engine = _FakeEngine();
    final c = LivePlaybackController(engine: engine, onReady: (_, __) async {});
    c.select(_channel('a'));
    await tester.pump(const Duration(milliseconds: 200));
    for (var i = 1; i <= 3; i++) {
      engine.event(c.generation, 'error');
      expect(c.retries, i);
      await tester.pump(Duration(seconds: i * 2));
      await tester.pump(const Duration(milliseconds: 200));
    }
    engine.event(c.generation, 'error');
    expect(c.status, 'failed');
    await tester.pump(const Duration(seconds: 30));
    expect(engine.opened, hasLength(4));
    c.select(_channel('b'));
    expect(c.retries, 0);
    await c.close();
    c.dispose();
  });
  testWidgets('suspend cancels queued opens and stale callbacks',
      (tester) async {
    final engine = _FakeEngine();
    final c = LivePlaybackController(engine: engine, onReady: (_, __) async {});
    c.select(_channel('a'));
    c.suspend();
    await tester.pump(const Duration(seconds: 20));
    expect(engine.opened, isEmpty);
    expect(c.status, 'suspended');
    await c.close();
    c.dispose();
  });
}

class _FakeEngine implements LiveEngine {
  final opened = <String>[];
  void Function(int, String) event = (_, __) {};
  @override
  Future<void> open(
      LiveLine line, int generation, void Function(int, String) onState) async {
    opened.add(line.url);
    event = onState;
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<List<(String, String)>> audioTracks() async => [];
  @override
  Future<void> selectAudio(String id) async {}
}
