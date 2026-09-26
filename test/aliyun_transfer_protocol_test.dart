import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dart_lz4/dart_lz4.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:starflow/core/logging/app_log_api.dart';
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/features/search/data/aliyun_transfer_client.dart';
import 'package:starflow/features/search/data/cloud115_instant_upload_client.dart';
import 'package:starflow/features/search/data/cloud115_upload_cipher.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/search/data/cloud115_save_client.dart';
import 'package:starflow/features/search/application/search_share_validator.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

final _key = _hex('57a29257cd2320e5d6d143322fa4bb8a');
final _iv = _hex('2fa4bb8a3cf9d3cc623ef5edac62b767');
Uint8List _hex(String value) => Uint8List.fromList([
      for (var i = 0; i < value.length; i += 2)
        int.parse(value.substring(i, i + 2), radix: 16),
    ]);
Uint8List _cbc(List<int> input, bool encrypt) {
  final cipher = pc.CBCBlockCipher(pc.AESEngine())
    ..init(encrypt, pc.ParametersWithIV(pc.KeyParameter(_key), _iv));
  final bytes = Uint8List.fromList(input);
  final out = Uint8List(bytes.length);
  for (var i = 0; i < bytes.length; i += 16) {
    cipher.processBlock(bytes, i, out, i);
  }
  return out;
}

http.Response _encrypted(Map<String, dynamic> json) {
  final block = lz4Compress(Uint8List.fromList(utf8.encode(jsonEncode(json))));
  final raw = [block.length & 255, block.length >> 8, ...block];
  return http.Response.bytes(
      _cbc([...raw, ...List.filled(16 - raw.length % 16, 0)], true), 200);
}

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);
Map<String, String> _form(http.Request request) {
  final data = _cbc(request.bodyBytes, false);
  return Uri.splitQueryString(
      utf8.decode(data.sublist(0, data.length - data.last)));
}

final _file = AliyunTransferFile(
    id: 'copy1',
    name: 'a.mkv',
    parentId: 'stage',
    isDirectory: false,
    size: 4,
    sha1: sha1.convert([1, 2, 3, 4]).toString().toUpperCase());
final _session = AliyunTransferSession(
    accessToken: 'secret',
    driveId: 'drive',
    deviceId: 'device',
    signature: 'sig');
Map<String, dynamic> _row({String id = 'f1', String parent = 'root'}) => {
      'file_id': id,
      'name': 'a.mkv',
      'type': 'file',
      'parent_file_id': parent,
      'size': 4,
      'content_hash': _file.sha1,
      'content_hash_name': 'sha1',
      'status': 'available',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory logDirectory;
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUpAll(() async {
    logDirectory = await Directory.systemTemp.createTemp('starflow-transfer-');
    messenger.setMockMethodCallHandler(
        pathChannel, (_) async => logDirectory.path);
    await appLogger.configure(
        enabled: true,
        maxBytes: 1024 * 1024,
        recordedLevels: AppLogLevel.values.toSet());
  });
  tearDownAll(() async {
    await appLogger.configure(
        enabled: false,
        maxBytes: 1024 * 1024,
        recordedLevels: AppLogLevel.values.toSet());
    messenger.setMockMethodCallHandler(pathChannel, null);
    await logDirectory.delete(recursive: true);
  });
  setUp(() => appLogger.clear());

  test('Aliyun 400 share errors are invalid and actionable on save', () async {
    final client = AliyunTransferClient(
        MockClient((_) async => _json({'code': 'ShareLinkPwdInvalid'}, 400)));
    final validation = await client.validateShareLink(
        shareUrl: 'https://alipan.com/s/abc', password: 'bad');
    expect(validation.isInvalid, isTrue);
    expect(validation.reason, contains('提取码'));
    await expectLater(
        client.shareToken(
            AliyunShareLink.parse('https://alipan.com/s/abc', password: 'bad')),
        throwsA(isA<QuarkSaveException>().having(
            (error) => error.message, 'message', contains('分享已失效或提取码错误'))));
  });

  test('passwordless Aliyun share omits the empty password field', () async {
    final client = AliyunTransferClient(MockClient((request) async {
      final body = jsonDecode(request.body) as Map;
      expect(body, {'share_id': 'abc'});
      expect(body.containsKey('share_pwd'), isFalse);
      return _json({'share_token': 'share'});
    }));
    expect(
        await client
            .shareToken(AliyunShareLink.parse('https://alipan.com/s/abc')),
        'share');
  });

  test('shared file metadata accepts a valid SHA1 without hash_name', () {
    final row = Map<String, dynamic>.from(_row())..remove('content_hash_name');
    final file = AliyunTransferFile.parse(row);
    expect(file.sha1, _file.sha1);
    expect(file.size, 4);
  });

  test('missing hash is allowed only for shared metadata, never owned copies',
      () {
    final row = {..._row(), 'content_hash': ''};
    expect(AliyunTransferFile.parse(row, allowMissingSha1: true).sha1, isEmpty);
    expect(() => AliyunTransferFile.parse(row),
        throwsA(isA<QuarkSaveException>()));
    expect(
        () => AliyunTransferFile.parse({...row, 'content_hash_name': 'md5'},
            allowMissingSha1: true),
        throwsA(isA<QuarkSaveException>()));
    expect(
        () => AliyunTransferFile.parse({...row, 'content_hash': 'broken'},
            allowMissingSha1: true),
        throwsA(isA<QuarkSaveException>()));
  });

  test('shared file list allows missing SHA1 until owner copy is available',
      () async {
    var calls = 0;
    final client = AliyunTransferClient(MockClient((request) async {
      calls++;
      if (request.url.path == '/adrive/v3/file/list') {
        final row = Map<String, dynamic>.from(_row())
          ..remove('content_hash')
          ..remove('content_hash_name');
        return _json({
          'items': [row],
          'next_marker': ''
        });
      }
      fail('Shared list must not fetch unusable file details');
    }));
    final files = await client.listSharedTree(
        const AliyunShareLink('share', 'root', ''), 'token');
    expect(files.single.sha1, isEmpty);
    expect(calls, 1);
  });

  test('Aliyun validation resolver never depends on 115 credentials', () async {
    final noOtherDrive =
        MockClient((_) async => fail('No other drive requests'));
    final validator = SearchShareValidator(
        quark: QuarkSaveClient(noOtherDrive),
        cloud115: Cloud115SaveClient(noOtherDrive),
        aliyun: AliyunTransferClient(MockClient(
            (request) async => request.url.path.endsWith('get_share_token')
                ? _json({'share_token': 'share'})
                : _json({
                    'items': [_row()],
                    'next_marker': ''
                  }))));
    const result = SearchResult(
        id: 'ali',
        title: 'Ali',
        posterUrl: '',
        providerId: 'p',
        providerName: 'p',
        quality: '',
        sizeLabel: '',
        seeders: 0,
        summary: '',
        resourceUrl: 'https://alipan.com/s/abc');
    expect(validator.resolve(result, const NetworkStorageConfig()), isNull);
    for (final to115 in [false, true]) {
      final job = validator.resolve(
          result,
          NetworkStorageConfig(
              aliyunRefreshToken: 'token', aliyunTo115Enabled: to115));
      expect((await job!()).isValid, isTrue);
    }
  });
  test(
      'Aliyun validation only reads share token and first page without account credentials',
      () async {
    var requests = 0;
    final client = AliyunTransferClient(MockClient((request) async {
      requests++;
      expect(request.headers.keys.map((e) => e.toLowerCase()),
          isNot(contains('authorization')));
      expect(request.followRedirects, isFalse);
      expect(request.url.host, 'api.alipan.com');
      final body = jsonDecode(request.body) as Map;
      if (requests == 1) {
        expect(body['share_pwd'], '1234');
        return _json({'share_token': 'share'});
      }
      expect(body['limit'], 1);
      expect(body['fields'], '*');
      return _json({
        'items': [_row()],
        'next_marker': ''
      });
    }));
    expect(
        (await client.validateShareLink(
                shareUrl: 'https://alipan.com/s/abc?pwd=1234'))
            .isValid,
        isTrue);
    expect(requests, 2);
  });
  test(
      'Aliyun validation keeps transient failures and rejects explicit invalid shares',
      () async {
    for (final code in [
      'ShareLink.Expired',
      'ShareLink.Forbidden',
      'TooManyRequests',
      'AccessTokenInvalid'
    ]) {
      final client =
          AliyunTransferClient(MockClient((_) async => _json({'code': code})));
      expect(
          (await client.validateShareLink(shareUrl: 'https://alipan.com/s/abc'))
              .isInvalid,
          code == 'ShareLink.Expired' || code == 'ShareLink.Forbidden');
    }
  });
  test(
      'P224 public key, token CRC, AES and compressed response are interoperable',
      () {
    final cipher = Cloud115UploadCipher(privateKey: BigInt.one);
    final token = base64Decode(cipher.token(1234));
    final public = [...token.take(15), ...token.skip(24).take(15)];
    expect(
        public, [29, ...pc.ECDomainParameters('secp224r1').G.getEncoded(true)]);
    expect(ByteData.sublistView(token).getUint32(20, Endian.little), 1234);
    expect(
        ByteData.sublistView(token).getUint32(44, Endian.little),
        getCrc32(
            [...ascii.encode('^j>WD3Kr?J2gLFjD4W2y@'), ...token.take(44)]));
    expect(_cbc(cipher.encrypt(ascii.encode('hello')), false).take(5),
        ascii.encode('hello'));
    expect(
        jsonDecode(
            utf8.decode(cipher.decrypt(_encrypted({'status': 2}).bodyBytes))),
        {'status': 2});
    expect(() => cipher.decrypt(Uint8List(3)), throwsFormatException);
  });

  test('encrypted proof challenge sends exact range SHA1 then confirms target',
      () async {
    var calls = 0;
    final client = Cloud115InstantUploadClient(MockClient((request) async {
      expect(request.url.host, 'uplb.115.com');
      expect(request.followRedirects, isFalse);
      final form = _form(request);
      final timestamp = int.parse(form['t']!);
      expect(timestamp, greaterThan(1000000000000));
      final ecToken = base64Decode(request.url.queryParameters['k_ec']!);
      expect(ByteData.sublistView(ecToken).getUint32(20, Endian.little),
          timestamp & 0xffffffff);
      expect(
          form['token'],
          md5
              .convert(ascii.encode('Qclm8MGWUv59TnrR0XPg'
                  '${_file.sha1}4${form['sign_key'] ?? ''}'
                  '${form['sign_val'] ?? ''}1$timestamp'
                  '${md5.convert(ascii.encode('1'))}'
                  '${Cloud115InstantUploadClient.version}'))
              .toString());
      expect(form['topupload'], 'true');
      expect(form['userkey'], 'key');
      expect(form['fileid'], _file.sha1);
      expect(form['filename'], 'a.mkv');
      expect(form['target'], 'U_1_0');
      calls++;
      if (calls == 1) {
        return _encrypted({
          'status': 7,
          'statuscode': 701,
          'sign_key': 'proof',
          'sign_check': '1-2'
        });
      }
      expect(form['sign_key'], 'proof');
      expect(form['sign_val'], sha1.convert([2, 3]).toString().toUpperCase());
      return _encrypted({
        'status': 2,
        'statuscode': 0,
        'target': 'U_1_0',
        'pickcode': 'pick'
      });
    }), cipherFactory: () => Cloud115UploadCipher(privateKey: BigInt.one));
    expect(
        await client.upload(
            cookie: 'cookie',
            account: const Cloud115UploadAccount('1', 'key', 100),
            parentId: '0',
            name: 'a.mkv',
            size: 4,
            fileSha1: _file.sha1,
            readRange: (start, end) async {
              expect([start, end], [1, 2]);
              return Uint8List.fromList([2, 3]);
            }),
        isTrue);
    expect(calls, 2);
  });

  for (final response in <Map<String, dynamic>>[
    {'status': 2, 'statuscode': 0},
    {'status': '2', 'statuscode': '0'},
    {'status': 2},
    {'status': 2, 'statuscode': 0, 'target': 'U_1_0'},
  ]) {
    test('upload accepts success for subsequent target verification: $response',
        () async {
      final client = Cloud115InstantUploadClient(
          MockClient((_) async => _encrypted(response)),
          cipherFactory: () => Cloud115UploadCipher(privateKey: BigInt.one));
      expect(
          await client.upload(
              cookie: 'cookie',
              account: const Cloud115UploadAccount('1', 'key', 100),
              parentId: '0',
              name: 'a.mkv',
              size: 4,
              fileSha1: _file.sha1,
              readRange: (_, __) async => fail('No proof requested')),
          isTrue);
    });
  }

  for (final response in <Map<String, dynamic>>[
    {'status': 2, 'statuscode': 0, 'target': 'U_1_999'},
    {'status': 2, 'statuscode': 0, 'target': null},
    {'status': 2, 'statuscode': 400},
    {'status': 2, 'statuscode': null},
    {'status': 2, 'statuscode': 'invalid'},
    {'status': false, 'statuscode': 402},
    {'status': 9, 'statuscode': 999},
    <String, dynamic>{},
  ]) {
    test('upload rejects contradictory or unknown responses: $response',
        () async {
      var calls = 0;
      final client = Cloud115InstantUploadClient(MockClient((_) async {
        calls++;
        return _encrypted({
          ...response,
          'statusmsg': 'private filename Cookie=secret',
          'sign_key': 'private-proof',
          'pickcode': 'private-pickcode',
        });
      }), cipherFactory: () => Cloud115UploadCipher(privateKey: BigInt.one));
      await expectLater(
          client.upload(
              cookie: 'cookie',
              account: const Cloud115UploadAccount('1', 'key', 100),
              parentId: '0',
              name: 'a.mkv',
              size: 4,
              fileSha1: _file.sha1,
              readRange: (_, __) async => fail('No proof requested')),
          throwsA(isA<QuarkSaveException>().having(
              (e) => e.message,
              'safe diagnostics',
              allOf(contains('status='), contains('statuscode='),
                  isNot(contains('private')), isNot(contains('secret'))))));
      expect(calls, 1);
      final log = (await appLogger.read()).last;
      expect(log.category, '115.instant-upload');
      expect(log.level, AppLogLevel.warning);
      expect(log.fields['status'], int.tryParse('${response['status']}'));
      expect(
          log.fields['statuscode'],
          response.containsKey('statuscode')
              ? int.tryParse('${response['statuscode']}')
              : 0);
      final exported = utf8.decode((await appLogger.export()).bytes);
      for (final sensitive in [
        'private',
        'secret',
        'cookie',
        'a.mkv',
        _file.sha1,
        'U_1_999'
      ]) {
        expect(exported, isNot(contains(sensitive)));
      }
    });
  }

  for (final invalid in [false, true]) {
    test(
        'upload ${invalid ? 'invalid proof' : 'miss'} never downloads full file',
        () async {
      var calls = 0;
      final client = Cloud115InstantUploadClient(MockClient((request) async {
        calls++;
        return _encrypted(invalid
            ? {
                'status': 7,
                'statuscode': 701,
                'sign_key': 'k',
                'sign_check': '0-9'
              }
            : {'status': 1, 'statuscode': 0});
      }), cipherFactory: () => Cloud115UploadCipher(privateKey: BigInt.one));
      final pending = client.upload(
          cookie: 'cookie',
          account: const Cloud115UploadAccount('1', 'key', 100),
          parentId: '0',
          name: 'a.mkv',
          size: 4,
          fileSha1: _file.sha1,
          readRange: (_, __) async => throw StateError('must not read'));
      if (invalid) {
        await expectLater(pending, throwsA(isA<QuarkSaveException>()));
      } else {
        expect(await pending, isFalse);
      }
      expect(calls, 1);
    });
  }

  test('Aliyun accepts scoped share and rejects lookalike hosts', () {
    final link = AliyunShareLink.parse(
        'https://www.alipan.com/s/abc/folder/xyz?pwd=1234');
    expect([link.id, link.parentId, link.password], ['abc', 'xyz', '1234']);
    for (final url in [
      'https://evilalipan.com/s/abc',
      'https://alipan.com.evil/s/abc',
      'https://user@alipan.com/s/abc',
      'https://alipan.com:444/s/abc'
    ]) {
      expect(
          () => AliyunShareLink.parse(url), throwsA(isA<QuarkSaveException>()));
    }
  });

  test('Aliyun share pagination detects repeated markers and retains password',
      () async {
    var calls = 0;
    final client = AliyunTransferClient(MockClient((request) async {
      expect(request.headers['X-Share-Token'], 'share');
      final body = jsonDecode(request.body) as Map;
      expect(body['parent_file_id'], 'scoped');
      expect(body['fields'], '*');
      calls++;
      return _json({
        'items': [_row(id: 'file$calls')],
        'next_marker': 'repeat'
      });
    }));
    await expectLater(
        client.listSharedTree(
            const AliyunShareLink('share', 'scoped', ''), 'share'),
        throwsA(isA<QuarkSaveException>()));
    expect(calls, 2);
  });

  test('range proof has no account credentials and requires exact 206',
      () async {
    final client = AliyunTransferClient(MockClient((request) async {
      if (request.url.host == 'api.alipan.com') {
        expect(request.headers['Authorization'], 'Bearer secret');
        return _json({'url': 'https://bucket.aliyuncs.com/file?sign=x'});
      }
      expect(request.headers.containsKey('Authorization'), isFalse);
      expect(request.headers.containsKey('Cookie'), isFalse);
      expect(request.headers['Range'], 'bytes=1-2');
      return http.Response.bytes([2, 3], 206,
          headers: {'content-range': 'bytes 1-2/4'});
    }));
    expect(await client.readRange(_session, _file, 1, 2), [2, 3]);
  });

  test(
      'range proof rejects 200 and external redirects without forwarding secrets',
      () async {
    var calls = 0;
    final client = AliyunTransferClient(MockClient((request) async {
      calls++;
      if (request.url.host == 'api.alipan.com') {
        return _json({'url': 'https://bucket.aliyuncs.com/file'});
      }
      return http.Response('', 302,
          headers: {'location': 'https://evil.test/'});
    }));
    await expectLater(client.readRange(_session, _file, 1, 2),
        throwsA(isA<QuarkSaveException>()));
    expect(calls, 2);
  });

  test('recycle refuses changed parent before mutation', () async {
    var calls = 0;
    final client = AliyunTransferClient(MockClient((request) async {
      calls++;
      expect(request.url.path, '/v2/file/get');
      expect((jsonDecode(request.body) as Map)['fields'], '*');
      return _json(_row(id: 'copy1', parent: 'other'));
    }));
    await expectLater(client.recycleStagedFile(_session, 'stage', _file),
        throwsA(isA<QuarkSaveException>()));
    expect(calls, 1);
  });

  for (final status in [204, 202]) {
    test('recycle HTTP $status distinguishes completion from acceptance',
        () async {
      var mutations = 0;
      final client = AliyunTransferClient(MockClient((request) async {
        if (request.url.path == '/v2/file/get') {
          return _json(_row(id: 'copy1', parent: 'stage'));
        }
        mutations++;
        return status == 204
            ? http.Response('', 204)
            : _json({'async_task_id': 'task'}, 202);
      }));
      final result = client.recycleStagedFile(_session, 'stage', _file);
      if (status == 204) {
        await result;
      } else {
        await expectLater(result, throwsA(isA<QuarkSaveException>()));
      }
      expect(mutations, 1);
    });
  }

  test('login persists rotation before device session and signs recoverably',
      () async {
    final events = <String>[];
    final client = AliyunTransferClient(MockClient((request) async {
      if (request.url.host == 'auth.alipan.com') {
        return _json({
          'access_token': 'access',
          'refresh_token': 'rotated',
          'user_id': 'user',
          'resource_drive_id': 'drive'
        });
      }
      expect(events, ['persist']);
      expect(request.url.path, '/users/v1/users/device/create_session');
      final body = jsonDecode(request.body) as Map;
      final curve = pc.ECDomainParameters('secp256k1');
      expect((body['pubKey'] as String).length, 128);
      final public =
          curve.curve.decodePoint([4, ..._hex(body['pubKey'] as String)]);
      final signature = request.headers['X-Signature']!;
      final signed = pc.ECSignature(
          BigInt.parse(signature.substring(0, 64), radix: 16),
          BigInt.parse(signature.substring(64, 128), radix: 16));
      final verifier = pc.ECDSASigner()
        ..init(false, pc.PublicKeyParameter(pc.ECPublicKey(public, curve)));
      expect(
          verifier.verifySignature(
              Uint8List.fromList(sha256
                  .convert(utf8.encode(
                      '5dde4e1bdf9e4966b387ba58f4b3fdc3:${request.headers['X-Device-Id']}:user:0'))
                  .bytes),
              signed),
          isTrue);
      return _json({});
    }));
    final session = await client.login('old', persistToken: (value) async {
      expect(value, 'rotated');
      events.add('persist');
    });
    expect(session.driveId, 'drive');
  });

  test('Open OAuth login uses OpenList renewal and openFile paths', () async {
    final client = AliyunTransferClient(MockClient((request) async {
      if (request.url.host == 'api.oplist.org') {
        expect(request.url.path, '/alicloud2/renewapi');
        expect(request.url.queryParameters['refresh_ui'], 'old.jwt.token');
        return _json({
          'access_token': 'open-access',
          'refresh_token': 'new.jwt.token',
        });
      }
      if (request.url.host == 'openapi.alipan.com' &&
          request.url.path == '/adrive/v1.0/user/getDriveInfo') {
        expect(request.headers['Authorization'], 'Bearer open-access');
        return _json(
            {'user_id': 'open-user', 'resource_drive_id': 'open-drive'});
      }
      if (request.url.host == 'openapi.alipan.com' &&
          request.url.path == '/adrive/v1.0/openFile/list') {
        expect(request.headers['Authorization'], 'Bearer open-access');
        final body = jsonDecode(request.body) as Map;
        expect(body['drive_id'], 'open-drive');
        expect(body.containsKey('fields'), isFalse);
        return _json({
          'items': [_row()],
          'next_marker': '',
        });
      }
      fail('Unexpected request ${request.url}');
    }));
    var persisted = '';
    final session = await client.login('old.jwt.token',
        open: true, persistToken: (value) async => persisted = value);
    expect(session.open, isTrue);
    expect(session.driveId, 'open-drive');
    expect(persisted, 'new.jwt.token');
    expect(await client.listOwned(session, 'root'), hasLength(1));
  });

  test('Open OAuth share copy uses open host and share token', () async {
    final client = AliyunTransferClient(MockClient((request) async {
      expect(request.url.host, 'openapi.alipan.com');
      expect(request.headers['Authorization'], 'Bearer open-access');
      if (request.url.path == '/v2/file/copy') {
        expect(request.headers['X-Share-Token'], 'share-token');
        final body = jsonDecode(request.body) as Map;
        expect(body['share_id'], 'share');
        expect(body['file_id'], 'share-source');
        expect(body['to_drive_id'], 'open-drive');
        expect(body['to_parent_file_id'], 'stage');
        return _json({'file_id': 'copy1'});
      }
      if (request.url.path == '/adrive/v1.0/openFile/list') {
        return _json({
          'items': [_row(id: 'copy1', parent: 'stage')],
          'next_marker': '',
        });
      }
      fail('Unexpected request ${request.url}');
    }));
    final session = AliyunTransferSession(
        open: true,
        accessToken: 'open-access',
        driveId: 'open-drive',
        deviceId: '',
        signature: '');
    final copy = await client.stageFile(
        session,
        const AliyunShareLink('share', 'root', ''),
        'share-token',
        'stage',
        AliyunTransferFile(
            id: 'share-source',
            name: 'a.mkv',
            parentId: 'root',
            isDirectory: false,
            size: 4,
            sha1: _file.sha1));
    expect(copy.id, 'copy1');
    expect(copy.sha1, _file.sha1);
  });

  test('overlapping logins share one refresh and one device session', () async {
    final gate = Completer<void>();
    var refreshes = 0;
    var sessions = 0;
    var persists = 0;
    final client = AliyunTransferClient(MockClient((request) async {
      if (request.url.host == 'auth.alipan.com') {
        refreshes++;
        await gate.future;
        return _json({
          'access_token': 'access',
          'refresh_token': 'rotated',
          'user_id': 'user',
          'resource_drive_id': 'drive'
        });
      }
      sessions++;
      return _json({});
    }));
    final first = client.login('old', persistToken: (_) async {
      persists++;
    });
    final second = client.login('old', persistToken: (_) async {
      persists++;
    });
    gate.complete();
    final result = await Future.wait([first, second]);
    expect(refreshes, 1);
    expect(sessions, 1);
    expect(persists, 2);
    expect(identical(result.first, result.last), isTrue);
    expect(result.last.refreshToken, 'rotated');
    expect(result.last.userId, 'user');
  });

  test('rotated token joins an in-flight device session', () async {
    final deviceStarted = Completer<void>();
    final finishDevice = Completer<void>();
    var refreshes = 0;
    var sessions = 0;
    var persisted = '';
    final client = AliyunTransferClient(MockClient((request) async {
      if (request.url.host == 'auth.alipan.com') {
        refreshes++;
        return _json({
          'access_token': 'access',
          'refresh_token': 'rotated',
          'user_id': 'user',
          'resource_drive_id': 'drive'
        });
      }
      sessions++;
      deviceStarted.complete();
      await finishDevice.future;
      return _json({});
    }));
    final first = client.login('old', persistToken: (_) async {});
    await deviceStarted.future;
    final second = client.login('rotated', persistToken: (value) async {
      persisted = value;
    });
    finishDevice.complete();
    final result = await Future.wait([first, second]);
    expect(refreshes, 1);
    expect(sessions, 1);
    expect(persisted, 'rotated');
    expect(identical(result.first, result.last), isTrue);
  });

  test('share copy is submitted once and checked against staging identity',
      () async {
    var copies = 0;
    final client = AliyunTransferClient(MockClient((request) async {
      final body = jsonDecode(request.body) as Map;
      if (request.url.path == '/v2/file/copy') {
        copies++;
        expect(body['to_parent_file_id'], 'stage');
        expect(body['share_id'], 'share');
        expect(request.headers['X-Share-Token'], 'token');
        return _json({'file_id': 'copied'}, 201);
      }
      expect(request.url.path, '/v2/file/get');
      expect(body['fields'], '*');
      return _json(_row(id: 'copied', parent: 'stage'));
    }));
    final copy = await client.stageFile(_session,
        const AliyunShareLink('share', 'root', ''), 'token', 'stage', _file);
    expect(copy.id, 'copied');
    expect(copies, 1);
  });

  test('copy network failure is not retried and never triggers trash',
      () async {
    var requests = 0;
    final client = AliyunTransferClient(MockClient((request) async {
      requests++;
      expect(request.url.path, '/v2/file/copy');
      throw http.ClientException('lost response');
    }));
    await expectLater(
        client.stageFile(_session, const AliyunShareLink('share', 'root', ''),
            'token', 'stage', _file),
        throwsA(isA<QuarkSaveException>()));
    expect(requests, 1);
  });
}
