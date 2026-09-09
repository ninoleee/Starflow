import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/presentation/widgets/player_controls_layout.dart';

void main() {
  test('seek bar adds spacing only below the track', () {
    expect(playbackSeekBarMargin, const EdgeInsets.only(bottom: 6));
  });
  const safeArea = EdgeInsets.fromLTRB(24, 44, 12, 21);

  test('portrait preserves only the supplied safe area', () {
    expect(
      playbackControlsPadding(viewport: const Size(390, 844), safeArea: safeArea),
      safeArea,
    );
  });

  test('landscape preserves only the supplied safe area', () {
    expect(
      playbackControlsPadding(viewport: const Size(844, 390), safeArea: safeArea),
      safeArea,
    );
  });

  test('fullscreen without system insets adds no clearance', () {
    expect(
      playbackControlsPadding(viewport: const Size(1920, 1080), safeArea: EdgeInsets.zero),
      EdgeInsets.zero,
    );
    expect(
      playbackControlsPadding(viewport: const Size(390, 844), safeArea: EdgeInsets.zero),
      EdgeInsets.zero,
    );
  });

  test('square viewport uses the landscape rule', () {
    expect(
      playbackControlsPadding(viewport: const Size(600, 600), safeArea: EdgeInsets.zero),
      EdgeInsets.zero,
    );
  });
}
