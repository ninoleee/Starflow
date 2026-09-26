import 'dart:convert';

import 'package:starflow/features/settings/domain/webdav_sync_config.dart';
import 'package:starflow/features/update/domain/app_update.dart';

/// A snapshot of one sync configuration; never serialize it into a manifest.
class UpdateSource {
  UpdateSource.fromSync(WebDavSyncConfig config)
      : directory = _releaseDirectory(config),
        _username = config.username,
        _password = config.password;

  final Uri directory;
  final String _username;
  final String _password;

  Uri get manifestUri => directory.resolve('latest.json');

  Map<String, String> headersFor(Uri target) {
    validate(target);
    if (_username.isEmpty && _password.isEmpty) return const {};
    return {
      'Authorization':
          'Basic ${base64Encode(utf8.encode('$_username:$_password'))}',
    };
  }

  void validate(Uri target) {
    _validateUri(target);
    final root = directory.pathSegments.where((s) => s.isNotEmpty).toList();
    final path = target.pathSegments;
    if (target.scheme != directory.scheme ||
        target.host != directory.host ||
        target.port != directory.port ||
        path.length <= root.length) {
      throw _scopeFailure;
    }
    for (var i = 0; i < root.length; i++) {
      if (path[i] != root[i]) throw _scopeFailure;
    }
  }

  static Uri _releaseDirectory(WebDavSyncConfig config) {
    try {
      if (RegExp(r'^https://[^/?#]*@', caseSensitive: false)
              .hasMatch(config.url) ||
          config.username.contains(':')) {
        throw _scopeFailure;
      }
      final directory = config.directoryUri.resolve('releases/');
      _validateUri(directory);
      return directory;
    } catch (_) {
      throw const UpdateFailure(
          'syncConfigurationInvalid', '应用更新需要有效的 HTTPS WebDAV 同步地址和目录。');
    }
  }

  static void _validateUri(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.authority.contains('@') ||
        uri.hasFragment ||
        uri.port < 1 ||
        uri.port > 65535 ||
        uri.pathSegments.any((s) =>
            s == '.' ||
            s == '..' ||
            s.contains('/') ||
            s.contains('\\') ||
            s.contains('%') ||
            RegExp(r'[\x00-\x1f\x7f]').hasMatch(s))) {
      throw _scopeFailure;
    }
  }

  static const _scopeFailure = UpdateFailure(
      'updateSourceMismatch', '更新文件必须位于当前 WebDAV 同步目录的 releases 子目录中。');
}
