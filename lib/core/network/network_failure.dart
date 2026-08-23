import 'dart:async';

import 'package:http/http.dart' as http;

enum NetworkFailureKind {
  timeout,
  tlsHandshake,
  dns,
  connection,
  connectionClosed,
  httpStatus,
  circuitOpen,
  cancelled,
  unknown,
}

class NetworkFailureInfo {
  const NetworkFailureInfo({
    required this.kind,
    required this.isTransient,
    this.statusCode,
  });

  final NetworkFailureKind kind;
  final bool isTransient;
  final int? statusCode;
}

NetworkFailureInfo classifyNetworkFailure(
  Object error, {
  int? statusCode,
}) {
  if (statusCode != null) {
    return NetworkFailureInfo(
      kind: NetworkFailureKind.httpStatus,
      isTransient: isTransientHttpStatus(statusCode),
      statusCode: statusCode,
    );
  }
  if (error is NetworkCircuitOpenException) {
    return const NetworkFailureInfo(
      kind: NetworkFailureKind.circuitOpen,
      isTransient: true,
    );
  }
  if (error is TimeoutException) {
    return const NetworkFailureInfo(
      kind: NetworkFailureKind.timeout,
      isTransient: true,
    );
  }

  final text = error.toString().toLowerCase();
  if (text.contains('handshakeexception') ||
      text.contains('handshake terminated') ||
      text.contains('tls') ||
      text.contains('certificate_verify_failed')) {
    return const NetworkFailureInfo(
      kind: NetworkFailureKind.tlsHandshake,
      isTransient: true,
    );
  }
  if (text.contains('failed host lookup') ||
      text.contains('name or service not known') ||
      text.contains('nodename nor servname') ||
      text.contains('no address associated with hostname')) {
    return const NetworkFailureInfo(
      kind: NetworkFailureKind.dns,
      isTransient: true,
    );
  }
  if (text.contains('connection closed') ||
      text.contains('connection terminated') ||
      text.contains('unexpected end of file') ||
      text.contains('unexpected eof')) {
    return const NetworkFailureInfo(
      kind: NetworkFailureKind.connectionClosed,
      isTransient: true,
    );
  }
  if (text.contains('cancelled') || text.contains('canceled')) {
    return const NetworkFailureInfo(
      kind: NetworkFailureKind.cancelled,
      isTransient: false,
    );
  }
  if (text.contains('connection refused') ||
      text.contains('connection reset') ||
      text.contains('connection aborted') ||
      text.contains('network is unreachable') ||
      text.contains('software caused connection abort') ||
      text.contains('socketexception') ||
      error is http.ClientException) {
    return const NetworkFailureInfo(
      kind: NetworkFailureKind.connection,
      isTransient: true,
    );
  }
  return const NetworkFailureInfo(
    kind: NetworkFailureKind.unknown,
    isTransient: false,
  );
}

bool isTransientHttpStatus(int statusCode) {
  return statusCode == 408 ||
      statusCode == 425 ||
      statusCode == 429 ||
      statusCode >= 500;
}

class NetworkCircuitOpenException implements Exception {
  const NetworkCircuitOpenException({
    required this.policyId,
    required this.host,
    required this.retryAfter,
  });

  final String policyId;
  final String host;
  final DateTime retryAfter;

  @override
  String toString() =>
      '$policyId requests for $host are paused until ${retryAfter.toIso8601String()}';
}
