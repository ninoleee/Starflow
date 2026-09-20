import 'dart:typed_data';

Future<String> defaultLiveBackupPath() async => '';
Future<Uint8List> readLiveBackupFile(String path) async =>
    throw UnsupportedError('Local paths unavailable');
Future<void> writeLiveBackupFile(String path, Uint8List bytes) async =>
    throw UnsupportedError('Local paths unavailable');
