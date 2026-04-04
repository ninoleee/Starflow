import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';

void main() {
  group('EmbyApiClient helpers', () {
    test('adds /emby fallback when endpoint is bare host', () {
      final candidates = EmbyApiClient.candidateBaseUris(
        'https://media.example.com',
      );

      expect(
        candidates.map((item) => item.toString()),
        [
          'https://media.example.com',
          'https://media.example.com/emby',
        ],
      );
    });

    test('builds direct stream uri with media source and token', () {
      final uri = EmbyApiClient.buildDirectStreamUri(
        baseUri: Uri.parse('https://media.example.com/emby'),
        itemId: 'item-123',
        container: 'mkv',
        mediaSourceId: 'source-456',
        accessToken: 'token-789',
      );

      expect(
        uri.toString(),
        'https://media.example.com/emby/Videos/item-123/stream.mkv?static=true&MediaSourceId=source-456&api_key=token-789',
      );
    });

    test('formats runtime ticks as hour-minute label', () {
      expect(
        EmbyApiClient.formatRunTimeTicks(54000000000),
        '1h 30m',
      );
    });
  });
}
