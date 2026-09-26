import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/mpv_tuning_policy.dart';
import 'package:starflow/features/playback/application/playback_stream_relay_contract.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

void main() {
  group('MPV playback policy', () {
    test('detects remote and live playback urls', () {
      expect(
          isLikelyRemotePlaybackUrl('https://example.com/movie.mkv'), isTrue);
      expect(isLikelyRemotePlaybackUrl('rtsp://example.com/live'), isTrue);
      expect(isLikelyRemotePlaybackUrl(r'\\nas\movies\movie.mkv'), isFalse);
      expect(isLikelyRemotePlaybackUrl(r'D:\movies\movie.mkv'), isFalse);

      expect(
        isLikelyLiveRemotePlaybackUrl('rtsp://example.com/live'),
        isTrue,
      );
      expect(
        isLikelyLiveRemotePlaybackUrl('https://example.com/movie.mkv'),
        isFalse,
      );
    });

    test('detects heavy playback metadata', () {
      const heavyTarget = PlaybackTarget(
        title: '4K HEVC',
        sourceId: 'emby-main',
        streamUrl: 'https://example.com/movie.mkv',
        sourceName: 'Emby',
        sourceKind: MediaSourceKind.emby,
        width: 3840,
        height: 2160,
        bitrate: 18000000,
        videoCodec: 'hevc',
      );
      const lightTarget = PlaybackTarget(
        title: '1080p AVC',
        sourceId: 'emby-main',
        streamUrl: 'https://example.com/movie.mkv',
        sourceName: 'Emby',
        sourceKind: MediaSourceKind.emby,
        width: 1920,
        height: 1080,
        bitrate: 8000000,
        videoCodec: 'h264',
      );

      expect(isHeavyPlaybackTargetMetadata(heavyTarget), isTrue);
      expect(isHeavyPlaybackTargetMetadata(lightTarget), isFalse);
    });

    test('uses high-risk buffered tuning profile for heavy http playback', () {
      const target = PlaybackTarget(
        title: 'HTTP Movie',
        sourceId: 'emby-main',
        streamUrl: 'https://example.com/movie.mkv',
        sourceName: 'Emby',
        sourceKind: MediaSourceKind.emby,
      );

      final profile = resolveMpvRemotePlaybackTuningProfile(
        target: target,
        aggressiveTuning: false,
        heavyPlayback: true,
      );

      expect(profile, isNotNull);
      expect(profile!.lowLatency, isFalse);
      expect(profile.cacheOnDisk, 'no');
      expect(profile.cacheSecs, '120');
      expect(profile.demuxerReadaheadSecs, '120');
      expect(profile.demuxerHysteresisSecs, '20');
      expect(profile.cachePauseWait, '2.0');
      expect(profile.networkTimeoutSeconds, '32');
      expect(profile.cachePauseInitial, 'yes');
    });

    test('uses high-risk buffered tuning profile for quark playback', () {
      const target = PlaybackTarget(
        title: 'Quark Movie',
        sourceId: 'quark-main',
        streamUrl: 'https://download.example.com/movie.mkv',
        sourceName: 'Quark',
        sourceKind: MediaSourceKind.quark,
      );

      final profile = resolveMpvRemotePlaybackTuningProfile(
        target: target,
        aggressiveTuning: false,
        heavyPlayback: false,
      );

      expect(profile, isNotNull);
      expect(isLikelyQuarkPlaybackTarget(target), isTrue);
      expect(profile!.lowLatency, isFalse);
      expect(profile.cacheOnDisk, 'no');
      expect(profile.cacheSecs, '120');
      expect(profile.demuxerReadaheadSecs, '120');
      expect(profile.cachePauseWait, '2.0');
      expect(profile.cachePauseInitial, 'yes');
      expect(profile.networkTimeoutSeconds, '32');
    });

    test('caps quark buffers on low-memory televisions', () {
      const target = PlaybackTarget(
        title: 'Quark 4K',
        sourceId: 'quark-main',
        streamUrl: 'https://download.example.com/movie.mkv',
        sourceName: 'Quark',
        sourceKind: MediaSourceKind.quark,
        width: 3840,
        height: 2160,
      );

      final budget = resolveMpvBufferBudget(
        target: target,
        aggressiveTuning: true,
        isTelevision: true,
        memoryClassMb: 192,
      );

      expect(budget.forwardBytes, 112 * 1024 * 1024);
      expect(budget.backBytes, 16 * 1024 * 1024);
      expect(budget.memoryCapApplied, isTrue);
    });

    test('keeps full quark buffer budget on non-television devices', () {
      const target = PlaybackTarget(
        title: 'Quark 4K',
        sourceId: 'quark-main',
        streamUrl: 'https://download.example.com/movie.mkv',
        sourceName: 'Quark',
        sourceKind: MediaSourceKind.quark,
      );

      final budget = resolveMpvBufferBudget(
        target: target,
        aggressiveTuning: true,
        isTelevision: false,
        memoryClassMb: 192,
      );

      expect(budget.forwardBytes, 256 * 1024 * 1024);
      expect(budget.memoryCapApplied, isFalse);
    });

    test('classifies only transient network failures for open retry', () {
      expect(
        classifyMpvOpenFailure(
          Exception('tcp: ffurl_read returned 0xdfb9b0bb'),
        ),
        MpvOpenFailureKind.transientNetwork,
      );
      expect(
        classifyMpvOpenFailure(Exception('[Player] has been disposed')),
        MpvOpenFailureKind.unknown,
      );
      expect(
        classifyMpvOpenFailure(TimeoutException('network timeout')),
        MpvOpenFailureKind.transientNetwork,
      );
      expect(
        classifyMpvOpenFailure(Exception('HTTP error 404 file not found')),
        MpvOpenFailureKind.permanent,
      );
      expect(
        classifyMpvOpenFailure(Exception('server returned status code 503')),
        MpvOpenFailureKind.transientNetwork,
      );
      expect(
        classifyMpvOpenFailure(Exception('decoder initialization failed')),
        MpvOpenFailureKind.unknown,
      );
    });

    test('uses standard buffering without a cached bandwidth estimate', () {
      const target = PlaybackTarget(
        title: 'Cold MP4',
        sourceId: 'nas-main',
        streamUrl: 'https://media.example.com/movie.mp4',
        sourceName: 'NAS',
        sourceKind: MediaSourceKind.nas,
        container: 'mp4',
        bitrate: 10000000,
      );

      final profile = resolveMpvRemotePlaybackTuningProfile(
        target: target,
        aggressiveTuning: false,
        heavyPlayback: false,
      );

      expect(profile?.name, 'buffered-standard');
      expect(profile?.networkTimeoutSeconds, '24');
      expect(profile?.cachePauseInitial, 'yes');
      expect(profile?.cachePauseWait, '2.0');
      expect(profile?.cacheSecs, '120');
      expect(profile?.demuxerReadaheadSecs, '120');
    });

    test('uses fast-start profile when cached throughput beats bitrate', () {
      const target = PlaybackTarget(
        title: 'Fast MP4',
        sourceId: 'nas-main',
        streamUrl: 'https://media.example.com/movie.mp4',
        sourceName: 'NAS',
        sourceKind: MediaSourceKind.nas,
        container: 'mp4',
        bitrate: 10000000,
      );

      final profile = resolveMpvRemotePlaybackTuningProfile(
        target: target,
        aggressiveTuning: false,
        heavyPlayback: false,
        estimatedMegabitsPerSecond: 30,
      );

      expect(profile?.name, 'fast-start');
      expect(profile?.cachePauseInitial, 'no');
      expect(profile?.cacheSecs, '120');
      expect(profile?.demuxerReadaheadSecs, '120');
      expect(profile?.cachePauseWait, '1.2');
    });

    test('keeps unified high-risk tuning for heavy aggressive quark playback',
        () {
      const target = PlaybackTarget(
        title: 'Quark 4K',
        sourceId: 'quark-main',
        streamUrl: 'https://download.example.com/movie-4k.mkv',
        sourceName: 'Quark',
        sourceKind: MediaSourceKind.quark,
      );

      final profile = resolveMpvRemotePlaybackTuningProfile(
        target: target,
        aggressiveTuning: true,
        heavyPlayback: true,
      );

      expect(profile, isNotNull);
      expect(profile!.cacheSecs, '120');
      expect(profile.demuxerReadaheadSecs, '120');
      expect(profile.demuxerHysteresisSecs, '20');
      expect(profile.cachePauseWait, '2.0');
      expect(profile.networkTimeoutSeconds, '32');
    });

    test('keeps high-risk quark recovery when throughput is fast', () {
      const target = PlaybackTarget(
        title: 'Fast Quark',
        sourceId: 'quark-main',
        streamUrl: 'https://download.example.com/episode',
        sourceName: 'Quark',
        sourceKind: MediaSourceKind.quark,
        bitrate: 8000000,
      );

      final profile = resolveMpvRemotePlaybackTuningProfile(
        target: target,
        aggressiveTuning: false,
        heavyPlayback: false,
        estimatedMegabitsPerSecond: 40,
      );

      expect(profile?.name, 'buffered-high-risk');
      expect(profile?.cachePauseInitial, 'yes');
      expect(profile?.cachePauseWait, '2.0');
      expect(profile?.demuxerReadaheadSecs, '120');
    });

    test('keeps remote quark tuning after stream url is wrapped by relay', () {
      const target = PlaybackTarget(
        title: 'Quark Relay',
        sourceId: 'quark-main',
        streamUrl: 'http://127.0.0.1:8787/playback-relay/session/video.mkv',
        actualAddress: 'https://download.example.com/video.mkv',
        sourceName: 'Quark',
        sourceKind: MediaSourceKind.quark,
      );

      final profile = resolveMpvRemotePlaybackTuningProfile(
        target: target,
        aggressiveTuning: false,
        heavyPlayback: false,
      );

      expect(isLoopbackPlaybackRelayUrl(target.streamUrl), isTrue);
      expect(isLikelyRemotePlaybackTargetTransport(target), isTrue);
      expect(isLikelyQuarkPlaybackTarget(target), isTrue);
      expect(profile, isNotNull);
      expect(profile!.cacheSecs, '120');
      expect(profile.cachePauseInitial, 'yes');
    });

    test('uses low latency tuning profile for rtsp playback', () {
      const target = PlaybackTarget(
        title: 'RTSP Live',
        sourceId: 'cam-main',
        streamUrl: 'rtsp://example.com/live',
        sourceName: 'Camera',
        sourceKind: MediaSourceKind.nas,
      );

      final profile = resolveMpvRemotePlaybackTuningProfile(
        target: target,
        aggressiveTuning: false,
        heavyPlayback: false,
      );

      expect(profile, isNotNull);
      expect(profile!.lowLatency, isTrue);
      expect(profile.cacheOnDisk, 'no');
      expect(profile.cacheSecs, isEmpty);
      expect(profile.cachePauseInitial, 'no');
      expect(profile.cachePauseWait, '0.5');
    });

    test('recognizes local iso device sources only for local paths', () {
      expect(
        isLikelyLocalMpvIsoDeviceSource(
          r'D:\Movies\Movie.iso',
          windowsPlatform: true,
          posixPlatform: false,
        ),
        isTrue,
      );
      expect(
        isLikelyLocalMpvIsoDeviceSource(
          r'\\NAS\Movies\Movie.iso',
          windowsPlatform: true,
          posixPlatform: false,
        ),
        isTrue,
      );
      expect(
        isLikelyLocalMpvIsoDeviceSource(
          'file:///D:/Movies/Movie.iso',
          windowsPlatform: true,
          posixPlatform: false,
        ),
        isTrue,
      );
      expect(
        isLikelyLocalMpvIsoDeviceSource(
          'https://example.com/Movie.iso',
          windowsPlatform: true,
          posixPlatform: false,
        ),
        isFalse,
      );
    });
  });

  group('MPV recovery and readahead separation', () {
    const standard = PlaybackTarget(
      title: 'Movie',
      sourceId: 'nas-main',
      streamUrl: 'https://example.com/movie.mp4',
      sourceName: 'NAS',
      sourceKind: MediaSourceKind.nas,
      container: 'mp4',
      videoCodec: 'h264',
      bitrate: 10000000,
    );

    test('fast estimates never bypass source or decode risk protection', () {
      final riskyTargets = [
        standard.copyWith(container: 'mkv'),
        standard.copyWith(sourceKind: MediaSourceKind.quark),
        standard.copyWith(videoCodec: 'hevc'),
        standard.copyWith(videoCodec: 'av1'),
        standard.copyWith(width: 3840, height: 2160),
      ];
      for (final target in riskyTargets) {
        for (final aggressive in [false, true]) {
          final profile = resolveMpvRemotePlaybackTuningProfile(
            target: target,
            aggressiveTuning: aggressive,
            heavyPlayback: isHeavyPlaybackTargetMetadata(target),
            estimatedMegabitsPerSecond: 100,
          )!;
          expect(profile.name, 'buffered-high-risk');
          expect(profile.cachePauseInitial, 'yes');
          expect(profile.cachePauseWait, '2.0');
          expect(profile.cacheSecs, '120');
          expect(profile.demuxerReadaheadSecs, '120');
        }
      }
    });

    test('slow absolute throughput or limited bitrate headroom gets 3 seconds',
        () {
      for (final (bitrate, speed) in [(10000000, 5.0), (40000000, 40.0)]) {
        final profile = resolveMpvRemotePlaybackTuningProfile(
          target: standard.copyWith(bitrate: bitrate),
          aggressiveTuning: true,
          heavyPlayback: false,
          estimatedMegabitsPerSecond: speed,
        )!;
        expect(profile.cachePauseWait, '3.0');
        expect(profile.cachePauseInitial, 'yes');
        expect(profile.cacheSecs, '120');
        expect(profile.demuxerReadaheadSecs, '120');
      }
    });

    test('missing or invalid throughput cannot enable fast start', () {
      for (final speed in [null, 0.0, -1.0, double.nan, double.infinity]) {
        final profile = resolveMpvRemotePlaybackTuningProfile(
          target: standard,
          aggressiveTuning: false,
          heavyPlayback: false,
          estimatedMegabitsPerSecond: speed,
        )!;
        expect(profile.name, 'buffered-standard');
        expect(profile.cachePauseWait, '2.0');
        expect(profile.cachePauseInitial, 'yes');
      }
    });

    test('unknown bitrate cannot enable fast start', () {
      final profile = resolveMpvRemotePlaybackTuningProfile(
        target: standard.copyWith(bitrate: 0),
        aggressiveTuning: false,
        heavyPlayback: false,
        estimatedMegabitsPerSecond: 100,
      )!;
      expect(profile.name, 'buffered-standard');
      expect(profile.cachePauseWait, '2.0');
    });

    test('local targets have no remote tuning profile', () {
      expect(
        resolveMpvRemotePlaybackTuningProfile(
          target: standard.copyWith(streamUrl: '/movies/movie.mp4'),
          aggressiveTuning: true,
          heavyPlayback: false,
        ),
        isNull,
      );
    });
  });

  group('MPV TV bitrate budget', () {
    const mib = 1024 * 1024;
    const target = PlaybackTarget(
      title: 'Movie',
      sourceId: 'nas-main',
      streamUrl: 'https://example.com/movie.mp4',
      sourceName: 'NAS',
      sourceKind: MediaSourceKind.nas,
    );

    test('adds twelve seconds for known bitrate without shrinking base budget',
        () {
      final budget = resolveMpvBufferBudget(
        target: target.copyWith(bitrate: 80000000),
        aggressiveTuning: false,
        isTelevision: true,
        memoryClassMb: 1024,
      );
      expect(budget.forwardBytes, 144 * mib);
      expect(budget.backBytes, 32 * mib);
      expect(budget.memoryCapApplied, isFalse);

      for (final (source, aggressive, expected) in [
        (MediaSourceKind.nas, false, 144),
        (MediaSourceKind.nas, true, 176),
        (MediaSourceKind.quark, false, 192),
        (MediaSourceKind.quark, true, 256),
      ]) {
        final budget = resolveMpvBufferBudget(
          target: target.copyWith(sourceKind: source, bitrate: 1000000),
          aggressiveTuning: aggressive,
          isTelevision: true,
          memoryClassMb: 1024,
        );
        expect(budget.forwardBytes, expected * mib);
      }
    });

    test('keeps low and medium memory caps after bitrate sizing', () {
      for (final (memory, bitrate, expected, back) in [
        (256, 20000000, 80, 16),
        (256, 160000000, 112, 16),
        (512, 160000000, 176, 32),
      ]) {
        final budget = resolveMpvBufferBudget(
          target: target.copyWith(bitrate: bitrate),
          aggressiveTuning: false,
          isTelevision: true,
          memoryClassMb: memory,
        );
        expect(budget.forwardBytes, expected * mib);
        expect(budget.backBytes, back * mib);
        expect(budget.memoryCapApplied, isTrue);
      }
    });

    test('caps huge bitrate even with high or unknown device memory', () {
      for (final memory in [null, 0, -1, 1024]) {
        final budget = resolveMpvBufferBudget(
          target: target.copyWith(bitrate: 2000000000),
          aggressiveTuning: true,
          isTelevision: true,
          memoryClassMb: memory,
        );
        expect(budget.forwardBytes, 256 * mib);
        expect(budget.backBytes, 32 * mib);
        expect(budget.memoryCapApplied, isTrue);
      }
    });

    test('unknown bitrate leaves original TV budgets unchanged', () {
      for (final bitrate in [null, 0, -1]) {
        for (final (memory, expected, capped) in [
          (null, 144, false),
          (256, 80, true),
          (512, 144, false),
          (1024, 144, false),
        ]) {
          final budget = resolveMpvBufferBudget(
            target: target.copyWith(bitrate: bitrate),
            aggressiveTuning: false,
            isTelevision: true,
            memoryClassMb: memory,
          );
          expect(budget.forwardBytes, expected * mib);
          expect(budget.memoryCapApplied, capped);
        }
      }
    });

    test('non-TV budgets never grow with bitrate or shrink with memory class',
        () {
      for (final (source, aggressive, expected) in [
        (MediaSourceKind.nas, false, 96),
        (MediaSourceKind.nas, true, 128),
        (MediaSourceKind.quark, false, 192),
        (MediaSourceKind.quark, true, 256),
      ]) {
        final budget = resolveMpvBufferBudget(
          target: target.copyWith(sourceKind: source, bitrate: 2000000000),
          aggressiveTuning: aggressive,
          isTelevision: false,
          memoryClassMb: 128,
        );
        expect(budget.forwardBytes, expected * mib);
        expect(budget.memoryCapApplied, isFalse);
      }
    });
  });

  group('MPV static option cache', () {
    test('skips only successful identical writes on the same player', () async {
      final cache = MpvStaticOptionCache();
      final player = Object();
      final values = <String>[];
      for (final value in ['96', '96', '128', '128', '96']) {
        await cache.write(
          player: player,
          name: 'demuxer-max-bytes',
          value: value,
          writeProperty: () async => values.add(value),
        );
      }
      expect(values, ['96', '128', '96']);
    });

    test('failed property writes remain retryable', () async {
      final cache = MpvStaticOptionCache();
      final player = Object();
      var attempts = 0;
      Future<void> write() => cache.write(
            player: player,
            name: 'cache-pause-wait',
            value: '2.0',
            writeProperty: () async {
              if (++attempts == 1) throw StateError('unsupported');
            },
          );
      await expectLater(write(), throwsStateError);
      await write();
      await write();
      expect(attempts, 2);
    });

    test('failed updates invalidate an earlier successful cached value',
        () async {
      final cache = MpvStaticOptionCache();
      final player = Object();
      final values = <String>[];
      Future<void> write(String value, {bool fail = false}) => cache.write(
            player: player,
            name: 'scale',
            value: value,
            writeProperty: () async {
              values.add(value);
              if (fail) throw StateError('write failed');
            },
          );
      await write('bilinear');
      await expectLater(write('spline36', fail: true), throwsStateError);
      await write('bilinear');
      await write('bilinear');
      expect(values, ['bilinear', 'spline36', 'bilinear']);
    });

    test('a replacement player receives all static options again', () async {
      final cache = MpvStaticOptionCache();
      final first = Object();
      final second = Object();
      final writes = <Object>[];
      for (final player in [first, first, second, second, first]) {
        await cache.write(
          player: player,
          name: 'scale',
          value: 'bilinear',
          writeProperty: () async => writes.add(player),
        );
      }
      expect(writes, [first, second]);
    });

    test('transport, file-local and subtitle properties are never cached',
        () async {
      final cache = MpvStaticOptionCache();
      final player = Object();
      for (final name in [
        'http-header-fields',
        'http-proxy',
        'stream-lavf-o',
        'demuxer-lavf-o',
        'dvd-device',
        'bluray-device',
        'sub-pos',
        'secondary-sub-pos',
        'secondary-sub-visibility',
        'sub-ass-override',
      ]) {
        var writes = 0;
        for (var i = 0; i < 2; i++) {
          await cache.write(
            player: player,
            name: name,
            value: 'same-value',
            writeProperty: () async => writes++,
          );
        }
        expect(writes, 2, reason: name);
      }
    });

    test('overlapping writes wait for success before deduplication', () async {
      final cache = MpvStaticOptionCache();
      final player = Object();
      final started = Completer<void>();
      final finish = Completer<void>();
      var writes = 0;
      Future<void> write() => cache.write(
            player: player,
            name: 'cache-pause-wait',
            value: '2.0',
            writeProperty: () async {
              writes++;
              started.complete();
              await finish.future;
            },
          );
      final first = write();
      await started.future;
      var secondCompleted = false;
      final second = write().then((_) => secondCompleted = true);
      await Future<void>.delayed(Duration.zero);
      expect(secondCompleted, isFalse);
      finish.complete();
      await Future.wait([first, second]);
      expect(writes, 1);
    });
  });
}
