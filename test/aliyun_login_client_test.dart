import 'dart:convert';

import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/settings/data/aliyun_login_client.dart';

const _token = AliyunQrToken(
    t: '123',
    ck: 'session',
    qrcode: 'https://passport.aliyundrive.com/qrcodeCheck.htm?code=test');
Map<String, dynamic> _qr() =>
    {'t': 123, 'ck': 'session', 'codeContent': _token.qrcode};
http.Response _response(Object data) => http.Response(
    jsonEncode({
      'content': {'success': true, 'data': data}
    }),
    200);

void main() {
  test('uses fixed official endpoints, form fields and no redirects', () async {
    var calls = 0;
    final client = AliyunLoginClient(MockClient((request) async {
      expect(request.url.host, 'passport.aliyundrive.com');
      expect(request.url.scheme, 'https');
      expect(request.followRedirects, isFalse);
      expect(request.headers.containsKey('authorization'), isFalse);
      expect(request.headers.containsKey('cookie'), isFalse);
      expect(request.url.queryParameters, {'appName': 'aliyun_drive'});
      if (calls++ == 0) {
        expect(request.method, 'GET');
        expect(request.url.path, '/newlogin/qrcode/generate.do');
        return _response(_qr());
      }
      expect(request.method, 'POST');
      expect(request.url.path, '/newlogin/qrcode/query.do');
      expect(request.bodyFields, {'t': '123', 'ck': 'session'});
      return _response({'qrCodeStatus': 'NEW'});
    }));
    final token = await client.createToken();
    expect(token.qrcode, _token.qrcode);
    expect((await client.status(token)).status, AliyunQrStatus.waiting);
  });

  for (final entry in {
    'NEW': AliyunQrStatus.waiting,
    'SCANED': AliyunQrStatus.scanned,
    'EXPIRED': AliyunQrStatus.expired,
    'CANCELED': AliyunQrStatus.cancelled,
    'CANCELLED': AliyunQrStatus.cancelled,
  }.entries) {
    test('maps ${entry.key} without accepting credentials', () async {
      final client = AliyunLoginClient(MockClient((_) async => _response(
          {'qrCodeStatus': entry.key, 'bizExt': 'must-not-be-decoded'})));
      final result = await client.status(_token);
      expect(result.status, entry.value);
      expect(result.refreshToken, isNull);
    });
  }

  for (final encoding in [utf8, gbk]) {
    test('confirmed decodes ${encoding.name} payload', () async {
      final payload = base64.encode(encoding.encode(jsonEncode({
        'pds_login_result': {'refreshToken': 'token-._~+/=', 'nickName': '测试账号'}
      })));
      final client = AliyunLoginClient(MockClient((_) async =>
          _response({'qrCodeStatus': 'CONFIRMED', 'bizExt': payload})));
      final result = await client.status(_token);
      expect(result.status, AliyunQrStatus.confirmed);
      expect(result.refreshToken, 'token-._~+/=');
    });
  }

  for (final change in <Map<String, Object?>>[
    {'t': 1.5},
    {'t': 'bad'},
    {'ck': ''},
    {'ck': 'bad\n'},
    {'codeContent': 'https://evil.example/qrcodeCheck.htm?code=test'},
    {
      'codeContent': 'http://passport.aliyundrive.com/qrcodeCheck.htm?code=test'
    },
    {'codeContent': 'https://passport.aliyundrive.com:444/qrcodeCheck.htm?x=1'},
    {'codeContent': 'https://u@passport.aliyundrive.com/qrcodeCheck.htm?x=1'},
    {'codeContent': 'https://passport.aliyundrive.com/other?x=1'},
    {'codeContent': 'https://passport.aliyundrive.com/qrcodeCheck.htm?x=1#bad'},
    {'codeContent': null},
  ]) {
    test('rejects malformed QR ${change.keys.single}: ${change.values.single}',
        () async {
      final client = AliyunLoginClient(
          MockClient((_) async => _response({..._qr(), ...change})));
      await expectLater(
          client.createToken(), throwsA(isA<AliyunLoginException>()));
    });
  }

  for (final payload in [
    null,
    'not-base64!',
    base64.encode(utf8.encode('not-json')),
    base64.encode(utf8.encode(jsonEncode({'pds_login_result': {}}))),
    base64.encode(utf8.encode(jsonEncode({
      'pds_login_result': {'refreshToken': 'secret\ninvalid'}
    }))),
  ]) {
    test('rejects incomplete confirmation ${payload?.length}', () async {
      final client = AliyunLoginClient(MockClient((_) async =>
          _response({'qrCodeStatus': 'CONFIRMED', 'bizExt': payload})));
      await expectLater(
          client.status(_token), throwsA(isA<AliyunLoginException>()));
    });
  }

  test('unknown status and provider errors never echo remote content',
      () async {
    for (final response in [
      _response({'qrCodeStatus': 'secret-status'}),
      http.Response('{"content":{"success":false,"message":"secret"}}', 200),
      http.Response('secret', 500),
      http.Response('secret', 200),
      http.Response('secret' * 30000, 200),
    ]) {
      final client = AliyunLoginClient(MockClient((_) async => response));
      await expectLater(
          client.status(_token),
          throwsA(isA<AliyunLoginException>().having(
              (e) => e.message, 'safe message', isNot(contains('secret')))));
    }
  });

  test('rejects redirects even to the same endpoint', () async {
    var requests = 0;
    final client = AliyunLoginClient(MockClient((request) async {
      requests++;
      return http.Response('', 302,
          headers: {'location': request.url.toString()});
    }));
    await expectLater(
        client.createToken(), throwsA(isA<AliyunLoginException>()));
    expect(requests, 1);
  });
}
