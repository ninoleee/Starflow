import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_stream_relay_contract.dart';
import 'package:starflow/features/playback/application/playback_stream_relay_service.dart';
import 'package:starflow/features/playback/application/playback_target_resolver.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  test('PlaybackTargetResolver wraps Quark targets with playback relay',
      () async {
    final relayService = _FakePlaybackStreamRelayService();
    final container = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWithValue(
          SeedData.defaultSettings.copyWith(
            mediaSources: const [
              MediaSourceConfig(
                id: 'quark-main',
                name: 'Quark Drive',
                kind: MediaSourceKind.quark,
                endpoint: '0',
                libraryPath: '/',
                enabled: true,
              ),
            ],
            networkStorage: const NetworkStorageConfig(
              quarkCookie: 'kps=test; sign=test;',
            ),
          ),
        ),
        quarkSaveClientProvider.overrideWithValue(
          QuarkSaveClient(
            MockClient((request) async {
              expect(request.url.path, '/1/clouddrive/file/download');
              return http.Response(
                jsonEncode({
                  'code': 0,
                  'data': {
                    'download_list': [
                      {
                        'fid': 'quark-file-1',
                        'download_url':
                            'https://download.example.com/quark-file-1.mkv',
                        'size': 3221225472,
                      },
                    ],
                  },
                }),
                200,
                headers: const {
                  'set-cookie': '__puus=abc; Path=/',
                },
              );
            }),
          ),
        ),
        playbackStreamRelayServiceProvider.overrideWithValue(relayService),
      ],
    );
    addTearDown(container.dispose);

    final resolver = PlaybackTargetResolver(read: container.read);
    final target = const PlaybackTarget(
      title: '请求救援 S01E01',
      sourceId: 'quark-main',
      sourceName: 'Quark Drive',
      sourceKind: MediaSourceKind.quark,
      streamUrl: '',
      itemId: 'quark-file-1',
      itemType: 'episode',
      container: 'mkv',
    );

    final resolved = await resolver.resolve(target);

    expect(
      resolved.streamUrl,
      'http://127.0.0.1:8787/playback-relay/session/quark-file-1.mkv',
    );
    expect(resolved.actualAddress,
        'https://download.example.com/quark-file-1.mkv');
    expect(resolved.headers, isEmpty);
    expect(resolved.fileSizeBytes, 3221225472);
    expect(relayService.preparedTarget, isNotNull);
    expect(
      relayService.preparedTarget!.headers['Cookie'],
      contains('__puus=abc'),
    );
  });

  test('PlaybackTargetResolver resolves Quark resource ids to file ids', () async {
    final requestedFids = <String>[];
    final relayService = _FakePlaybackStreamRelayService();
    final container = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWithValue(
          SeedData.defaultSettings.copyWith(
            mediaSources: const [
              MediaSourceConfig(
                id: 'quark-main',
                name: 'Quark Drive',
                kind: MediaSourceKind.quark,
                endpoint: '0',
                libraryPath: '/',
                enabled: true,
              ),
            ],
            networkStorage: const NetworkStorageConfig(
              quarkCookie: 'kps=test; sign=test;',
            ),
          ),
        ),
        quarkSaveClientProvider.overrideWithValue(
          QuarkSaveClient(
            MockClient((request) async {
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              requestedFids.addAll(
                (body['fids'] as List<dynamic>? ?? const [])
                    .map((item) => '$item'),
              );
              return http.Response(
                jsonEncode({
                  'code': 0,
                  'data': {
                    'download_list': [
                      {
                        'fid': 'quark-file-2',
                        'download_url':
                            'https://download.example.com/quark-file-2.mkv',
                        'size': 1234,
                      },
                    ],
                  },
                }),
                200,
              );
            }),
          ),
        ),
        playbackStreamRelayServiceProvider.overrideWithValue(relayService),
      ],
    );
    addTearDown(container.dispose);

    final resolver = PlaybackTargetResolver(read: container.read);
    final target = const PlaybackTarget(
      title: 'Quark Movie',
      sourceId: 'quark-main',
      streamUrl: '',
      sourceName: 'Quark Drive',
      sourceKind: MediaSourceKind.quark,
      itemId: 'quark://entry/quark-file-2?path=%2FMovies%2FMovie.2024.mkv',
      itemType: 'movie',
    );

    final resolved = await resolver.resolve(target);

    expect(requestedFids, ['quark-file-2']);
    expect(resolved.itemId, 'quark-file-2');
    expect(
      resolved.streamUrl.startsWith('http://127.0.0.1:8787/playback-relay/'),
      isTrue,
    );
    expect(relayService.preparedTarget?.actualAddress,
        'https://download.example.com/quark-file-2.mkv');
  });
}

class _FakePlaybackStreamRelayService implements PlaybackStreamRelayService {
  PlaybackTarget? preparedTarget;

  @override
  Future<void> clear({String reason = ''}) async {}

  @override
  Future<void> close() async {}

  @override
  Future<PlaybackTarget> prepareTarget(PlaybackTarget target) async {
    preparedTarget = target;
    final fileName = Uri.tryParse(target.streamUrl)?.pathSegments.lastOrNull ??
        'stream.mkv';
    return target.copyWith(
      streamUrl:
          'http://127.0.0.1:8787/$kPlaybackRelayPathSegment/session/$fileName',
      headers: const <String, String>{},
    );
  }
}
