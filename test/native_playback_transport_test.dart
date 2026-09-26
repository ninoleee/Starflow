import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_stream_relay_contract.dart';
import 'package:starflow/features/playback/data/native_playback_launcher.dart';
import 'package:starflow/features/playback/data/native_playback_launcher_io.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart'
    show buildPlaybackItemKey, buildSeriesKeyForTarget;
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

const _platform = MethodChannel('starflow/platform');
const _resolver = MethodChannel('starflow/native_playback_resolver');
const _codec = StandardMethodCodec();
const _target = PlaybackTarget(
  title: 'Synthetic episode',
  sourceId: 'nas-fixture',
  sourceName: 'Synthetic NAS',
  sourceKind: MediaSourceKind.nas,
  streamUrl: 'https://nas.example.test/show/episode-1.mp4',
  seriesId: 'show',
  seasonNumber: 1,
  episodeNumber: 1,
  container: 'mp4',
  headers: {'Authorization': 'Basic c3ludGhldGljOnRlc3Q='},
);

class _FakeRelay implements PlaybackStreamRelayService {
  _FakeRelay(this.url, {this.pending});

  final String url;
  final Completer<PlaybackTarget>? pending;
  final started = Completer<void>();
  final targets = <PlaybackTarget>[];
  int closeCalls = 0;

  PlaybackTarget prepared(PlaybackTarget target) =>
      target.copyWith(streamUrl: url, headers: const {});

  @override
  Future<PlaybackTarget> prepareTarget(PlaybackTarget target) {
    targets.add(target);
    started.complete();
    return pending?.future ?? Future.value(prepared(target));
  }

  @override
  Future<void> clear({String reason = ''}) async {}

  @override
  Future<void> close() async => closeCalls++;
}

Future<Map<String, dynamic>> _nativeCall(
    String method, Map<String, Object?> arguments) async {
  final reply = Completer<Map<String, dynamic>>();
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    _resolver.name,
    _codec.encodeMethodCall(MethodCall(method, arguments)),
    (data) {
      try {
        reply.complete(
            Map<String, dynamic>.from(_codec.decodeEnvelope(data!) as Map));
      } catch (error, stack) {
        reply.completeError(error, stack);
      }
    },
  );
  return reply.future;
}

Future<NativePlaybackLaunchResult> _launch(
  NativePlaybackLauncher launcher, {
  PlaybackTarget target = _target,
  NativePlaybackEpisodeResolver? episodeResolver,
}) =>
    launcher.launch(
      target,
      decodeMode: PlaybackDecodeMode.auto,
      audioOutputMode: NativeAudioOutputMode.auto,
      subtitleScale: 1,
      backgroundPlaybackEnabled: false,
      subtitlePreference: PlaybackSubtitlePreference.auto,
      defaultSubtitle: PlaybackDefaultSubtitle.systemLanguage,
      dualSubtitlePrimaryLanguage: PlaybackSubtitleLanguage.simplifiedChinese,
      dualSubtitleSecondaryLanguage: PlaybackSubtitleLanguage.english,
      episodeResolver: episodeResolver,
    );

void _expectOriginalIdentity(Map<String, dynamic> args, PlaybackTarget target) {
  expect(jsonDecode(args['playbackTargetJson'] as String), target.toJson());
  expect(args['playbackItemKey'], buildPlaybackItemKey(target));
  expect(args['seriesKey'], buildSeriesKeyForTarget(target));
  expect(args['playbackItemKey'], isNot(contains('127.0.0.1')));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late ProviderContainer container;
  late PlatformNativePlaybackLauncher launcher;
  late List<MethodCall> launches;
  late List<_FakeRelay> relays;
  late _FakeRelay Function() makeRelay;
  late bool launchAccepted;
  late bool disposed;

  setUp(() {
    launches = [];
    relays = [];
    launchAccepted = true;
    disposed = false;
    makeRelay = () => _FakeRelay(
        'http://127.0.0.1:49152/playback-relay/fixture-${relays.length}/video');
    messenger.setMockMethodCallHandler(_platform, (call) async {
      expect(call.method, 'launchNativePlaybackContainer');
      launches.add(call);
      return launchAccepted;
    });
    final provider = Provider<PlatformNativePlaybackLauncher>((ref) {
      return PlatformNativePlaybackLauncher(ref, isIOS: true, relayFactory: () {
        final relay = makeRelay();
        relays.add(relay);
        return relay;
      });
    });
    container = ProviderContainer(overrides: [
      appSettingsProvider.overrideWithValue(const AppSettings(
        mediaSources: [],
        searchProviders: [],
        doubanAccount: DoubanAccountConfig(enabled: false),
        homeModules: [],
      )),
    ]);
    launcher = container.read(provider);
  });

  tearDown(() async {
    if (!disposed) container.dispose();
    await Future<void>.delayed(Duration.zero);
    messenger.setMockMethodCallHandler(_platform, null);
    _resolver.setMethodCallHandler(null);
  });

  test('unified cache opt-in routes ordinary HTTP through the shared transport',
      () async {
    container.dispose();
    container = ProviderContainer(overrides: [
      appSettingsProvider.overrideWithValue(AppSettings.fromJson(const {})
          .copyWith(playbackDiskCacheMiB: 512, playbackMemoryCacheMiB: 128)),
    ]);
    final provider = Provider<PlatformNativePlaybackLauncher>((ref) =>
        PlatformNativePlaybackLauncher(ref, isIOS: true, relayFactory: () {
          final relay = makeRelay();
          relays.add(relay);
          return relay;
        }));
    launcher = container.read(provider);
    final ordinary = _target.copyWith(headers: const {});
    expect((await _launch(launcher, target: ordinary)).launched, true);
    expect(relays.single.targets.single, ordinary);
    final args = Map<String, dynamic>.from(launches.single.arguments as Map);
    expect(args['url'], relays.single.url);
    expect(args['memoryCacheMiB'], 128);
    _expectOriginalIdentity(args, ordinary);
  });

  test(
      'NAS launch uses loopback transport but preserves target and history key',
      () async {
    expect((await _launch(launcher)).launched, isTrue);
    final args = Map<String, dynamic>.from(launches.single.arguments as Map);
    expect(relays.single.targets.single, same(_target));
    expect(args['url'], relays.single.url);
    expect(jsonDecode(args['headersJson'] as String), isEmpty);
    expect(args['resolverSessionId'], isNotEmpty);
    _expectOriginalIdentity(args, _target);
    expect(relays.single.closeCalls, 0);
  });

  for (final method in [
    'releaseNativePlaybackTransport',
    'closeNativeFntvSession',
    'closeNativePlaybackTransports',
  ]) {
    test('$method releases only the owning relay and is repeatable', () async {
      expect((await _launch(launcher)).launched, isTrue);
      final args = Map<String, dynamic>.from(launches.single.arguments as Map);
      final relay = relays.single;
      final request = <String, Object?>{
        'resolverSessionId': args['resolverSessionId'],
        'transportUrl': relay.url,
      };
      await _nativeCall(method, {...request, 'resolverSessionId': 'stale'});
      expect(relay.closeCalls, 0);
      expect(await _nativeCall(method, request), {'ok': true});
      expect(relay.closeCalls, 1);
      expect(await _nativeCall(method, request), {'ok': true});
      expect(relay.closeCalls, 1);
    });
  }

  test('episode resolver returns separate transport and original target JSON',
      () async {
    final next = _target.copyWith(
      streamUrl: 'https://nas.example.test/show/episode-2.mp4',
      episodeNumber: 2,
    );
    PlaybackTarget? requested;
    expect(
        (await _launch(launcher, episodeResolver: (target) async {
          requested = target;
          return NativeResolvedPlaybackTarget(
              target: next, mediaMimeType: 'video/mp4');
        }))
            .launched,
        isTrue);
    final args = Map<String, dynamic>.from(launches.single.arguments as Map);
    final result = await _nativeCall('resolveNativePlaybackEpisode', {
      'resolverSessionId': args['resolverSessionId'],
      'playbackTargetJson': jsonEncode(next.toJson()),
    });
    expect(requested?.toJson(), next.toJson());
    expect(result['ok'], isTrue);
    expect(result['transportUrl'], relays[1].url);
    expect(result['transportHeaders'], isEmpty);
    expect(result['mediaMimeType'], 'video/mp4');
    _expectOriginalIdentity(result, next);
    expect(relays[1].targets.single.toJson(), next.toJson());
    expect(launches, hasLength(1));
    await _nativeCall('releaseNativePlaybackTransport', {
      'resolverSessionId': args['resolverSessionId'],
      'transportUrl': relays.first.url,
    });
    expect(relays.first.closeCalls, 1);
    expect(relays.last.closeCalls, 0);
    await _nativeCall('closeNativeFntvSession', {
      'resolverSessionId': args['resolverSessionId'],
    });
    expect(relays.first.closeCalls, 1);
    expect(relays.last.closeCalls, 1);
  });

  test(
      'provider disposal during initial prepare closes relay and never launches',
      () async {
    final pending = Completer<PlaybackTarget>();
    final relay = _FakeRelay(
        'http://127.0.0.1:49152/playback-relay/pending/video',
        pending: pending);
    makeRelay = () => relay;
    final launching = _launch(launcher);
    await relay.started.future;
    expect(launches, isEmpty);
    container.dispose();
    disposed = true;
    expect(relay.closeCalls, 1);
    pending.complete(relay.prepared(_target));
    expect((await launching).launched, isFalse);
    expect(relay.closeCalls, 1);
    expect(launches, isEmpty);
  });

  test('native close during episode prepare rejects the late transport',
      () async {
    final next = _target.copyWith(
        streamUrl: 'https://nas.example.test/show/episode-2.mp4');
    await _launch(launcher,
        episodeResolver: (_) async =>
            NativeResolvedPlaybackTarget(target: next));
    final args = Map<String, dynamic>.from(launches.single.arguments as Map);
    final pending = Completer<PlaybackTarget>();
    final relay = _FakeRelay(
        'http://127.0.0.1:49152/playback-relay/pending-episode/video',
        pending: pending);
    makeRelay = () => relay;
    final resolving = _nativeCall('resolveNativePlaybackEpisode', {
      'resolverSessionId': args['resolverSessionId'],
      'playbackTargetJson': jsonEncode(next.toJson()),
    });
    await relay.started.future;
    expect(
        await _nativeCall('closeNativeFntvSession', {
          'resolverSessionId': args['resolverSessionId'],
        }),
        {'ok': true});
    expect(relay.closeCalls, 1);
    pending.complete(relay.prepared(next));
    final result = await resolving;
    expect(result['ok'], isFalse);
    expect(result.containsKey('transportUrl'), isFalse);
    expect(relay.closeCalls, 1);
    expect(launches, hasLength(1));
  });

  test('native launch rejection closes the prepared relay', () async {
    launchAccepted = false;
    expect((await _launch(launcher)).launched, isFalse);
    expect(launches, hasLength(1));
    expect(relays.single.closeCalls, 1);
  });

  test('bypassed transport owner closes immediately instead of surviving exit',
      () async {
    makeRelay = () => _FakeRelay(_target.streamUrl);
    expect((await _launch(launcher)).launched, true);
    expect(relays.single.closeCalls, 1);
  });

  test('failed episode prepare releases relay while current playback survives',
      () async {
    await _launch(launcher,
        episodeResolver: (target) async =>
            NativeResolvedPlaybackTarget(target: target));
    final args = Map<String, dynamic>.from(launches.single.arguments as Map);
    final pending = Completer<PlaybackTarget>();
    final failing =
        _FakeRelay('http://127.0.0.1/playback-relay/failed', pending: pending);
    makeRelay = () => failing;
    final resolving = _nativeCall('resolveNativePlaybackEpisode', {
      'resolverSessionId': args['resolverSessionId'],
      'playbackTargetJson': jsonEncode(_target.toJson()),
    });
    await failing.started.future;
    pending.completeError(const PlaybackRelayException());
    expect((await resolving)['ok'], false);
    expect(failing.closeCalls, 1);
    expect(relays.first.closeCalls, 0);
  });

  test('failed launch invalidates its resolver without closing another session',
      () async {
    launchAccepted = false;
    var resolutions = 0;
    await _launch(launcher, episodeResolver: (target) async {
      resolutions++;
      return NativeResolvedPlaybackTarget(target: target);
    });
    final args = Map<String, dynamic>.from(launches.single.arguments as Map);
    final response = await _nativeCall('resolveNativePlaybackEpisode', {
      'resolverSessionId': args['resolverSessionId'],
      'playbackTargetJson': jsonEncode(_target.toJson()),
    });
    expect(response['ok'], false);
    expect(resolutions, 0);
    expect(relays.single.closeCalls, 1);
  });

  test('closing old session preserves replacement transport', () async {
    await _launch(launcher);
    final old = Map<String, dynamic>.from(launches.single.arguments as Map);
    await _launch(launcher);
    final current = relays.last;
    await _nativeCall('closeNativeFntvSession', {
      'resolverSessionId': old['resolverSessionId'],
    });
    expect(relays.first.closeCalls, 1);
    expect(current.closeCalls, 0);
  });

  test('relaunch closes the previous native session before replacing its id',
      () async {
    await _launch(launcher);
    final old = relays.first;
    await _launch(launcher);
    expect(old.closeCalls, 1);
    expect(relays.last.closeCalls, 0);
  });

  test(
      'version browsing validates session and does not allocate playback transport',
      () async {
    await _launch(launcher,
        episodeResolver: (target) async =>
            NativeResolvedPlaybackTarget(target: target));
    final args = Map<String, dynamic>.from(launches.single.arguments as Map);
    final request = <String, Object?>{
      'resolverSessionId': args['resolverSessionId'],
      'playbackTargetJson': jsonEncode(_target.toJson()),
    };
    expect(
        (await _nativeCall('browseNativePlaybackVersions',
            {...request, 'resolverSessionId': 'stale'}))['ok'],
        isFalse);
    final result = await _nativeCall('browseNativePlaybackVersions', request);
    expect(result['ok'], isTrue);
    expect(result['versions'], hasLength(1));
    expect((result['versions'] as List).single['selected'], isTrue);
    expect(relays, hasLength(1));
  });

  test('NAS without sensitive headers bypasses relay', () async {
    final target = _target.copyWith(headers: const {'User-Agent': 'Starflow'});
    expect((await _launch(launcher, target: target)).launched, isTrue);
    expect(relays, isEmpty);
    final args = Map<String, dynamic>.from(launches.single.arguments as Map);
    expect(args['url'], target.streamUrl);
    expect(jsonDecode(args['headersJson'] as String), target.headers);
    _expectOriginalIdentity(args, target);
  });
}
