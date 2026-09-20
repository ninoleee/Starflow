import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/live_tv/application/live_mpv_options.dart';

void main() {
  test('live defaults match Exo without changing provider headers', () {
    final input = {
      'Referer': 'https://example.test/',
      'Authorization': 'secret'
    };
    expect(liveMediaHeaders(input), {'User-Agent': 'Starflow', ...input});
    expect(input.containsKey('User-Agent'), isFalse);
  });

  test('provider user agent is preserved case insensitively including empty',
      () {
    for (final key in ['User-Agent', 'user-agent', 'USER-AGENT']) {
      for (final value in ['Provider/1.0', '']) {
        expect(liveMediaHeaders({key: value}), {key: value});
      }
    }
  });

  test('HLS options use FFmpeg 6 options and deny local protocols', () {
    expect(liveMpvProtocols, ['http', 'https', 'tcp', 'tls', 'crypto']);
    expect(
        liveMpvDemuxerOptions,
        'seg_max_retry=1,strict=experimental,http_persistent=0,'
        'protocol_whitelist=[http,https,tcp,tls,crypto]');
    expect(liveMpvDemuxerOptions, isNot(contains('allowed_extensions=ALL')));
    expect(liveMpvDemuxerOptions, isNot(contains('extension_picky')));
  });
}
