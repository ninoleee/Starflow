import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'live_backup.dart';

Future<String> defaultLiveBackupPath() async =>
    '${(await getApplicationDocumentsDirectory()).path}/exports/live-tv/starflow-live-tv-${DateTime.now().millisecondsSinceEpoch}.json';

Future<Uint8List> readLiveBackupFile(String path) async {
  final result = BytesBuilder(copy: false);
  await for (final chunk in File(path).openRead()) {
    if (result.length + chunk.length > liveBackupMaxBytes) {
      throw const FormatException('直播备份超过 32 MiB');
    }
    result.add(chunk);
  }
  return result.takeBytes();
}

Future<void> writeLiveBackupFile(String path, Uint8List bytes) async {
  if (bytes.length > liveBackupMaxBytes) throw const FormatException();
  final destination = File(path);
  if (await destination.exists()) throw const FileSystemException('文件已存在');
  await destination.parent.create(recursive: true);
  final temp = File('$path.${DateTime.now().microsecondsSinceEpoch}.tmp');
  try {
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(path);
  } finally {
    if (await temp.exists()) await temp.delete();
  }
}
