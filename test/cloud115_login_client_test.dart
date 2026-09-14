import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/settings/data/cloud115_login_client.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

const token = Cloud115QrToken(
    uid: 'uid', time: '123', sign: 'secret', qrcode: 'https://115.com/scan');

void main() {
  test('QR token, status and exchange use fixed endpoints without redirects',
      () async {
    final client = Cloud115LoginClient(MockClient((request) async {
      expect(request.followRedirects, isFalse);
      Object data;
      if (request.url.path.endsWith('/token/')) {
        expect(request.url.host, 'qrcodeapi.115.com');
        data = {
          'uid': token.uid,
          'time': token.time,
          'sign': token.sign,
          'qrcode': token.qrcode
        };
      } else if (request.url.path == '/get/status/') {
        expect(request.url.queryParameters,
            {'uid': 'uid', 'time': '123', 'sign': 'secret'});
        data = {'status': 2};
      } else {
        expect(request.url.toString(),
            'https://passportapi.115.com/app/1.0/web/1.0/login/qrcode/');
        expect(request.method, 'POST');
        expect(Uri.splitQueryString(request.body), {'account': 'uid'});
        data = {
          'cookie': {'UID': 'user', 'CID': 'cid', 'SEID': 'session'}
        };
      }
      return http.Response(jsonEncode({'state': true, 'data': data}), 200);
    }));
    final result = await client.createToken();
    expect(result.qrcode, token.qrcode);
    expect(await client.status(result), Cloud115QrStatus.confirmed);
    expect(await client.exchange(result), 'UID=user; CID=cid; SEID=session');
  });

  for (final entry in {
    0: Cloud115QrStatus.waiting,
    1: Cloud115QrStatus.scanned,
    -1: Cloud115QrStatus.expired,
    -2: Cloud115QrStatus.cancelled
  }.entries) {
    test('maps status ${entry.key}', () async {
      final client = Cloud115LoginClient(MockClient((_) async => http.Response(
          jsonEncode({
            'state': true,
            'data': {'status': entry.key}
          }),
          200)));
      expect(await client.status(token), entry.value);
    });
  }

  test('errors never expose response secrets', () async {
    final client = Cloud115LoginClient(MockClient((_) async =>
        http.Response('{"state":false,"message":"SEID=secret"}', 200)));
    await expectLater(
        client.createToken(),
        throwsA(isA<Cloud115LoginException>().having(
            (error) => error.message, 'message', isNot(contains('secret')))));
  });

  test('rejects malformed credentials', () async {
    final client = Cloud115LoginClient(MockClient((_) async => http.Response(
        jsonEncode({
          'state': true,
          'data': {
            'cookie': {'UID': 'x', 'CID': 'x', 'SEID': 'x\r\nInjected: value'}
          },
        }),
        200)));
    await expectLater(
        client.exchange(token), throwsA(isA<Cloud115LoginException>()));
  });

  test('cookie remains in exported configuration and survives import', () {
    const settings =
        NetworkStorageConfig(cloud115Cookie: 'UID=u; CID=c; SEID=s');
    final json = settings.toJson();
    expect(json['cloud115Cookie'], settings.cloud115Cookie);
    expect(
        NetworkStorageConfig.fromJson(jsonDecode(jsonEncode(json)))
            .cloud115Cookie,
        settings.cloud115Cookie);
  });
}
