import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/search/domain/search_models.dart';

void main() {
  test('detects 115cdn share URLs without relying on provider hints', () {
    for (final url in [
      'https://115cdn.com/s/example?password=abcd',
      'http://www.115cdn.com/s/example',
      'https://115CDN.COM/s/example',
      '115cdn.com/s/example',
      'https://115.com/s/example',
      'https://anxia.com/s/example',
    ]) {
      expect(detectSearchCloudTypeFromUrl(url), SearchCloudType.cloud115,
          reason: url);
      expect(resolveSearchCloudTypeCode(rawUrl: url, hints: ['quark']), '115');
    }
    for (final url in [
      'https://115cdn.com.example.org/s/example',
      'https://example.org/115cdn.com/s/example',
      'https://example.org/?next=https://115cdn.com/s/example',
    ]) {
      expect(detectSearchCloudTypeFromUrl(url), isNull, reason: url);
    }
  });

  test('cloud type counts use URL first and provider hint as fallback', () {
    SearchResult result(String url, String type) => SearchResult(
          id: url,
          title: 'private title',
          posterUrl: '',
          providerId: 'test',
          providerName: 'test',
          quality: '',
          sizeLabel: '',
          seeders: 0,
          summary: '',
          resourceUrl: url,
          cloudType: type,
        );
    expect(countSearchResultsByCloudType([
      result('https://115cdn.com/s/example', 'quark'),
      result('https://example.org/share', '115'),
      result('https://pan.quark.cn/s/example', '115'),
      result('https://example.org/unknown', ''),
    ]), {'115': 2, 'quark': 1, 'unknown': 1});
    expect(countSearchResultsByCloudType(const []), isEmpty);
  });

  group('SearchProviderConfig', () {
    test('disables unknown provider kinds instead of routing them as panSou',
        () {
      final config = SearchProviderConfig.fromJson(const {
        'id': 'unknown-provider',
        'name': 'Unknown',
        'kind': 'unknown-kind',
        'endpoint': 'https://unknown.example.com',
        'enabled': true,
      });

      expect(config.kind, SearchProviderKind.panSou);
      expect(config.enabled, isFalse);
    });
  });
}
