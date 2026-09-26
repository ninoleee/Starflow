import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:starflow/core/network/starflow_http_transport.dart';

import '../domain/app_update.dart';
import '../domain/update_source.dart';
import 'update_manifest_parser.dart';

class UpdateManifestClient {
  UpdateManifestClient({http.Client? client}) : _client = client;

  static const _maxBytes = 256 * 1024;
  static const _timeout = Duration(seconds: 20);
  final http.Client? _client;
  final _privateClients = <http.Client>{};
  final _active = <Completer<void>>{};
  bool _closed = false;

  Future<AppUpdate> fetch(Uri uri, {UpdateSource? source}) async {
    if (_closed) {
      throw const UpdateFailure('closed', 'The update client is closed.');
    }
    final abort = Completer<void>();
    _active.add(abort);
    http.Client? transport;
    try {
      _checkUri(uri);
      transport = _client ?? createStarflowTransportClient();
      if (_client == null) _privateClients.add(transport);
      final body =
          await _download(transport, uri, abort, source).timeout(_timeout);
      final json = jsonDecode(utf8.decode(body));
      if (json is! Map<String, dynamic>) {
        throw const UpdateFailure(
            'invalid_manifest', 'The update manifest is invalid.');
      }
      return parseUpdateManifest(json);
    } on UpdateFailure {
      rethrow;
    } on TimeoutException {
      throw const UpdateFailure(
          'update_timeout', 'The update request timed out.');
    } on FormatException {
      throw const UpdateFailure(
          'invalid_manifest', 'The update manifest is invalid.');
    } catch (_) {
      // Transport and decoder exceptions can contain URLs, tokens or payloads.
      throw const UpdateFailure('update_failed', 'The update request failed.');
    } finally {
      if (!abort.isCompleted) abort.complete();
      _active.remove(abort);
      // Closing private transports also terminates connection setup, which
      // can precede the transport's registration of the request abort signal.
      if (transport != null && _privateClients.remove(transport)) {
        transport.close();
      }
    }
  }

  Future<Uint8List> _download(http.Client transport, Uri uri,
      Completer<void> abort, UpdateSource? source) async {
    var current = uri;
    final cancelled = abort.future.then<Never>((_) => throw const UpdateFailure(
        'cancelled', 'The update request was cancelled.'));
    // send() may throw synchronously before the first cancellation race exists.
    unawaited(
        cancelled.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
    for (var redirects = 0;; redirects++) {
      _checkUri(current);
      if (abort.isCompleted) {
        throw const UpdateFailure(
            'cancelled', 'The update request was cancelled.');
      }
      final request =
          http.AbortableRequest('GET', current, abortTrigger: abort.future)
            ..followRedirects = false
            ..maxRedirects = 0;
      if (source != null) request.headers.addAll(source.headersFor(current));
      final pending = transport.send(request);
      // Also discard late responses from transports that do not support abort.
      unawaited(pending.then<void>((response) {
        if (abort.isCompleted) _discard(response.stream);
      }, onError: (Object _, StackTrace __) {}));
      final response = await Future.any([pending, cancelled]);
      if (const [301, 302, 303, 307, 308].contains(response.statusCode)) {
        _discard(response.stream);
        final location = response.headers['location'];
        if (redirects >= 3 ||
            location == null ||
            location.isEmpty ||
            location.length > 8192 ||
            RegExp(r'^(?:https:)?//[^/?#]*@', caseSensitive: false)
                .hasMatch(location) ||
            RegExp(r'[\x00-\x20\x7f\\]').hasMatch(location)) {
          throw const UpdateFailure(
              'invalid_redirect', 'The update redirect was rejected.');
        }
        current = current.resolve(location);
        continue;
      }
      if (response.statusCode != 200) {
        _discard(response.stream);
        if (source != null &&
            (response.statusCode == 401 || response.statusCode == 403)) {
          throw const UpdateFailure(
              'updateUnauthorized', '无法访问更新目录，请检查网络同步账号及读取权限。');
        }
        if (source != null && response.statusCode == 404) {
          throw const UpdateFailure('updateNotPublished', '同步目录中尚未发布更新清单。');
        }
        throw const UpdateFailure(
            'http_error', 'The update server returned an error.');
      }
      if ((response.contentLength ?? 0) > _maxBytes) {
        _discard(response.stream);
        throw const UpdateFailure(
            'manifest_too_large', 'The update manifest is too large.');
      }
      final bytes = BytesBuilder(copy: false);
      final completed = Completer<Uint8List>();
      final subscription = response.stream.listen((chunk) {
        if (completed.isCompleted) return;
        if (bytes.length + chunk.length > _maxBytes) {
          completed.completeError(const UpdateFailure(
              'manifest_too_large', 'The update manifest is too large.'));
        } else {
          bytes.add(chunk);
        }
      }, onError: (Object error, StackTrace stack) {
        if (!completed.isCompleted) completed.completeError(error, stack);
      }, onDone: () {
        if (!completed.isCompleted) completed.complete(bytes.takeBytes());
      });
      try {
        return await Future.any([completed.future, cancelled]);
      } finally {
        // A misbehaving transport's cancellation must not extend the deadline.
        unawaited(subscription.cancel().catchError((Object _) {}));
      }
    }
  }

  /// Cancels this wrapper's requests without closing a caller-owned transport.
  void close() {
    if (_closed) return;
    _closed = true;
    for (final abort in _active) {
      if (!abort.isCompleted) abort.complete();
    }
    for (final client in _privateClients) {
      client.close();
    }
    _privateClients.clear();
  }
}

void _discard(Stream<List<int>> stream) {
  unawaited(stream
      .listen(null, onError: (Object _) {})
      .cancel()
      .catchError((Object _) {}));
}

void _checkUri(Uri uri) {
  if (uri.scheme != 'https' ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.authority.contains('@') ||
      uri.hasFragment ||
      uri.port < 1 ||
      uri.port > 65535 ||
      uri.toString().length > 8192 ||
      RegExp(r'[\x00-\x20\x7f\\]').hasMatch(uri.toString())) {
    throw const UpdateFailure('invalid_url',
        'The update URL must use HTTPS without credentials or fragments.');
  }
}
