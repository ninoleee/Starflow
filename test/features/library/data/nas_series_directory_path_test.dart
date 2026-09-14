import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/data/nas_media_path_policy.dart';

void main() {
  for (final directory in [
    '/dav/strm/115/Example Show (2026)',
    '/dav/strm/115/Example Show (2026)(1)',
    'Example Show (2026)',
    'https://nas.test/dav/strm/115/Example%20Show%20%232026%25',
    '/dav/strm/115/Parent/Parent',
  ]) {
    test('series root preserves the exact directory: $directory', () {
      final nestedParent = directory.endsWith('/Parent/Parent');
      final section = nestedParent
          ? '/dav/strm/115/Parent'
          : 'https://nas.test/dav/strm/115/';
      for (final child in [
        'Season 1/E01.strm',
        '2025/Season 1/E01.strm',
        '4K 12集/E01.strm',
        '%23004%20long%20title/E01.strm',
        'E01.strm',
      ]) {
        final resource = '$directory/$child';
        final resolution = NasMediaPathPolicy.resolveSeriesRoot(
          resourcePath: resource,
          sectionId: section,
          fileFallbackTitle: 'Different Metadata Title',
          seriesLike: true,
        );
        expect(resolution.directoryPathForResource(resource), directory);
      }
    });
  }

  test('a section that is itself a series keeps its full directory', () {
    const directory = '/dav/strm/115/Example Show';
    for (final child in ['E01.strm', 'Season 1/E01.strm']) {
      final resource = '$directory/$child';
      final resolution = NasMediaPathPolicy.resolveSeriesRoot(
        resourcePath: resource,
        sectionId: 'https://nas.test$directory/',
        fileFallbackTitle: 'Show',
        seriesLike: true,
      );
      expect(resolution.directoryPathForResource(resource), directory);
    }
  });

  test('public-root files never resolve to the whole media source', () {
    for (final resource in ['/dav/strm/E01.strm', 'E01.strm']) {
      final resolution = NasMediaPathPolicy.resolveSeriesRoot(
        resourcePath: resource,
        sectionId: 'https://nas.test/dav/strm/',
        fileFallbackTitle: 'Show',
        seriesLike: true,
      );
      expect(resolution.directoryPathForResource(resource), isEmpty);
    }
  });

  test('incomplete URI parsing never produces an ancestor delete path', () {
    const resource = '/dav/strm/115/Example Show/#004 Long Title/E01.strm';
    final resolution = NasMediaPathPolicy.resolveSeriesRoot(
      resourcePath: resource,
      sectionId: 'https://nas.test/dav/strm/115/',
      fileFallbackTitle: 'Example Show',
      seriesLike: true,
    );
    expect(resolution.directoryPathForResource(resource), isEmpty);
  });
}
