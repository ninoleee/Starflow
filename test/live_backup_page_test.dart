import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/live_tv/data/live_backup.dart';
import 'package:starflow/features/live_tv/data/live_backup_file_io.dart';
import 'package:starflow/features/live_tv/data/live_repository.dart';
import 'package:starflow/features/live_tv/domain/live_models.dart';
import 'package:starflow/features/live_tv/presentation/live_backup_dialog.dart';

void main() {
  test('backup file is flushed, cannot overwrite and enforces read size',
      () async {
    final dir = await Directory.systemTemp.createTemp('live-backup-test');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/backup.json';
    final bytes = Uint8List.fromList(utf8.encode('{}'));
    await writeLiveBackupFile(path, bytes);
    expect(await readLiveBackupFile(path), bytes);
    await expectLater(
        writeLiveBackupFile(path, bytes), throwsA(isA<FileSystemException>()));
    final file = await File('${dir.path}/large').open(mode: FileMode.write);
    await file.truncate(liveBackupMaxBytes + 1);
    await file.close();
    await expectLater(
        readLiveBackupFile('${dir.path}/large'), throwsFormatException);
  });

  testWidgets(
      'live backup dialog offers scoped modes, warns credentials and exports locally',
      (tester) async {
    late Directory dir;
    late LiveRepository repository;
    // Real filesystem and isolate work cannot be awaited in testWidgets' clock.
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('live-backup-page');
      repository = LiveRepository(
          openDatabase: () => databaseFactoryMemory.openDatabase('backup-page'),
          client: MockClient((_) async => http.Response('', 404)));
      await repository.saveSource(const LiveSource(id: 's', name: 'Local'),
          imported:
              Uint8List.fromList(utf8.encode('News,https://a.test/live')));
    });
    addTearDown(() async {
      repository.dispose();
      await dir.delete(recursive: true);
    });
    await tester.pumpWidget(_dialog(repository));
    await tester.pump();
    expect(find.textContaining('文件未加密'), findsOneWidget);
    expect(find.text('选择备份文件'), findsOneWidget);
    expect(
        tester
            .widget<DropdownButton<LiveBackupImportMode>>(
                find.byType(DropdownButton<LiveBackupImportMode>))
            .items!
            .map((item) => item.value),
        LiveBackupImportMode.values);
    await _enterPath(tester, '${dir.path}/live.json');
    final export = tester
        .widget<StarflowButton>(find.widgetWithText(StarflowButton, '导出'));
    // Await the entire action, including flush/rename and its UI continuation.
    await tester.runAsync(export.onPressed! as Future<void> Function());
    await tester.pump();
    expect(find.text('直播备份已导出'), findsOneWidget);
    await tester.runAsync(() async {
      final backup =
          LiveBackup.decode(await readLiveBackupFile('${dir.path}/live.json'));
      expect(backup.stores['sources']!.keys, ['s']);
    });
    final exported = await tester
        .runAsync(() => readLiveBackupFile('${dir.path}/live.json'));
    await tester.runAsync(tester
        .widget<StarflowButton>(find.widgetWithText(StarflowButton, '导出'))
        .onPressed! as Future<void> Function());
    await tester.pump();
    expect(find.textContaining('操作失败'), findsOneWidget);
    await tester.runAsync(() async {
      expect(await readLiveBackupFile('${dir.path}/live.json'), exported);
      expect(await dir.list().length, 1,
          reason: 'Failed exports leave no temporary files');
    });
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'restore cancellation preserves data and confirmed replace is scoped',
      (tester) async {
    late Directory dir;
    late LiveRepository repository;
    late Uint8List before;
    late Uint8List incoming;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('live-restore-page');
      repository = LiveRepository(
          openDatabase: () =>
              databaseFactoryMemory.openDatabase('restore-page'),
          client: MockClient((_) async => http.Response('', 404)));
      await repository.saveSource(
          const LiveSource(id: 'incoming', name: 'Incoming'),
          imported:
              Uint8List.fromList(utf8.encode('Incoming,https://a.test/live')));
      incoming = await repository.exportBackup();
      await writeLiveBackupFile('${dir.path}/restore.json', incoming);
      await repository.removeSource('incoming');
      await repository.saveSource(
          const LiveSource(id: 'existing', name: 'Existing'),
          imported:
              Uint8List.fromList(utf8.encode('Existing,https://b.test/live')));
      await repository.setEngine('exo');
      before = await repository.exportBackup();
    });
    addTearDown(() async {
      repository.dispose();
      await dir.delete(recursive: true);
    });
    await tester.pumpWidget(_dialog(repository));
    await _enterPath(tester, '${dir.path}/restore.json');
    await tester.tap(find.byType(DropdownButton<LiveBackupImportMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('替换：全部直播数据').last);
    await tester.pumpAndSettle();

    for (final confirm in [false, true]) {
      final restore = tester
          .widget<StarflowButton>(find.widgetWithText(StarflowButton, '恢复'));
      late Future<void> action;
      await tester.runAsync(() async {
        action = (restore.onPressed! as Future<void> Function())();
        // Let file IO and isolate decoding complete without awaiting the modal.
        final deadline = Stopwatch()..start();
        while (find.text('确认恢复直播备份？').evaluate().isEmpty &&
            deadline.elapsed < const Duration(seconds: 5)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();
      expect(find.text('确认恢复直播备份？'), findsOneWidget);
      expect(find.textContaining('替换将删除当前全部直播数据'), findsOneWidget);
      final modal = find.ancestor(
          of: find.text('确认恢复直播备份？'), matching: find.byType(AlertDialog));
      await tester.tap(find.descendant(
          of: modal,
          matching:
              find.widgetWithText(StarflowButton, confirm ? '恢复' : '取消')));
      await tester.pump();
      await tester.runAsync(() => action);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        expect(jsonDecode(utf8.decode(await repository.exportBackup())),
            jsonDecode(utf8.decode(confirm ? incoming : before)));
      });
      expect(find.text('直播备份已恢复'), confirm ? findsOneWidget : findsNothing);
    }
    await tester.runAsync(() => writeLiveBackupFile('${dir.path}/invalid.json',
        Uint8List.fromList(utf8.encode('{invalid'))));
    await _enterPath(tester, '${dir.path}/invalid.json');
    await tester.runAsync(tester
        .widget<StarflowButton>(find.widgetWithText(StarflowButton, '恢复'))
        .onPressed! as Future<void> Function());
    await tester.pumpAndSettle();
    expect(find.text('确认恢复直播备份？'), findsNothing);
    expect(find.textContaining('操作失败'), findsOneWidget);
    await tester.runAsync(() async {
      expect(await repository.exportBackup(), incoming);
    });
    await tester.pumpWidget(const SizedBox());
  });
}

Widget _dialog(LiveRepository repository) => ProviderScope(
    overrides: [isTelevisionProvider.overrideWith((_) => false)],
    child: MaterialApp(
        theme: ThemeData.dark().copyWith(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
            body: LiveBackupDialog(
                repository: repository, isTelevision: false))));

Future<void> _enterPath(WidgetTester tester, String path) async {
  await tester.enterText(find.byType(TextField), path);
  await tester.pumpAndSettle();
}
