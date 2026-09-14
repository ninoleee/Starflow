import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/search/application/cloud_save_planner.dart';
import 'package:starflow/features/search/domain/cloud_save_rules.dart';

class _Entry implements CloudSaveEntry {
  const _Entry(this.fid, this.name, {this.isDirectory = false});
  @override
  final String fid;
  @override
  final String name;
  @override
  final bool isDirectory;
}

CloudSavePlanner<_Entry> _planner({
  Map<String, List<_Entry>> shared = const {},
  Map<String, List<_Entry>> stored = const {},
  int maxDepth = 64,
}) =>
    CloudSavePlanner<_Entry>(
      driveName: 'test',
      maxDepth: maxDepth,
      listShared: (id) async =>
          shared[id] ?? (throw StateError('Unexpected share: $id')),
      listStored: (id) async =>
          stored[id] ?? (throw StateError('Unexpected folder: $id')),
      createDirectory: (_, __) async =>
          fail('Preview must not create directories'),
    );

void main() {
  test('preview matches the cleaned recursive save plan and actual target path',
      () async {
    const shared = {
      'wrapper': [
        _Entry('season', '#Season.1', isDirectory: true),
        _Entry('cover', 'poster.jpg'),
      ],
      'season': [
        _Entry('ep1', '#E01.mkv'),
        _Entry('ep2', '#E02.mkv'),
        _Entry('format', '#E01.mp4'),
        _Entry('version', '#E01.4K.mkv'),
      ],
    };
    const stored = {
      'root': [_Entry('show', 'SHOW', isDirectory: true)],
      'show': [_Entry('local-season', 'Season1', isDirectory: true)],
      'local-season': [_Entry('old', 'e01.MKV')],
    };
    const entries = [_Entry('wrapper', 'Release', isDirectory: true)];
    final preview = await _planner(shared: shared, stored: stored).preview(
      entries: entries,
      folderId: 'root',
      folderPath: '/Library/',
      saveFolderName: 'Show',
      sanitizedNameCharacters: '#.',
    );
    final plan = await _planner(shared: shared, stored: stored).build(
      entries: entries,
      folderId: 'root',
      folderPath: '/Library/',
      saveFolderName: 'Show',
      sanitizedNameCharacters: '#.',
    );
    expect(preview.targetFolderPath, '/Library/SHOW');
    expect(preview.targetFolderPath, plan.targetFolderPath);
    expect(preview.localFolderExists, isTrue);
    expect(preview.missingVideos.map((e) => e.relativePath), [
      '#Season.1/#E02.mkv',
      '#Season.1/#E01.mp4',
      '#Season.1/#E01.4K.mkv',
    ]);
    expect(plan.skippedCount, 1);
    expect(plan.batches.last.entries.map((e) => e.name),
        preview.missingVideos.map((e) => e.name));
  });

  test('a missing target only previews and flattens the sole wrapper once',
      () async {
    final preview = await _planner(shared: const {
      'wrapper': [_Entry('season', 'Season 1', isDirectory: true)],
      'season': [_Entry('ep', 'E01.mkv')],
    }, stored: const {
      'root': []
    }).preview(
      entries: const [_Entry('wrapper', 'Release', isDirectory: true)],
      folderId: 'root',
      folderPath: '/Library',
      saveFolderName: ' A/B:*? ',
    );
    expect(preview.localFolderExists, isFalse);
    expect(preview.targetFolderPath, '/Library/A B');
    expect(preview.missingVideos.single.relativePath, 'Season 1/E01.mkv');
  });

  test(
      'selected target already named is reused and repeated saves have no updates',
      () async {
    final preview = await _planner(stored: const {
      'root': [_Entry('old', 'E01.mkv'), _Entry('poster', 'poster.png')],
    }).preview(
        entries: const [_Entry('new', 'e01.MKV')],
        folderId: 'root',
        folderPath: '/Library/SHOW/',
        saveFolderName: 'Show');
    expect(preview.targetFolderPath, '/Library/SHOW');
    expect(preview.localFolderExists, isTrue);
    expect(preview.missingVideos, isEmpty);
    expect(preview.localEntries.where((e) => e.isVideo), hasLength(1));
  });

  test(
      'unnamed direct save preserves wrapper and does not claim duplicate skipping',
      () async {
    final preview = await _planner(shared: const {
      'wrapper': [_Entry('new', 'E01.mkv')],
    }, stored: const {
      'root': [_Entry('old-wrapper', 'Release', isDirectory: true)],
      'old-wrapper': [_Entry('old', 'E01.mkv')],
    }).preview(
        entries: const [_Entry('wrapper', 'Release', isDirectory: true)],
        folderId: 'root',
        folderPath: '/',
        saveFolderName: '');
    expect(preview.missingVideos.single.relativePath, 'Release/E01.mkv');
  });

  for (final entries in [
    const [_Entry('1', '#E01.mkv'), _Entry('2', 'E01.mkv')],
    const [_Entry('1', 'E01.mkv'), _Entry('1', 'E02.mkv')],
    const [_Entry('1', '')],
    const [_Entry('0', 'E01.mkv')],
    const [_Entry('1', '../E01.mkv')],
  ]) {
    test('invalid or ambiguous preview aborts: ${entries.map((e) => e.name)}',
        () async {
      await expectLater(
          _planner(stored: const {'root': []}).preview(
            entries: entries,
            folderId: 'root',
            folderPath: '/Show',
            saveFolderName: 'Show',
            sanitizedNameCharacters: '#',
          ),
          throwsA(isA<CloudSaveException>()));
    });
  }

  test('file-directory conflicts are reported instead of missing videos',
      () async {
    await expectLater(
        _planner(stored: const {
          'root': [_Entry('old', 'E01.mkv', isDirectory: true)],
          'old': [],
        }).preview(
            entries: const [_Entry('new', 'E01.mkv')],
            folderId: 'root',
            folderPath: '/Show',
            saveFolderName: 'Show'),
        throwsA(isA<CloudSaveException>()
            .having((e) => e.message, 'message', contains('冲突'))));
  });

  for (final cycle in [false, true]) {
    test('cyclic or excessive depth fails promptly: cycle=$cycle', () async {
      await expectLater(
          _planner(maxDepth: cycle ? 64 : 2, shared: {
            '1': [_Entry(cycle ? '1' : '2', 'Nested', isDirectory: true)],
            '2': const [_Entry('3', 'Deep', isDirectory: true)],
            '3': const [],
          }, stored: const {
            'root': []
          }).preview(
            entries: const [
              _Entry('1', 'Season', isDirectory: true),
              _Entry('video', 'E01.mkv')
            ],
            folderId: 'root',
            folderPath: '/Show',
            saveFolderName: 'Show',
          ),
          throwsA(isA<CloudSaveException>()));
    });
  }
}
