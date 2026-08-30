import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/playback_system_session.dart';

void main() {
  test('exposes system controls only in foreground or with background enabled',
      () {
    expect(
      shouldExposePlaybackSystemSession(
        isForeground: true,
        backgroundPlaybackEnabled: false,
      ),
      isTrue,
    );
    expect(
      shouldExposePlaybackSystemSession(
        isForeground: false,
        backgroundPlaybackEnabled: true,
      ),
      isTrue,
    );
    expect(
      shouldExposePlaybackSystemSession(
        isForeground: false,
        backgroundPlaybackEnabled: false,
      ),
      isFalse,
    );
  });

  group('playback system session update pacing', () {
    final now = DateTime.utc(2026, 8, 28, 12);

    test('publishes position changes immediately in the foreground', () {
      expect(
        shouldPublishPlaybackSystemSessionUpdate(
          force: false,
          isForeground: true,
          positionChanged: true,
          hasNonPositionChange: false,
          lastPublishedAt: now.subtract(const Duration(seconds: 1)),
          now: now,
        ),
        isTrue,
      );
    });

    test('throttles position-only changes while in the background', () {
      expect(
        shouldPublishPlaybackSystemSessionUpdate(
          force: false,
          isForeground: false,
          positionChanged: true,
          hasNonPositionChange: false,
          lastPublishedAt: now.subtract(const Duration(seconds: 9)),
          now: now,
        ),
        isFalse,
      );
      expect(
        shouldPublishPlaybackSystemSessionUpdate(
          force: false,
          isForeground: false,
          positionChanged: true,
          hasNonPositionChange: false,
          lastPublishedAt: now.subtract(const Duration(seconds: 10)),
          now: now,
        ),
        isTrue,
      );
    });

    test('never delays forced or state-changing updates', () {
      expect(
        shouldPublishPlaybackSystemSessionUpdate(
          force: true,
          isForeground: false,
          positionChanged: false,
          hasNonPositionChange: false,
          lastPublishedAt: now,
          now: now,
        ),
        isTrue,
      );
      expect(
        shouldPublishPlaybackSystemSessionUpdate(
          force: false,
          isForeground: false,
          positionChanged: false,
          hasNonPositionChange: true,
          lastPublishedAt: now,
          now: now,
        ),
        isTrue,
      );
    });
  });

  test('serializes ordered artwork fallback candidates', () {
    const state = PlaybackSystemSessionState(
      title: 'Movie',
      position: Duration(seconds: 12),
      duration: Duration(minutes: 90),
      playing: true,
      artworkCandidates: [
        PlaybackSystemSessionArtworkCandidate(
          url: 'https://images.example.com/poster.jpg',
          headers: {'Authorization': 'Bearer poster'},
        ),
        PlaybackSystemSessionArtworkCandidate(
          url: 'https://images.example.com/backdrop.jpg',
        ),
      ],
    );

    expect(state.toMap()['artworkCandidates'], [
      {
        'url': 'https://images.example.com/poster.jpg',
        'headers': {'Authorization': 'Bearer poster'},
      },
      {
        'url': 'https://images.example.com/backdrop.jpg',
        'headers': <String, String>{},
      },
    ]);
  });

  test('serializes episode navigation mode for native media controls', () {
    const state = PlaybackSystemSessionState(
      title: 'Episode',
      position: Duration(minutes: 12),
      duration: Duration(minutes: 45),
      playing: true,
      hasEpisodeQueue: true,
      hasPrevious: true,
      hasNext: false,
    );

    expect(state.toMap(), containsPair('hasEpisodeQueue', true));
    expect(state.toMap(), containsPair('hasPrevious', true));
    expect(state.toMap(), containsPair('hasNext', false));
  });
}
