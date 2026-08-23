import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/data/external_playback_playlist.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

void main() {
  test('desktop playlist carries common authentication headers', () {
    const target = PlaybackTarget(
      streamUrl: 'https://example.test/video.mkv',
      title: 'Demo',
      sourceId: 'source',
      sourceName: 'NAS',
      sourceKind: MediaSourceKind.nas,
      headers: {
        'User-Agent': 'Starflow-Test',
        'Referer': 'https://example.test/',
        'Cookie': 'token=secret',
        'Authorization': 'Bearer example',
      },
    );

    final playlist = buildExternalPlaybackPlaylist(target);

    expect(playlist, contains('#EXTHTTP:'));
    expect(playlist, contains('"Authorization":"Bearer example"'));
    expect(playlist, contains('#EXTVLCOPT:http-user-agent=Starflow-Test'));
    expect(
      playlist,
      contains('#EXTVLCOPT:http-referrer=https://example.test/'),
    );
    expect(playlist, contains('#EXTVLCOPT:http-cookie=token=secret'));
    expect(playlist, endsWith('https://example.test/video.mkv\n'));
  });

  test('playlist strips line breaks from user-controlled values', () {
    const target = PlaybackTarget(
      streamUrl: 'https://example.test/video.mp4',
      title: 'Demo\n#Injected',
      sourceId: 'source',
      sourceName: 'NAS',
      sourceKind: MediaSourceKind.nas,
      headers: {'Cookie': 'a=1\r\n#Injected'},
    );

    final playlist = buildExternalPlaybackPlaylist(target);

    expect(playlist, contains('#EXTINF:-1,Demo #Injected'));
    expect(playlist, contains('#EXTVLCOPT:http-cookie=a=1 #Injected'));
    expect(playlist, isNot(contains('\n#Injected')));
  });
}
