import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/metadata/data/imdb_metadata_client.dart';

void main() {
  group('ImdbMetadataClient', () {
    test('matches movie metadata from suggestion response', () async {
      final client = ImdbMetadataClient(
        MockClient((request) async {
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
                  's': 'Keanu Reeves, Laurence Fishburne',
                  'i': {
                    'imageUrl': 'https://m.media-amazon.com/images/matrix.jpg',
                  },
                },
                {
                  'id': 'tt0234215',
                  'l': 'The Matrix Reloaded',
                  'q': 'feature',
                  'qid': 'movie',
                  'rank': 2227,
                  'y': 2003,
                },
              ],
            }),
            200,
          );
        }),
      );

      final result = await client.matchTitle(
        query: 'The.Matrix.1999.1080p.BluRay',
        year: 1999,
      );

      expect(result, isNotNull);
      expect(result!.imdbId, 'tt0133093');
      expect(result.title, 'The Matrix');
      expect(result.year, 1999);
      expect(result.posterUrl, 'https://m.media-amazon.com/images/matrix.jpg');
      expect(result.actors, ['Keanu Reeves', 'Laurence Fishburne']);
      expect(result.overview, contains('IMDb 自动匹配到《The Matrix》'));
    });

    test('prefers tv result when series is requested', () async {
      final client = ImdbMetadataClient(
        MockClient((request) async {
          return http.Response(
            jsonEncode({
              'd': [
                {
                  'id': 'tt3581920',
                  'l': 'The Last of Us',
                  'q': 'feature',
                  'qid': 'movie',
                  'rank': 500,
                  'y': 2023,
                },
                {
                  'id': 'tt3581920-tv',
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
        }),
      );

      final result = await client.matchTitle(
        query: 'The Last of Us',
        year: 2023,
        preferSeries: true,
      );

      expect(result, isNotNull);
      expect(result!.imdbId, 'tt3581920-tv');
    });
  });
}
