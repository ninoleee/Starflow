import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/live_tv/application/live_playback_error.dart';

void main() {
  test('native summaries retain only allowlisted categories and numeric codes',
      () {
    final details = LivePlaybackErrorDetails.fromNative({
      'errorCategory': 'http',
      'nativeErrorCode': 2000,
      'httpStatus': 403,
      'message': 'https://private.test/account/password?token=secret',
      'headers': {'Cookie': 'secret'},
    });
    expect(details.fields, {
      'errorCategory': 'http',
      'nativeErrorCode': 2000,
      'httpStatus': 403,
    });
    expect(details.label, contains('403'));
    expect(details.label, contains('拒绝访问'));
  });

  test('malformed or older native events cannot inject diagnostic text', () {
    for (final value in [
      null,
      'https://private.test/password',
      {'errorCategory': 'private', 'httpStatus': '403', 'nativeErrorCode': -1},
      {'httpStatus': 999, 'nativeErrorCode': 1000001},
      {'httpStatus': double.nan, 'nativeErrorCode': double.infinity},
    ]) {
      final details = LivePlaybackErrorDetails.fromNative(value);
      expect(details.fields, {'errorCategory': 'unknown'});
      expect(details.label, isNull);
    }
  });

  test('network, format and decoder summaries have distinct presentation', () {
    for (final category in LivePlaybackErrorCategory.values) {
      if (category == LivePlaybackErrorCategory.unknown ||
          category == LivePlaybackErrorCategory.http) {
        continue;
      }
      final details =
          LivePlaybackErrorDetails.fromNative({'errorCategory': category.name});
      expect(details.category, category);
      expect(details.label, isNotEmpty);
    }
    for (final status in [401, 403, 404, 410, 429, 503]) {
      expect(LivePlaybackErrorDetails.fromNative({'httpStatus': status}).label,
          contains('HTTP $status'));
    }
  });
}
