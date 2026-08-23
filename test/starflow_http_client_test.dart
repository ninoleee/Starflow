import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/core/network/starflow_http_client.dart';

void main() {
  test('StarflowHttpClient applies the shared transport timeout', () async {
    final inner = MockClient((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      return http.Response('{}', 200);
    });
    final client = StarflowHttpClient(
      inner,
      requestTimeout: const Duration(milliseconds: 10),
    );
    addTearDown(client.close);

    await expectLater(
      client.get(Uri.parse('https://api.example.com/test')),
      throwsA(isA<TimeoutException>()),
    );
  });

  group('resolveStarflowWebProxyBase', () {
    test('does not auto-enable localhost proxy without explicit config', () {
      final resolved = resolveStarflowWebProxyBase(
        isWeb: true,
        configuredProxyBase: '',
      );

      expect(resolved, isEmpty);
    });

    test('returns trimmed configured proxy base on web', () {
      final resolved = resolveStarflowWebProxyBase(
        isWeb: true,
        configuredProxyBase: '  http://127.0.0.1:8787  ',
      );

      expect(resolved, 'http://127.0.0.1:8787');
    });

    test('disables proxy outside web even when configured', () {
      final resolved = resolveStarflowWebProxyBase(
        isWeb: false,
        configuredProxyBase: 'http://127.0.0.1:8787',
      );

      expect(resolved, isEmpty);
    });
  });
}
