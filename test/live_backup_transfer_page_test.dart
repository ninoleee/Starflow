import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart' hide Finder;
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/live_tv/data/live_backup.dart';
import 'package:starflow/features/live_tv/data/live_playlist_transfer_service.dart';
import 'package:starflow/features/live_tv/data/live_repository.dart';
import 'package:starflow/features/live_tv/presentation/live_backup_dialog.dart';
import 'package:starflow/features/settings/presentation/widgets/lan_transfer_qr_address_card.dart';

final _bytes =
    LiveBackup({for (final name in liveBackupStores) name: {}}).encode();

void main() {
  Future<(_Repository, _Service)> open(WidgetTester tester) async {
    final repository = _Repository();
    final service = _Service();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((_) => true),
          livePlaylistTransferServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: LiveBackupDialog(
                    repository: repository, isTelevision: true)))));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      repository.dispose();
    });
    return (repository, service);
  }

  for (final size in [const Size(320, 640), const Size(1280, 720)]) {
    testWidgets(
        'TV backup uses shared QR and never asks for a local path at $size',
        (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final (repository, service) = await open(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('选择备份文件'), findsNothing);
      _press(tester, '手机备份');
      await tester.pumpAndSettle();
      expect(service.mode, LivePlaylistTransferMode.backupExport);
      expect(service.bytes, _bytes);
      expect(find.byType(LanTransferQrAddressCard), findsOneWidget);
      expect(tester.takeException(), isNull);
      service.session.result.complete(const LiveBackupDownloaded());
      await tester.pumpAndSettle();
      expect(service.session.closed, isTrue);
      expect(find.text('直播备份已发送，请在手机确认下载文件'), findsOneWidget);
      expect(repository.imports, 0);
    });
  }

  for (final mode in LiveBackupImportMode.values) {
    testWidgets(
        'TV upload requires confirmation for $mode and cancellation is read only',
        (tester) async {
      final (repository, service) = await open(tester);
      final dropdown =
          tester.widget<DropdownButtonFormField<LiveBackupImportMode>>(
              find.byType(DropdownButtonFormField<LiveBackupImportMode>));
      dropdown.onChanged!(mode);
      await tester.pumpAndSettle();
      for (final confirm in [false, true]) {
        _press(tester, '手机恢复');
        await tester.pumpAndSettle();
        expect(service.mode, LivePlaylistTransferMode.backupImport);
        await tester.runAsync(() async {
          service.session.result
              .complete(LivePlaylistUpload(name: 'backup.json', bytes: _bytes));
          final deadline = Stopwatch()..start();
          while (find.text('确认恢复直播备份？').evaluate().isEmpty &&
              deadline.elapsed < const Duration(seconds: 5)) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            await tester.pump();
          }
        });
        await tester.pumpAndSettle();
        expect(find.text('确认恢复直播备份？'), findsOneWidget);
        expect(service.session.closed, isTrue);
        expect(repository.imports, 0);
        _press(tester, confirm ? '恢复' : '取消');
        await tester.pumpAndSettle();
        expect(repository.imports, confirm ? 1 : 0);
      }
      expect(repository.mode, mode);
      expect(repository.imported, _bytes);
      expect(find.text('直播备份已恢复'), findsOneWidget);
    });
  }

  testWidgets(
      'TV background and close discard uploaded backup without restoring',
      (tester) async {
    final (repository, service) = await open(tester);
    _press(tester, '手机恢复');
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(service.session.closed, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    service.session.result
        .complete(LivePlaylistUpload(name: 'late.json', bytes: _bytes));
    await tester.pumpAndSettle();
    expect(find.text('确认恢复直播备份？'), findsNothing);
    expect(repository.imports, 0);
    _press(tester, '手机备份');
    await tester.pumpAndSettle();
    _press(tester, '关闭服务');
    await tester.pumpAndSettle();
    expect(service.session.closed, isTrue);
    expect(find.text('直播备份已发送，请在手机确认下载文件'), findsNothing);
  });
}

void _press(WidgetTester tester, String label) => tester
    .widget<StarflowButton>(find.widgetWithText(StarflowButton, label))
    .onPressed!();

class _Repository extends LiveRepository {
  _Repository()
      : super(
            openDatabase: () =>
                databaseFactoryMemory.openDatabase('unused-backup-ui'),
            client: MockClient((_) async => http.Response('', 404)));
  int imports = 0;
  LiveBackupImportMode? mode;
  Uint8List? imported;
  @override
  Future<Uint8List> exportBackup() async => _bytes;
  @override
  Future<void> importBackup(Uint8List bytes, LiveBackupImportMode mode) async {
    imports++;
    imported = bytes;
    this.mode = mode;
  }
}

class _Service implements LivePlaylistTransferService {
  late _Session session;
  LivePlaylistTransferMode? mode;
  Uint8List? bytes;
  @override
  Future<LivePlaylistTransferSession> start({
    LivePlaylistTransferMode mode = LivePlaylistTransferMode.file,
    Uint8List? backupBytes,
  }) async {
    this.mode = mode;
    bytes = backupBytes;
    return session = _Session();
  }
}

class _Session implements LivePlaylistTransferSession {
  final result = Completer<LivePlaylistTransferResult?>();
  bool closed = false;
  @override
  List<String> get urls => ['http://192.168.1.8:8123/?token=backup-session'];
  @override
  Stream<String> get errors => const Stream.empty();
  @override
  Future<LivePlaylistTransferResult?> get received => result.future;
  @override
  Future<void> close() async {
    closed = true;
  }
}
