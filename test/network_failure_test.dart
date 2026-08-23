import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/core/network/network_failure.dart';

void main() {
  test('classifies common transport failures consistently', () {
    expect(
      classifyNetworkFailure(TimeoutException('slow')).kind,
      NetworkFailureKind.timeout,
    );
    expect(
      classifyNetworkFailure(
        Exception('HandshakeException: Connection terminated during handshake'),
      ).kind,
      NetworkFailureKind.tlsHandshake,
    );
    expect(
      classifyNetworkFailure(Exception('Failed host lookup: api.test')).kind,
      NetworkFailureKind.dns,
    );
    expect(
      classifyNetworkFailure(
        http.ClientException('Connection closed before full header'),
      ).kind,
      NetworkFailureKind.connectionClosed,
    );
    expect(
      classifyNetworkFailure(
        http.ClientException('Request cancelled by caller'),
      ).kind,
      NetworkFailureKind.cancelled,
    );
  });

  test('classifies retryable and permanent HTTP statuses', () {
    expect(isTransientHttpStatus(408), isTrue);
    expect(isTransientHttpStatus(429), isTrue);
    expect(isTransientHttpStatus(503), isTrue);
    expect(isTransientHttpStatus(404), isFalse);
  });
}
