import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/data/external_playback_file_store.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

void main() {
  late Directory root;
  late Directory directory;
  late DateTime now;
  late ExternalPlaybackFileStore store;
  const target = PlaybackTarget(
    streamUrl: 'https://example.test/video.mp4',
    title: 'Demo / movie',
    sourceId: 'source',
    sourceName: 'NAS',
    sourceKind: MediaSourceKind.nas,
    headers: {'Authorization': 'Bearer example'},
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('starflow-file-store-test-');
    directory = Directory(p.join(root.path, 'playlists'));
    now = DateTime.now();
    store = ExternalPlaybackFileStore(directory: directory, now: () => now);
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('concurrent launches allocate separate authenticated playlists',
      () async {
    final files =
        await Future.wait([store.create(target), store.create(target)]);
    expect(files[0].path, isNot(files[1].path));
    for (final file in files) {
      expect(p.dirname(file.parent.path), directory.path);
      expect(p.basename(file.path), 'Demo movie.m3u');
      expect(await file.readAsString(), contains('Bearer example'));
    }
    await store.delete(files.first);
    expect(await files.first.parent.exists(), isFalse);
    expect(await files.last.exists(), isTrue);
  });

  test('stale cleanup only touches owned allocations in dedicated directory',
      () async {
    final stale = await store.create(target);
    final outside = File(p.join(root.path, 'starflow-old.m3u'));
    await outside.writeAsString('keep');
    final unrelated = Directory(p.join(directory.path, 'other-app'));
    await unrelated.create();
    now = now.add(const Duration(hours: 2));
    await store.cleanup();
    expect(await stale.exists(), isFalse);
    expect(await outside.exists(), isTrue);
    expect(await unrelated.exists(), isTrue);
    await store.delete(outside);
    expect(await outside.exists(), isTrue);
  });

  test('recent files and linked directories are retained', () async {
    final file = await store.create(target);
    final outside = Directory(p.join(root.path, 'external'));
    await outside.create();
    final keep = File(p.join(outside.path, 'keep.m3u'));
    await keep.writeAsString('keep');
    final link = Link(p.join(directory.path, 'starflow-linked'));
    await link.create(outside.path);
    now = now.add(const Duration(minutes: 11));
    await store.cleanup();
    expect(await file.exists(), isTrue);
    expect(await keep.exists(), isTrue);
    expect(await link.exists(), isTrue);
  });
}
