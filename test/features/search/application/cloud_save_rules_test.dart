import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/search/application/cloud_save_planner.dart';
import 'package:starflow/features/search/application/cloud_saved_name_sanitizer.dart';
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

void main() {
  test('shared path and name rules preserve selected folder and extension', () {
    expect(normalizeCloudDirectoryPath(' Library\\Shows/ '), '/Library/Shows');
    expect(sanitizeCloudDirectoryName(' A / B:*? '), 'A B');
    expect(
        resolveCloudSaveFolderPath('/Library/SHOW/', 'Show'), '/Library/SHOW');
    expect(resolveCloudSaveFolderPath('/', 'Show'), '/Show');
    expect(
        sanitizeCloudSavedEntryName('Ep#01.mkv',
            isDirectory: false, characters: '#.m'),
        'Ep01.mkv');
    expect(
        sanitizeCloudSavedEntryName('#.mkv',
            isDirectory: false, characters: '#'),
        isEmpty);
    expect(cloudSaveNameKey('###', characters: '#', isDirectory: true), '###');
  });

  for (final provider in ['115', '夸克']) {
    test('$provider uses the same flattened, recursive, cleaned-name plan',
        () async {
      final storedCalls = <String>[];
      final planner = CloudSavePlanner<_Entry>(
        driveName: provider,
        listShared: (id) async => switch (id) {
          'wrapper' => const [
              _Entry('season', '#Season', isDirectory: true),
              _Entry('new', 'new.mkv')
            ],
          'season' => const [
              _Entry('ep1', '#01.mkv'),
              _Entry('ep2', '#02.mkv')
            ],
          _ => throw StateError('Unexpected shared directory'),
        },
        listStored: (id) async {
          storedCalls.add(id);
          return switch (id) {
            'root' => const [_Entry('show', 'SHOW', isDirectory: true)],
            'show' => const [
                _Entry('target-season', 'Season', isDirectory: true)
              ],
            'target-season' => const [_Entry('old-ep', '01.mkv')],
            _ => throw StateError('Unexpected stored directory'),
          };
        },
        createDirectory: (_, __) async => fail('Must reuse'),
      );
      final plan = await planner.build(
        entries: const [_Entry('wrapper', 'Release', isDirectory: true)],
        folderId: 'root',
        folderPath: '/Library',
        saveFolderName: 'Show',
        sanitizedNameCharacters: '#',
      );
      expect(plan.targetFolderPath, '/Library/SHOW');
      expect(plan.skippedCount, 1);
      expect(
          plan.batches.map((batch) => [
                batch.targetDirectoryFid,
                ...batch.entries.map((entry) => entry.fid)
              ]),
          [
            ['show', 'new'],
            ['target-season', 'ep2'],
          ]);
      final tracked = await planner.trackNewEntries(plan.batches);
      expect(tracked.last.previousFids, {'old-ep'});
      expect(storedCalls, ['root', 'show', 'target-season']);
    });
  }

  test('cleaned-name collision prevents mkdir and save planning', () async {
    final planner = CloudSavePlanner<_Entry>(
      driveName: 'drive',
      listShared: (_) async => fail('No nested directory'),
      listStored: (_) async => fail('Collision should be found first'),
      createDirectory: (_, __) async => fail('No mkdir'),
    );
    await expectLater(
        planner.build(
          entries: const [_Entry('1', '#01.mkv'), _Entry('2', '01.mkv')],
          folderId: '0',
          folderPath: '/',
          saveFolderName: 'Show',
          sanitizedNameCharacters: '#',
        ),
        throwsA(isA<CloudSaveException>()));
  });

  test(
      'sanitizer excludes previous IDs, handles new subtree and checks conflicts',
      () async {
    final renames = <String, String>{};
    final sanitizer = CloudSavedNameSanitizer(
      listEntries: (id) async => switch (id) {
        'show' => const [
            _Entry('old', '#old.mkv'),
            _Entry('new', '#Extras', isDirectory: true),
            _Entry('clash', '#01.mkv'),
            _Entry('existing', '01.mkv'),
          ],
        'new' => const [_Entry('nested', 'a#b.mkv')],
        _ => throw StateError('Must not traverse old content'),
      },
      renameEntry: (id, name) async => renames[id] = name,
    );
    final result = await sanitizer.sanitize(savedEntries: const [
      CloudSavedEntry(
          parentFid: 'show',
          name: '#Extras',
          previousFids: {'old', 'existing'}),
      CloudSavedEntry(
          parentFid: 'show',
          name: '#01.mkv',
          previousFids: {'old', 'existing'}),
    ], characters: '#');
    expect(renames, {'new': 'Extras', 'nested': 'ab.mkv'});
    expect(result.failedNames, ['#01.mkv']);
    expect(result.listedDirectoryCount, 2);
  });

  test('only an old same-name ID must never be renamed', () async {
    final result = await CloudSavedNameSanitizer(
      listEntries: (_) async => const [_Entry('old', '#01.mkv')],
      renameEntry: (_, __) async => fail('Do not rename old file'),
    ).sanitize(savedEntries: const [
      CloudSavedEntry(
        parentFid: 'show',
        name: '#01.mkv',
        previousFids: {'old'},
      )
    ], characters: '#');
    expect(result.completed, isFalse);
  });

  for (final eventuallyVisible in [false, true]) {
    test(
        'complete new subtree must be visible before any rename: $eventuallyVisible',
        () async {
      var pass = 0;
      var waits = 0;
      final renames = <String>[];
      final result = await CloudSavedNameSanitizer(
        visibilityAttempts: 3,
        wait: (_) async {
          waits++;
        },
        listEntries: (id) async {
          if (id == 'show') {
            pass++;
            return const [_Entry('new', '#Season', isDirectory: true)];
          }
          expect(id, 'new');
          return eventuallyVisible && pass >= 2
              ? const [_Entry('ep', '#01.mkv')]
              : const [];
        },
        renameEntry: (id, _) async {
          renames.add(id);
        },
      ).sanitize(savedEntries: const [
        CloudSavedEntry(
          parentFid: 'show',
          name: '#Season',
          isDirectory: true,
          expectedChildren: [
            CloudCopyEntry(name: '#01.mkv', isDirectory: false)
          ],
        )
      ], characters: '#');
      expect(result.completed, eventuallyVisible);
      expect(renames, eventuallyVisible ? ['new', 'ep'] : isEmpty);
      expect(waits, eventuallyVisible ? 1 : 2);
    });
  }

  test('rename acknowledgement without changed name is not completion',
      () async {
    var writes = 0;
    final result = await CloudSavedNameSanitizer(
      verifyRenames: true,
      listEntries: (_) async => const [_Entry('1', '#01.mkv')],
      renameEntry: (_, __) async {
        writes++;
      },
    ).sanitize(savedEntries: const [
      CloudSavedEntry(parentFid: 'show', name: '#01.mkv')
    ], characters: '#');
    expect(writes, 1);
    expect(result.renamedCount, 0);
    expect(result.completed, isFalse);
  });

  test('common post-save gate blocks STRM for failed or unsettled renames',
      () async {
    for (final settled in [false, true]) {
      final outcome = await processCloudSavedNames(
        characters: '#',
        savedCount: 1,
        settled: settled,
        savedEntries: const [
          CloudSavedEntry(parentFid: 'show', name: '#01.mkv')
        ],
        sanitize: () async {
          expect(settled, isTrue);
          return const CloudNameSanitizeResult(failedNames: ['#01.mkv']);
        },
      );
      expect(outcome.canTriggerSmartStrm, isFalse);
      expect(outcome.warning, contains('未触发 STRM'));
    }
  });
}
