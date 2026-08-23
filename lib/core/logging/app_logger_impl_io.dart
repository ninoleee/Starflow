import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:starflow/core/logging/app_log_api.dart';

AppLogService createAppLogService() => _IoAppLogService();

class _IoAppLogService implements AppLogService {
  static const int _minimumMaxBytes = 64 * 1024;

  bool _enabled = false;
  int _maxBytes = 20 * 1024 * 1024;
  Set<AppLogLevel> _recordedLevels = kDefaultRecordedAppLogLevels;
  Future<void> _pending = Future<void>.value();
  Future<FileAppLogStorage>? _storageFuture;

  @override
  bool get isEnabled => _enabled;

  @override
  bool get isSupported => true;

  @override
  int get maxBytes => _maxBytes;

  @override
  Set<AppLogLevel> get recordedLevels => Set<AppLogLevel>.unmodifiable(
        _recordedLevels,
      );

  @override
  Future<void> configure({
    required bool enabled,
    required int maxBytes,
    required Set<AppLogLevel> recordedLevels,
  }) {
    _enabled = enabled;
    _maxBytes = maxBytes < _minimumMaxBytes ? _minimumMaxBytes : maxBytes;
    _recordedLevels = Set<AppLogLevel>.from(recordedLevels);
    return _enqueue((storage) async {
      await storage.writeNativeConfig(
        enabled: _enabled,
        maxBytes: _maxBytes,
        recordedLevels: _recordedLevels,
      );
      await storage.enforceLimit(_maxBytes);
    });
  }

  @override
  void log(
    AppLogLevel level,
    String category,
    String message, {
    Map<String, Object?> fields = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!_enabled || !_recordedLevels.contains(level)) {
      return;
    }
    final line = AppLogFormatter.format(
      level: level,
      category: category,
      message: message,
      fields: fields,
      error: error,
      stackTrace: stackTrace,
    );
    final limit = _maxBytes;
    _enqueue(
      (storage) => storage.append(line, maxBytes: limit),
      swallowErrors: true,
    );
  }

  @override
  Future<void> logCritical(
    String category,
    String message, {
    Map<String, Object?> fields = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!_enabled || !_recordedLevels.contains(AppLogLevel.error)) {
      return Future<void>.value();
    }
    final line = AppLogFormatter.format(
      level: AppLogLevel.error,
      category: category,
      message: message,
      fields: fields,
      error: error,
      stackTrace: stackTrace,
    );
    final limit = _maxBytes;
    return _enqueue(
      (storage) => storage.append(line, maxBytes: limit, flush: true),
      swallowErrors: true,
    ).catchError((Object _) {});
  }

  @override
  Future<void> flush() => _pending;

  @override
  Future<AppLogSummary> inspect() async {
    await flush();
    return (await _storage()).inspect();
  }

  @override
  Future<List<AppLogEntry>> read({int limit = 300}) async {
    await flush();
    return (await _storage()).read(limit: limit);
  }

  @override
  Future<AppLogExportData> export() async {
    await flush();
    return (await _storage()).export();
  }

  @override
  Future<void> clear() {
    return _enqueue((storage) => storage.clear());
  }

  Future<void> _enqueue(
    Future<void> Function(FileAppLogStorage storage) operation, {
    bool swallowErrors = false,
  }) {
    final scheduled = _pending
        .catchError((Object _) {})
        .then((_) async => operation(await _storage()));
    _pending = swallowErrors ? scheduled.catchError((Object _) {}) : scheduled;
    return scheduled;
  }

  Future<FileAppLogStorage> _storage() {
    return _storageFuture ??= _createStorage();
  }

  Future<FileAppLogStorage> _createStorage() async {
    final supportDirectory = await getApplicationSupportDirectory();
    return FileAppLogStorage(Directory(p.join(supportDirectory.path, 'logs')));
  }
}

class FileAppLogStorage {
  FileAppLogStorage(this.directory);

  final Directory directory;

  File get activeFile => File(p.join(directory.path, 'starflow.log'));

  File get previousFile =>
      File(p.join(directory.path, 'starflow.previous.log'));

  File get nativeFile => File(p.join(directory.path, 'starflow-native.log'));

  File get nativeConfigFile => File(
        p.join(directory.parent.path, 'starflow-native-logging.json'),
      );

  Future<void> append(
    String line, {
    required int maxBytes,
    bool flush = false,
  }) async {
    await directory.create(recursive: true);
    final normalizedLimit = maxBytes < 2 ? 2 : maxBytes;
    final nativeReservedBytes = normalizedLimit ~/ 5;
    final activeLimit = (normalizedLimit - nativeReservedBytes) ~/ 2;
    var bytes = utf8.encode(line);
    if (bytes.length > activeLimit) {
      bytes = bytes.sublist(bytes.length - activeLimit);
    }

    final activeLength = await _length(activeFile);
    if (activeLength > 0 && activeLength + bytes.length > activeLimit) {
      await _deleteIfExists(previousFile);
      await activeFile.rename(previousFile.path);
      await _trimFileToLastBytes(previousFile, activeLimit);
    }
    await activeFile.writeAsBytes(bytes, mode: FileMode.append, flush: flush);
    await _trimFileToLastBytes(activeFile, activeLimit);
  }

  Future<void> writeNativeConfig({
    required bool enabled,
    required int maxBytes,
    required Set<AppLogLevel> recordedLevels,
  }) async {
    await nativeConfigFile.parent.create(recursive: true);
    await nativeConfigFile.writeAsString(
      jsonEncode(<String, Object?>{
        'enabled': enabled,
        'maxBytes': maxBytes,
        'recordedLevels': AppLogLevel.values
            .where(recordedLevels.contains)
            .map((level) => level.name)
            .toList(growable: false),
      }),
      flush: true,
    );
  }

  Future<void> enforceLimit(int maxBytes) async {
    if (!await directory.exists()) {
      return;
    }
    final normalizedLimit = maxBytes < 2 ? 2 : maxBytes;
    final nativeLimit = normalizedLimit ~/ 5;
    final perFileLimit = (normalizedLimit - nativeLimit) ~/ 2;
    await _trimFileToLastBytes(nativeFile, nativeLimit);
    await _trimFileToLastBytes(previousFile, perFileLimit);
    await _trimFileToLastBytes(activeFile, perFileLimit);
  }

  Future<AppLogSummary> inspect() async {
    if (!await directory.exists()) {
      return AppLogSummary(
        supported: true,
        fileCount: 0,
        totalBytes: 0,
        directoryPath: directory.path,
      );
    }
    var fileCount = 0;
    var totalBytes = 0;
    for (final file in <File>[nativeFile, previousFile, activeFile]) {
      if (await file.exists()) {
        fileCount += 1;
        totalBytes += await file.length();
      }
    }
    return AppLogSummary(
      supported: true,
      fileCount: fileCount,
      totalBytes: totalBytes,
      directoryPath: directory.path,
    );
  }

  Future<List<AppLogEntry>> read({int limit = 300}) async {
    if (!await directory.exists() || limit <= 0) {
      return const <AppLogEntry>[];
    }
    final entries = <AppLogEntry>[];
    for (final file in <File>[nativeFile, previousFile, activeFile]) {
      if (!await file.exists()) {
        continue;
      }
      final content = utf8.decode(
        await file.readAsBytes(),
        allowMalformed: true,
      );
      for (final line in const LineSplitter().convert(content)) {
        final entry = AppLogEntry.tryParse(line);
        if (entry != null) {
          entries.add(entry);
        }
      }
    }
    entries.sort((left, right) => left.timestamp.compareTo(right.timestamp));
    if (entries.length <= limit) {
      return entries;
    }
    return entries.sublist(entries.length - limit);
  }

  Future<AppLogExportData> export() async {
    if (!await directory.exists()) {
      return const AppLogExportData(bytes: <int>[], fileCount: 0);
    }
    final bytes = <int>[];
    var fileCount = 0;
    for (final file in <File>[nativeFile, previousFile, activeFile]) {
      if (!await file.exists()) {
        continue;
      }
      final fileBytes = await file.readAsBytes();
      if (fileBytes.isEmpty) {
        continue;
      }
      if (bytes.isNotEmpty && bytes.last != 0x0A) {
        bytes.add(0x0A);
      }
      bytes.addAll(fileBytes);
      fileCount += 1;
    }
    return AppLogExportData(bytes: bytes, fileCount: fileCount);
  }

  Future<void> clear() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<int> _length(File file) async {
    return await file.exists() ? file.length() : 0;
  }

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> _trimFileToLastBytes(File file, int maxBytes) async {
    if (!await file.exists()) {
      return;
    }
    final length = await file.length();
    if (length <= maxBytes) {
      return;
    }
    final handle = await file.open();
    late final List<int> tail;
    try {
      await handle.setPosition(length - maxBytes);
      tail = await handle.read(maxBytes);
    } finally {
      await handle.close();
    }
    await file.writeAsBytes(tail, mode: FileMode.write, flush: false);
  }
}
