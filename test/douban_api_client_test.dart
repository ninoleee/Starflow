import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/discovery/data/douban_api_client.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';

void main() {
  group('DoubanApiClient', () {
    test('maps interest items with poster, note and credits', () async {
      final client = DoubanApiClient(
        MockClient((request) async {
          expect(
            request.url.path,
            '/rexxar/api/v2/user/demo-user/interests',
          );
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'interests': [
                  {
                    'comment': '',
                    'create_time': '2026-04-04 12:34:56',
                    'subject': {
                      'id': '1292063',
                      'title': '美丽人生',
                      'year': '1997',
                      'pic': {
                        'large':
                            'https://img9.doubanio.com/view/photo/l/public/p2578474613.jpg',
                      },
                      'rating': {'value': 9.6},
                      'card_subtitle': '1997 / 意大利 / 剧情 喜剧 / 116分钟',
                      'description': '圭多用幽默守护家人。',
                      'genres': ['剧情', '喜剧'],
                      'directors': [
                        {'name': '罗伯托·贝尼尼'},
                      ],
                      'actors': [
                        {'name': '罗伯托·贝尼尼'},
                        {'name': '尼可莱塔·布拉斯基'},
                      ],
                      'type_name': '电影',
                      'durations': ['116分钟'],
                    },
                  },
                ],
              }),
            ),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final items = await client.fetchInterestItems(
        userId: 'demo-user',
        status: DoubanInterestStatus.mark,
      );

      expect(items, hasLength(1));
      expect(items.first.title, '美丽人生');
      expect(
        items.first.posterUrl,
        'https://img9.doubanio.com/view/photo/l/public/p2578474613.jpg',
      );
      expect(items.first.note, '圭多用幽默守护家人。');
      expect(items.first.ratingLabel, '豆瓣 9.6');
      expect(items.first.subjectType, '电影');
      expect(items.first.durationLabel, '116分钟');
      expect(items.first.genres, ['剧情', '喜剧']);
      expect(items.first.directors, ['罗伯托·贝尼尼']);
      expect(items.first.actors, ['罗伯托·贝尼尼', '尼可莱塔·布拉斯基']);
    });
  });
}
