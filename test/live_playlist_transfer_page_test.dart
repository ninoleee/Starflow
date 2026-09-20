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
import 'package:starflow/features/settings/presentation/widgets/settings_text_input_field.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';
import 'package:starflow/features/settings/data/text_input_transfer_service.dart';

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
    expect(_icon('手机扫码填写订阅地址'), findsNothing);
    expect(service.starts, 0);
  });

  for (final size in [const Size(320, 640), const Size(1280, 720)]) {
    testWidgets('TV URL scan fills only the draft until saved at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final service = _Service();
      final repository = await _editor(tester, service);
      _field(tester, '名称').text = 'My subscription';
      _field(tester, 'XMLTV / XMLTV.gz 节目单地址').text =
          'https://example.test/epg.xml';
      await _open(tester, url: true);
      expect(service.text.label, 'M3U / TXT 订阅地址');
      expect(find.text('手机扫码输入'), findsOneWidget);
      expect(find.text('等待手机输入'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel,
          'text-transfer-close');
      service.text.session.errorsController.add('请重试');
      await tester.pumpAndSettle();
      expect(find.text('请重试'), findsOneWidget);
      service.text.session.result
          .complete('https://example.test/list?token=abc');
      await tester.pumpAndSettle();
      expect(service.text.session.closes, 1);
      expect(_field(tester, 'M3U / TXT 订阅地址').text, isEmpty);
      await _press(tester, '保存');
      expect(_field(tester, 'M3U / TXT 订阅地址').text,
          'https://example.test/list?token=abc');
      expect(_field(tester, '名称').text, 'My subscription');
      expect(_field(tester, 'XMLTV / XMLTV.gz 节目单地址').text,
          'https://example.test/epg.xml');
      expect((await repository.load()).sources, isEmpty);
      expect(repository.refreshes, 0);
      await _press(tester, '保存');
      expect((await repository.load()).sources.single.url,
          'https://example.test/list?token=abc');
      expect(repository.refreshes, 1);
      expect(tester.takeException(), isNull);
    });
  }

  for (final exit in ['back', 'background', 'close']) {
    testWidgets('URL scan $exit ignores a late result', (tester) async {
      final service = _Service();
      final repository = await _editor(tester, service);
      _field(tester, 'M3U / TXT 订阅地址').text = 'https://old.test/list';
      await _open(tester, url: true);
      if (exit == 'back') {
        await tester.binding.handlePopRoute();
      } else if (exit == 'background') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      } else {
        await _press(tester, '关闭服务');
      }
      await tester.pumpAndSettle();
      expect(service.text.session.closes, 1);
      service.text.session.result.complete('https://late.test/list');
      if (exit == 'background') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      }
      await tester.pumpAndSettle();
      expect(_field(tester, 'M3U / TXT 订阅地址').text, 'https://old.test/list');
      expect((await repository.load()).sources, isEmpty);
      expect(find.byType(QrImageView), findsNothing);
    });
  }

  testWidgets('URL scan replaces a file draft without saving it',
      (tester) async {
    final service = _Service();
    final repository = await _editor(tester, service);
    await _open(tester);
    service.session.result.complete(_upload);
    await tester.pumpAndSettle();
    expect(_icon('取消文件导入'), findsOneWidget);
    await _open(tester, url: true);
    service.text.session.result.complete('https://example.test/list');
    await tester.pumpAndSettle();
    await _press(tester, '保存');
    expect(_icon('取消文件导入'), findsNothing);
    expect(_field(tester, '名称').text, 'channels.txt');
    expect((await repository.load()).sources, isEmpty);
    await _press(tester, '保存');
    expect((await repository.load()).sources.single.url,
        'https://example.test/list');
    expect((await repository.load()).channels, isEmpty);
  });
}

TextEditingController _field(WidgetTester tester, String label) => tester
    .widget<SettingsTextInputField>(find.byWidgetPredicate(
        (w) => w is SettingsTextInputField && w.labelText == label))
    .controller;

Future<_Repository> _editor(WidgetTester tester, _Service service,
    {bool television = true}) async {
  final repository = _Repository();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    repository.dispose();
    await service.session.errorsController.close();
    await service.text.session.errorsController.close();
  });
  await tester.pumpWidget(ProviderScope(overrides: [
    isTelevisionProvider.overrideWith((_) => television),
    liveRepositoryProvider.overrideWithValue(repository),
    livePlaylistTransferServiceProvider.overrideWithValue(service),
    textInputTransferServiceProvider.overrideWithValue(service.text),
  ], child: const MaterialApp(home: LiveSourcesPage())));
  await tester.pumpAndSettle();
  tester.widget<LiveIconButton>(_icon('添加订阅')).onPressed!();
  await tester.pumpAndSettle();
  return repository;
}

Future<void> _open(WidgetTester tester, {bool url = false}) async {
  if (url) {
    final tile = find.byWidgetPredicate(
        (w) => w is SettingsSelectionTile && w.title == 'M3U / TXT 订阅地址');
    await tester.ensureVisible(tile);
    tester.widget<SettingsSelectionTile>(tile).onPressed!();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('手机扫码输入'));
    await tester.pumpAndSettle();
    return;
  }
  final finder = _icon('手机导入 M3U / TXT 文件');
  await tester.ensureVisible(finder);
  tester.widget<LiveIconButton>(finder).onPressed!();
  await tester.pumpAndSettle();
}

Future<void> _press(WidgetTester tester, String label) async {
  final finder =
      find.byWidgetPredicate((w) => w is StarflowButton && w.label == label);
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 250,
        scrollable: find.byType(Scrollable).last);
  }
  await tester.ensureVisible(finder.last);
  tester.widget<StarflowButton>(finder.last).onPressed!();
  await tester.pumpAndSettle();
}

Finder _icon(String label) =>
    find.byWidgetPredicate((w) => w is LiveIconButton && w.label == label);

final _upload = LivePlaylistUpload(
    name: 'channels.txt',
    bytes: Uint8List.fromList(utf8.encode('News,https://example.test/live')));

class _Service implements LivePlaylistTransferService {
  final text = _TextService();
  var session = _Session();
  Completer<LivePlaylistTransferSession>? starting;
  Object? failure;
  int starts = 0;
  LivePlaylistTransferMode? mode;
  @override
  Future<LivePlaylistTransferSession> start({
    LivePlaylistTransferMode mode = LivePlaylistTransferMode.file,
    Uint8List? backupBytes,
  }) async {
    this.mode = mode;
    starts++;
    if (failure != null) throw failure!;
    return await (starting?.future ?? Future.value(session));
  }
}

class _TextService implements TextInputTransferService {
  final session = _TextSession();
  String? label;
  @override
  Future<TextInputTransferSession> start(
      {required String label,
      bool multiline = false,
      bool obscureText = false}) async {
    this.label = label;
    return session;
  }
}

class _TextSession implements TextInputTransferSession {
  final errorsController = StreamController<String>.broadcast();
  final result = Completer<String?>();
  int closes = 0;
  @override
  List<String> get urls => ['http://192.168.1.8:8123/?token=example-session'];
  @override
  Stream<String> get errors => errorsController.stream;
  @override
  Future<String?> get received => result.future;
  @override
  Future<void> close() async {
    closes++;
  }
}

class _Session implements LivePlaylistTransferSession {
  final errorsController = StreamController<String>.broadcast();
  final result = Completer<LivePlaylistTransferResult?>();
  int closes = 0;
  @override
  List<String> get urls => ['http://192.168.1.8:8123/?token=example-session'];
  @override
  Stream<String> get errors => errorsController.stream;
  @override
  Future<LivePlaylistTransferResult?> get received => result.future;
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
  int refreshes = 0;
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
        channels: imported == null
            ? const []
            : parseLivePlaylist(decodeLiveText(imported), source.id).channels);
    _snapshots.add(snapshot);
  }

  @override
  Future<void> refresh(String sourceId) async {
    refreshes++;
  }

  @override
  void dispose() {
    unawaited(_snapshots.close());
    super.dispose();
  }
}
