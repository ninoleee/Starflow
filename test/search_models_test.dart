import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/search/domain/search_models.dart';

void main() {
  group('SearchProviderConfig', () {
    test('disables unknown provider kinds instead of routing them as panSou',
        () {
      final config = SearchProviderConfig.fromJson(const {
        'id': 'legacy-provider',
        'name': 'Legacy',
        'kind': 'legacy-kind',
        'endpoint': 'https://legacy.example.com',
        'enabled': true,
      });

      expect(config.kind, SearchProviderKind.panSou);
      expect(config.enabled, isFalse);
    });
  });
}
