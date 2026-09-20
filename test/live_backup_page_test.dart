import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/live_tv/data/live_backup.dart';
import 'package:starflow/features/live_tv/data/live_backup_file_io.dart';
import 'package:starflow/features/live_tv/data/live_repository.dart';
import 'package:starflow/features/live_tv/domain/live_models.dart';
import 'package:starflow/features/live_tv/presentation/live_backup_dialog.dart';

void main() {
  test('backup file is flushed, cannot overwrite and enforces read size', () async {
    final dir = await Directory.systemTemp.createTemp('live-backup-test');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/backup.json';
    final bytes = Uint8List.fromList(utf8.encode('{}'));
    await writeLiveBackupFile(path, bytes);
    expect(await readLiveBackupFile(path), bytes);
    await expectLater(writeLiveBackupFile(path, bytes), throwsA(isA<FileSystemException>()));
    final file = await File('${dir.path}/large').open(mode: FileMode.write);
    await file.truncate(liveBackupMaxBytes + 1);
    await file.close();
    await expectLater(readLiveBackupFile('${dir.path}/large'), throwsFormatException);
  });

  testWidgets('live backup dialog offers scoped modes, warns credentials and exports locally', (tester) async {
    final dir = await Directory.systemTemp.createTemp('live-backup-page');
    final repository = LiveRepository(openDatabase: () => databaseFactoryMemory.openDatabase('backup-page'),
        client: MockClient((_) async => http.Response('', 404)));
    await tester.runAsync(() => repository.saveSource(const LiveSource(id: 's', name: 'Local'),
        imported: Uint8List.fromList(utf8.encode('News,https://a.test/live'))));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: LiveBackupDialog(repository: repository, isTelevision: true))));
    await tester.pump();
    expect(find.textContaining('文件未加密'), findsOneWidget);
    expect(find.text('选择备份文件'), findsNothing);
    await tester.enterText(find.byType(TextField).first, '${dir.path}/live.json');
    final export = tester.widget<StarflowButton>(find.widgetWithText(StarflowButton, '导出'));
    await tester.runAsync(() async {
      export.onPressed!();
      for (var i = 0; i < 100 && !await File('${dir.path}/live.json').exists(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    expect(find.text('直播备份已导出'), findsOneWidget);
    await tester.runAsync(() async {
      final backup = LiveBackup.decode(await readLiveBackupFile('${dir.path}/live.json'));
      expect(backup.stores['sources']!.keys, ['s']);
    });
    await tester.pumpWidget(const SizedBox());
    repository.dispose();
    await tester.runAsync(() => dir.delete(recursive: true));
  });
}
