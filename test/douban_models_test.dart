import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';

void main() {
  group('resolveDoubanItemType', () {
    test('maps movie-like types to movie', () {
      expect(resolveDoubanItemType('movie'), 'movie');
      expect(resolveDoubanItemType('film'), 'movie');
    });

    test('maps tv-like types to series', () {
      expect(resolveDoubanItemType('tv'), 'series');
      expect(resolveDoubanItemType('tvshow'), 'series');
      expect(resolveDoubanItemType('show'), 'series');
    });
  });
}
