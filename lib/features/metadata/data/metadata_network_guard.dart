import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/core/network/network_failure.dart';
import 'package:starflow/core/network/network_request_guard.dart';

final metadataNetworkGuardProvider = Provider<MetadataNetworkGuard>((ref) {
  return MetadataNetworkGuard();
});

class MetadataNetworkGuard {
  MetadataNetworkGuard({
    Duration requestTimeout = const Duration(seconds: 6),
    int failureThreshold = 3,
    Duration circuitOpenDuration = const Duration(minutes: 2),
  }) : _delegate = NetworkRequestGuard(
          policy: NetworkRequestPolicy(
            id: 'metadata',
            logCategory: 'metadata.network',
            requestTimeout: requestTimeout,
            failureThreshold: failureThreshold,
            circuitOpenDuration: circuitOpenDuration,
          ),
          circuitExceptionFactory: MetadataNetworkCircuitOpenException.new,
        );

  final NetworkRequestGuard _delegate;

  Future<http.Response> get(
    http.Client client,
    Uri uri, {
    Map<String, String>? headers,
  }) {
    return _delegate.get(client, uri, headers: headers);
  }

  void allowManualProbe({required String reason}) {
    _delegate.allowSingleProbeForOpenHosts(reason: reason);
  }
}

class MetadataNetworkCircuitOpenException extends NetworkCircuitOpenException {
  const MetadataNetworkCircuitOpenException(String host, DateTime retryAfter)
      : super(
          policyId: 'metadata',
          host: host,
          retryAfter: retryAfter,
        );

  @override
  String toString() =>
      'Metadata requests for $host are paused until ${retryAfter.toIso8601String()}';
}
