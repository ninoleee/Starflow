import 'dart:typed_data';
import 'live_playlist_transfer_service.dart';

LivePlaylistTransferService createLivePlaylistTransferService() =>
    const UnsupportedLivePlaylistTransferService();

class UnsupportedLivePlaylistTransferService
    implements LivePlaylistTransferService {
  const UnsupportedLivePlaylistTransferService();

  @override
  Future<LivePlaylistTransferSession> start({
    LivePlaylistTransferMode mode = LivePlaylistTransferMode.file,
    Uint8List? backupBytes,
  }) =>
      Future.error(UnsupportedError('当前平台不支持手机传输'));
}
