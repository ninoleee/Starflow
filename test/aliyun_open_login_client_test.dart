import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/settings/data/aliyun_open_login_client.dart';

http.Response _json(Object value, [int status = 200]) =>
    http.Response(jsonEncode(value), status);

void main() {
  test('built-in Open QR flow validates state and returns credentials',
      () async {
    var calls = 0;
    final client = AliyunOpenLoginClient(MockClient((request) async {
      expect(request.headers['X-Client-Fingerprint'], 'starflow');
      expect(request.followRedirects, isFalse);
      calls++;
      if (request.url.path == '/alicloud2/generate_qr') {
        return _json({
          'success': true,
          'session_id': 'session-1',
          'qr_code_url':
              'https://passport.aliyundrive.com/qrcodeCheck.htm?lgToken=x',
          'expires_in': 120,
        });
      }
      if (request.url.path == '/alicloud2/check_login') {
        expect(request.url.queryParameters['session_id'], 'session-1');
        return _json({'success': true, 'status': 'CONFIRMED'});
      }
      if (request.url.path == '/alicloud2/get_user_info') {
        return _json({
          'success': true,
          'access_token': 'open-access',
          'refresh_token': 'a.b.c',
          'user_info': {'user_id': 'user-1'},
        });
      }
      fail('Unexpected request ${request.url}');
    }));

    final qr = await client.createToken();
    expect(qr.sessionId, 'session-1');
    expect(await client.status(qr), isA<AliyunOpenQrResult>());
    final token = await client.complete(qr);
    expect(token.accessToken, 'open-access');
    expect(token.refreshToken, 'a.b.c');
    expect(token.userId, 'user-1');
    expect(calls, 3);
  });

  test('built-in Open refresh rejects a non-JWT refresh token', () async {
    final client = AliyunOpenLoginClient(MockClient((request) async {
      expect(request.url.path, '/alicloud2/renewapi');
      return _json({'access_token': 'access', 'refresh_token': 'not-a-jwt'});
    }));
    await expectLater(
        client.refresh('old'), throwsA(isA<AliyunOpenLoginException>()));
  });

  test('built-in Open falls back to the mainland service on network failure',
      () async {
    final hosts = <String>[];
    final client = AliyunOpenLoginClient(MockClient((request) async {
      hosts.add(request.url.host);
      if (request.url.host == 'api.oplist.org') {
        throw http.ClientException('offline');
      }
      return _json({
        'success': true,
        'session_id': 'session-cn',
        'qr_code_url':
            'https://passport.aliyundrive.com/qrcodeCheck.htm?lgToken=x',
        'expires_in': 120,
      });
    }));
    final token = await client.createToken();
    expect(token.sessionId, 'session-cn');
    expect(hosts, ['api.oplist.org', 'api.oplist.org.cn']);
  });
}
