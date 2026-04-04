import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/metadata/data/imdb_rating_client.dart';

void main() {
  group('ImdbRatingClient', () {
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
  });
}
