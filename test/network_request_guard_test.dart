import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/core/network/network_failure.dart';
import 'package:starflow/core/network/network_request_guard.dart';

void main() {
  test('shared guard retries an idempotent request only within policy',
      () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests += 1;
      return http.Response('', requests == 1 ? 503 : 200);
    });
    final guard = NetworkRequestGuard(
      policy: const NetworkRequestPolicy(
        id: 'test',
        logCategory: 'test.network',
        maxRetries: 1,
        retryDelay: Duration.zero,
      ),
    );

    final response = await guard.get(
      client,
      Uri.parse('https://api.example.com/items'),
    );

    expect(response.statusCode, 200);
    expect(requests, 2);
  });

  test('shared guard never retries a non-idempotent operation', () async {
    var requests = 0;
    final guard = NetworkRequestGuard(
      policy: const NetworkRequestPolicy(
        id: 'write',
        logCategory: 'test.network',
        maxRetries: 2,
        retryDelay: Duration.zero,
      ),
    );
    final uri = Uri.parse('https://api.example.com/save');

    await expectLater(
      guard.run<void>(
        uri: uri,
        request: () async {
          requests += 1;
          throw http.ClientException('connection reset', uri);
        },
      ),
      throwsA(isA<http.ClientException>()),
    );
    expect(requests, 1);
  });

  test('shared guard opens circuit independently per host', () async {
    final client = MockClient((_) async => http.Response('', 503));
    final guard = NetworkRequestGuard(
      policy: const NetworkRequestPolicy(
        id: 'test',
        logCategory: 'test.network',
        failureThreshold: 1,
      ),
    );
    final firstHost = Uri.parse('https://one.example.com/items');
    final secondHost = Uri.parse('https://two.example.com/items');

    expect((await guard.get(client, firstHost)).statusCode, 503);
    await expectLater(
      guard.get(client, firstHost),
      throwsA(isA<NetworkCircuitOpenException>()),
    );
    expect((await guard.get(client, secondHost)).statusCode, 503);
  });

  test('manual refresh admits one half-open probe without clearing circuit',
      () async {
    final probeGate = Completer<void>();
    var requests = 0;
    final client = MockClient((_) async {
      requests += 1;
      if (requests == 1) {
        return http.Response('', 503);
      }
      await probeGate.future;
      return http.Response('', 200);
    });
    final guard = NetworkRequestGuard(
      policy: const NetworkRequestPolicy(
        id: 'test',
        logCategory: 'test.network',
        failureThreshold: 1,
      ),
    );
    final uri = Uri.parse('https://api.example.com/items');

    expect((await guard.get(client, uri)).statusCode, 503);
    guard.allowSingleProbeForOpenHosts(reason: 'manual-refresh');
    final probe = guard.get(client, uri);
    await Future<void>.delayed(Duration.zero);
    expect(requests, 2);

    await expectLater(
      guard.get(client, uri),
      throwsA(isA<NetworkCircuitOpenException>()),
    );
    probeGate.complete();
    expect((await probe).statusCode, 200);

    expect((await guard.get(client, uri)).statusCode, 200);
    expect(requests, 3);
  });
}
