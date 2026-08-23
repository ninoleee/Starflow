import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/metadata/data/metadata_network_guard.dart';

void main() {
  test('opens a per-host circuit after repeated transport failures', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests += 1;
      throw http.ClientException('handshake terminated', request.url);
    });
    final guard = MetadataNetworkGuard(
      failureThreshold: 2,
      circuitOpenDuration: const Duration(minutes: 1),
    );
    final uri = Uri.parse('https://metadata.example.com/search');

    await expectLater(
        guard.get(client, uri), throwsA(isA<http.ClientException>()));
    await expectLater(
        guard.get(client, uri), throwsA(isA<http.ClientException>()));
    await expectLater(
      guard.get(client, uri),
      throwsA(isA<MetadataNetworkCircuitOpenException>()),
    );
    expect(requests, 2);
  });

  test('successful response resets the host failure counter', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests += 1;
      if (requests == 1) {
        throw http.ClientException('temporary failure', request.url);
      }
      return http.Response('{}', 200);
    });
    final guard = MetadataNetworkGuard(failureThreshold: 2);
    final uri = Uri.parse('https://metadata.example.com/search');

    await expectLater(
        guard.get(client, uri), throwsA(isA<http.ClientException>()));
    expect((await guard.get(client, uri)).statusCode, 200);
    expect((await guard.get(client, uri)).statusCode, 200);
    expect(requests, 3);
  });
}
