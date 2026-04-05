import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

final quarkSaveClientProvider = Provider<QuarkSaveClient>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return QuarkSaveClient(client);
});

class QuarkSaveClient {
  QuarkSaveClient(this._client);

  static const _baseUrl = 'https://drive-pc.quark.cn';
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) quark-cloud-drive/3.14.2 Chrome/112.0.5615.165 '
      'Electron/24.1.3.8 Safari/537.36 Channel/pckk_other_ch';

  final http.Client _client;

  Future<QuarkSaveResult> saveShareLink({
    required String shareUrl,
    required String cookie,
    String toPdirFid = '0',
    String toPdirPath = '/',
    String saveFolderName = '',
  }) async {
    final trimmedCookie = cookie.trim();
    if (trimmedCookie.isEmpty) {
      throw const QuarkSaveException('请先在搜索设置里填写夸克 Cookie');
    }

    final parsed = _parseShareUrl(shareUrl);
    if (parsed == null) {
      throw const QuarkSaveException('不是可识别的夸克分享链接');
    }

    final stoken = await _fetchShareToken(
      pwdId: parsed.pwdId,
      passcode: parsed.passcode,
      cookie: trimmedCookie,
    );
    final sharedEntries = await _fetchShareEntries(
      pwdId: parsed.pwdId,
      stoken: stoken,
      pdirFid: parsed.pdirFid,
      cookie: trimmedCookie,
    );
    if (sharedEntries.isEmpty) {
      throw const QuarkSaveException('分享链接里没有可保存的文件');
    }

    final normalizedTargetDirectoryPath = _normalizeDirectoryPath(toPdirPath);
    var resolvedTargetDirectoryId =
        toPdirFid.trim().isEmpty ? '0' : toPdirFid.trim();
    final sanitizedFolderName = _sanitizeDirectoryName(saveFolderName);
    final currentTargetDirectoryName = _sanitizeDirectoryName(
        _lastDirectoryName(normalizedTargetDirectoryPath));
    final shouldCreateNamedDirectory = sanitizedFolderName.isNotEmpty &&
        currentTargetDirectoryName.toLowerCase() !=
            sanitizedFolderName.toLowerCase();
    if (shouldCreateNamedDirectory) {
      resolvedTargetDirectoryId = await _ensureDirectory(
        cookie: trimmedCookie,
        parentFid: resolvedTargetDirectoryId,
        parentPath: toPdirPath,
        folderName: sanitizedFolderName,
      );
    }
    final effectiveSharedEntries = sanitizedFolderName.isEmpty
        ? sharedEntries
        : await _flattenTopDirectory(
            pwdId: parsed.pwdId,
            stoken: stoken,
            cookie: trimmedCookie,
            entries: sharedEntries,
          );
    final resolvedTargetDirectoryPath = !shouldCreateNamedDirectory
        ? normalizedTargetDirectoryPath
        : sanitizedFolderName.isEmpty
            ? normalizedTargetDirectoryPath
            : normalizedTargetDirectoryPath == '/'
                ? '/$sanitizedFolderName'
                : '$normalizedTargetDirectoryPath/$sanitizedFolderName';

    final response = await _client.post(
      Uri.parse('$_baseUrl/1/clouddrive/share/sharepage/save').replace(
        queryParameters: {
          'pr': 'ucpro',
          'fr': 'pc',
          'uc_param_str': '',
          'app': 'clouddrive',
          '__dt': '${(math.Random().nextDouble() * 4 + 1).round() * 60 * 1000}',
          '__t': '${DateTime.now().millisecondsSinceEpoch / 1000}',
        },
      ),
      headers: _headers(trimmedCookie),
      body: jsonEncode({
        'fid_list': effectiveSharedEntries.map((item) => item.fid).toList(),
        'fid_token_list':
            effectiveSharedEntries.map((item) => item.shareFidToken).toList(),
        'to_pdir_fid': resolvedTargetDirectoryId,
        'pwd_id': parsed.pwdId,
        'stoken': stoken,
        'pdir_fid': '0',
        'scene': 'link',
      }),
    );

    final payload = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw QuarkSaveException(
          _resolveErrorMessage(payload, response.statusCode));
    }
    final code = payload['code'] as int? ?? -1;
    if (code != 0) {
      throw QuarkSaveException(
          _resolveErrorMessage(payload, response.statusCode));
    }

    final data = payload['data'] as Map<String, dynamic>? ?? const {};
    final taskId = '${data['task_id'] ?? ''}'.trim();
    return QuarkSaveResult(
      taskId: taskId,
      savedCount: effectiveSharedEntries.length,
      targetFolderPath: resolvedTargetDirectoryPath,
    );
  }

  Future<QuarkConnectionStatus> testConnection({
    required String cookie,
  }) async {
    final directories = await listDirectories(
      cookie: cookie,
      parentFid: '0',
    );
    return QuarkConnectionStatus(rootDirectoryCount: directories.length);
  }

  Future<String> _ensureDirectory({
    required String cookie,
    required String parentFid,
    required String parentPath,
    required String folderName,
  }) async {
    final existingDirectories = await listDirectories(
      cookie: cookie,
      parentFid: parentFid,
    );
    for (final directory in existingDirectories) {
      if (directory.name.trim() == folderName) {
        return directory.fid;
      }
    }

    final normalizedParentPath = _normalizeDirectoryPath(parentPath);
    final targetPath = normalizedParentPath == '/'
        ? '/$folderName'
        : '$normalizedParentPath/$folderName';
    final response = await _client.post(
      Uri.parse('$_baseUrl/1/clouddrive/file').replace(
        queryParameters: const {
          'pr': 'ucpro',
          'fr': 'pc',
          'uc_param_str': '',
        },
      ),
      headers: _headers(cookie),
      body: jsonEncode({
        'pdir_fid': parentFid.trim().isEmpty ? '0' : parentFid.trim(),
        'file_name': folderName,
        'dir_path': targetPath,
        'dir_init_lock': false,
      }),
    );
    final payload = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw QuarkSaveException(
          _resolveErrorMessage(payload, response.statusCode));
    }
    final code = payload['code'] as int? ?? -1;
    if (code != 0) {
      throw QuarkSaveException(
          _resolveErrorMessage(payload, response.statusCode));
    }

    final createdFid =
        '${(payload['data'] as Map<String, dynamic>? ?? const {})['fid'] ?? ''}'
            .trim();
    if (createdFid.isNotEmpty) {
      return createdFid;
    }

    final refreshedDirectories = await listDirectories(
      cookie: cookie,
      parentFid: parentFid,
    );
    for (final directory in refreshedDirectories) {
      if (directory.name.trim() == folderName) {
        return directory.fid;
      }
    }
    throw const QuarkSaveException('夸克文件夹创建成功，但未返回目录 ID');
  }

  Future<List<QuarkDirectoryEntry>> listDirectories({
    required String cookie,
    String parentFid = '0',
  }) async {
    final trimmedCookie = cookie.trim();
    if (trimmedCookie.isEmpty) {
      throw const QuarkSaveException('请先填写夸克 Cookie');
    }

    final response = await _client.get(
      Uri.parse('$_baseUrl/1/clouddrive/file/sort').replace(
        queryParameters: {
          'pr': 'ucpro',
          'fr': 'pc',
          'uc_param_str': '',
          'pdir_fid': parentFid,
          '_page': '1',
          '_size': '200',
          '_fetch_total': '1',
          '_fetch_sub_dirs': '0',
          '_sort': 'file_type:asc,updated_at:desc',
          '_fetch_full_path': '1',
          'fetch_all_file': '1',
          'fetch_risk_file_name': '1',
        },
      ),
      headers: _headers(trimmedCookie),
    );
    final payload = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw QuarkSaveException(
          _resolveErrorMessage(payload, response.statusCode));
    }
    final code = payload['code'] as int? ?? -1;
    if (code != 0) {
      throw QuarkSaveException(
          _resolveErrorMessage(payload, response.statusCode));
    }

    final entries = (payload['data'] as Map<String, dynamic>? ??
            const {})['list'] as List<dynamic>? ??
        const [];
    return entries
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => item['dir'] == true)
        .map(QuarkDirectoryEntry.fromJson)
        .whereType<QuarkDirectoryEntry>()
        .toList(growable: false);
  }

  Future<String> _fetchShareToken({
    required String pwdId,
    required String passcode,
    required String cookie,
  }) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/1/clouddrive/share/sharepage/token').replace(
        queryParameters: const {
          'pr': 'ucpro',
          'fr': 'pc',
        },
      ),
      headers: _headers(cookie),
      body: jsonEncode({
        'pwd_id': pwdId,
        'passcode': passcode,
      }),
    );
    final payload = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw QuarkSaveException(
          _resolveErrorMessage(payload, response.statusCode));
    }
    final code = payload['code'] as int? ?? -1;
    if (code != 0) {
      throw QuarkSaveException(
          _resolveErrorMessage(payload, response.statusCode));
    }
    final data = payload['data'] as Map<String, dynamic>? ?? const {};
    final stoken = '${data['stoken'] ?? ''}'.trim();
    if (stoken.isEmpty) {
      throw const QuarkSaveException('夸克返回了空的 stoken');
    }
    return stoken;
  }

  Future<List<_QuarkShareEntry>> _fetchShareEntries({
    required String pwdId,
    required String stoken,
    required String pdirFid,
    required String cookie,
  }) async {
    final entries = <_QuarkShareEntry>[];
    var page = 1;

    while (true) {
      final response = await _client.get(
        Uri.parse('$_baseUrl/1/clouddrive/share/sharepage/detail').replace(
          queryParameters: {
            'pr': 'ucpro',
            'fr': 'pc',
            'pwd_id': pwdId,
            'stoken': stoken,
            'pdir_fid': pdirFid,
            'force': '0',
            '_page': '$page',
            '_size': '50',
            '_fetch_banner': '0',
            '_fetch_share': '0',
            '_fetch_total': '1',
            '_sort': 'file_type:asc,updated_at:desc',
            'ver': '2',
            'fetch_share_full_path': '0',
          },
        ),
        headers: _headers(cookie),
      );
      final payload = _decode(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw QuarkSaveException(
            _resolveErrorMessage(payload, response.statusCode));
      }
      final code = payload['code'] as int? ?? -1;
      if (code != 0) {
        throw QuarkSaveException(
            _resolveErrorMessage(payload, response.statusCode));
      }

      final data = payload['data'] as Map<String, dynamic>? ?? const {};
      final list = (data['list'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .map(_QuarkShareEntry.fromJson)
          .whereType<_QuarkShareEntry>()
          .toList(growable: false);
      if (list.isEmpty) {
        break;
      }
      entries.addAll(list);
      final metadata = payload['metadata'] as Map<String, dynamic>? ?? const {};
      final total = metadata['_total'] as int? ?? entries.length;
      if (entries.length >= total) {
        break;
      }
      page += 1;
    }

    return entries;
  }

  Future<List<_QuarkShareEntry>> _flattenTopDirectory({
    required String pwdId,
    required String stoken,
    required String cookie,
    required List<_QuarkShareEntry> entries,
  }) async {
    if (entries.length != 1 || !entries.single.isDirectory) {
      return entries;
    }
    final nestedEntries = await _fetchShareEntries(
      pwdId: pwdId,
      stoken: stoken,
      pdirFid: entries.single.fid,
      cookie: cookie,
    );
    if (nestedEntries.isEmpty) {
      return entries;
    }
    return nestedEntries;
  }

  Map<String, String> _headers(String cookie) {
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Cookie': cookie,
      'User-Agent': _userAgent,
    };
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.body.trim().isEmpty) {
      return const {};
    }
    final decoded =
        jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return const {};
  }

  String _resolveErrorMessage(Map<String, dynamic> payload, int statusCode) {
    final message = '${payload['message'] ?? payload['msg'] ?? ''}'.trim();
    if (message.isNotEmpty) {
      return message;
    }
    return '夸克保存失败：HTTP $statusCode';
  }

  String _normalizeDirectoryPath(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty || trimmed == '/') {
      return '/';
    }
    final normalized = trimmed.replaceAll('\\', '/');
    final withLeadingSlash =
        normalized.startsWith('/') ? normalized : '/$normalized';
    return withLeadingSlash.replaceFirst(RegExp(r'/+$'), '');
  }

  String _sanitizeDirectoryName(String rawName) {
    final sanitized = rawName
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return sanitized == '.' || sanitized == '..' ? '' : sanitized;
  }

  String _lastDirectoryName(String path) {
    final normalized = _normalizeDirectoryPath(path);
    if (normalized == '/') {
      return '';
    }
    final segments = normalized
        .split('/')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    return segments.isEmpty ? '' : segments.last;
  }

  _ParsedQuarkShare? _parseShareUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) {
      return null;
    }
    final segments = uri.pathSegments;
    final shareIndex = segments.indexOf('s');
    if (shareIndex < 0 || shareIndex + 1 >= segments.length) {
      return null;
    }
    final pwdId = segments[shareIndex + 1].trim();
    if (pwdId.isEmpty) {
      return null;
    }

    var pdirFid = '0';
    for (var index = shareIndex + 2; index < segments.length; index++) {
      final segment = Uri.decodeComponent(segments[index]).trim();
      final match = RegExp(r'^([a-zA-Z0-9]{32})').firstMatch(segment);
      if (match != null) {
        pdirFid = match.group(1)!;
      }
    }

    return _ParsedQuarkShare(
      pwdId: pwdId,
      passcode: uri.queryParameters['pwd']?.trim() ?? '',
      pdirFid: pdirFid,
    );
  }
}

class QuarkSaveResult {
  const QuarkSaveResult({
    required this.taskId,
    required this.savedCount,
    required this.targetFolderPath,
  });

  final String taskId;
  final int savedCount;
  final String targetFolderPath;
}

class QuarkConnectionStatus {
  const QuarkConnectionStatus({
    required this.rootDirectoryCount,
  });

  final int rootDirectoryCount;

  String get summary => '根目录文件夹 $rootDirectoryCount 个';
}

class QuarkSaveException implements Exception {
  const QuarkSaveException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _ParsedQuarkShare {
  const _ParsedQuarkShare({
    required this.pwdId,
    required this.passcode,
    required this.pdirFid,
  });

  final String pwdId;
  final String passcode;
  final String pdirFid;
}

class QuarkDirectoryEntry {
  const QuarkDirectoryEntry({
    required this.fid,
    required this.name,
    required this.path,
  });

  final String fid;
  final String name;
  final String path;

  static QuarkDirectoryEntry? fromJson(Map<String, dynamic> json) {
    final fid = '${json['fid'] ?? ''}'.trim();
    final name = '${json['file_name'] ?? json['name'] ?? ''}'.trim();
    final rawPath = '${json['file_path'] ?? ''}'.trim();
    final normalizedPath = rawPath.isEmpty ? '/$name' : rawPath;
    if (fid.isEmpty || name.isEmpty) {
      return null;
    }
    return QuarkDirectoryEntry(
      fid: fid,
      name: name,
      path: normalizedPath,
    );
  }
}

class _QuarkShareEntry {
  const _QuarkShareEntry({
    required this.fid,
    required this.shareFidToken,
    required this.isDirectory,
  });

  final String fid;
  final String shareFidToken;
  final bool isDirectory;

  static _QuarkShareEntry? fromJson(Map<String, dynamic> json) {
    final fid = '${json['fid'] ?? ''}'.trim();
    final shareFidToken = '${json['share_fid_token'] ?? ''}'.trim();
    if (fid.isEmpty || shareFidToken.isEmpty) {
      return null;
    }
    return _QuarkShareEntry(
      fid: fid,
      shareFidToken: shareFidToken,
      isDirectory: json['dir'] == true,
    );
  }
}
