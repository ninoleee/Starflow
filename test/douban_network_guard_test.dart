import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/discovery/data/douban_network_guard.dart';

void main() {
  test('Douban guard opens its host circuit after transient failures',
      () async {
    var requestCount = 0;
    final client = MockClient((_) async {
      requestCount += 1;
      return http.Response('', 503);
    });
    final guard = DoubanNetworkGuard(
      failureThreshold: 2,
      circuitOpenDuration: const Duration(minutes: 1),
    );
    final uri = Uri.parse('https://m.douban.com/rexxar/api/v2/test');

    expect((await guard.get(client, uri)).statusCode, 503);
    expect((await guard.get(client, uri)).statusCode, 503);
    await expectLater(
      guard.get(client, uri),
      throwsA(isA<DoubanNetworkCircuitOpenException>()),
    );
    expect(requestCount, 2);
  });

  test('Douban guard resets failures after a successful response', () async {
    var requestCount = 0;
    final client = MockClient((_) async {
      requestCount += 1;
      return http.Response('', requestCount.isOdd ? 503 : 200);
    });
    final guard = DoubanNetworkGuard(failureThreshold: 2);
    final uri = Uri.parse('https://m.douban.com/rexxar/api/v2/test');

    expect((await guard.get(client, uri)).statusCode, 503);
    expect((await guard.get(client, uri)).statusCode, 200);
    expect((await guard.get(client, uri)).statusCode, 503);
    expect((await guard.get(client, uri)).statusCode, 200);
  });
}
