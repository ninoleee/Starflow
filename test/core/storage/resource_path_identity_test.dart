import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/storage/resource_path_identity.dart';

void main() {
  test('URL and decoded filesystem paths share identity', () {
    for (final name in ['Show Name', '\u7535\u5f71', '100%', 'A#B', 'A?B']) {
      final url =
          Uri(scheme: 'https', host: 'nas.test', path: '/dav/$name/a.mkv');
      expect(resourcePathsEqual(url.toString(), '/dav/$name/a.mkv'), isTrue);
      expect(
          resourcePathIsWithinScope(
              '/dav/$name/a.mkv',
              Uri(scheme: 'https', host: 'nas.test', path: '/dav/$name/')
                  .toString()),
          isTrue);
    }
  });

  test('directory boundaries, case and literal percent escapes are retained',
      () {
    expect(
        resourcePathIsWithinScope('/shows/One More/a', '/shows/One'), isFalse);
    expect(resourcePathIsWithinScope('/shows/one/a', '/shows/One'), isFalse);
    expect(resourcePathsEqual('https://nas.test/a%2520b', '/a%20b'), isTrue);
    expect(resourcePathsEqual('https://nas.test/a%2520b', '/a b'), isFalse);
    expect(resourcePathsEqual('https://nas.test/a%2Fb', '/a/b'), isFalse);
    expect(
        resourcePathIsWithinScope('https://nas.test/a%2Fb/c', '/a'), isFalse);
    expect(resourcePathIsWithinScope('/a/b', ''), isFalse);
    expect(resourcePathsEqual('', ''), isFalse);
    expect(resourcePathsEqual(r'C:\Movies\a.mkv', 'C:/Movies/a.mkv'), isTrue);
    expect(resourcePathsEqual('/a//b/', '/a/b'), isTrue);
  });
}
