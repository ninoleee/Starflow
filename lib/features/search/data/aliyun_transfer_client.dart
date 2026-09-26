import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';
import 'package:starflow/core/network/bounded_http_request.dart';
import 'package:starflow/features/search/domain/share_link_validation.dart';
import 'package:starflow/features/search/data/aliyun_transfer_http.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/search/domain/cloud_save_rules.dart';
import 'package:starflow/features/search/domain/cloud_account_auth_exception.dart';
import 'package:starflow/features/settings/data/aliyun_open_oauth_config.dart';

const _aliyunShareErrorCodes = {
  'ShareLink.Cancelled',
  'ShareLink.Expired',
  'ShareLink.Forbidden',
  'ShareLink.NotFound',
  'ShareLinkPunished',
  'ShareLinkPwdInvalid',
};

Map<String, dynamic>? _tryDecodeTransferJson(http.Response response) {
  try {
    final value = jsonDecode(utf8.decode(response.bodyBytes));
    return value is Map<String, dynamic> ? value : null;
  } catch (_) {
    return null;
  }
}

Map<String, Object> _shareTokenBody(AliyunShareLink link) => {
      'share_id': link.id,
      if (link.password.isNotEmpty) 'share_pwd': link.password,
    };

class AliyunShareLink {
  const AliyunShareLink(this.id, this.parentId, this.password);
  final String id;
  final String parentId;
  final String password;

  factory AliyunShareLink.parse(String raw, {String password = ''}) {
    final uri = Uri.tryParse(raw.trim());
    final parts = uri?.pathSegments ?? const <String>[];
    if (uri == null ||
        !{'https', 'http'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        !{
          'alipan.com',
          'www.alipan.com',
          'aliyundrive.com',
          'www.aliyundrive.com'
        }.contains(uri.host.toLowerCase()) ||
        !(parts.length == 2 || parts.length == 4 && parts[2] == 'folder') ||
        parts.first != 's' ||
        !RegExp(r'^[a-zA-Z0-9]+$').hasMatch(parts[1]) ||
        parts.length == 4 && !RegExp(r'^[a-zA-Z0-9]+$').hasMatch(parts[3])) {
      throw const QuarkSaveException('不是可识别的阿里云盘分享链接');
    }
    return AliyunShareLink(
        parts[1],
        parts.length == 4 ? parts[3] : 'root',
        uri.queryParameters['pwd'] ??
            uri.queryParameters['password'] ??
            password);
  }
}

class AliyunTransferFile implements CloudSaveEntry {
  const AliyunTransferFile(
      {required this.id,
      required this.name,
      required this.parentId,
      required this.isDirectory,
      this.size = 0,
      this.sha1 = '',
      this.path = const []});
  final String id;
  @override
  String get fid => id;
  @override
  final String name;
  final String parentId;
  @override
  final bool isDirectory;
  final int size;
  final String sha1;
  final List<String> path;

  AliyunTransferFile withTargetName(String name, List<String> path) =>
      AliyunTransferFile(
          id: id,
          name: name,
          parentId: parentId,
          isDirectory: isDirectory,
          size: size,
          sha1: sha1,
          path: path);

  AliyunTransferFile withSha1(String value) => AliyunTransferFile(
      id: id,
      name: name,
      parentId: parentId,
      isDirectory: isDirectory,
      size: size,
      sha1: value,
      path: path);

  factory AliyunTransferFile.parse(Map<String, dynamic> row,
      {List<String> path = const [], bool allowMissingSha1 = false}) {
    final id = row['file_id'];
    final name = row['name'];
    final folder = row['type'] == 'folder';
    final size = int.tryParse('${row['size']}');
    final hash = '${row['content_hash'] ?? ''}'.toUpperCase();
    final hashName = '${row['content_hash_name'] ?? ''}'.toLowerCase();
    final validSha1 = RegExp(r'^[A-F0-9]{40}$').hasMatch(hash) &&
        (hashName.isEmpty || hashName == 'sha1');
    final missingSha1 =
        hash.isEmpty && (hashName.isEmpty || hashName == 'sha1');
    final invalidHash = !validSha1 && !(allowMissingSha1 && missingSha1);
    if (id is! String ||
        !RegExp(r'^[a-zA-Z0-9]+$').hasMatch(id) ||
        id == 'root' ||
        name is! String ||
        name.isEmpty ||
        name == '.' ||
        name == '..' ||
        RegExp(r'[/\\\x00-\x1f]').hasMatch(name) ||
        !{'file', 'folder'}.contains(row['type']) ||
        !folder && (size == null || size < 0 || invalidHash)) {
      throw const QuarkSaveException(
          '阿里文件数据不完整（需要有效的文件 ID、名称、类型、大小和 SHA1），已停止转存');
    }
    return AliyunTransferFile(
        id: id,
        name: name,
        parentId: '${row['parent_file_id'] ?? ''}',
        isDirectory: folder,
        size: size ?? 0,
        sha1: hash,
        path: List.unmodifiable(path));
  }
}

class AliyunTransferSession {
  AliyunTransferSession(
      {this.userId = '',
      this.refreshToken = '',
      this.open = false,
      required this.accessToken,
      required this.driveId,
      required this.deviceId,
      required this.signature});
  final String accessToken;
  final String userId;
  final String refreshToken;
  final bool open;
  final String driveId;
  final String deviceId;
  final String signature;
  Map<String, String> get headers => {
        'Authorization': 'Bearer $accessToken',
        if (!open) ...{
          'X-Device-Id': deviceId,
          'X-Signature': signature,
        },
      };
}

class AliyunTransferClient {
  AliyunTransferClient(this.client);
  final http.Client client;
  final _pendingLogins = <String, Future<AliyunTransferSession>>{};

  Future<ShareLinkValidationResult> validateShareLink(
      {required String shareUrl, String password = ''}) async {
    try {
      final link = AliyunShareLink.parse(shareUrl, password: password);
      final deadline = DateTime.now().add(const Duration(seconds: 8));
      Future<Map<String, dynamic>> read(String path, Map<String, Object> body,
          {String? token}) async {
        final uri = Uri.https('api.alipan.com', path);
        var visited = false;
        final response = await sendBoundedRequest(client, 'POST', uri,
            headers: {
              'Content-Type': 'application/json',
              'Referer': 'https://www.alipan.com/',
              if (token != null) 'X-Share-Token': token,
            },
            body: jsonEncode(body),
            maxBytes: 128 * 1024,
            timeout: deadline.difference(DateTime.now()), allowUri: (next) {
          if (visited) return false;
          visited = true;
          return next == uri;
        });
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final data = _tryDecodeTransferJson(response);
          if (data != null) return data;
        }
        return transferJson(response, '阿里云盘');
      }

      ShareLinkValidationResult? error(Map<String, dynamic> data) {
        final code = data['code'];
        if (code == null) return null;
        if (_aliyunShareErrorCodes.contains(code)) {
          return const ShareLinkValidationResult.invalid('分享失效或提取码错误');
        }
        return const ShareLinkValidationResult.unavailable('阿里暂未验证');
      }

      final auth =
          await read('/v2/share_link/get_share_token', _shareTokenBody(link));
      final authError = error(auth);
      if (authError != null) return authError;
      final token = auth['share_token'];
      if (token is! String || token.isEmpty) {
        return const ShareLinkValidationResult.unavailable('阿里分享授权不完整');
      }
      final data = await read(
          '/adrive/v3/file/list',
          {
            'share_id': link.id,
            'parent_file_id': link.parentId,
            'limit': 1,
            'fields': '*',
            'marker': ''
          },
          token: token);
      final listError = error(data);
      if (listError != null) return listError;
      final items = data['items'];
      if (items is! List || data['next_marker'] is! String) {
        return const ShareLinkValidationResult.unavailable('阿里目录响应不完整');
      }
      if (items.isEmpty) {
        return data['next_marker'] == ''
            ? const ShareLinkValidationResult.invalid('分享内容为空')
            : const ShareLinkValidationResult.unavailable('阿里目录响应不完整');
      }
      if (items.first is! Map ||
          items.first['file_id'] is! String ||
          !{'file', 'folder'}.contains(items.first['type'])) {
        return const ShareLinkValidationResult.unavailable('阿里目录响应异常');
      }
      return const ShareLinkValidationResult.valid();
    } catch (_) {
      return const ShareLinkValidationResult.unavailable('阿里暂未验证');
    }
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body,
      {AliyunTransferSession? session,
      String? shareToken,
      String host = 'api.alipan.com'}) async {
    final effectiveHost = session?.open == true ? 'openapi.alipan.com' : host;
    final effectivePath = session?.open == true ? _openPath(path) : path;
    final response = await transferRequest(
        client, 'POST', Uri.https(effectiveHost, effectivePath),
        headers: {
          'Content-Type': 'application/json',
          'Referer': 'https://www.alipan.com/',
          'Origin': 'https://www.alipan.com',
          if (session?.open != true)
            'X-Canary': 'client=web,app=share,version=v2.3.1',
          ...?session?.headers,
          if (shareToken != null) 'X-Share-Token': shareToken,
        },
        body: jsonEncode(body));
    if (path == '/v2/recyclebin/trash' &&
        (response.statusCode == 204 || session?.open == true)) {
      return const {'completed': true};
    }
    if (path == '/v2/share_link/get_share_token') {
      final error = _tryDecodeTransferJson(response);
      if (_aliyunShareErrorCodes.contains(error?['code'])) {
        throw const QuarkSaveException('阿里分享已失效或提取码错误，请重新搜索');
      }
    }
    if (response.statusCode == 401 && shareToken == null) {
      throw const CloudAccountAuthException();
    }
    final data = transferJson(response, '阿里云盘');
    if (const [
      'RefreshTokenExpired',
      'InvalidRefreshToken',
      'AccessTokenInvalid',
      'AccessTokenExpired'
    ].contains(data['code'])) {
      throw const CloudAccountAuthException();
    }
    if (data['code'] != null) {
      // Provider messages can echo credentials or URLs; use a fixed message.
      throw const QuarkSaveException('阿里请求被拒绝，请检查登录、提取码、容量或设备授权');
    }
    return data;
  }

  static String _openPath(String path) => switch (path) {
        '/v2/file/list' || '/v3/file/list' => '/adrive/v1.0/openFile/list',
        '/v3/file/update' => '/adrive/v1.0/openFile/update',
        '/adrive/v2/file/createWithFolders' => '/adrive/v1.0/openFile/create',
        '/v2/recyclebin/trash' => '/adrive/v1.0/openFile/recyclebin/trash',
        '/v2/file/get_download_url' => '/adrive/v1.0/openFile/getDownloadUrl',
        _ => path,
      };

  Future<AliyunTransferSession> login(String refreshToken,
      {required Future<void> Function(String) persistToken,
      bool open = false}) async {
    final key = _loginKey(refreshToken, open);
    final pending = _pendingLogins[key];
    if (pending != null) {
      final session = await pending;
      await persistToken(session.refreshToken);
      return session;
    }
    late Future<AliyunTransferSession> operation;
    operation = (open
        ? _loginOpen(refreshToken, persistToken: (next) async {
            final rotatedKey = _loginKey(next, true);
            _pendingLogins[rotatedKey] = operation;
            await persistToken(next);
          })
        : _login(refreshToken, persistToken: (next) async {
            final rotatedKey = _loginKey(next, false);
            _pendingLogins[rotatedKey] = operation;
            await persistToken(next);
          }));
    _pendingLogins[key] = operation;
    try {
      return await operation;
    } finally {
      _pendingLogins.removeWhere((_, value) => identical(value, operation));
    }
  }

  static String _loginKey(String refreshToken, bool open) => hashes.sha256
      .convert(utf8.encode('${open ? 'open' : 'consumer'}:'
          '${refreshToken.trim()}'))
      .toString();

  Future<AliyunTransferSession> _login(String refreshToken,
      {required Future<void> Function(String) persistToken}) async {
    if (refreshToken.trim().isEmpty) {
      throw const QuarkSaveException('请先配置阿里云盘 Refresh Token');
    }
    final auth = await _post(
        '/v2/account/token',
        {
          'refresh_token': refreshToken.trim(),
          'grant_type': 'refresh_token',
        },
        host: 'auth.alipan.com');
    final access = auth['access_token'];
    final rotated = auth['refresh_token'];
    final user = auth['user_id'];
    final drive = auth['resource_drive_id'] ?? auth['default_drive_id'];
    if (access is! String ||
        access.isEmpty ||
        rotated is! String ||
        rotated.isEmpty ||
        user is! String ||
        user.isEmpty ||
        drive is! String ||
        drive.isEmpty) {
      throw const QuarkSaveException('阿里登录响应不完整');
    }
    await persistToken(rotated);
    final device =
        hashes.sha256.convert(utf8.encode('starflow:$user')).toString();
    final curve = ECDomainParameters('secp256k1');
    final random = Random.secure();
    final key = BigInt.parse(
                _hex(List.generate(32, (_) => random.nextInt(256))),
                radix: 16) %
            (curve.n - BigInt.one) +
        BigInt.one;
    final public = (curve.G * key)!;
    final digest = Uint8List.fromList(hashes.sha256
        .convert(
            utf8.encode('5dde4e1bdf9e4966b387ba58f4b3fdc3:$device:$user:0'))
        .bytes);
    final signer = ECDSASigner(null, HMac(SHA256Digest(), 64))
      ..init(true, PrivateKeyParameter(ECPrivateKey(key, curve)));
    final signed = signer.generateSignature(digest) as ECSignature;
    final s = signed.s > curve.n >> 1 ? curve.n - signed.s : signed.s;
    final e = BigInt.parse(_hex(digest), radix: 16);
    int? recovery;
    for (var i = 0; i < 4; i++) {
      try {
        final rPoint = curve.curve
            .decompressPoint(i & 1, signed.r + curve.n * BigInt.from(i >> 1));
        final recovered = ((rPoint * s)! - (curve.G * (e % curve.n))!)! *
            signed.r.modInverse(curve.n);
        if (recovered == public) {
          recovery = i;
          break;
        }
      } catch (_) {}
    }
    if (recovery == null) throw const QuarkSaveException('阿里设备签名失败');
    final signature = '${signed.r.toRadixString(16).padLeft(64, '0')}'
        '${s.toRadixString(16).padLeft(64, '0')}'
        '${recovery.toRadixString(16).padLeft(2, '0')}';
    final session = AliyunTransferSession(
        userId: user,
        refreshToken: rotated,
        accessToken: access,
        driveId: drive,
        deviceId: device,
        signature: signature);
    await _post(
        '/users/v1/users/device/create_session',
        {
          'deviceName': 'Starflow',
          'modelName': 'Starflow',
          'nonce': 0,
          'pubKey': _hex(public.getEncoded(false).sublist(1)),
          'refreshToken': rotated,
        },
        session: session);
    return session;
  }

  Future<AliyunTransferSession> _loginOpen(String refreshToken,
      {required Future<void> Function(String) persistToken}) async {
    if (refreshToken.trim().isEmpty) {
      throw const QuarkSaveException('请先完成阿里开放平台扫码登录');
    }
    Map<String, dynamic>? data;
    Object? lastError;
    for (final base in AliyunOpenOAuthConfig.serviceBases) {
      final uri = Uri.parse('$base${AliyunOpenOAuthConfig.renewPath}')
          .replace(queryParameters: {'refresh_ui': refreshToken.trim()});
      var visited = false;
      try {
        final response = await sendBoundedRequest(client, 'GET', uri,
            headers: const {
              'Accept': 'application/json',
              'X-Client-Fingerprint': 'starflow',
            },
            timeout: const Duration(seconds: 30),
            maxBytes: 128 * 1024, allowUri: (next) {
          if (visited) return false;
          visited = true;
          return next == uri;
        });
        data = transferJson(response, '阿里开放平台');
        break;
      } catch (error) {
        lastError = error;
      }
    }
    if (data == null) {
      if (lastError is QuarkSaveException) throw lastError;
      throw const QuarkSaveException('阿里开放平台暂时不可用，请稍后重试');
    }
    final access = data['access_token'];
    final rotated = data['refresh_token'];
    if (access is! String ||
        access.isEmpty ||
        rotated is! String ||
        rotated.isEmpty ||
        rotated.split('.').length != 3) {
      throw const QuarkSaveException('阿里开放平台登录已失效，请重新扫码');
    }
    await persistToken(rotated);
    final provisional = AliyunTransferSession(
        refreshToken: rotated,
        open: true,
        accessToken: access,
        driveId: '',
        deviceId: '',
        signature: '');
    final info = await _post('/adrive/v1.0/user/getDriveInfo', const {},
        session: provisional);
    final user = '${info['user_id'] ?? ''}';
    final drive =
        '${info['resource_drive_id'] ?? info['default_drive_id'] ?? info['drive_id'] ?? ''}';
    if (drive.isEmpty) {
      throw const QuarkSaveException('阿里开放平台未返回可用资源盘');
    }
    return AliyunTransferSession(
        userId: user,
        refreshToken: rotated,
        open: true,
        accessToken: access,
        driveId: drive,
        deviceId: '',
        signature: '');
  }

  static String _hex(List<int> data) =>
      data.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  Future<List<AliyunTransferFile>> listOwned(
      AliyunTransferSession session, String parentId) async {
    final entries = <AliyunTransferFile>[];
    var marker = '';
    final markers = <String>{};
    final ids = <String>{};
    do {
      if (!markers.add(marker)) throw const QuarkSaveException('阿里目录分页重复');
      final data = await _post(
          '/v2/file/list',
          {
            'drive_id': session.driveId,
            'parent_file_id': parentId,
            'limit': 100,
            'marker': marker,
            if (!session.open) 'fields': '*',
            'order_by': 'name',
            'order_direction': 'ASC',
          },
          session: session);
      final rows = data['items'];
      if (rows is! List || data['next_marker'] is! String) {
        throw const QuarkSaveException('阿里目录分页不完整');
      }
      for (final row in rows) {
        if (row is! Map<String, dynamic>) {
          throw const QuarkSaveException('阿里目录格式异常');
        }
        final entry = AliyunTransferFile.parse(row);
        if (!ids.add(entry.id) || ids.length > 10000 || entry.id == parentId) {
          throw const QuarkSaveException('阿里目录文件标识异常');
        }
        entries.add(entry);
      }
      marker = data['next_marker'] as String;
      if (marker.isNotEmpty && rows.isEmpty) {
        throw const QuarkSaveException('阿里目录分页为空');
      }
    } while (marker.isNotEmpty);
    return entries;
  }

  Future<AliyunTransferFile> _getOwned(
      AliyunTransferSession session, String parentId, String id) async {
    if (session.open) {
      final matches =
          (await listOwned(session, parentId)).where((e) => e.id == id);
      if (matches.length != 1) {
        throw const QuarkSaveException('阿里开放平台文件身份已变化');
      }
      return matches.single;
    }
    final row = await _post('/v2/file/get',
        {'drive_id': session.driveId, 'file_id': id, 'fields': '*'},
        session: session);
    return AliyunTransferFile.parse(row);
  }

  Future<void> renameOwned(AliyunTransferSession session,
      AliyunTransferFile file, String name) async {
    await _post(
        '/v3/file/update',
        {
          'drive_id': session.driveId,
          'file_id': file.id,
          'name': name,
          'check_name_mode': 'refuse'
        },
        session: session);
    final row = await _getOwned(session, file.parentId, file.id);
    if (row.name != name ||
        row.parentId != file.parentId ||
        row.sha1 != file.sha1) {
      throw const QuarkSaveException('阿里名称修改未确认');
    }
  }

  Future<void> recycleOwned(
      AliyunTransferSession session, String parentId, List<String> ids) async {
    if (ids.any((id) => id == 'root' || id == parentId || id.isEmpty)) {
      throw const QuarkSaveException('不能删除阿里根目录或当前目录');
    }
    final entries = await listOwned(session, parentId);
    if (ids.any((id) => entries.where((e) => e.id == id).length != 1)) {
      throw const QuarkSaveException('阿里删除目标已变化，请刷新目录');
    }
    for (final id in ids) {
      final result = await _post(
          '/v2/recyclebin/trash', {'drive_id': session.driveId, 'file_id': id},
          session: session);
      if (result['completed'] != true) {
        throw const QuarkSaveException('阿里清理尚未确认，请刷新后检查');
      }
    }
    if ((await listOwned(session, parentId)).any((e) => ids.contains(e.id))) {
      throw const QuarkSaveException('阿里删除尚未生效');
    }
  }

  Future<String> shareToken(AliyunShareLink link) async {
    final data =
        await _post('/v2/share_link/get_share_token', _shareTokenBody(link));
    final token = data['share_token'];
    if (token is! String || token.isEmpty) {
      throw const QuarkSaveException('未取得阿里分享授权');
    }
    return token;
  }

  Future<List<AliyunTransferFile>> listSharedTree(
      AliyunShareLink link, String token) async {
    final files = <AliyunTransferFile>[];
    final ids = <String>{};
    Future<void> visit(String parent, List<String> path) async {
      if (path.length > 25) throw const QuarkSaveException('阿里目录层级过深');
      var marker = '';
      final markers = <String>{};
      do {
        if (!markers.add(marker)) throw const QuarkSaveException('阿里分页重复');
        final data = await _post(
            '/adrive/v3/file/list',
            {
              'share_id': link.id,
              'parent_file_id': parent,
              'limit': 100,
              'fields': '*',
              'marker': marker,
              'order_by': 'name',
              'order_direction': 'ASC',
            },
            shareToken: token);
        final rows = data['items'];
        if (rows is! List || data['next_marker'] is! String) {
          throw const QuarkSaveException('阿里目录分页不完整');
        }
        for (final row in rows) {
          if (row is! Map<String, dynamic>) {
            throw const QuarkSaveException('阿里目录格式异常');
          }
          final entry = AliyunTransferFile.parse(
              {...row, 'parent_file_id': parent},
              path: path, allowMissingSha1: true);
          if (!ids.add(entry.id) || ids.length > 10000) {
            throw const QuarkSaveException('阿里目录重复或超过一万项');
          }
          files.add(entry);
          if (entry.isDirectory) await visit(entry.id, [...path, entry.name]);
        }
        marker = data['next_marker'] as String;
        if (marker.isNotEmpty && rows.isEmpty) {
          throw const QuarkSaveException('阿里目录分页为空，已停止');
        }
      } while (marker.isNotEmpty);
    }

    await visit(link.parentId, const []);
    return files;
  }

  Future<String> createStagingFolder(
      AliyunTransferSession session, String name) async {
    return createSaveDirectory(session, 'root', name);
  }

  Future<String> createSaveDirectory(
      AliyunTransferSession session, String parentId, String name) async {
    final data = await _post(
        '/adrive/v2/file/createWithFolders',
        {
          'drive_id': session.driveId,
          'parent_file_id': parentId,
          'name': name,
          'type': 'folder',
          'check_name_mode': 'refuse',
        },
        session: session);
    final id = data['file_id'];
    if (id is! String ||
        !RegExp(r'^[a-zA-Z0-9]+$').hasMatch(id) ||
        id == 'root' ||
        id == parentId ||
        data['exist'] == true) {
      throw const QuarkSaveException('阿里保存目录未确认创建，未继续操作');
    }
    return id;
  }

  Future<AliyunTransferFile> stageFile(
      AliyunTransferSession session,
      AliyunShareLink link,
      String token,
      String stagingId,
      AliyunTransferFile source) async {
    final data = await _post(
        '/v2/file/copy',
        {
          'share_id': link.id,
          'file_id': source.id,
          'to_drive_id': session.driveId,
          'to_parent_file_id': stagingId,
          'auto_rename': true,
        },
        session: session,
        shareToken: token);
    final id = data['file_id'];
    if (id is! String || id.isEmpty || id == source.id || id == stagingId) {
      throw const QuarkSaveException('阿里副本 ID 未确认，已停止');
    }
    // A copy may be asynchronous. Poll only metadata, never repeat the copy.
    for (var attempt = 0; attempt < 4; attempt++) {
      if (attempt > 0) await Future<void>.delayed(const Duration(seconds: 1));
      late final AliyunTransferFile staged;
      try {
        staged = await _getOwned(session, stagingId, id);
      } on QuarkSaveException {
        continue;
      }
      if (staged.id != id ||
          staged.parentId != stagingId ||
          staged.isDirectory ||
          staged.size != source.size ||
          source.sha1.isNotEmpty && staged.sha1 != source.sha1) {
        throw const QuarkSaveException('阿里副本校验不一致，未继续转存');
      }
      return staged;
    }
    throw const QuarkSaveException('阿里副本仍在生成，请稍后检查暂存目录');
  }

  Future<Uint8List> readRange(AliyunTransferSession session,
      AliyunTransferFile file, int start, int end) async {
    if (start < 0 ||
        end < start ||
        end >= file.size ||
        end - start + 1 > 1024 * 1024) {
      throw const QuarkSaveException('115 请求的校验范围无效或超过 1 MiB');
    }
    final data = await _post(
        '/v2/file/get_download_url',
        {
          'drive_id': session.driveId,
          'file_id': file.id,
          'expire_sec': 600,
        },
        session: session);
    final uri = Uri.tryParse('${data['url'] ?? ''}');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        !(uri.host.endsWith('.aliyuncs.com') ||
            uri.host.endsWith('.alipan.com') ||
            uri.host.endsWith('.aliyundrive.com'))) {
      throw const QuarkSaveException('阿里下载地址不在可信域名内');
    }
    final length = end - start + 1;
    final response = await transferRequest(client, 'GET', uri,
        headers: {
          'Range': 'bytes=$start-$end',
          'Referer': 'https://www.alipan.com/',
          'Accept-Encoding': 'identity'
        },
        maxBytes: length);
    if (response.statusCode != 206 ||
        response.headers['content-range'] != 'bytes $start-$end/${file.size}' ||
        response.bodyBytes.length != length) {
      throw const QuarkSaveException('阿里范围读取未通过校验，未提交秒传证明');
    }
    return response.bodyBytes;
  }

  Future<void> recycleStagedFile(AliyunTransferSession session,
      String stagingId, AliyunTransferFile expected) async {
    final current = await _getOwned(session, stagingId, expected.id);
    if (current.parentId != stagingId ||
        current.id != expected.id ||
        current.name != expected.name ||
        current.isDirectory ||
        current.sha1 != expected.sha1 ||
        current.size != expected.size) {
      throw const QuarkSaveException('阿里副本已变化，未删除');
    }
    final result = await _post('/v2/recyclebin/trash',
        {'drive_id': session.driveId, 'file_id': expected.id},
        session: session);
    if (result['completed'] != true) {
      throw const QuarkSaveException('阿里清理已受理但尚未确认完成，请手动检查回收站');
    }
  }

  static String newStagingName() => 'Starflow-transfer-'
      '${DateTime.now().millisecondsSinceEpoch}-'
      '${Random.secure().nextInt(0x7fffffff).toRadixString(16)}';
}
