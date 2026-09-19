import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/library/data/fntv_api_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/fntv_session_owner.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/domain/playback_memory_models.dart';
import 'package:starflow/features/playback/domain/playback_episode_queue.dart';

const source = MediaSourceConfig(
    id: 'nas',
    name: 'NAS',
    kind: MediaSourceKind.fntv,
    endpoint: 'https://nas.example',
    enabled: true,
    accessToken: 'secret',
    userId: 'user');
const target = PlaybackTarget(
    title: 'Film',
    sourceId: 'nas',
    sourceName: 'NAS',
    sourceKind: MediaSourceKind.fntv,
    streamUrl: '',
    itemId: 'item');

http.Response ok(Object data) =>
    http.Response(jsonEncode({'code': 0, 'data': data}), 200);

void main() {
  test('history and episode queue never retain active transcode selections',
      () {
    final playing = target.copyWith(
        fntvSessionLink: 'private',
        fntvStartPositionMs: 42000,
        preferredPlaybackQualityIndex: -1);
    final history = PlaybackProgressEntry(
        key: 'item',
        target: playing,
        updatedAt: DateTime(2026),
        position: const Duration(seconds: 42));
    final saved = PlaybackProgressEntry.fromJson(history.toJson());
    expect(saved.target.fntvSessionLink, '');
    expect(saved.target.fntvStartPositionMs, 0);
    expect(saved.target.preferredPlaybackQualityIndex, 0);
    expect(saved.position.inSeconds, 42);
    final queue = PlaybackEpisodeQueue(entries: [
      PlaybackEpisodeQueueEntry(
          target: target, playbackItemKey: 'item', seriesKey: ''),
    ]).replaceCurrentTarget(playing);
    expect(queue.currentEntry!.target.fntvSessionLink, '');
    expect(queue.currentEntry!.target.preferredPlaybackQualityIndex, 0);
  });
  late FntvApiClient client;
  late List<http.Request> requests;
  late Map<String, Object?> stream;
  late String link;
  var failPlay = false;
  setUp(() {
    requests = [];
    link = '/v/api/v1/media/hls/session/index.m3u8';
    failPlay = false;
    stream = {
      'file_stream': {'guid': 'file', 'can_play': 1},
      'video_stream': {
        'guid': 'video',
        'codec_name': 'hevc',
        'bps': 40000000,
        'wrapper': 'mkv'
      },
      'audio_streams': [
        {'guid': 'zh', 'codec_name': 'ac3'},
        {'guid': 'en', 'codec_name': 'aac'},
      ],
      'subtitle_streams': [
        {'guid': 'sub', 'codec_name': 'srt'},
      ],
      'qualities': [
        {'resolution': '2160', 'bitrate': 40000000},
        {'resolution': '1080', 'bitrate': 8000000},
        {'resolution': '720', 'bitrate': 4000000},
      ],
    };
    client = FntvApiClient(MockClient((request) async {
      requests.add(request);
      return switch (request.url.path) {
        '/v/api/v1/play/info' => ok(
            {'media_guid': 'file', 'audio_guid': 'zh', 'subtitle_guid': 'sub'}),
        '/v/api/v1/stream' => ok(stream),
        '/v/api/v1/play/play' => failPlay
            ? http.Response('{"code":8192}', 200)
            : ok({'play_link': link}),
        '/v/api/v1/media/p' => ok({'result': 'succ'}),
        '/v/api/v1/play/record' => ok(true),
        _ => throw StateError('Unexpected endpoint'),
      };
    }));
  });

  test('server qualities are selectable without starting transcode by default',
      () async {
    final resolved =
        await client.resolvePlaybackTarget(source: source, target: target);
    expect(resolved.streamUrl, 'https://nas.example/v/api/v1/media/range/file');
    expect(resolved.playbackQualities.map((q) => q.index), [0, -1, -2]);
    expect(resolved.playbackQualities.last.serverTranscode, true);
    expect(resolved.isFntvTranscoding, false);
    expect(requests.length, 2);
  });

  test(
      'selected quality starts signed H264/AAC session with position and tracks',
      () async {
    final resolved = await client.resolvePlaybackTarget(
        source: source,
        target: target.copyWith(
            preferredPlaybackQualityIndex: -2,
            fntvStartPositionMs: 42345,
            fntvTrackSelectionExplicit: true,
            preferredAudioStreamId: 'en',
            preferredSubtitleStreamId: ''));
    final request = requests.last;
    final body = jsonDecode(request.body);
    expect(body, {
      'media_guid': 'file',
      'video_guid': 'video',
      'video_encoder': 'h264',
      'resolution': '720',
      'bitrate': 4000000,
      'startTimestamp': 42,
      'audio_encoder': 'aac',
      'audio_guid': 'en',
      'subtitle_guid': '',
      'channels': 2,
      'forced_sdr': 0,
    });
    final auth = Uri.splitQueryString(request.headers['Authx']!);
    expect(
        request.headers['Authx'],
        FntvApiClient.buildAuthx(
            path: '/v/api/v1/play/play',
            body: request.body,
            nonce: auth['nonce']!,
            timestamp: int.parse(auth['timestamp']!)));
    expect(resolved.streamUrl, 'https://nas.example$link');
    expect(resolved.headers['Authorization'], 'secret');
    expect(resolved.container, 'm3u8');
    expect(resolved.videoCodec, 'h264');
    expect(resolved.bitrate, 4000000);
    expect(resolved.audioStreams.length, 2);
    expect(resolved.preferredAudioStreamId, 'en');
    final restored = PlaybackTarget.fromJson(resolved.toJson());
    expect(restored.fntvSessionLink, link);
    expect(restored.playbackQualities.last.serverTranscode, true);
    expect(restored.fntvTrackSelectionExplicit, true);
    expect(restored.fntvStartPositionMs, 42345);
    await client.reportPlaybackProgress(
        source: source,
        target: restored,
        position: const Duration(seconds: 43),
        duration: const Duration(minutes: 90));
    expect(jsonDecode(requests.last.body)['play_link'], link);
    await client.releasePlaybackSession(source: source, target: restored);
    expect(jsonDecode(requests.last.body)['req'], 'media.quit');
    expect(jsonDecode(requests.last.body)['playLink'], link);
  });

  test(
      'direct indices coexist with server indices and retain third-party headers',
      () async {
    stream.addAll({
      'cloud_storage_info': {'cloud_storage_type': 9001},
      'header': {
        'User-Agent': ['Provider']
      },
      'direct_link_qualities': [
        {'resolution': 'Original', 'url': 'https://cdn.example/original'},
        {'resolution': 'Fast', 'url': 'https://cdn.example/fast'},
      ],
    });
    final resolved = await client.resolvePlaybackTarget(
        source: source,
        target: target.copyWith(preferredPlaybackQualityIndex: 1));
    expect(resolved.playbackQualities.map((q) => q.index), [0, 1, -1, -2]);
    expect(resolved.streamUrl, 'https://cdn.example/fast');
    expect(resolved.headers, {'User-Agent': 'Provider'});
    final transcode = await client.resolvePlaybackTarget(
        source: source,
        target: resolved.copyWith(preferredPlaybackQualityIndex: -1));
    expect(transcode.headers.containsKey('X-Wp-Header'), false);
    final original = await client.resolvePlaybackTarget(
        source: source,
        target: transcode.copyWith(preferredPlaybackQualityIndex: 0));
    expect(original.isFntvTranscoding, false);
    expect(original.streamUrl, 'https://cdn.example/original');
  });

  test(
      'missing requested profile and rejected transcode do not silently fall back',
      () async {
    await expectLater(
        client.resolvePlaybackTarget(
            source: source,
            target: target.copyWith(preferredPlaybackQualityIndex: -8)),
        throwsA(isA<FntvApiException>()));
    expect(requests.length, 2);
    failPlay = true;
    await expectLater(
        client.resolvePlaybackTarget(
            source: source,
            target: target.copyWith(preferredPlaybackQualityIndex: -1)),
        throwsA(isA<FntvApiException>()));
    expect(requests.where((r) => r.url.path.endsWith('/play/play')).length, 1);
  });

  test('cross-origin session URLs are rejected and allocation is released',
      () async {
    link = 'https://untrusted.example/hls.m3u8';
    await expectLater(
        client.resolvePlaybackTarget(
            source: source,
            target: target.copyWith(preferredPlaybackQualityIndex: -1)),
        throwsA(isA<FntvApiException>()));
    expect(requests.every((r) => r.url.host == 'nas.example'), true);
    expect(jsonDecode(requests.last.body)['req'], 'media.quit');
  });

  test('session owner retains rollback until success and cleans late results',
      () async {
    final released = <String>[];
    final owner = FntvSessionOwner((t) async {
      released.add(t.fntvSessionLink);
    });
    final old = target.copyWith(fntvSessionLink: 'old');
    final next = target.copyWith(fntvSessionLink: 'next');
    await owner.retain(old);
    await owner.retain(next);
    expect(released, isEmpty);
    await owner.release(next);
    expect(released, ['next']);
    await owner.close();
    await owner.close();
    await owner.retain(target.copyWith(fntvSessionLink: 'late'));
    await owner.retain(target);
    expect(released, ['next', 'old', 'late']);
  });
}
