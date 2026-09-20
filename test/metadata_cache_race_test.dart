import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/metadata/data/metadata_network_guard.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';
import 'package:starflow/features/metadata/data/wmdb_metadata_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final mode in _Mode.values) {
    test('$mode stale failure cannot remove the replacement inflight',
        () async {
      final started = [Completer<void>(), Completer<void>()];
      final replies = [Completer<http.Response>(), Completer<http.Response>()];
      var requests = 0;
      final harness = _Harness(mode, (_) {
        final index = requests++;
        if (index >= 2) fail('Unexpected duplicate request');
        started[index].complete();
        return replies[index].future;
      });
      addTearDown(harness.close);
      final old = harness.lookup();
      final oldFailure = expectLater(old, throwsException);
      await started[0].future;
      harness.clear();
      final fresh = harness.lookup();
      await started[1].future;
      replies[0].complete(http.Response('Unauthorized', 401));
      await oldFailure;
      final joiner = harness.lookup();
      replies[1].complete(harness.response('Fresh'));
      expect(await fresh, 'Fresh');
      expect(await joiner, 'Fresh');
      expect(await harness.lookup(), 'Fresh');
      expect(requests, 2);
    });

    for (final oldFinishesFirst in [false, true]) {
      test(
          '$mode clear isolates writes and cleanup (old first: '
          '$oldFinishesFirst)', () async {
        final started = [Completer<void>(), Completer<void>()];
        final replies = [
          Completer<http.Response>(),
          Completer<http.Response>()
        ];
        var requests = 0;
        final harness = _Harness(mode, (_) {
          final index = requests++;
          if (index >= 2) {
            fail('A stale finally removed the new inflight request');
          }
          started[index].complete();
          return replies[index].future;
        });
        addTearDown(harness.close);
        final old = harness.lookup();
        await started[0].future;
        harness.clear();
        final fresh = harness.lookup();
        await started[1].future;

        if (oldFinishesFirst) {
          replies[0].complete(harness.response('Old'));
          expect(await old, 'Old');
          final joiner = harness.lookup();
          replies[1].complete(harness.response('Fresh'));
          expect(await fresh, 'Fresh');
          expect(await joiner, 'Fresh');
        } else {
          replies[1].complete(harness.response('Fresh'));
          expect(await fresh, 'Fresh');
          replies[0].complete(harness.response('Old'));
          expect(await old, 'Old');
        }
        expect(await harness.lookup(), 'Fresh');
        expect(requests, 2);
      });
    }

    for (final status in [401, 403, 429, 500, 503]) {
      test('$mode HTTP $status is not negative cached', () async {
        var failed = true;
        var requests = 0;
        late _Harness harness;
        harness = _Harness(mode, (_) async {
          requests++;
          return failed
              ? http.Response('Failure', status)
              : harness.response('Recovered');
        });
        addTearDown(harness.close);
        await expectLater(harness.lookup(), throwsException);
        final beforeRetry = requests;
        failed = false;
        expect(await harness.lookup(), 'Recovered');
        expect(requests, greaterThan(beforeRetry));
        expect(await harness.lookup(), 'Recovered');
      });
    }

    test('$mode invalid response is not negative cached', () async {
      var failed = true;
      late _Harness harness;
      harness = _Harness(
          mode,
          (_) async => failed
              ? http.Response('invalid JSON', 200)
              : harness.response('Recovered'));
      addTearDown(harness.close);
      await expectLater(harness.lookup(), throwsException);
      failed = false;
      expect(await harness.lookup(), 'Recovered');
    });

    test('$mode null response can recover without clear', () async {
      var missing = true;
      late _Harness harness;
      harness = _Harness(
          mode,
          (_) async => missing
              ? (mode.isTmdb
                  ? http.Response('{}', 404)
                  : http.Response(
                      mode == _Mode.wmdbTitle ? '{"data":[]}' : '{}', 200))
              : harness.response('Recovered'));
      addTearDown(harness.close);
      expect(await harness.lookup(), isNull);
      missing = false;
      expect(await harness.lookup(), 'Recovered');
    });
  }

  test('TMDB search retains movie and TV with the same numeric ID', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/search/multi')) {
        return http.Response(
            jsonEncode({
              'results': [
                {'id': 123, 'media_type': 'movie', 'title': 'Probe'},
                {'id': 123, 'media_type': 'tv', 'name': 'Probe'},
              ],
            }),
            200);
      }
      return http.Response('{}', 200);
    });
    addTearDown(client.close);
    final matches = await TmdbMetadataClient(client).searchTitleMatches(
      query: 'Probe',
      readAccessToken: 'synthetic',
    );
    expect(matches.map((match) => (match.tmdbId, match.isSeries)),
        [(123, false), (123, true)]);
  });
}

enum _Mode {
  tmdbTitle,
  tmdbImdb,
  wmdbTitle,
  wmdbDouban;

  bool get isTmdb => this == tmdbTitle || this == tmdbImdb;
}

class _Harness {
  _Harness(this.mode, Future<http.Response> Function(http.Request) reply) {
    client = MockClient((request) async {
      if (mode.isTmdb &&
          (request.url.path.endsWith('/search/multi') ||
              request.url.path.contains('/find/'))) {
        return http.Response(
            jsonEncode({
              mode == _Mode.tmdbTitle ? 'results' : 'movie_results': [
                {'id': 123, 'media_type': 'movie', 'title': 'Probe'},
              ],
            }),
            200);
      }
      return reply(request);
    });
    // Keep HTTP retry policy active, but avoid circuit cooldown masking the
    // cache behavior under test after several deliberately failed responses.
    final guard = MetadataNetworkGuard(failureThreshold: 100);
    tmdb = TmdbMetadataClient(client, networkGuard: guard);
    wmdb = WmdbMetadataClient(client, networkGuard: guard);
  }

  final _Mode mode;
  late final http.Client client;
  late final TmdbMetadataClient tmdb;
  late final WmdbMetadataClient wmdb;

  Future<String?> lookup() async => switch (mode) {
        _Mode.tmdbTitle =>
          (await tmdb.matchTitle(query: 'Probe', readAccessToken: 'synthetic'))
              ?.title,
        _Mode.tmdbImdb => (await tmdb.matchByImdbId(
                imdbId: 'tt123', readAccessToken: 'synthetic'))
            ?.title,
        _Mode.wmdbTitle => (await wmdb.matchTitle(query: 'Probe'))?.title,
        _Mode.wmdbDouban =>
          (await wmdb.matchByDoubanId(doubanId: '123'))?.title,
      };

  http.Response response(String title) {
    final data = {
      'originalName': 'Probe',
      'type': 'movie',
      'data': [
        {'lang': 'Cn', 'name': title}
      ]
    };
    return http.Response(
        jsonEncode(mode.isTmdb
            ? {'title': title}
            : mode == _Mode.wmdbTitle
                ? {
                    'data': [data]
                  }
                : data),
        200);
  }

  void clear() => mode.isTmdb ? tmdb.clearCache() : wmdb.clearCache();
  void close() => client.close();
}
