import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  test('memory capacity defaults to auto and round trips independently', () {
    final initial = AppSettings.fromJson(const {});
    expect(initial.playbackMemoryCacheMiB, 0);
    for (final value in [0, 64, 128, 256, 512]) {
      final changed = initial.copyWith(
          playbackMemoryCacheMiB: value, playbackDiskCacheMiB: 1024);
      final restored = AppSettings.fromJson(changed.toJson());
      expect(restored.playbackMemoryCacheMiB, value);
      expect(restored.playbackDiskCacheMiB, 1024);
      expect(
          restored.copyWith(playbackDefaultSpeed: 1.5).playbackMemoryCacheMiB,
          value);
    }
  });

  test('invalid imported capacity falls back to auto', () {
    for (final value in [null, -1, 65, 1024, 128.5, '128', true]) {
      expect(
          AppSettings.fromJson({'playbackMemoryCacheMiB': value})
              .playbackMemoryCacheMiB,
          0);
    }
  });
}
