import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:starflow/core/network/network_proxy_runtime.dart';

http.Client createStarflowTransportClient() => _ProxyAwareIoClient();

class _ProxyAwareIoClient extends http.BaseClient {
  http.Client? _inner;
  final List<http.Client> _retiredClients = <http.Client>[];
  int _activeRevision = -1;
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (_closed) {
      throw StateError('HTTP client is closed.');
    }
    return _resolveInner().send(request);
  }

  http.Client _resolveInner() {
    final revision = networkProxyRuntime.revision;
    final current = _inner;
    if (current != null && revision == _activeRevision) {
      return current;
    }
    if (current != null) {
      _retiredClients.add(current);
      Timer(const Duration(minutes: 2), () {
        if (_retiredClients.remove(current)) {
          current.close();
        }
      });
    }
    _activeRevision = revision;
    return _inner = IOClient(_createIoClient());
  }

  HttpClient _createIoClient() {
    final proxyConfig = networkProxyRuntime.config;
    late final HttpClient client;
    client = HttpClient()
      ..findProxy = proxyConfig.proxyDirectiveFor
      ..authenticateProxy = (host, port, scheme, realm) async {
        if (!proxyConfig.isActive ||
            proxyConfig.username.trim().isEmpty ||
            host.toLowerCase() != proxyConfig.normalizedHost.toLowerCase() ||
            port != proxyConfig.port) {
          return false;
        }
        client.addProxyCredentials(
          host,
          port,
          realm ?? '',
          HttpClientBasicCredentials(
            proxyConfig.username.trim(),
            proxyConfig.password,
          ),
        );
        return true;
      };
    return client;
  }

  @override
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _inner?.close();
    _inner = null;
    for (final client in _retiredClients) {
      client.close();
    }
    _retiredClients.clear();
  }
}
