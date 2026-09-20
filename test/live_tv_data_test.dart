import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:starflow/features/live_tv/data/live_epg_parser.dart';
import 'package:starflow/features/live_tv/data/live_playlist_parser.dart';
import 'package:starflow/features/live_tv/data/live_repository.dart';
import 'package:starflow/features/live_tv/domain/live_models.dart';

const source = LiveSource(id: 's', name: 'Source', url: 'https://a.test/list');
Uint8List bytes(String value) => Uint8List.fromList(utf8.encode(value));
String playlist(String name) => '$name,https://a.test/$name';
var _databaseSequence = 0;
LiveRepository repositoryWith(http.Client client) {
  final repository = LiveRepository(
      openDatabase: () => databaseFactoryMemory
          .openDatabase('live-data-${_databaseSequence++}'),
      client: client);
  addTearDown(repository.dispose);
  return repository;
}

String stamp(DateTime date) =>
    '${date.year}${date.month.toString().padLeft(2, '0')}'
    '${date.day.toString().padLeft(2, '0')}${date.hour.toString().padLeft(2, '0')}'
    '${date.minute.toString().padLeft(2, '0')}${date.second.toString().padLeft(2, '0')} +0000';

String guideXml(String logo) {
  final now = DateTime.now().toUtc();
  return '<tv><channel id="A"><icon src="$logo"/></channel>'
      '<programme channel="A" start="${stamp(now.subtract(const Duration(hours: 1)))}" '
      'stop="${stamp(now.add(const Duration(hours: 1)))}"><title>Now</title>'
      '</programme></tv>';
}

void main() {
  group('playlist boundaries', () {
    test('UTF-8 BOM, UTF-16 LE/BE and GBK decode consistently', () {
      const text = '新闻,https://a.test/live';
      final le = [
        0xff,
        0xfe,
        for (final c in text.codeUnits) ...[c & 255, c >> 8]
      ];
      final be = [
        0xfe,
        0xff,
        for (final c in text.codeUnits) ...[c >> 8, c & 255]
      ];
      for (final input in [bytes('\uFEFF$text'), le, be, gbk.encode(text)]) {
        expect(
            parseLivePlaylist(decodeLiveText(input), 's').channels.single.name,
            '新闻');
      }
      expect(() => decodeLiveText([0xff, 0xfe, 0]), throwsFormatException);
    });

    test('empty IDs fall back and display names cannot inject attributes', () {
      final parsed = parseLivePlaylist('''#EXTM3U url-tvg=guide.xml
#EXTINF:-1 tvg-id="" tvg-name="Fallback" group-title="News",Name tvg-id="wrong"
stream
#EXTINF:-1 tvg-name="Blank name fallback",
other
''', 's', baseUrl: source.url);
      expect(parsed.epgUrl, 'https://a.test/guide.xml');
      expect(parsed.channels.first.epgId, 'Fallback');
      expect(parsed.channels.first.name, 'Name tvg-id="wrong"');
      expect(parsed.channels.last.name, 'Blank name fallback');
    });

    test('canonical headers override case-insensitively and deduplicate', () {
      final parsed = parseLivePlaylist('''#EXTM3U
#EXTINF:-1,Channel
#EXTVLCOPT:http-user-agent=old
https://a.test/live|referer=https%3A%2F%2Fa.test&user-agent=new
#EXTINF:-1,Channel
https://a.test/live|User-Agent=new&Referer=https%3A%2F%2Fa.test
''', 's');
      final line = parsed.channels.single.lines.single;
      expect(line.headers, {'User-Agent': 'new', 'Referer': 'https://a.test'});
    });

    test('reject control headers, unsafe URLs and indented HLS manifests', () {
      final parsed = parseLivePlaylist(
          'A,https://a.test/live|User-Agent=x%0D%0AX-Secret%3Ay&Origin=https%3A%2F%2Fa.test',
          's');
      expect(parsed.channels.single.lines.single.headers,
          {'Origin': 'https://a.test'});
      for (final url in [
        'https://u:p@a.test/live',
        'file:///tmp/live',
        'https://a.test/live\rsecret',
        'https://a.test/live secret'
      ]) {
        expect(isLiveHttpUrl(url), false);
      }
      expect(
          () => parseLivePlaylist(
              '\uFEFF#EXTM3U\n  #EXT-X-STREAM-INF:BANDWIDTH=1\nA,https://a.test/live',
              's'),
          throwsFormatException);
    });

    test('per-channel line cap counts distinct lines only', () {
      String lines(int count) =>
          List.generate(count, (i) => 'A,https://a.test/$i').join('\n');
      final atLimit = lines(liveMaxLinesPerChannel);
      expect(
          parseLivePlaylist('$atLimit\nA,https://a.test/0', 's')
              .channels
              .single
              .lines,
          hasLength(liveMaxLinesPerChannel));
      expect(() => parseLivePlaylist(lines(liveMaxLinesPerChannel + 1), 's'),
          throwsFormatException);
    });

    test('channel and aggregate line caps reject oversized lists', () {
      final channels =
          List.generate(liveMaxChannels, (i) => 'C$i,https://a.test/$i')
              .join('\n');
      expect(parseLivePlaylist(channels, 's').channels,
          hasLength(liveMaxChannels));
      expect(() => parseLivePlaylist('$channels\nExtra,https://a.test/x', 's'),
          throwsFormatException);
      final lines = List.generate(liveMaxLines,
              (i) => 'C${i ~/ liveMaxLinesPerChannel},https://a.test/$i')
          .join('\n');
      expect(
          parseLivePlaylist(lines, 's')
              .channels
              .fold<int>(0, (sum, c) => sum + c.lines.length),
          liveMaxLines);
      expect(() => parseLivePlaylist('$lines\nExtra,https://a.test/x', 's'),
          throwsFormatException);
    });
  });

  group('XMLTV boundaries', () {
    test('invalid calendar values and offsets do not normalize silently', () {
      for (final value in [
        '20260230000000 Z',
        '20261301000000 Z',
        '20260001000000 Z',
        '20260920240000 Z',
        '20260920126000 Z',
        '20260920120060 Z',
        '20260920120000 +2400',
        '20260920120000 +0060'
      ]) {
        expect(parseXmltvTime(value), isNull, reason: value);
      }
      expect(parseXmltvTime('202609201200'), DateTime.utc(2026, 9, 20, 12));
      expect(parseXmltvTime('20260920174500 +0545'),
          DateTime.utc(2026, 9, 20, 12));
    });

    test('retention excludes exact edges and counts invalid entries too', () {
      final now = DateTime.utc(2026, 9, 20);
      final parsed = parseLiveEpg('''<tv>
<programme channel="a" start="20260918000000" stop="20260919000000"/>
<programme channel="a" start="20260927000000" stop="20260927010000"/>
<programme channel=" a " start="20260920000000" stop="20260920010000"><title>Valid</title></programme>
</tv>''', now: now);
      expect(parsed.programmes.single.channel, 'a');
      final invalid = List.filled(liveEpgMaxEntries, '<programme/>').join();
      expect(parseLiveEpg('<tv>$invalid</tv>', now: now).programmes, isEmpty);
      expect(() => parseLiveEpg('<tv>$invalid<programme/></tv>', now: now),
          throwsFormatException);
    });

    test('XML errors never expose subscription content', () {
      for (final xml in [
        '<tv><secret-password></tv>',
        '<!DOCTYPE tv [<!ENTITY x "secret-password">]><tv/>',
        '<!ENTITY x "secret-password"><tv/>'
      ]) {
        expect(
            () => parseLiveEpg(xml),
            throwsA(isA<FormatException>().having((e) => e.toString(),
                'safe error', isNot(contains('secret-password')))));
      }
    });
  });

  group('repository retention and ordering', () {
    test('missing channels retain prefs until their source is removed',
        () async {
      final r = repositoryWith(MockClient((_) async => http.Response('', 500)));
      await r.saveSource(source, imported: bytes(playlist('A')));
      final id = (await r.load()).channels.single.id;
      await r
          .preference(id, {'favorite': true, 'hidden': true, 'name': 'Custom'});
      await r.remember(id, 999);
      expect((await r.load()).preferences[id]!.line, 0);
      await r.saveSource(source, imported: bytes(playlist('B')));
      expect((await r.load()).preferences[id]!.favorite, true);
      await r.saveSource(source, imported: bytes(playlist('A')));
      expect((await r.load()).preferences[id]!.name, 'Custom');
      await r.saveSource(source, imported: bytes(playlist('B')));
      const other = LiveSource(id: 'other', name: 'Other');
      await r.saveSource(other, imported: bytes(playlist('A')));
      final otherId =
          (await r.load()).channels.firstWhere((c) => c.sourceId == 'other').id;
      await r.preference(otherId, {'favorite': true});
      await r.removeSource('s');
      await r.preference(id, {'favorite': true});
      await r.remember(id, 0);
      final snapshot = await r.load();
      expect(snapshot.lastChannel, isEmpty);
      expect(snapshot.preferences.keys, [otherId]);
      expect(snapshot.preferences[otherId]!.favorite, true);
    });

    test('legacy prefs acquire ownership before old channels disappear',
        () async {
      final r = repositoryWith(MockClient((_) async => http.Response('', 500)));
      await r.saveSource(source, imported: bytes(playlist('A')));
      final id = (await r.load()).channels.single.id;
      final db = await r.database;
      await StoreRef<String, String>('channelOwners').delete(db);
      await stringMapStoreFactory
          .store('preferences')
          .record(id)
          .put(db, {'favorite': true});
      await r.saveSource(source, imported: bytes(playlist('B')));
      await r.removeSource('s');
      expect((await r.load()).preferences, isEmpty);
    });

    test('custom order survives refresh; new channels append stably', () async {
      final r = repositoryWith(MockClient((_) async => http.Response('', 500)));
      await r.saveSource(source,
          imported: bytes(['A', 'B', 'C'].map(playlist).join('\n')));
      final b = (await r.load()).channels.firstWhere((c) => c.name == 'B');
      await r.move(b.id, -1);
      await r.saveSource(source,
          imported: bytes(['D', 'C', 'B', 'A'].map(playlist).join('\n')));
      expect(
          (await r.load()).visible().map((c) => c.name), ['B', 'A', 'C', 'D']);
      await r.preference(b.id, {'favorite': true});
      expect(
          (await r.load()).visible().map((c) => c.name), ['B', 'A', 'C', 'D']);
    });

    test('EPG failures preserve programmes and logos, success replaces logos',
        () async {
      var listing = playlist('A');
      var xml = guideXml('https://a.test/old.png');
      var epgStatus = 200;
      final r = repositoryWith(MockClient((request) async =>
          request.url.path == '/guide'
              ? http.Response(xml, epgStatus)
              : http.Response(listing, 200)));
      const s = LiveSource(
          id: 's',
          name: 'EPG',
          url: 'https://a.test/list',
          epgUrl: 'https://a.test/guide');
      await r.saveSource(s);
      await r.refresh('s');
      epgStatus = 500;
      listing = 'A,https://a.test/new-token';
      await expectLater(r.refresh('s'), throwsStateError);
      var snapshot = await r.load();
      expect(snapshot.channels.single.lines.single.url, endsWith('new-token'));
      expect(snapshot.channels.single.logo, endsWith('old.png'));
      expect((await r.guide('s', 'A')).single.title, 'Now');
      listing = playlist('B');
      await expectLater(r.refresh('s'), throwsStateError);
      listing = playlist('A');
      await expectLater(r.refresh('s'), throwsStateError);
      expect((await r.load()).channels.single.logo, endsWith('old.png'));
      epgStatus = 200;
      xml = guideXml('https://a.test/new.png');
      await r.refresh('s');
      expect((await r.load()).channels.single.logo, endsWith('new.png'));
      listing =
          '#EXTM3U\n#EXTINF:-1 tvg-id="A" tvg-logo="https://a.test/list.png",A\nhttps://a.test/a';
      await r.refresh('s');
      expect((await r.load()).channels.single.logo, endsWith('list.png'));
      await r.removeSource('s');
      expect(await r.guide('s', 'A'), isEmpty);
      expect(
          await stringMapStoreFactory.store('epgLogos').count(await r.database),
          0);
    });
  });

  group('refresh generations', () {
    for (final oldFails in [false, true]) {
      test(
          'edited source refresh does not coalesce with old ${oldFails ? 'failure' : 'success'}',
          () async {
        final pending = Completer<http.Response>();
        final started = Completer<void>();
        var newRequests = 0;
        final r = repositoryWith(MockClient((request) {
          if (request.url.path == '/list') {
            started.complete();
            return pending.future;
          }
          newRequests++;
          return Future.value(http.Response(playlist('New'), 200));
        }));
        await r.saveSource(source);
        final old = r.refresh('s');
        await started.future;
        final save = r.saveSource(const LiveSource(
            id: 's', name: 'Edited', url: 'https://a.test/new'));
        final fresh = r.refresh('s');
        await save;
        await fresh;
        expect(newRequests, 1);
        pending.complete(http.Response(playlist('Old'), oldFails ? 500 : 200));
        await old;
        expect((await r.load()).channels.single.name, 'New');
        expect((await r.load()).sources.single.name, 'Edited');
      });
    }

    test(
        'delete and recreate rejects old EPG response and old completion cleanup',
        () async {
      final pending = Completer<http.Response>();
      final epgStarted = Completer<void>();
      final freshResponse = Completer<http.Response>();
      final freshStarted = Completer<void>();
      var newRequests = 0;
      final r = repositoryWith(MockClient((request) {
        if (request.url.path == '/guide') {
          epgStarted.complete();
          return pending.future;
        }
        if (request.url.path == '/new') {
          newRequests++;
          freshStarted.complete();
          return freshResponse.future;
        }
        return Future.value(http.Response(playlist('A'), 200));
      }));
      await r.saveSource(const LiveSource(
          id: 's',
          name: 'Old',
          url: 'https://a.test/list',
          epgUrl: 'https://a.test/guide'));
      final old = r.refresh('s');
      await epgStarted.future;
      await r.removeSource('s');
      await r.saveSource(
          const LiveSource(id: 's', name: 'New', url: 'https://a.test/new'));
      final fresh = r.refresh('s');
      await freshStarted.future;
      pending.complete(http.Response(guideXml('https://a.test/old.png'), 200));
      await old;
      final coalesced = r.refresh('s');
      expect(identical(fresh, coalesced), true);
      freshResponse.complete(http.Response(playlist('A'), 200));
      await Future.wait([fresh, coalesced]);
      expect(newRequests, 1);
      expect(await r.guide('s', 'A'), isEmpty);
      expect((await r.load()).channels.single.logo, isEmpty);
    });

    test('disable prevents late playlist and automatic requests', () async {
      final pending = Completer<http.Response>();
      final started = Completer<void>();
      var requests = 0;
      final r = repositoryWith(MockClient((_) {
        requests++;
        started.complete();
        return pending.future;
      }));
      await r.saveSource(source, imported: bytes(playlist('Cached')));
      final refresh = r.refresh('s');
      await started.future;
      await r.saveSource(const LiveSource(
          id: 's',
          name: 'Disabled',
          url: 'https://a.test/list',
          enabled: false));
      pending.complete(http.Response(playlist('Late'), 200));
      await refresh;
      await r.refresh('s');
      await r.refreshDue();
      expect(requests, 1);
      expect((await r.load()).channels.single.name, 'Cached');
      expect((await r.load()).visible(), isEmpty);
    });

    test('delete while import parses cannot resurrect source', () async {
      final r = repositoryWith(MockClient((_) async => http.Response('', 500)));
      await r.saveSource(source, imported: bytes(playlist('Cached')));
      final imported = r.saveSource(source, imported: bytes(playlist('Late')));
      final removed = r.removeSource('s');
      await Future.wait([imported, removed]);
      expect((await r.load()).sources, isEmpty);
      expect((await r.load()).channels, isEmpty);
    });

    test('edit clears retry throttle and preserves committed timestamps',
        () async {
      var count = 0;
      final r = repositoryWith(MockClient((request) async {
        count++;
        return http.Response(
            playlist('A'), request.url.path == '/list' ? 500 : 200);
      }));
      await r.saveSource(source);
      await expectLater(r.refresh('s'), throwsStateError);
      const edited =
          LiveSource(id: 's', name: 'Edited', url: 'https://a.test/new');
      await r.saveSource(edited);
      await r.refreshDue();
      expect(count, 2);
      final updatedAt = (await r.load()).sources.single.updatedAt;
      expect(updatedAt, greaterThan(0));
      await r.saveSource(edited);
      expect((await r.load()).sources.single.updatedAt, updatedAt);
    });
  });

  group('download and compression bounds', () {
    test('oversized local bytes fail before decode and keep cached channels',
        () async {
      final r = repositoryWith(MockClient((_) async => http.Response('', 500)));
      await r.saveSource(source, imported: bytes(playlist('A')));
      final oversized = Uint8List(livePlaylistMaxBytes + 1);
      await expectLater(
          r.saveSource(source, imported: oversized), throwsFormatException);
      expect((await r.load()).channels.single.name, 'A');
    });

    for (final advertised in [false, true]) {
      test(
          'oversized ${advertised ? 'declared' : 'streamed'} response retains cache',
          () async {
        final r = repositoryWith(_StreamingClient((_) async =>
            http.StreamedResponse(
                Stream.value(
                    Uint8List(advertised ? 0 : livePlaylistMaxBytes + 1)),
                200,
                contentLength: advertised ? livePlaylistMaxBytes + 1 : null)));
        await r.saveSource(source, imported: bytes(playlist('A')));
        await expectLater(r.refresh('s'), throwsStateError);
        expect((await r.load()).channels.single.name, 'A');
      });
    }

    test('network exception URI and body content are not rethrown', () async {
      final r = repositoryWith(MockClient((request) async =>
          throw http.ClientException('secret-password', request.url)));
      await r.saveSource(const LiveSource(
          id: 'secret-source',
          name: 'Source',
          url:
              'https://a.test/secret-user/secret-password?token=secret-token'));
      await expectLater(
          r.refresh('secret-source'),
          throwsA(isA<StateError>().having(
              (e) => e.toString(), 'safe error', isNot(contains('secret')))));
    });

    test('truncated gzip, bad CRC, bad size and decompression bomb retain EPG',
        () async {
      final valid = const GZipEncoder()
          .encode(bytes(guideXml('https://a.test/logo.png')));
      var data = valid;
      final r = repositoryWith(
          MockClient((_) async => http.Response.bytes(data, 200)));
      await r.saveSource(const LiveSource(
          id: 's', name: 'EPG', epgUrl: 'https://a.test/guide'));
      await r.refresh('s');
      final bomb = const GZipEncoder().encode(Uint8List(liveEpgMaxBytes + 1));
      final forgedSizeBomb = Uint8List.fromList(bomb);
      ByteData.sublistView(forgedSizeBomb)
          .setUint32(forgedSizeBomb.length - 4, 0, Endian.little);
      for (final invalid in [
        Uint8List.fromList([31, 139]),
        Uint8List.fromList(valid.sublist(0, valid.length - 5)),
        Uint8List.fromList(valid)..[valid.length - 8] ^= 255,
        Uint8List.fromList(valid)..[valid.length - 4] ^= 255,
        Uint8List.fromList(valid)..[3] |= 0x20,
        bomb,
        forgedSizeBomb,
      ]) {
        data = invalid;
        await expectLater(r.refresh('s'),
            throwsA(anyOf(isA<FormatException>(), isA<StateError>())));
        expect((await r.guide('s', 'A')).single.title, 'Now');
      }
    });
  });
}

class _StreamingClient extends http.BaseClient {
  _StreamingClient(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}
