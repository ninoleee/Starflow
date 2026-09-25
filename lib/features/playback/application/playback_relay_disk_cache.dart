import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const _blockSize = 2 * 1024 * 1024;
const _reserveBytes = 512 * 1024 * 1024;

/// Temporary, process-owned byte ranges. URLs and credentials never enter filenames or indexes.
class PlaybackRelayDiskCache {
  PlaybackRelayDiskCache({
    required this.capacityBytes,
    Future<Directory> Function()? directoryProvider,
    Future<int?> Function()? freeBytes,
  })  : _directoryProvider = directoryProvider ?? _defaultDirectory,
        _freeBytes = freeBytes ?? _platformFreeBytes;

  final int capacityBytes;
  final Future<Directory> Function() _directoryProvider;
  final Future<int?> Function() _freeBytes;
  final _entries = <String, List<_Block>>{};
  Future<void> _tail = Future.value();
  Directory? _directory;
  int _sequence = 0;
  int _bytes = 0;
  bool _disabled = false;
  bool _closed = false;
  int _generation = 0;
  final _revokedPrefixes = <String>{};
  static Future<Directory>? _root;
  static Future<int?> availableBytes() => _platformFreeBytes();

  static Future<void> clearInactiveFiles() async {
    try {
      final root = await (_root ??= _prepareRoot());
      await for (final item in root.list(followLinks: false)) {
        await item.delete(recursive: true);
      }
    } catch (_) {/* Cache cleanup cannot interrupt playback. */}
  }

  bool get disabled => _disabled || _closed;

  Future<void> removePrefix(String prefix) {
    _revokedPrefixes.add(prefix);
    return _serial(() async {
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
    });
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<PlaybackCachedResponse?> read(String key, String? range) =>
      _serial(() async {
        if (_closed || _disabled) return null;
        final blocks = _entries[key];
        if (blocks == null || blocks.isEmpty) return null;
        final parsed = range == null
            ? null
            : RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
        if (range != null && parsed == null) return null;
        final start = parsed == null ? 0 : int.parse(parsed[1]!);
        final total = blocks.first.total;
        final end = parsed == null || parsed[2]!.isEmpty
            ? total - 1
            : min(int.parse(parsed[2]!), total - 1);
        if (start < 0 || end < start || end - start + 1 > capacityBytes) {
          return null;
        }
        final sorted = blocks.toList()
          ..sort((a, b) => a.start.compareTo(b.start));
        var position = start;
        final selected = <(_Block, int, int)>[];
        for (final block in sorted) {
          if (block.start > position) break;
          if (block.start + block.length <= position) continue;
          final count = min(end + 1, block.start + block.length) - position;
          selected.add((block, position - block.start, count));
          position += count;
          if (position > end) break;
        }
        if (position <= end) return null;
        // Open handles before exposing headers; eviction may unlink paths but cannot corrupt this read.
        final handles = <(RandomAccessFile, int)>[];
        try {
          for (final (block, offset, count) in selected) {
            final file = await block.file.open();
            handles.add((file, count));
            await file.setPosition(offset);
            block.touched = ++_sequence;
          }
          return PlaybackCachedResponse(handles, start, end, total,
              blocks.first.contentType, range != null);
        } catch (_) {
          for (final (file, _) in handles) {
            try {
              await file.close();
            } catch (_) {}
          }
          await _disable();
          return null;
        }
      });

  PlaybackCacheWriter? writer(String key, int status, HttpHeaders headers,
      {bool reusable = true}) {
    if (_closed || _disabled || !reusable || capacityBytes <= 0) return null;
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
    return PlaybackCacheWriter(
        this,
        key,
        start,
        total,
        length,
        headers.contentType?.toString() ?? 'application/octet-stream',
        _generation);
  }

  Future<void> _store(String key, int start, int total, String type,
          List<int> bytes, int generation) =>
      _serial(() async {
        if (_closed ||
            _disabled ||
            generation != _generation ||
            bytes.isEmpty ||
            bytes.length > capacityBytes ||
            _revokedPrefixes.any(key.startsWith)) {
          return;
        }
        try {
          final free = await _freeBytes();
          if (free == null ||
              free < _reserveBytes + _blockSize + bytes.length) {
            await _disable();
            return;
          }
          _directory ??= await _directoryProvider();
          final overlaps = (_entries[key] ?? [])
              .where((block) =>
                  block.start < start + bytes.length &&
                  start < block.start + block.length)
              .toList();
          for (final block in overlaps) {
            await _remove(key, block);
          }
          while (_bytes + bytes.length > capacityBytes) {
            final all = _entries.entries
                .expand(
                    (entry) => entry.value.map((block) => (entry.key, block)))
                .toList()
              ..sort((a, b) => a.$2.touched.compareTo(b.$2.touched));
            if (all.isEmpty) break;
            await _remove(all.first.$1, all.first.$2);
          }
          final file = File('${_directory!.path}/${++_sequence}.bin');
          await file.writeAsBytes(bytes, flush: false);
          (_entries[key] ??= [])
              .add(_Block(file, start, bytes.length, total, type, _sequence));
          _bytes += bytes.length;
        } catch (_) {
          await _disable();
        }
      });

  Future<void> _remove(String key, _Block block) async {
    await block.file.delete();
    _entries[key]!.remove(block);
    if (_entries[key]!.isEmpty) _entries.remove(key);
    _bytes -= block.length;
  }

  Future<void> _disable() async {
    _disabled = true;
    _entries.clear();
    _bytes = 0;
    try {
      await _directory?.delete(recursive: true);
    } catch (_) {}
    _directory = null;
  }

  Future<void> clear() {
    _disabled = true;
    _generation++;
    return _serial(() async {
      await _disable();
    });
  }

  Future<void> close() {
    _closed = true;
    return clear();
  }

  static Future<Directory> _defaultDirectory() async {
    final root = await (_root ??= _prepareRoot());
    return root.createTemp('session-');
  }

  static Future<Directory> _prepareRoot() async {
    final root = Directory(
        '${(await getTemporaryDirectory()).path}/starflow/playback_ranges');
    if (await root.exists()) await root.delete(recursive: true);
    await root.create(recursive: true);
    return root;
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
      this.remaining, this.type, this.generation);
  final PlaybackRelayDiskCache cache;
  final String key;
  int position;
  final int total;
  int remaining;
  final String type;
  final int generation;
  final _pending = BytesBuilder(copy: false);

  Future<void> add(List<int> bytes) async {
    if (cache._disabled || cache._closed || generation != cache._generation) {
      _pending.clear();
      return;
    }
    if (bytes.length > remaining) {
      await cache.clear();
      return;
    }
    remaining -= bytes.length;
    var offset = 0;
    while (offset < bytes.length) {
      final count = min(_blockSize - _pending.length, bytes.length - offset);
      _pending.add(Uint8List.fromList(bytes.sublist(offset, offset + count)));
      offset += count;
      if (_pending.length == _blockSize ||
          remaining == 0 && offset == bytes.length) {
        final block = _pending.takeBytes();
        await cache._store(key, position, total, type, block, generation);
        position += block.length;
      }
    }
  }
}

class PlaybackCachedResponse {
  PlaybackCachedResponse(
      this.handles, this.start, this.end, this.total, this.type, this.partial);
  final List<(RandomAccessFile, int)> handles;
  final int start, end, total;
  final String type;
  final bool partial;
  int delivered = 0;
  Future<void> send(HttpResponse response) async {
    response.statusCode = partial ? 206 : 200;
    response.contentLength = end - start + 1;
    response.headers.set('content-type', type);
    response.headers.set('accept-ranges', 'bytes');
    if (partial) {
      response.headers.set('content-range', 'bytes $start-$end/$total');
    }
    for (final (file, count) in handles) {
      var remaining = count;
      while (remaining > 0) {
        final bytes = await file.read(min(64 * 1024, remaining));
        if (bytes.isEmpty) {
          throw const FileSystemException('Truncated playback cache');
        }
        response.add(bytes);
        await response.flush();
        delivered += bytes.length;
        remaining -= bytes.length;
      }
    }
  }

  Future<void> close() async {
    for (final (file, _) in handles) {
      try {
        await file.close();
      } catch (_) {}
    }
  }
}

class _Block {
  _Block(this.file, this.start, this.length, this.total, this.contentType,
      this.touched);
  final File file;
  final int start, length, total;
  final String contentType;
  int touched;
}
