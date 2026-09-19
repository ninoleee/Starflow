import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/details/application/douban_rating_stats_service.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/discovery/data/douban_api_client.dart';

void main() {
  test('adds the Douban rating count to the existing rating labels', () async {
    final client = DoubanApiClient(
      MockClient((_) async => http.Response.bytes(
            utf8.encode(jsonEncode({
              'rating': {'value': 9.2, 'count': 315946},
            })),
            200,
          )),
    );
    const target = MediaDetailTarget(
      title: '半泽直树',
      posterUrl: '',
      overview: '',
      doubanId: '24697949',
      ratingLabels: ['豆瓣 9.1', 'IMDb 8.0'],
    );

    final enriched = await enrichDetailTargetWithDoubanRatingStats(
      target: target,
      doubanApiClient: client,
    );

    expect(enriched.ratingCount, 315946);
    expect(enriched.ratingLabels, ['豆瓣 9.2', 'IMDb 8.0']);
  });
}
