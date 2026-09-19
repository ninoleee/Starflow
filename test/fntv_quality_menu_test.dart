import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/application/fntv_quality_menu.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

void main() {
  const qualities = [
    FntvPlaybackQuality(index: 0, resolution: '原画'),
    FntvPlaybackQuality(
        index: -1,
        resolution: '2160',
        bitrate: 20000000,
        serverTranscode: true),
    FntvPlaybackQuality(
        index: -2, resolution: '1080', bitrate: 8000000, serverTranscode: true),
    FntvPlaybackQuality(
        index: -3,
        resolution: '1080P',
        bitrate: 4000000,
        serverTranscode: true),
    FntvPlaybackQuality(
        index: -4, resolution: '720', bitrate: 2000000, serverTranscode: true),
  ];
  test('presets group aliases without changing protocol indices', () {
    final presets = fntvQualityPresets(qualities, 0);
    expect(presets.map(fntvQualityTitle), ['原画', '4K', '1080P', '720P']);
    expect(presets.map((q) => q.index), [0, -1, -2, -4]);
    expect(qualities.length, 5);
  });
  test('current custom bitrate remains selected in its resolution group', () {
    expect(
        fntvQualityPresets(qualities, -3).map((q) => q.index), [0, -1, -3, -4]);
    expect(fntvQualityDetail(qualities[3]), '1080P · 4.0 Mbps');
    expect(fntvQualityPresets([], null), isEmpty);
  });
  test('provider names and original aliases stay usable', () {
    expect(
        fntvQualityTitle(
            const FntvPlaybackQuality(index: 0, resolution: 'Original')),
        '原画');
    expect(
        fntvQualityTitle(const FntvPlaybackQuality(index: 1, resolution: '流畅')),
        '流畅');
    expect(fntvQualityTitle(const FntvPlaybackQuality(index: -2)), '画质 3');
  });
}
