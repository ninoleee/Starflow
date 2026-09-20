import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sembast/sembast_memory.dart' hide Finder;
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/live_tv/data/live_playlist_transfer_service.dart';
import 'package:starflow/features/live_tv/data/live_playlist_parser.dart';
import 'package:starflow/features/live_tv/data/live_repository.dart';
import 'package:starflow/features/live_tv/domain/live_models.dart';
import 'package:starflow/features/live_tv/presentation/live_sources_page.dart';
import 'package:starflow/features/live_tv/presentation/live_widgets.dart';
import 'package:starflow/features/settings/presentation/widgets/lan_transfer_qr_address_card.dart';

void main() {
  for (final size in [const Size(320, 640), const Size(1280, 720)]) {
    testWidgets(
        'TV scan uses shared QR, receives a draft and saves only on confirmation at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final service = _Service();
      final repository = await _editor(tester, service);
      expect(_icon('导入 M3U / TXT 文件'), findsNothing);
      await _open(tester);
      expect(service.starts, 1);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(
          tester
              .widget<LanTransferQrAddressCard>(
                  find.byType(LanTransferQrAddressCard))
              .url,
          service.session.urls.single);
      expect(find.text('等待手机上传'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel,
          'live-transfer-close');
      service.session.errorsController.add('文件不是有效的频道列表');
      await tester.pumpAndSettle();
      expect(find.text('文件不是有效的频道列表'), findsOneWidget);
      service.session.result.complete(_upload);
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsNothing);
      expect(service.session.closes, 1);
      expect(find.text('channels.txt'), findsWidgets);
      expect((await repository.load()).sources, isEmpty);
      await _press(tester, '保存');
      expect((await repository.load()).channels.single.name, 'News');
      expect((await repository.load()).sources.single.url, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'back closes service immediately and a late upload cannot change the draft',
      (tester) async {
    final service = _Service();
    final repository = await _editor(tester, service);
    await _open(tester);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(service.session.closes, 1);
    service.session.result.complete(_upload);
    await tester.pumpAndSettle();
    expect(find.text('channels.txt'), findsNothing);
    expect((await repository.load()).sources, isEmpty);
  });

  testWidgets('background closes scan and does not reopen on resume',
      (tester) async {
    final service = _Service();
    await _editor(tester, service);
    await _open(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(service.session.closes, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNothing);
    expect(service.starts, 1);
  });

  testWidgets('closing during startup closes a late session without reopening',
      (tester) async {
    final service = _Service()
      ..starting = Completer<LivePlaylistTransferSession>();
    await _editor(tester, service);
    await _open(tester);
    expect(find.text('正在启动手机传输'), findsOneWidget);
    await _press(tester, '关闭服务');
    service.starting!.complete(service.session);
    await tester.pumpAndSettle();
    expect(service.session.closes, 1);
    expect(find.byType(QrImageView), findsNothing);
  });

  testWidgets(
      'startup failure is sanitized and does not fall back to TV file picker',
      (tester) async {
    final service = _Service()..failure = StateError('private token');
    await _editor(tester, service);
    await _open(tester);
    expect(find.text('无法启动手机传输，请检查局域网连接后重试'), findsOneWidget);
    expect(find.textContaining('private token'), findsNothing);
    await _press(tester, '关闭服务');
    expect(_icon('手机导入 M3U / TXT 文件'), findsOneWidget);
  });

  testWidgets('non-TV retains local import entry', (tester) async {
    final service = _Service();
    await _editor(tester, service, television: false);
    expect(_icon('导入 M3U / TXT 文件'), findsOneWidget);
    expect(_icon('手机导入 M3U / TXT 文件'), findsNothing);
    expect(service.starts, 0);
  });
}

Future<LiveRepository> _editor(WidgetTester tester, _Service service,
    {bool television = true}) async {
  final repository = _Repository();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    repository.dispose();
    await service.session.errorsController.close();
  });
  await tester.pumpWidget(ProviderScope(overrides: [
    isTelevisionProvider.overrideWith((_) => television),
    liveRepositoryProvider.overrideWithValue(repository),
    livePlaylistTransferServiceProvider.overrideWithValue(service),
  ], child: const MaterialApp(home: LiveSourcesPage())));
  await tester.pumpAndSettle();
  tester.widget<LiveIconButton>(_icon('添加订阅')).onPressed!();
  await tester.pumpAndSettle();
  return repository;
}

Future<void> _open(WidgetTester tester) async {
  final finder = _icon('手机导入 M3U / TXT 文件');
  await tester.ensureVisible(finder);
  tester.widget<LiveIconButton>(finder).onPressed!();
  await tester.pumpAndSettle();
}

Future<void> _press(WidgetTester tester, String label) async {
  final finder =
      find.byWidgetPredicate((w) => w is StarflowButton && w.label == label);
  await tester.ensureVisible(finder);
  tester.widget<StarflowButton>(finder).onPressed!();
  await tester.pumpAndSettle();
}

Finder _icon(String label) =>
    find.byWidgetPredicate((w) => w is LiveIconButton && w.label == label);

final _upload = LivePlaylistUpload(
    name: 'channels.txt',
    bytes: Uint8List.fromList(utf8.encode('News,https://example.test/live')));

class _Service implements LivePlaylistTransferService {
  final session = _Session();
  Completer<LivePlaylistTransferSession>? starting;
  Object? failure;
  int starts = 0;
  @override
  Future<LivePlaylistTransferSession> start() async {
    starts++;
    if (failure != null) throw failure!;
    return await (starting?.future ?? Future.value(session));
  }
}

class _Session implements LivePlaylistTransferSession {
  final errorsController = StreamController<String>.broadcast();
  final result = Completer<LivePlaylistUpload?>();
  int closes = 0;
  @override
  List<String> get urls => ['http://192.168.1.8:8123/?token=example-session'];
  @override
  Stream<String> get errors => errorsController.stream;
  @override
  Future<LivePlaylistUpload?> get received => result.future;
  @override
  Future<void> close() async {
    closes++;
  }
}

class _Repository extends LiveRepository {
  _Repository()
      : super(
            openDatabase: () => databaseFactoryMemory.openDatabase('unused'),
            client: MockClient((_) async => http.Response('', 404)));

  LiveSnapshot snapshot = const LiveSnapshot();
  final _snapshots = StreamController<LiveSnapshot>.broadcast();

  @override
  Stream<LiveSnapshot> watch() async* {
    yield snapshot;
    yield* _snapshots.stream;
  }

  @override
  Future<LiveSnapshot> load() async => snapshot;

  @override
  Future<void> saveSource(LiveSource source, {Uint8List? imported}) async {
    snapshot = LiveSnapshot(
        sources: [source],
        channels:
            parseLivePlaylist(decodeLiveText(imported!), source.id).channels);
    _snapshots.add(snapshot);
  }

  @override
  void dispose() {
    unawaited(_snapshots.close());
    super.dispose();
  }
}
