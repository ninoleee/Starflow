import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/features/search/data/aliyun_transfer_http.dart';
import 'package:starflow/features/search/data/cloud115_upload_cipher.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/search/domain/cloud_account_auth_exception.dart';

class Cloud115UploadAccount {
  const Cloud115UploadAccount(this.userId, this.userKey, this.sizeLimit);
  final String userId;
  final String userKey;
  final int sizeLimit;
}

class Cloud115InstantUploadClient {
  Cloud115InstantUploadClient(this.client,
      {Cloud115UploadCipher Function()? cipherFactory})
      : _cipherFactory = cipherFactory ?? Cloud115UploadCipher.new;
  final http.Client client;
  final Cloud115UploadCipher Function() _cipherFactory;
  static const version = '27.0.5.7';

  Map<String, String> _headers(String cookie) => {
        'Cookie': cookie.trim(),
        'Referer': 'https://115.com/',
        'User-Agent': 'Mozilla/5.0 115Browser/$version',
      };

  Future<Cloud115UploadAccount> account(String cookie) async {
    final response = await transferRequest(
        client, 'POST', Uri.https('proapi.115.com', '/app/uploadinfo'),
        headers: _headers(cookie));
    if (response.statusCode == 401) throw const CloudAccountAuthException();
    final data = transferJson(response, '115');
    final id = '${data['user_id'] ?? ''}';
    final key = data['userkey'];
    final limit = int.tryParse('${data['size_limit']}');
    if ((data['state'] != true && data['state'] != 1) ||
        !RegExp(r'^[1-9][0-9]*$').hasMatch(id) ||
        key is! String ||
        key.isEmpty ||
        data['upload_allowed'] != true ||
        limit == null ||
        limit <= 0) {
      throw const QuarkSaveException('115 上传权限未确认，请检查 Cookie 和账号状态');
    }
    return Cloud115UploadAccount(id, key, limit);
  }

  Future<bool> upload(
      {required String cookie,
      required Cloud115UploadAccount account,
      required String parentId,
      required String name,
      required int size,
      required String fileSha1,
      required Future<Uint8List> Function(int, int) readRange}) async {
    if (size < 0 ||
        size > account.sizeLimit ||
        !RegExp(r'^[A-Fa-f0-9]{40}$').hasMatch(fileSha1) ||
        !RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(parentId)) {
      throw const QuarkSaveException('115 文件大小、SHA1 或目标目录无效');
    }
    final hash = fileSha1.toUpperCase();
    final target = 'U_1_$parentId';
    final cipher = _cipherFactory();
    var signKey = '';
    var signVal = '';
    for (var proof = 0; proof < 2; proof++) {
      final time = DateTime.now().millisecondsSinceEpoch;
      final inner =
          sha1.convert(ascii.encode('${account.userId}$hash${target}0'));
      final signature = sha1
          .convert(ascii.encode('${account.userKey}${inner.toString()}000000'))
          .toString()
          .toUpperCase();
      final token = md5
          .convert(ascii.encode('Qclm8MGWUv59TnrR0XPg'
              '$hash$size$signKey$signVal${account.userId}$time'
              '${md5.convert(ascii.encode(account.userId))}$version'))
          .toString();
      final fields = {
        'appid': '0',
        'appversion': version,
        'userid': account.userId,
        // The v4 endpoint validates the upload key in the encrypted form as
        // well as using it to derive sig. Older Go clients omitted this field,
        // but current 115 responses reject that request with status 4/400.
        'userkey': account.userKey,
        'filename': name,
        'filesize': '$size',
        'fileid': hash,
        'target': target,
        'topupload': 'true',
        'sig': signature,
        't': '$time',
        'token': token,
        if (signKey.isNotEmpty) 'sign_key': signKey,
        if (signVal.isNotEmpty) 'sign_val': signVal,
      };
      final encoded = fields.entries
          .map((e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      final response = await transferRequest(
          client,
          'POST',
          Uri.https('uplb.115.com', '/4.0/initupload.php',
              {'k_ec': cipher.token(time)}),
          headers: {
            ..._headers(cookie),
            'Content-Type': 'application/x-www-form-urlencoded'
          },
          body: cipher.encrypt(utf8.encode(encoded)),
          maxBytes: 128 * 1024);
      if (response.statusCode != 200) {
        throw QuarkSaveException('115 秒传响应未确认（HTTP ${response.statusCode}）');
      }
      late Map<String, dynamic> data;
      try {
        data = jsonDecode(utf8.decode(cipher.decrypt(response.bodyBytes)))
            as Map<String, dynamic>;
      } catch (_) {
        throw const QuarkSaveException('115 秒传响应校验失败');
      }
      final status = int.tryParse('${data['status']}');
      final hasCode = data.containsKey('statuscode');
      final code = hasCode ? int.tryParse('${data['statuscode']}') : 0;
      final hasTarget = data.containsKey('target');
      final diagnostics = <String, Object?>{
        'status': status,
        'statuscode': code,
        'statuscodePresent': hasCode,
        'errno': int.tryParse('${data['errno']}'),
        'errorCode': int.tryParse('${data['code']}'),
        'targetPresent': hasTarget,
        'targetMatches': hasTarget ? data['target'] == target : null,
        'proofAttempt': proof,
      };
      QuarkSaveException rejected(String reason) {
        appLogWarning('115.instant-upload', 'Upload response not confirmed',
            fields: {...diagnostics, 'reason': reason});
        return QuarkSaveException('$reason'
            '（status=${status ?? '未知'}，'
            'statuscode=${hasCode ? code ?? '无效' : '未返回'}），阿里副本保留');
      }

      if (hasTarget && data['target'] != target) {
        throw rejected('115 秒传响应目标不一致');
      }
      // target/pickcode may be omitted. The workflow still verifies the actual
      // destination name, size and SHA1 before reporting success or cleanup.
      if (status == 2 && code == 0) {
        appLogInfo('115.instant-upload', 'Instant upload awaiting target check',
            fields: diagnostics);
        return true;
      }
      if (status == 1 && code == 0) {
        appLogInfo('115.instant-upload', 'Instant upload not matched',
            fields: diagnostics);
        return false;
      }
      if (status != 7 || (code != 0 && code != 701) || proof != 0) {
        throw rejected(switch (code) {
          400 => '115 拒绝秒传签名',
          402 => '115 拒绝秒传文件或目标参数',
          99 || 990001 => '115 登录状态失效，请重新登录',
          _ => '115 未确认秒传成功',
        });
      }
      appLogInfo('115.instant-upload', 'Upload range proof requested',
          fields: diagnostics);
      signKey = '${data['sign_key'] ?? ''}';
      final range =
          RegExp(r'^(\d+)-(\d+)$').firstMatch('${data['sign_check']}');
      if (signKey.isEmpty || range == null) {
        throw rejected('115 秒传校验要求不完整');
      }
      final start = int.tryParse(range[1]!);
      final end = int.tryParse(range[2]!);
      if (start == null ||
          end == null ||
          start < 0 ||
          end < start ||
          end >= size ||
          end - start + 1 > 1024 * 1024) {
        throw rejected('115 秒传校验范围无效');
      }
      final bytes = await readRange(start, end);
      if (bytes.length != end - start + 1) {
        throw const QuarkSaveException('阿里校验数据长度不一致');
      }
      signVal = sha1.convert(bytes).toString().toUpperCase();
    }
    throw const QuarkSaveException('115 秒传未完成');
  }
}
