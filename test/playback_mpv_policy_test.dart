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
      expect(profile.cacheSecs, '150');
      expect(profile.demuxerReadaheadSecs, '42');
      expect(profile.demuxerHysteresisSecs, '20');
      expect(profile.cachePauseWait, '5.2');
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
      expect(profile.cacheSecs, '150');
      expect(profile.demuxerReadaheadSecs, '42');
      expect(profile.cachePauseWait, '5.2');
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

      expect(budget.forwardBytes, 96 * 1024 * 1024);
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

    test('uses fast-start profile when throughput comfortably beats bitrate',
        () {
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
        preflightEstimatedMegabitsPerSecond: 30,
      );

      expect(profile?.name, 'fast-start');
      expect(profile?.cachePauseInitial, 'no');
      expect(profile?.demuxerReadaheadSecs, '12');
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
      expect(profile!.cacheSecs, '150');
      expect(profile.demuxerReadaheadSecs, '42');
      expect(profile.demuxerHysteresisSecs, '20');
      expect(profile.cachePauseWait, '5.2');
      expect(profile.networkTimeoutSeconds, '32');
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
      expect(profile!.cacheSecs, '150');
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
}
