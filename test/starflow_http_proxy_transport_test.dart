import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/network/network_proxy_config.dart';
import 'package:starflow/core/network/network_proxy_runtime.dart';
import 'package:starflow/core/network/starflow_http_client.dart';
import 'package:starflow/core/network/starflow_http_transport.dart';

void main() {
  test('shared transport follows runtime proxy changes', () async {
    final proxyRequests = <HttpRequest>[];
    final proxyServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = proxyServer.listen((request) async {
      proxyRequests.add(request);
      request.response
        ..statusCode = HttpStatus.ok
        ..write('proxied');
      await request.response.close();
    });
    final client = StarflowHttpClient(createStarflowTransportClient());
    addTearDown(() async {
      networkProxyRuntime.configure(const NetworkProxyConfig());
      client.close();
      await subscription.cancel();
      await proxyServer.close(force: true);
    });

    networkProxyRuntime.configure(
      NetworkProxyConfig(
        enabled: true,
        host: proxyServer.address.address,
        port: proxyServer.port,
        bypassLocalAddresses: false,
      ),
    );

    final response = await client
        .get(Uri.parse('http://unresolvable.invalid/proxy-check'))
        .timeout(const Duration(seconds: 3));

    expect(response.statusCode, HttpStatus.ok);
    expect(response.body, 'proxied');
    expect(proxyRequests, hasLength(1));
    expect(proxyRequests.single.uri.host, 'unresolvable.invalid');
    expect(proxyRequests.single.uri.path, '/proxy-check');
  });
}
