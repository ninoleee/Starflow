import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/metadata/data/imdb_rating_client.dart';
import 'package:starflow/features/metadata/data/imdb_rating_dataset.dart';

http.Response _ratingsResponse(String rows) => http.Response.bytes(
      GZipEncoder().encodeBytes(
        utf8.encode('tconst\taverageRating\tnumVotes\n$rows'),
      ),
      200,
    );

void main() {
  group('ImdbRatingClient', () {
    test('concurrent and distinct IDs share one download and one decode',
        () async {
      var requests = 0;
      var decodes = 0;
      final pending = Completer<http.Response>();
      final client = ImdbRatingClient(
        MockClient((_) {
          requests++;
          return pending.future;
        }),
        decodeDataset: (bytes) async {
          decodes++;
          return decodeImdbRatingDataset(bytes);
        },
      );
      final first = client.matchRating(query: '', imdbId: 'tt1');
      final second = client.matchRating(query: '', imdbId: 'tt2');
      final duplicate = client.matchRating(query: '', imdbId: 'tt1');
      pending.complete(_ratingsResponse('tt1\t8.1\t10\ntt2\t7.2\t20\n'));
      final results = await Future.wait([first, second, duplicate]);
      expect(results.map((result) => result?.ratingLabel),
          ['IMDb 8.1', 'IMDb 7.2', 'IMDb 8.1']);
      expect((await client.matchRating(query: '', imdbId: 'tt3'))?.ratingLabel,
          '');
      expect(requests, 1);
      expect(decodes, 1);
      client.clearCache();
      expect(
          (await client.matchRating(query: '', imdbId: 'tt2'))?.voteCount, 20);
      expect(decodes, 1);
    });

    test('failed HTTP and invalid datasets do not poison future requests',
        () async {
      var requests = 0;
      final client = ImdbRatingClient(MockClient((_) async {
        requests++;
        if (requests == 1) return http.Response('unavailable', 503);
        if (requests == 2) return http.Response('invalid gzip', 200);
        return _ratingsResponse('tt1\t8.1\t10\n');
      }));
      await expectLater(client.matchRating(query: '', imdbId: 'tt1'),
          throwsA(isA<ImdbRatingException>()));
      await expectLater(
          client.matchRating(query: '', imdbId: 'tt1'), throwsFormatException);
      expect((await client.matchRating(query: '', imdbId: 'tt1'))?.ratingLabel,
          'IMDb 8.1');
      expect(requests, 3);
    });

    test('late dataset result cannot replace a freshly cleared snapshot',
        () async {
      var requests = 0;
      final oldResponse = Completer<http.Response>();
      final client = ImdbRatingClient(MockClient((_) {
        requests++;
        return requests == 1
            ? oldResponse.future
            : Future.value(_ratingsResponse('tt1\t9.1\t100\n'));
      }));
      final old = client.matchRating(query: '', imdbId: 'tt1');
      await Future<void>.delayed(Duration.zero);
      client.clearCache(includeDataset: true);
      expect((await client.matchRating(query: '', imdbId: 'tt1'))?.ratingLabel,
          'IMDb 9.1');
      oldResponse.complete(_ratingsResponse('tt1\t5.1\t10\n'));
      expect((await old)?.ratingLabel, 'IMDb 5.1');
      expect((await client.matchRating(query: '', imdbId: 'tt1'))?.ratingLabel,
          'IMDb 9.1');
      expect(requests, 2);
    });

    test('matches movie rating from suggestion and dataset', () async {
      final client = ImdbRatingClient(
        MockClient((request) async {
          if (request.url.host == 'v3.sg.media-imdb.com') {
            expect(
              request.url.toString(),
              contains('/suggestion/t/The%20Matrix%201999.json'),
            );
            return http.Response(
              jsonEncode({
                'd': [
                  {
                    'id': 'tt0133093',
                    'l': 'The Matrix',
                    'q': 'feature',
                    'qid': 'movie',
                    'rank': 391,
                    'y': 1999,
                  },
                ],
              }),
              200,
            );
          }

          if (request.url.host == 'datasets.imdbws.com') {
            final payload = utf8.encode(
              'tconst\taverageRating\tnumVotes\n'
              'tt0133093\t8.7\t2201020\n',
            );
            return http.Response.bytes(
              GZipEncoder().encodeBytes(payload),
              200,
            );
          }

          throw UnsupportedError('Unexpected request: ${request.url}');
        }),
      );

      final result = await client.matchRating(
        query: 'The.Matrix.1999.1080p.BluRay',
        year: 1999,
      );

      expect(result, isNotNull);
      expect(result!.imdbId, 'tt0133093');
      expect(result.ratingLabel, 'IMDb 8.7');
      expect(result.voteCount, 2201020);
    });

    test('prefers tv result when series is requested', () async {
      final client = ImdbRatingClient(
        MockClient((request) async {
          if (request.url.host == 'v3.sg.media-imdb.com') {
            return http.Response(
              jsonEncode({
                'd': [
                  {
                    'id': 'tt1111111',
                    'l': 'The Last of Us',
                    'q': 'feature',
                    'qid': 'movie',
                    'rank': 500,
                    'y': 2023,
                  },
                  {
                    'id': 'tt3581920',
                    'l': 'The Last of Us',
                    'q': 'TV series',
                    'qid': 'tvSeries',
                    'rank': 10,
                    'y': 2023,
                  },
                ],
              }),
              200,
            );
          }

          if (request.url.host == 'datasets.imdbws.com') {
            final payload = utf8.encode(
              'tconst\taverageRating\tnumVotes\n'
              'tt1111111\t6.1\t100\n'
              'tt3581920\t8.6\t666000\n',
            );
            return http.Response.bytes(
              GZipEncoder().encodeBytes(payload),
              200,
            );
          }

          throw UnsupportedError('Unexpected request: ${request.url}');
        }),
      );

      final result = await client.matchRating(
        query: 'The Last of Us',
        year: 2023,
        preferSeries: true,
      );

      expect(result, isNotNull);
      expect(result!.imdbId, 'tt3581920');
      expect(result.ratingLabel, 'IMDb 8.6');
    });

    test('deduplicates repeated series suggestion lookups', () async {
      var suggestionRequests = 0;
      final client = ImdbRatingClient(
        MockClient((request) async {
          if (request.url.host == 'v3.sg.media-imdb.com') {
            suggestionRequests += 1;
            return http.Response(
              jsonEncode({
                'd': [
                  {
                    'id': 'tt3581920',
                    'l': 'The Last of Us',
                    'q': 'TV series',
                    'qid': 'tvSeries',
                    'rank': 10,
                    'y': 2023,
                  },
                ],
              }),
              200,
            );
          }
          if (request.url.host == 'datasets.imdbws.com') {
            final payload = utf8.encode(
              'tconst\taverageRating\tnumVotes\n'
              'tt3581920\t8.6\t666000\n',
            );
            return http.Response.bytes(
              GZipEncoder().encodeBytes(payload),
              200,
            );
          }
          throw UnsupportedError('Unexpected request: ${request.url}');
        }),
      );

      await client.matchRating(
        query: 'The Last of Us',
        year: 2023,
        preferSeries: true,
      );
      await client.matchRating(
        query: 'The Last of Us',
        year: 2023,
        preferSeries: true,
      );

      expect(suggestionRequests, 1);
    });
  });
}
