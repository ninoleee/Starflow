import 'package:starflow/core/network/network_proxy_config.dart';

class NetworkProxyRuntime {
  NetworkProxyConfig _config = const NetworkProxyConfig();
  int _revision = 0;

  NetworkProxyConfig get config => _config;
  int get revision => _revision;

  void configure(NetworkProxyConfig config) {
    final normalized = NetworkProxyConfig.fromJson(config.toJson());
    if (_sameConfig(_config, normalized)) {
      return;
    }
    _config = normalized;
    _revision += 1;
  }

  String findProxy(Uri uri) => _config.proxyDirectiveFor(uri);
}

final NetworkProxyRuntime networkProxyRuntime = NetworkProxyRuntime();

bool _sameConfig(NetworkProxyConfig left, NetworkProxyConfig right) {
  return left.enabled == right.enabled &&
      left.normalizedHost == right.normalizedHost &&
      left.port == right.port &&
      left.username.trim() == right.username.trim() &&
      left.password == right.password &&
      left.bypassLocalAddresses == right.bypassLocalAddresses;
}
