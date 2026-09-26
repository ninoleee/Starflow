import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:starflow/core/storage/local_storage_models.dart';

const _blockSize = 2 * 1024 * 1024;
const _minimumReserveBytes = 512 * 1024 * 1024;
const _backtrackBytes = 8 * 1024 * 1024;

typedef _RetentionCandidate = ({
  String key,
  int start,
  int length,
  int touched,
  _Block? block,
});

/// Temporary, process-owned byte ranges. URLs and credentials never enter filenames or indexes.
class PlaybackRelayDiskCache {
  PlaybackRelayDiskCache({
    required this.capacityBytes,
    Future<Directory> Function()? directoryProvider,
    Future<int?> Function()? freeBytes,
  })  : _directoryProvider = directoryProvider ?? _defaultDirectory,
        _freeBytes = freeBytes ?? _platformFreeBytes {
    _instances.add(this);
  }

  final int capacityBytes;
  final Future<Directory> Function() _directoryProvider;
  final Future<int?> Function() _freeBytes;
  final _entries = <String, List<_Block>>{};
  final _identities = <String, (int, String?)>{};
  final _readCursors = <String, int>{};
  Future<void> _tail = Future.value();
  Directory? _directory;
  int _sequence = 0;
  int _bytes = 0;
  bool _disabled = false;
  bool _closed = false;
  int _generation = 0;
  bool _clearing = false;
  int _queuedBytes = 0;
  int _pendingBytes = 0;
  int? _freeEstimate;
  DateTime? _spaceChecked;
  final _readers = <PlaybackCachedResponse, String>{};
  int _openingReads = 0;
  Completer<void>? _readOpenIdle;
  final _writers = <PlaybackCacheWriter>{};
  final invalidationListeners = <void Function()>{};
  static const maxWriteQueueBytes = 8 * 1024 * 1024;
  int hitBytes = 0;
  int writtenBytes = 0;
  int droppedBytes = 0;
  int writeMicroseconds = 0;
  String? disabledReason;
  final _revokedPrefixes = <String>{};
  static Future<Directory>? _root;
  static final _activeDirectories = <String>{};
  static Future<int?> availableBytes() => _platformFreeBytes();
  static final _instances = <PlaybackRelayDiskCache>{};

  static Future<void> clearInactiveFiles() async {
    try {
      final root = await _cacheRootDirectory();
      if (!await root.exists()) return;
      await _removeInactiveFiles(root);
    } catch (_) {/* Cache cleanup cannot interrupt playback. */}
  }

  bool get disabled => _disabled || _closed;
  int get storedBytes => _bytes;
  int get storedEntryCount =>
      _entries.values.fold<int>(0, (sum, blocks) => sum + blocks.length);

  static Future<LocalStorageCacheSummary> inspectSummary() async {
    var entryCount = 0;
    var totalBytes = 0;
    for (final cache in _instances.where((cache) => !cache._closed)) {
      entryCount += cache.storedEntryCount;
      totalBytes += cache.storedBytes;
    }
    try {
      final root = await _cacheRootDirectory();
      if (await root.exists()) {
        await for (final item in root.list(followLinks: false)) {
          if (item is! Directory || _activeDirectories.contains(item.path)) {
            continue;
          }
          await for (final file
              in item.list(recursive: true, followLinks: false)) {
            if (file is File) {
              entryCount++;
              totalBytes += await file.length();
            }
          }
        }
      }
    } catch (_) {
      // A storage summary is informational and must not block settings.
    }
    return LocalStorageCacheSummary(
      type: LocalStorageCacheType.playbackDiskCache,
      entryCount: entryCount,
      totalBytes: totalBytes,
    );
  }

  /// Committed bytes currently retained for [prefix], excluding queued writes.
  int storedBytesForPrefix(String prefix) =>
      _entries.entries.where((entry) => entry.key.startsWith(prefix)).fold<int>(
          0,
          (sum, entry) =>
              sum + entry.value.fold<int>(0, (n, b) => n + b.length));

  int get queuedBytes => _queuedBytes + _pendingBytes;
  int get generation => _generation;
  Future<void> flushWrites() => _tail;

  /// Sets the current byte position, including backward seeks. This only
  /// changes retention under capacity pressure; it does not invalidate data.
  void setReadCursor(String key, int position) {
    if (disabled || _clearing || _revokedPrefixes.any(key.startsWith)) return;
    _readCursors[key] = max(0, position);
  }

  /// Restores ordinary LRU retention for this resource.
  void clearReadCursor(String key) => _readCursors.remove(key);

  int nextCachedStart(String key, int start, int fallback) {
    if (disabled || _clearing) return fallback;
    return (_entries[key] ?? [])
        .where((b) => b.start > start)
        .fold(fallback, (next, block) => min(next, block.start));
  }

  Future<void> removePrefix(String prefix) {
    _revokedPrefixes.add(prefix);
    _readCursors.removeWhere((key, _) => key.startsWith(prefix));
    for (final writer
        in _writers.where((w) => w.key.startsWith(prefix)).toList()) {
      writer.close();
    }
    return _serial(() async {
      try {
        await _readOpenIdle?.future;
        for (final reader in _readers.entries
            .where((e) => e.value.startsWith(prefix))
            .map((e) => e.key)
            .toList()) {
          await reader.close();
        }
        for (final key
            in _entries.keys.where((key) => key.startsWith(prefix)).toList()) {
          for (final block in _entries[key]!.toList()) {
            try {
              await _remove(key, block);
            } catch (_) {
              await _disable();
              return;
            }
          }
        }
        _identities.removeWhere((key, _) => key.startsWith(prefix));
      } finally {
        // Writers are closed before this action is queued, so no future write
        // can need this tombstone once all earlier queued writes have drained.
        _revokedPrefixes.remove(prefix);
      }
    });
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<PlaybackCachedResponse?> read(String key, String? range) async {
    if (_closed ||
        _disabled ||
        _clearing ||
        _revokedPrefixes.any(key.startsWith)) {
      return null;
    }
    final generation = _generation;
    final blocks = _entries[key];
    if (blocks == null || blocks.isEmpty) return null;
    final identity = _identities[key];
    final contentType = blocks.first.contentType;
    final parsed =
        range == null ? null : RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
    if (range != null && parsed == null) return null;
    final start = parsed == null ? 0 : int.parse(parsed[1]!);
    final total = blocks.first.total;
    final end = parsed == null || parsed[2]!.isEmpty
        ? total - 1
        : min(int.parse(parsed[2]!), total - 1);
    if (start < 0 || end < start) {
      return null;
    }
    final sorted = blocks.toList()..sort((a, b) => a.start.compareTo(b.start));
    var position = start;
    final selected = <(_Block, int, int)>[];
    for (final block in sorted) {
      if (block.start > position) break;
      if (block.start + block.length <= position) continue;
      final count = min(end + 1, block.start + block.length) - position;
      selected.add((block, position - block.start, count));
      position += count;
      if (position > end || selected.length == 16) break;
    }
    if (selected.isEmpty) return null;
    if (position <= end && selected.length < 16) return null;
    // Keep the number of open files bounded. Callers can request the next
    // contiguous slice after this response is closed.
    final responseEnd = min(end, position - 1);
    // Pin before the first await, including while file handles are opening.
    for (final (block, _, _) in selected) {
      block.readers++;
    }
    var ownsPins = true;
    void releasePins() {
      for (final (block, _, _) in selected) {
        block.readers--;
      }
    }

    final handles = <(RandomAccessFile, int)>[];
    if (_openingReads++ == 0) _readOpenIdle = Completer<void>();
    try {
      for (final (block, offset, count) in selected) {
        final file = await block.file.open();
        handles.add((file, count));
        await file.setPosition(offset);
        block.touched = ++_sequence;
      }
      if (generation != _generation ||
          identity != _identities[key] ||
          disabled ||
          _clearing ||
          _revokedPrefixes.any(key.startsWith)) {
        for (final (file, _) in handles) {
          await file.close();
        }
        return null;
      }
      late PlaybackCachedResponse result;
      result = PlaybackCachedResponse(
          handles, start, responseEnd, total, contentType, range != null,
          validator: identity?.$2,
          onClose: () {
            releasePins();
            _readers.remove(result);
          },
          onBytes: (count) => hitBytes += count);
      _readers[result] = key;
      ownsPins = false;
      return result;
    } catch (_) {
      for (final (file, _) in handles) {
        try {
          await file.close();
        } catch (_) {}
      }
      if (generation == _generation &&
          !_clearing &&
          !disabled &&
          selected.every(
              (selection) => _entries[key]?.contains(selection.$1) == true)) {
        unawaited(disable('read_failure'));
      }
      return null;
    } finally {
      if (ownsPins) releasePins();
      if (--_openingReads == 0) {
        _readOpenIdle?.complete();
        _readOpenIdle = null;
      }
    }
  }

  /// Returns the first contiguous cached span intersecting [range]. This is
  /// metadata only; callers still use [read] to open protected file handles.
  PlaybackCachedRange? firstAvailableRange(String key, String? range) {
    if (disabled || _clearing || _revokedPrefixes.any(key.startsWith)) {
      return null;
    }
    final blocks = _entries[key];
    if (blocks == null || blocks.isEmpty) return null;
    final parsed =
        range == null ? null : RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
    if (range != null && parsed == null) return null;
    final requestedStart = parsed == null ? 0 : int.parse(parsed[1]!);
    final total = blocks.first.total;
    final requestedEnd = parsed == null || parsed[2]!.isEmpty
        ? total - 1
        : min(int.parse(parsed[2]!), total - 1);
    if (requestedStart < 0 || requestedEnd < requestedStart) return null;
    final sorted = blocks.toList()..sort((a, b) => a.start.compareTo(b.start));
    _Block? first;
    for (final block in sorted) {
      if (block.start + block.length > requestedStart &&
          block.start <= requestedEnd) {
        first = block;
        break;
      }
    }
    if (first == null) return null;
    var start = max(requestedStart, first.start);
    var end = min(requestedEnd, first.start + first.length - 1);
    for (final block in sorted.where((block) => block.start > first!.start)) {
      if (block.start > end + 1) break;
      if (block.start + block.length > end + 1) {
        end = min(requestedEnd, block.start + block.length - 1);
      }
      if (end >= requestedEnd) break;
    }
    return PlaybackCachedRange(
        start, end, total, first.contentType, _identities[key]?.$2);
  }

  PlaybackCacheWriter? writer(String key, int status, HttpHeaders headers,
      {bool reusable = true}) {
    if (_closed ||
        _disabled ||
        _clearing ||
        !reusable ||
        capacityBytes <= 0 ||
        _revokedPrefixes.any(key.startsWith)) {
      return null;
    }
    final length = headers.contentLength;
    if (length <= 0) return null;
    var start = 0;
    var total = length;
    if (status == 206) {
      final range = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$')
          .firstMatch(headers.value('content-range') ?? '');
      if (range == null) return null;
      start = int.parse(range[1]!);
      total = int.parse(range[3]!);
      if (int.parse(range[2]!) - start + 1 != length ||
          start + length > total) {
        return null;
      }
    } else if (status != 200) {
      return null;
    }
    final etag = headers.value('etag');
    final validator = etag != null && !etag.startsWith('W/')
        ? etag
        : headers.value('last-modified');
    final identity = (total, validator);
    final previous = _identities[key];
    if (previous != null && previous != identity) {
      final stale = _entries.remove(key) ?? [];
      _bytes -= stale.fold<int>(0, (n, block) => n + block.length);
      unawaited(_serial(() async {
        for (final block in stale) {
          try {
            await block.file.delete();
          } catch (_) {}
        }
      }));
    }
    _identities[key] = identity;
    final writer = PlaybackCacheWriter(
        this,
        key,
        start,
        total,
        length,
        headers.contentType?.toString() ?? 'application/octet-stream',
        _generation,
        validator);
    _writers.add(writer);
    return writer;
  }

  bool _enqueue(String key, int start, int total, String type, List<int> bytes,
      int generation, String? validator) {
    if (disabled ||
        _clearing ||
        generation != _generation ||
        queuedBytes + bytes.length > maxWriteQueueBytes) {
      droppedBytes += bytes.length;
      return false;
    }
    _queuedBytes += bytes.length;
    final stored = _store(key, start, total, type, bytes, generation, validator)
        .whenComplete(() => _queuedBytes -= bytes.length);
    _tail = stored.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return true;
  }

  Future<void> _store(String key, int start, int total, String type,
          List<int> bytes, int generation, String? validator) =>
      _serial(() async {
        if (_closed ||
            _disabled ||
            generation != _generation ||
            _identities[key] != (total, validator) ||
            bytes.isEmpty ||
            bytes.length > capacityBytes ||
            _revokedPrefixes.any(key.startsWith)) {
          return;
        }
        try {
          if (_spaceChecked == null ||
              DateTime.now().difference(_spaceChecked!) >=
                  const Duration(seconds: 2)) {
            _freeEstimate =
                await _freeBytes().timeout(const Duration(seconds: 2));
            _spaceChecked = DateTime.now();
          }
          final free = _freeEstimate;
          final reserveBytes = max(_minimumReserveBytes, capacityBytes ~/ 4);
          if (free == null || free < reserveBytes + _blockSize + bytes.length) {
            disabledReason = free == null ? 'space_unknown' : 'low_space';
            await _disable();
            return;
          }
          _directory ??= await _directoryProvider();
          _activeDirectories.add(_directory!.path);
          if (generation != _generation ||
              _closed ||
              _identities[key] != (total, validator) ||
              _revokedPrefixes.any(key.startsWith)) {
            return;
          }
          if ((_entries[key] ?? []).any((block) =>
              block.total == total &&
              block.start <= start &&
              block.start + block.length >= start + bytes.length)) {
            return;
          }
          // Keep an already committed block intact. A concurrent or
          // overlapping Range write can be dropped from the cache without
          // affecting the foreground response; deleting the old block would
          // also discard its non-overlapping prefix.
          if ((_entries[key] ?? []).any((block) =>
              block.start < start + bytes.length &&
              start < block.start + block.length)) {
            return;
          }
          final victims = <_RetentionCandidate>[];
          var retainedBytes = _bytes + bytes.length;
          if (retainedBytes > capacityBytes) {
            final candidates = <_RetentionCandidate>[
              for (final entry in _entries.entries)
                for (final block in entry.value)
                  if (block.readers == 0)
                    (
                      key: entry.key,
                      start: block.start,
                      length: block.length,
                      touched: block.touched,
                      block: block
                    ),
              (
                key: key,
                start: start,
                length: bytes.length,
                touched: _sequence + 1,
                block: null
              ),
            ];
            // Plan before deleting: an unhelpful incoming block must not
            // evict useful data, even when several victims would be needed.
            while (retainedBytes > capacityBytes) {
              final victim = _retentionVictim(candidates);
              if (victim.block == null) {
                droppedBytes += bytes.length;
                return;
              }
              victims.add(victim);
              candidates.remove(victim);
              retainedBytes -= victim.length;
            }
          }
          // Detach the whole plan synchronously so new readers cannot pin
          // a later victim while an earlier file deletion is awaiting I/O.
          for (final victim in victims) {
            _detach(victim.key, victim.block!);
          }
          for (final victim in victims) {
            await victim.block!.file.delete();
          }
          final file = File('${_directory!.path}/${++_sequence}.bin');
          final timer = Stopwatch()..start();
          await file.writeAsBytes(bytes, flush: false);
          writeMicroseconds += timer.elapsedMicroseconds;
          _freeEstimate = free - bytes.length;
          if (generation != _generation ||
              _closed ||
              _identities[key] != (total, validator) ||
              _revokedPrefixes.any(key.startsWith)) {
            await file.delete();
            return;
          }
          (_entries[key] ??= [])
              .add(_Block(file, start, bytes.length, total, type, _sequence));
          _bytes += bytes.length;
          writtenBytes += bytes.length;
        } catch (_) {
          disabledReason = 'write_failure';
          await _disable();
        }
      });

  int _retentionClass(_RetentionCandidate candidate) {
    final cursor = _readCursors[candidate.key];
    if (cursor == null) return 1;
    final end = candidate.start + candidate.length;
    final backtrack = min(_backtrackBytes, max(0, capacityBytes ~/ 4));
    if (end <= cursor - backtrack) return 0;
    if (end <= cursor) return 2;
    if (candidate.start <= cursor) return 3;
    return 1;
  }

  _RetentionCandidate _retentionVictim(List<_RetentionCandidate> candidates) {
    // Consumed data goes first across all keys. Otherwise LRU chooses the
    // resource, and its cursor chooses the least useful range within it.
    final consumed = candidates.where((c) => _retentionClass(c) == 0);
    final pool = consumed.isEmpty ? candidates : consumed;
    var oldest = pool.first;
    for (final candidate in pool.skip(1)) {
      if (candidate.touched < oldest.touched) oldest = candidate;
    }
    if (!_readCursors.containsKey(oldest.key)) return oldest;
    var victim = oldest;
    for (final candidate in candidates.where((c) => c.key == oldest.key)) {
      final rank = _retentionClass(candidate);
      final victimRank = _retentionClass(victim);
      if (rank < victimRank ||
          rank == victimRank &&
              (rank == 1
                  ? candidate.start > victim.start
                  : candidate.start < victim.start)) {
        victim = candidate;
      }
    }
    return victim;
  }

  void _detach(String key, _Block block) {
    final blocks = _entries[key];
    if (blocks != null && blocks.remove(block)) {
      if (blocks.isEmpty) _entries.remove(key);
      _bytes -= block.length;
    }
  }

  Future<void> _remove(String key, _Block block) async {
    _detach(key, block);
    await block.file.delete();
  }

  Future<void> _disable() async {
    if (!_disabled) {
      for (final listener in invalidationListeners.toList()) {
        listener();
      }
    }
    _disabled = true;
    for (final writer in _writers.toList()) {
      writer.close();
    }
    await _readOpenIdle?.future;
    for (final reader in _readers.keys.toList()) {
      await reader.close();
    }
    _entries.clear();
    _identities.clear();
    _readCursors.clear();
    _bytes = 0;
    final directory = _directory;
    if (directory != null) _activeDirectories.remove(directory.path);
    try {
      await _directory?.delete(recursive: true);
    } catch (_) {}
    _directory = null;
  }

  Future<void> clear() {
    _clearing = true;
    final generation = ++_generation;
    for (final listener in invalidationListeners.toList()) {
      listener();
    }
    for (final writer in _writers.toList()) {
      writer.close();
    }
    return _serial(() async {
      await _disable();
      _freeEstimate = null;
      _spaceChecked = null;
      if (generation == _generation) {
        disabledReason = null;
        _disabled = false;
        _clearing = false;
      }
    });
  }

  Future<void> disable(String reason) {
    _disabled = true;
    _clearing = false;
    disabledReason = reason;
    _generation++;
    for (final listener in invalidationListeners.toList()) {
      listener();
    }
    for (final writer in _writers.toList()) {
      writer.close();
    }
    return _serial(_disable);
  }

  Future<void> close() {
    _closed = true;
    return clear().whenComplete(() => _instances.remove(this));
  }

  static Future<Directory> _defaultDirectory() async {
    final root = await (_root ??= _prepareRoot());
    await _removeInactiveFiles(root);
    return root.createTemp('session-');
  }

  static Future<Directory> _cacheRootDirectory() async {
    final temporary = await getTemporaryDirectory();
    return Directory('${temporary.path}/starflow/playback_ranges');
  }

  static Future<Directory> _prepareRoot() async {
    final root = Directory(
        '${(await getTemporaryDirectory()).path}/starflow/playback_ranges');
    await root.create(recursive: true);
    return root;
  }

  static Future<void> _removeInactiveFiles(Directory root) async {
    await for (final item in root.list(followLinks: false)) {
      if (_activeDirectories.contains(item.path)) continue;
      await item.delete(recursive: true);
    }
  }

  static Future<int?> _platformFreeBytes() async {
    try {
      if (Platform.isMacOS || Platform.isLinux) {
        final result = await Process.run(
                'df', ['-Pk', (await getTemporaryDirectory()).path])
            .timeout(const Duration(seconds: 2));
        if (result.exitCode != 0) return null;
        final line = result.stdout
            .toString()
            .trim()
            .split('\n')
            .last
            .trim()
            .split(RegExp(r'\s+'));
        return line.length >= 4
            ? int.tryParse(line[3]) == null
                ? null
                : int.parse(line[3]) * 1024
            : null;
      }
      if (Platform.isWindows) {
        final root = (await getTemporaryDirectory()).path.substring(0, 3);
        if (!RegExp(r'^[a-zA-Z]:\\$').hasMatch(root)) return null;
        final result = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          "([System.IO.DriveInfo]::new('$root')).AvailableFreeSpace"
        ]).timeout(const Duration(seconds: 2));
        return result.exitCode == 0
            ? int.tryParse(result.stdout.toString().trim())
            : null;
      }
      return await const MethodChannel('starflow/platform')
          .invokeMethod<int>('getPlaybackCacheFreeBytes');
    } catch (_) {
      return null;
    }
  }
}

class PlaybackCacheWriter {
  PlaybackCacheWriter(this.cache, this.key, this.position, this.total,
      this.remaining, this.type, this.generation, this.validator);
  final PlaybackRelayDiskCache cache;
  final String key;
  int position;
  final int total;
  int remaining;
  final String type;
  final int generation;
  final String? validator;
  final _pending = BytesBuilder(copy: false);
  bool _closed = false;
  bool get accepting =>
      !_closed && !cache.disabled && generation == cache.generation;

  void close() {
    _closed = true;
    cache._pendingBytes -= _pending.length;
    _pending.clear();
    cache._writers.remove(this);
  }

  Future<void> add(List<int> bytes) async {
    if (_closed ||
        cache.disabled ||
        cache._clearing ||
        generation != cache._generation) {
      close();
      return;
    }
    if (bytes.length > remaining) {
      close();
      return;
    }
    remaining -= bytes.length;
    var offset = 0;
    while (offset < bytes.length) {
      final count = min(_blockSize - _pending.length, bytes.length - offset);
      if (cache.queuedBytes + count >
          PlaybackRelayDiskCache.maxWriteQueueBytes) {
        cache.droppedBytes += bytes.length - offset;
        close();
        return;
      }
      // Own exactly one copy; neither typed views nor ordinary caller lists
      // may mutate bytes while a pending or queued write is waiting.
      final owned = Uint8List(count)..setRange(0, count, bytes, offset);
      _pending.add(owned);
      cache._pendingBytes += count;
      offset += count;
      if (_pending.length == _blockSize ||
          remaining == 0 && offset == bytes.length) {
        final block = _pending.takeBytes();
        cache._pendingBytes -= block.length;
        if (!cache._enqueue(
            key, position, total, type, block, generation, validator)) {
          close();
          return;
        }
        position += block.length;
      }
    }
    if (remaining == 0) close();
  }
}

class PlaybackCachedRange {
  const PlaybackCachedRange(
      this.start, this.end, this.total, this.type, this.validator);
  final int start;
  final int end;
  final int total;
  final String type;
  final String? validator;
}

class PlaybackCachedResponse {
  PlaybackCachedResponse(
      this.handles, this.start, this.end, this.total, this.type, this.partial,
      {required this.onClose, required this.onBytes, this.validator});
  final String? validator;
  final void Function() onClose;
  final void Function(int) onBytes;
  bool _closed = false;
  Future<List<int>>? _reading;
  Future<void>? _closing;
  final List<(RandomAccessFile, int)> handles;
  final int start, end, total;
  final String type;
  final bool partial;
  int delivered = 0;
  Future<void> send(HttpResponse response,
      {bool headers = true,
      Future<void> Function()? flush,
      Duration timeout = const Duration(seconds: 15)}) async {
    if (headers) {
      response.statusCode = partial ? 206 : 200;
      response.contentLength = end - start + 1;
      response.headers.set('content-type', type);
      response.headers.set('accept-ranges', 'bytes');
      if (partial) {
        response.headers.set('content-range', 'bytes $start-$end/$total');
      }
    }
    for (final (file, count) in handles) {
      var remaining = count;
      while (remaining > 0) {
        if (_closed) throw const FileSystemException('Playback cache closed');
        final bytes = await (_reading = file.read(min(64 * 1024, remaining)))
            .timeout(timeout);
        _reading = null;
        if (_closed) throw const FileSystemException('Playback cache closed');
        if (bytes.isEmpty) {
          throw const FileSystemException('Truncated playback cache');
        }
        response.add(bytes);
        await (flush == null ? response.flush().timeout(timeout) : flush());
        delivered += bytes.length;
        onBytes(bytes.length);
        remaining -= bytes.length;
      }
    }
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    try {
      await _reading?.timeout(const Duration(seconds: 1));
    } catch (_) {}
    for (final (file, _) in handles) {
      try {
        await file.close();
      } catch (_) {}
    }
    onClose();
  }
}

class _Block {
  _Block(this.file, this.start, this.length, this.total, this.contentType,
      this.touched);
  final File file;
  final int start, length, total;
  final String contentType;
  int touched;
  int readers = 0;
}
