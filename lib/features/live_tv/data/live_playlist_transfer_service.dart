import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'live_playlist_transfer_service_stub.dart'
    if (dart.library.io) 'live_playlist_transfer_service_io.dart' as impl;

final livePlaylistTransferServiceProvider =
    Provider<LivePlaylistTransferService>(
        (ref) => impl.createLivePlaylistTransferService());

enum LivePlaylistTransferMode { file, backupImport, backupExport }

sealed class LivePlaylistTransferResult {
  const LivePlaylistTransferResult();
}

class LivePlaylistUpload extends LivePlaylistTransferResult {
  const LivePlaylistUpload({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

abstract class LivePlaylistTransferSession {
  List<String> get urls;
  Stream<String> get errors;
  Future<LivePlaylistTransferResult?> get received;
  Future<void> close();
}

class LiveBackupDownloaded extends LivePlaylistTransferResult {
  const LiveBackupDownloaded();
}

abstract class LivePlaylistTransferService {
  Future<LivePlaylistTransferSession> start({
    LivePlaylistTransferMode mode = LivePlaylistTransferMode.file,
    Uint8List? backupBytes,
  });
}
