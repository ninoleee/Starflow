import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/network/starflow_http_client.dart';

void main() {
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
