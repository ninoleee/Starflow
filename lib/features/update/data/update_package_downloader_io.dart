import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:starflow/core/network/starflow_http_transport.dart';
import 'package:starflow/features/update/domain/app_update.dart';
import 'package:starflow/features/update/domain/update_source.dart';

/// Foreground-only APK transfers. Injected clients are owned and closed by this
/// downloader; use [clientFactory] to supply a fresh client for every retry.
/// [directory] replaces the private application-support root, not the updates
/// subdirectory. Progress reports cumulative bytes, not percentages.
class UpdatePackageDownloader with WidgetsBindingObserver {
  UpdatePackageDownloader({
    http.Client? client,
    http.Client Function()? clientFactory,
    Directory? directory,
  })  : assert(client == null || clientFactory == null),
        _clientFactory =
            clientFactory ?? (() => client ?? createStarflowTransportClient()),
        _directory = directory,
        _binding = WidgetsBinding.instance {
    _binding.addObserver(this);
    final state = _binding.lifecycleState;
    _background = state != null && state != AppLifecycleState.resumed;
  }

  static const int maxPackageBytes = 512 * 1024 * 1024;
  static const _networkTimeout = Duration(seconds: 30);
  static final _fileName = RegExp(r'^starflow-tv-\d+\.\d+\.\d+\.apk$');
  static final _hash = RegExp(r'^[a-fA-F0-9]{64}$');
  static final _unsafeUrl = RegExp(
      r'[\x00-\x20\x7f\\]|%(?:0[0-9a-f]|1[0-9a-f]|7f)',
      caseSensitive: false);
  final http.Client Function() _clientFactory;
  final Directory? _directory;
  final WidgetsBinding _binding;
  _Transfer? _active;
  bool _disposed = false;
  bool _background = false;
  Future<void>? _disposal;

  Future<String> download(
    UpdateArtifact artifact, {
    required void Function(int) onProgress,
    required void Function() onVerifying,
    UpdateSource? source,
  }) {
    if (_disposed) {
      return Future.error(
          const UpdateFailure('disposed', 'Downloader disposed.'));
    }
    if (_active != null) {
      return Future.error(
          const UpdateFailure('busy', 'Download already active.'));
    }
    if (_background) {
      return Future.error(const UpdateFailure(
        'background',
        'Updates can only be downloaded in the foreground.',
      ));
    }
    final transfer = _Transfer();
    _active = transfer;
    return _download(artifact, transfer, onProgress, onVerifying, source);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _background = state != AppLifecycleState.resumed;
    if (_background) cancel();
  }

  void cancel() {
    final transfer = _active;
    if (transfer == null || transfer.cancelled.isCompleted) return;
    transfer.cancelled.complete();
    transfer.cancellation.add(null);
    transfer.closeClient();
  }

  Future<void> dispose() {
    if (_disposal != null) return _disposal!;
    _disposed = true;
    _binding.removeObserver(this);
    cancel();
    return _disposal = _active?.done.future ?? Future<void>.value();
  }

  Future<String> _download(
    UpdateArtifact artifact,
    _Transfer transfer,
    void Function(int) onProgress,
    void Function() onVerifying,
    UpdateSource? source,
  ) async {
    Directory? staging;
    RandomAccessFile? output;
    try {
      _validateArtifact(artifact);
      source?.validate(artifact.url);
      final root = _directory ?? await getApplicationSupportDirectory();
      _checkCancelled(transfer);
      final updates = Directory(p.join(root.path, 'updates'));
      final type =
          await FileSystemEntity.type(updates.path, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.directory) {
        throw const UpdateFailure(
            'storage', 'Invalid private updates directory.');
      }
      await updates.create(recursive: true);
      await _cleanStale(updates, transfer);
      _checkCancelled(transfer);
      staging = await updates.createTemp('download-');
      final partial = File(p.join(staging.path, 'package.part'));
      output = await partial.open(mode: FileMode.write);
      _checkCancelled(transfer);
      transfer.client = _clientFactory();
      final response = await _response(artifact.url, transfer, source);
      final encoding = response.headers['content-encoding'];
      if (encoding != null && encoding.toLowerCase() != 'identity') {
        await _discard(response.stream);
        throw const UpdateFailure(
            'encoding', 'Encoded APK responses are refused.');
      }
      final length = response.contentLength;
      if (length != null && length != artifact.size) {
        await _discard(response.stream);
        throw const UpdateFailure(
            'length', 'APK length does not match manifest.');
      }
      var received = 0;
      var reported = 0;
      final progressClock = Stopwatch()..start();
      onProgress(0);
      final chunks = StreamIterator(response.stream);
      try {
        while (await _network(chunks.moveNext(), transfer)) {
          _checkCancelled(transfer);
          final chunk = chunks.current;
          if (chunk.length > artifact.size - received ||
              chunk.length > maxPackageBytes - received) {
            throw const UpdateFailure(
                'overflow', 'APK exceeds its size limit.');
          }
          await output.writeFrom(chunk);
          _checkCancelled(transfer);
          received += chunk.length;
          if (progressClock.elapsedMilliseconds >= 100) {
            onProgress(received);
            reported = received;
            progressClock.reset();
          }
        }
      } finally {
        await chunks.cancel();
      }
      if (received != artifact.size) {
        throw const UpdateFailure('length', 'APK download is incomplete.');
      }
      if (reported != received) onProgress(received);
      await output.flush();
      await output.close();
      output = null;
      transfer.closeClient();
      _checkCancelled(transfer);
      onVerifying();
      _checkCancelled(transfer);
      await _verify(partial, artifact, transfer);
      _checkCancelled(transfer);
      // Same-filesystem synchronous rename is the commit point: cancellation
      // cannot interleave after verification and before publication.
      return partial.renameSync(p.join(updates.path, artifact.fileName)).path;
    } catch (error) {
      if (transfer.cancelled.isCompleted) {
        throw const UpdateFailure('cancelled', 'APK download cancelled.');
      }
      if (error is UpdateFailure) rethrow;
      if (error is TimeoutException) {
        throw const UpdateFailure('timeout', 'APK download timed out.');
      }
      if (error is FileSystemException) {
        throw const UpdateFailure('storage', 'Unable to store the APK.');
      }
      // Do not expose signed URLs, response bodies, or transport credentials.
      throw const UpdateFailure('download', 'Unable to download the APK.');
    } finally {
      try {
        transfer.closeClient();
        try {
          await output?.close();
        } finally {
          if (staging != null) await staging.delete(recursive: true);
        }
      } on FileSystemException {
        throw const UpdateFailure(
            'storage', 'Unable to clean up the APK download.');
      } finally {
        await transfer.cancellation.close();
        _active = null;
        transfer.done.complete();
      }
    }
  }

  static void _validateArtifact(UpdateArtifact artifact) {
    if (artifact.fileName.length > 128 ||
        !_fileName.hasMatch(artifact.fileName) ||
        !_hash.hasMatch(artifact.sha256) ||
        artifact.size <= 0 ||
        artifact.size > maxPackageBytes) {
      throw const UpdateFailure('artifact', 'Invalid APK manifest metadata.');
    }
    _validateUrl(artifact.url);
  }

  static void _validateUrl(Uri url) {
    if (url.scheme != 'https' ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.authority.contains('@') ||
        url.hasFragment ||
        url.port < 1 ||
        url.port > 65535 ||
        url.toString().length > 8192 ||
        _unsafeUrl.hasMatch(url.toString())) {
      throw const UpdateFailure(
          'url', 'APK URL is not a safe credential-free HTTPS URL.');
    }
  }

  Future<http.StreamedResponse> _response(
      Uri url, _Transfer transfer, UpdateSource? source) async {
    for (var redirects = 0;; redirects++) {
      _checkCancelled(transfer);
      _validateUrl(url);
      final request = http.AbortableRequest(
        'GET',
        url,
        abortTrigger: transfer.cancelled.future,
      )
        ..followRedirects = false
        ..maxRedirects = 0
        ..headers['Accept-Encoding'] = 'identity';
      if (source != null) request.headers.addAll(source.headersFor(url));
      final pending = transfer.client!.send(request);
      var abandoned = false;
      unawaited(pending.then<void>((response) async {
        if (abandoned) await _discard(response.stream);
      }, onError: (Object _, StackTrace __) {}).catchError((Object _) {}));
      late http.StreamedResponse response;
      try {
        response = await _network(pending, transfer);
      } finally {
        abandoned = true;
      }
      if (const [301, 302, 303, 307, 308].contains(response.statusCode)) {
        // Cancel rather than drain an untrusted, potentially unbounded body.
        await _discard(response.stream);
        final location = response.headers['location'];
        if (redirects >= 3 ||
            location == null ||
            location.isEmpty ||
            location.length > 8192 ||
            _unsafeUrl.hasMatch(location) ||
            RegExp(r'^(?:[a-z][a-z0-9+.-]*:)?//[^/?#]*@', caseSensitive: false)
                .hasMatch(location)) {
          throw const UpdateFailure(
              'redirect', 'Invalid or excessive APK redirects.');
        }
        try {
          url = url.resolve(location);
        } on FormatException {
          throw const UpdateFailure('redirect', 'Invalid APK redirect URL.');
        }
        _validateUrl(url);
        continue;
      }
      if (response.statusCode != HttpStatus.ok) {
        await _discard(response.stream);
        throw const UpdateFailure(
            'http', 'APK server returned an unexpected status.');
      }
      return response;
    }
  }

  static Future<void> _discard(Stream<List<int>> stream) =>
      stream.listen(null, onError: (Object _) {}).cancel();

  Future<void> _cleanStale(Directory updates, _Transfer transfer) async {
    final cutoff = DateTime.now().subtract(const Duration(days: 1));
    var inspected = 0;
    var removed = 0;
    // Bound work and never descend into native installer snapshots or unrelated
    // directories. Only our old APKs and single-file staging directories qualify.
    await for (final entity in updates.list(followLinks: false)) {
      _checkCancelled(transfer);
      if (++inspected > 256 || removed >= 32) break;
      final name = p.basename(entity.path);
      if (entity is File && _fileName.hasMatch(name)) {
        if ((await entity.stat()).modified.isBefore(cutoff)) {
          await entity.delete();
          removed++;
        }
      } else if (entity is Directory &&
          RegExp(r'^download-[a-zA-Z0-9]+$').hasMatch(name)) {
        final children = await entity.list(followLinks: false).take(2).toList();
        if (children.isEmpty &&
            (await entity.stat()).modified.isBefore(cutoff)) {
          await entity.delete();
          removed++;
        } else if (children.length == 1 &&
            children.single is File &&
            p.basename(children.single.path) == 'package.part' &&
            (await children.single.stat()).modified.isBefore(cutoff)) {
          await children.single.delete();
          await entity.delete();
          removed++;
        }
      }
    }
  }

  Future<T> _network<T>(Future<T> work, _Transfer transfer) async {
    final stopped = Completer<T>();
    final subscription = transfer.cancellation.stream.listen((_) {
      stopped.completeError(
        const UpdateFailure('cancelled', 'APK download cancelled.'),
      );
    });
    if (transfer.cancelled.isCompleted) {
      stopped.completeError(
        const UpdateFailure('cancelled', 'APK download cancelled.'),
      );
    }
    try {
      return await Future.any([work, stopped.future]).timeout(_networkTimeout);
    } finally {
      await subscription.cancel();
    }
  }

  static void _checkCancelled(_Transfer transfer) {
    if (transfer.cancelled.isCompleted) {
      throw const UpdateFailure('cancelled', 'APK download cancelled.');
    }
  }

  Future<void> _verify(
    File file,
    UpdateArtifact artifact,
    _Transfer transfer,
  ) async {
    final digest = _DigestSink();
    final hasher = sha256.startChunkedConversion(digest);
    var length = 0;
    try {
      await for (final chunk in file.openRead()) {
        _checkCancelled(transfer);
        length += chunk.length;
        if (length > artifact.size || length > maxPackageBytes) {
          throw const UpdateFailure('length', 'Stored APK length changed.');
        }
        hasher.add(chunk);
      }
    } finally {
      hasher.close();
    }
    if (length != artifact.size) {
      throw const UpdateFailure('length', 'Stored APK length changed.');
    }
    if (digest.value.toString() != artifact.sha256.toLowerCase()) {
      throw const UpdateFailure('checksum', 'APK SHA-256 verification failed.');
    }
  }
}

class _Transfer {
  final cancelled = Completer<void>();
  final cancellation = StreamController<void>.broadcast(sync: true);
  final done = Completer<void>();
  http.Client? client;

  void closeClient() {
    final owned = client;
    client = null;
    owned?.close();
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
