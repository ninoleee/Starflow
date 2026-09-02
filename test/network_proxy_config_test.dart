import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/network/network_proxy_config.dart';

void main() {
  test('network proxy config defaults to direct connections', () {
    const config = NetworkProxyConfig();

    expect(config.enabled, isFalse);
    expect(config.isActive, isFalse);
    expect(
      config.proxyDirectiveFor(Uri.parse('https://example.com/video')),
      'DIRECT',
    );
  });

  test('network proxy config persists address, auth, and bypass preference',
      () {
    const config = NetworkProxyConfig(
      enabled: true,
      host: ' proxy.example.com ',
      port: 8080,
      username: 'alice',
      password: 'secret',
      bypassLocalAddresses: false,
    );

    final restored = NetworkProxyConfig.fromJson(config.toJson());

    expect(restored.isActive, isTrue);
    expect(restored.displayAddress, 'proxy.example.com:8080');
    expect(restored.username, 'alice');
    expect(restored.password, 'secret');
    expect(restored.bypassLocalAddresses, isFalse);
  });

  test('local addresses bypass an active proxy by default', () {
    const config = NetworkProxyConfig(
      enabled: true,
      host: '127.0.0.1',
      port: 7890,
    );

    expect(
      config.proxyDirectiveFor(Uri.parse('http://192.168.1.20/library')),
      'DIRECT',
    );
    expect(
      config.proxyDirectiveFor(Uri.parse('http://nas.local/library')),
      'DIRECT',
    );
    expect(
      config.proxyDirectiveFor(Uri.parse('https://api.themoviedb.org/3')),
      'PROXY 127.0.0.1:7890',
    );
  });

  test('MPV proxy URL encodes optional credentials', () {
    const config = NetworkProxyConfig(
      enabled: true,
      host: 'proxy.example.com',
      port: 7890,
      username: 'media user',
      password: 'p@ss/word',
    );

    expect(
      config.mpvProxyUrlFor(Uri.parse('https://media.example.com/video.mkv')),
      'http://media%20user:p%40ss%2Fword@proxy.example.com:7890',
    );
  });

  test('invalid host or port never activates proxy routing', () {
    const invalidHost = NetworkProxyConfig(
      enabled: true,
      host: 'http://127.0.0.1',
      port: 7890,
    );
    const invalidPort = NetworkProxyConfig(
      enabled: true,
      host: '127.0.0.1',
      port: 70000,
    );

    expect(invalidHost.isActive, isFalse);
    expect(invalidPort.isActive, isFalse);
  });
}
