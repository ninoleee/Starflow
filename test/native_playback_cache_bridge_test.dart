import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_stream_relay_contract.dart';
import 'package:starflow/features/playback/data/native_playback_launcher.dart';
import 'package:starflow/features/playback/data/native_playback_launcher_io.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

const _resolver = MethodChannel('starflow/native_playback_resolver');
const _platform = MethodChannel('starflow/platform');
const _codec = StandardMethodCodec();
const _target = PlaybackTarget(
  title: 'Cache fixture',
  sourceId: 'fixture',
  sourceName: 'Fixture',
  sourceKind: MediaSourceKind.nas,
  streamUrl: 'https://example.test/video.mp4',
  container: 'mp4',
);

class _CacheRelay
    implements
        PlaybackStreamRelayService,
        PlaybackRelayCacheControl,
        PlaybackRelayBufferControl {
  _CacheRelay(this.url, this.bytes);
  final String url;
  final int bytes;
  final calls = <Object>[];
  @override
  Future<PlaybackTarget> prepareTarget(PlaybackTarget target) async =>
      target.copyWith(streamUrl: url);
  @override
  PlaybackRelayCacheSnapshot? cacheSnapshot({String? url}) {
    calls.add(('snapshot', url));
    return PlaybackRelayCacheSnapshot(storedBytes: bytes, forwardBytes: 512);
  }

  @override
  void setPlaybackActive(bool active, {String? url}) =>
      calls.add((active, url));
  @override
  void cancelReadAhead({String? url}) => calls.add(('cancel', url));
  @override
  void updateBufferState({required bool memoryReady, String? url}) =>
      calls.add(('memoryReady', memoryReady, url));
  @override
  Future<void> clear({String reason = ''}) async {}
  @override
  Future<void> close() async => calls.add('close');
}

Future<Map<Object?, Object?>> _call(
    String method, Map<String, Object?> args) async {
  final result = Completer<Map<Object?, Object?>>();
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    _resolver.name,
    _codec.encodeMethodCall(MethodCall(method, args)),
    (data) {
      result.complete(_codec.decodeEnvelope(data!) as Map);
    },
  );
  return result.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late ProviderContainer container;
  late PlatformNativePlaybackLauncher launcher;
  late Map<String, Object?> launch;
  late List<_CacheRelay> relays;
  Future<void> start() async {
    final result = await launcher.launch(
      _target,
      decodeMode: PlaybackDecodeMode.auto,
      audioOutputMode: NativeAudioOutputMode.auto,
      subtitleScale: 1,
      backgroundPlaybackEnabled: false,
      subtitlePreference: PlaybackSubtitlePreference.auto,
      defaultSubtitle: PlaybackDefaultSubtitle.systemLanguage,
      dualSubtitlePrimaryLanguage: PlaybackSubtitleLanguage.simplifiedChinese,
      dualSubtitleSecondaryLanguage: PlaybackSubtitleLanguage.english,
      episodeResolver: (target) async =>
          NativeResolvedPlaybackTarget(target: target),
    );
    expect(result.launched, true);
  }

  Map<String, Object?> args(int generation, {String? url}) => {
        'resolverSessionId': launch['resolverSessionId'],
        'currentURL': url ?? launch['url'],
        'generation': generation,
      };
  setUp(() async {
    relays = [];
    messenger.setMockMethodCallHandler(_platform, (call) async {
      launch = Map<String, Object?>.from(call.arguments as Map);
      return true;
    });
    container = ProviderContainer(overrides: [
      appSettingsProvider.overrideWithValue(
          AppSettings.fromJson(const {}).copyWith(playbackDiskCacheMiB: 512)),
    ]);
    launcher = container.read(Provider((ref) =>
        PlatformNativePlaybackLauncher(ref, isIOS: true, relayFactory: () {
          final relay = _CacheRelay(
              'http://127.0.0.1:49152/playback-relay/${relays.length}/video',
              (relays.length + 1) * 1024);
          relays.add(relay);
          return relay;
        })));
    await start();
  });
  tearDown(() {
    container.dispose();
    messenger.setMockMethodCallHandler(_platform, null);
    _resolver.setMethodCallHandler(null);
  });
  test(
      'local snapshot uses the requested owner and never sums prepared episodes',
      () async {
    expect(relays.single.calls, isEmpty);
    final next = await _call('resolveNativePlaybackEpisode', {
      'resolverSessionId': launch['resolverSessionId'],
      'playbackTargetJson': jsonEncode(_target.toJson()),
    });
    final first = await _call('nativePlaybackCacheSnapshot', args(1));
    expect(first['storedBytes'], 1024);
    expect(first['showDiskCache'], true);
    expect(first['forwardBytes'], 512);
    expect(first['currentURL'], launch['url']);
    expect(relays.last.calls, isEmpty);
    final second = await _call('nativePlaybackCacheSnapshot',
        args(2, url: next['transportUrl'] as String));
    expect(second['storedBytes'], 2048);
    expect(
        (await _call(
            'setNativePlaybackActive', {...args(1), 'active': false}))['ok'],
        false);
    expect((await _call('nativePlaybackCacheSnapshot', args(2)))['ok'], false);
    expect(relays.first.calls, [('snapshot', launch['url'])]);
  });
  test('snapshot follows disabled setting even with retained transport bytes',
      () async {
    container.updateOverrides([
      appSettingsProvider.overrideWithValue(AppSettings.fromJson(const {})),
    ]);
    final snapshot = await _call('nativePlaybackCacheSnapshot', args(1));
    expect(snapshot['ok'], true);
    expect(snapshot['showDiskCache'], false);
    expect(snapshot['storedBytes'], 1024);
  });

  test('pause resume and seek preserve ownership and reject stale commands',
      () async {
    await _call('setNativePlaybackActive', {...args(10), 'active': false});
    await _call('cancelNativePlaybackReadAhead', args(11));
    await _call('setNativePlaybackActive', {...args(12), 'active': true});
    final before = relays.single.calls.toList();
    expect(before, [
      (false, launch['url']),
      ('cancel', launch['url']),
      (true, launch['url'])
    ]);
    for (final invalid in [
      {...args(9), 'active': false},
      {...args(13), 'resolverSessionId': 'old', 'active': false},
      {
        ...args(13),
        'currentURL': 'https://example.test/unknown',
        'active': false
      },
      {...args(13), 'generation': null, 'active': false},
    ]) {
      expect((await _call('setNativePlaybackActive', invalid))['ok'], false);
    }
    expect(relays.single.calls, before);
    await _call('releaseNativePlaybackTransport', {
      'resolverSessionId': launch['resolverSessionId'],
      'transportUrl': launch['url'],
    });
    expect((await _call('nativePlaybackCacheSnapshot', args(14)))['ok'], false);
  });
  test('buffer permission validates payload and rejects stale owners',
      () async {
    expect(
        (await _call('setNativePlaybackBufferState',
            {...args(10), 'memoryReady': true}))['ok'],
        true);
    expect(relays.single.calls, [('memoryReady', true, launch['url'])]);
    for (final invalid in [
      {...args(9), 'memoryReady': true},
      {...args(11), 'memoryReady': 'true'},
      {...args(11), 'memoryReady': true, 'resolverSessionId': 'old'},
      {...args(11), 'memoryReady': true, 'currentURL': 'https://other.test'},
    ]) {
      expect(
          (await _call('setNativePlaybackBufferState', invalid))['ok'], false);
    }
    await _call(
        'setNativePlaybackBufferState', {...args(11), 'memoryReady': false});
    expect(relays.single.calls.last, ('memoryReady', false, launch['url']));
  });
  test('closing or replacing a session rejects old snapshot and control calls',
      () async {
    final old = args(20);
    await start();
    expect((await _call('cancelNativePlaybackReadAhead', old))['ok'], false);
    expect(relays.last.calls, isEmpty);
    await _call('closeNativePlaybackTransports',
        {'resolverSessionId': launch['resolverSessionId']});
    expect((await _call('nativePlaybackCacheSnapshot', args(21)))['ok'], false);
  });
}
