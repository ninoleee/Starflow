import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/settings_page.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';
import 'package:starflow/features/update/application/update_controller.dart';
import 'package:starflow/features/update/domain/app_update.dart';
import 'package:starflow/features/update/presentation/update_settings_page.dart';

void main() {
  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'Starflow',
      packageName: 'com.example.starflow',
      version: '1.9.0',
      buildNumber: '100',
      buildSignature: '',
    );
  });

  testWidgets('opening the page does not check or download automatically',
      (tester) async {
    final controller = _FakeUpdateController();
    await _pumpPage(tester, controller);
    expect(find.text('1.9.0 (100)'), findsOneWidget);
    expect(find.text('尚未检查更新'), findsOneWidget);
    expect(controller.calls, isEmpty);
    await tester.tap(find.text('检查更新'));
    await tester.pump();
    expect(controller.calls, ['check']);
    expect(find.text('正在检查更新'), findsOneWidget);
    expect(_button(tester, 'update:check').onPressed, isNull);
    expect(_button(tester, 'update:check').loading, isTrue);
    await tester.tap(find.text('正在检查'));
    expect(controller.calls, ['check']);
  });

  testWidgets(
      'available update displays version notes size and starts download',
      (tester) async {
    final controller = _FakeUpdateController(_state(UpdatePhase.available));
    await _pumpPage(tester, controller);
    expect(find.text('1.9.1 (101)'), findsOneWidget);
    expect(find.text('安装包大小：10.0 MB'), findsOneWidget);
    expect(find.text('修复播放异常'), findsOneWidget);
    expect(find.text('改善电视遥控操作'), findsOneWidget);
    await tester.tap(find.text('下载更新'));
    await tester.pump();
    expect(controller.calls, ['download']);
    expect(find.text('正在下载安装包'), findsOneWidget);
    expect(_button(tester, 'update:check').onPressed, isNull);
    expect(find.text('下载更新'), findsNothing);
    await tester.tap(find.text('取消下载'));
    await tester.pump();
    expect(controller.calls, ['download', 'cancel']);
    expect(find.text('下载更新'), findsOneWidget);
  });

  testWidgets('download progress follows controller notifications and clamps',
      (tester) async {
    final controller = _FakeUpdateController(
      _state(UpdatePhase.downloading, receivedBytes: 5 * 1024 * 1024),
    );
    await _pumpPage(tester, controller);
    expect(find.text('5.0 MB / 10.0 MB'), findsOneWidget);
    expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        0.5);
    controller
        .emit(_state(UpdatePhase.downloading, receivedBytes: 20 * 1024 * 1024));
    await tester.pump();
    expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        1);
  });

  testWidgets('verification disables check and install but permits cancel',
      (tester) async {
    final controller = _FakeUpdateController(_state(UpdatePhase.verifying));
    await _pumpPage(tester, controller);
    expect(_button(tester, 'update:check').onPressed, isNull);
    expect(find.text('安装更新'), findsNothing);
    await tester.tap(find.text('取消下载'));
    expect(controller.calls, ['cancel']);
  });

  testWidgets('check failures retry the check without install permissions',
      (tester) async {
    final controller = _FakeUpdateController(const UpdateState(
      phase: UpdatePhase.failed,
      failure: UpdateFailure('network', '网络连接失败'),
    ));
    await _pumpPage(tester, controller);
    expect(find.text('网络连接失败'), findsOneWidget);
    expect(find.text('允许安装应用'), findsNothing);
    await tester.tap(find.text('重试检查'));
    expect(controller.calls, ['check']);
  });

  testWidgets('download failures retry download without opening settings',
      (tester) async {
    final controller = _FakeUpdateController(_state(
      UpdatePhase.failed,
      failure: const UpdateFailure('checksumMismatch', '安装包校验失败'),
    ));
    await _pumpPage(tester, controller);
    expect(find.text('安装包校验失败'), findsOneWidget);
    expect(find.text('允许安装应用'), findsNothing);
    expect(find.text('重试安装'), findsNothing);
    await tester.tap(find.text('重试下载'));
    expect(controller.calls, ['download']);
  });

  testWidgets('install permission failure opens settings only on request',
      (tester) async {
    final controller = _FakeUpdateController(_state(
      UpdatePhase.failed,
      packagePath: '/tmp/update.apk',
      failure: const UpdateFailure(
        'installPermissionRequired',
        '需要允许安装未知来源应用',
      ),
    ));
    await _pumpPage(tester, controller);
    expect(controller.calls, isEmpty);
    await tester.tap(find.text('允许安装应用'));
    expect(controller.calls, ['permission']);
    await tester.tap(find.text('重试安装'));
    expect(controller.calls, ['permission', 'install']);
  });

  testWidgets('other installer failures do not offer permission settings',
      (tester) async {
    final controller = _FakeUpdateController(_state(
      UpdatePhase.failed,
      packagePath: '/tmp/update.apk',
      failure: const UpdateFailure('installerUnavailable', '无法打开系统安装界面'),
    ));
    await _pumpPage(tester, controller);
    expect(find.text('允许安装应用'), findsNothing);
    await tester.tap(find.text('重试安装'));
    expect(controller.calls, ['install']);
  });

  testWidgets('installer handoff never claims the update was installed',
      (tester) async {
    final controller = _FakeUpdateController(_state(
      UpdatePhase.readyToInstall,
      packagePath: '/tmp/update.apk',
    ));
    await _pumpPage(tester, controller);
    await tester.tap(find.text('安装更新'));
    await tester.pump();
    expect(controller.calls, ['install']);
    expect(find.text('系统安装界面已打开，下次启动确认版本'), findsOneWidget);
    expect(find.textContaining('安装成功'), findsNothing);
    expect(find.text('当前已是最新版本'), findsNothing);
    expect(find.text('安装更新'), findsNothing);
    expect(_button(tester, 'update:check').onPressed, isNull);
  });

  for (final android in [false, true]) {
    testWidgets('unsupported or unconfigured check is disabled: $android',
        (tester) async {
      final controller = _FakeUpdateController()
        ..isAndroid = android
        ..configured = false;
      await _pumpPage(tester, controller);
      expect(find.text(android ? '未配置网络同步' : '此平台暂不支持应用内更新'), findsOneWidget);
      expect(_button(tester, 'update:check').onPressed, isNull);
      await tester.tap(find.text('检查更新'));
      expect(controller.calls, isEmpty);
    });
  }

  testWidgets('TV check retains focus while loading and disabled',
      (tester) async {
    final controller = _FakeUpdateController();
    await _pumpPage(tester, controller,
        television: true, size: const Size(1920, 1080));
    final action = _focusAction(tester, 'update:check');
    action.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(controller.calls, ['check']);
    expect(_focusAction(tester, 'update:check').focusNode!.hasFocus, isTrue);
    expect(_button(tester, 'update:check').focusableWhenDisabled, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(controller.calls, ['check']);
    controller.emit(_state(UpdatePhase.available));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(_focusAction(tester, 'update:download').focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(controller.calls, ['check', 'download']);
  });

  for (final phase in UpdatePhase.values) {
    testWidgets('320px layout has no overflow in ${phase.name}',
        (tester) async {
      final controller = _FakeUpdateController(_state(
        phase,
        packagePath:
            phase == UpdatePhase.readyToInstall || phase == UpdatePhase.failed
                ? '/tmp/update.apk'
                : null,
        failure: phase == UpdatePhase.failed
            ? const UpdateFailure(
                'installPermissionRequired', '需要允许安装未知来源应用，然后重新尝试安装此更新版本。')
            : null,
      ));
      await _pumpPage(tester, controller,
          size: const Size(320, 640), textScale: 1.3);
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('settings maintenance row opens updates without checking',
      (tester) async {
    final controller = _FakeUpdateController();
    await _pumpPage(tester, controller, page: const SettingsPage());
    await tester.runAsync(() async {
      await tester.scrollUntilVisible(find.text('应用更新'), 500);
    });
    await tester.tap(find.text('应用更新'));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateSettingsPage), findsOneWidget);
    expect(controller.calls, isEmpty);
  });

  for (final root in [false, true]) {
    testWidgets('version footer opens updates: root=$root', (tester) async {
      final controller = _FakeUpdateController();
      await _pumpPage(tester, controller,
          page: root
              ? const SettingsPage()
              : const SettingsPageScaffold(
                  children: [Text('其他设置')],
                ));
      await tester.runAsync(() async {
        await tester.scrollUntilVisible(find.text('1.9.0'), 500);
        await tester.tap(find.text('1.9.0'));
        await tester.pumpAndSettle();
      });
      expect(find.byType(UpdateSettingsPage), findsOneWidget);
      expect(controller.calls, isEmpty);
      await tester.runAsync(() async {
        await tester.pump();
        await tester.ensureVisible(find.text('1.9.0'));
        await tester.tap(find.text('1.9.0'));
        await tester.pumpAndSettle();
      });
      expect(
          find.byType(UpdateSettingsPage, skipOffstage: false), findsOneWidget);
      expect(controller.calls, isEmpty);
    });
  }
}

final _artifact = UpdateArtifact(
  platform: 'android',
  variant: 'tv',
  url: Uri.parse('https://updates.example.com/starflow-tv-1.9.1.apk'),
  fileName: 'starflow-tv-1.9.1.apk',
  size: 10 * 1024 * 1024,
  sha256: 'a' * 64,
  minSdk: 23,
  certificateSha256: 'b' * 64,
);
final _update = AppUpdate(
  appId: 'com.example.starflow',
  channel: 'stable',
  version: '1.9.1',
  versionCode: 101,
  publishedAt: DateTime.utc(2026, 9, 26),
  releaseNotes: ['修复播放异常', '改善电视遥控操作'],
  artifacts: [_artifact],
);

UpdateState _state(
  UpdatePhase phase, {
  int receivedBytes = 0,
  String? packagePath,
  UpdateFailure? failure,
}) =>
    UpdateState(
      phase: phase,
      currentVersion: '1.9.0',
      currentVersionCode: 100,
      update: _update,
      artifact: _artifact,
      receivedBytes: receivedBytes,
      packagePath: packagePath,
      failure: failure,
    );

class _FakeUpdateController extends ChangeNotifier implements UpdateController {
  _FakeUpdateController(
      [this.state = const UpdateState(
        currentVersion: '1.9.0',
        currentVersionCode: 100,
      )]);

  @override
  UpdateState state;
  @override
  bool isAndroid = true;
  @override
  bool configured = true;
  @override
  bool busy = false;
  final calls = <String>[];

  void emit(UpdateState next) {
    state = next;
    notifyListeners();
  }

  @override
  Future<void> check() async {
    calls.add('check');
    emit(_state(UpdatePhase.checking));
  }

  @override
  Future<void> download() async {
    calls.add('download');
    emit(_state(UpdatePhase.downloading));
  }

  @override
  Future<void> install() async {
    calls.add('install');
    emit(_state(UpdatePhase.installing));
  }

  @override
  Future<void> openInstallPermissionSettings() async => calls.add('permission');

  @override
  void cancel() {
    calls.add('cancel');
    emit(_state(UpdatePhase.available));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LoadedSettingsController extends SettingsController {
  @override
  Future<AppSettings> build() async => _settings;
}

const _settings = AppSettings(
  mediaSources: [],
  searchProviders: [],
  doubanAccount: DoubanAccountConfig(enabled: false),
  homeModules: [],
);

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeUpdateController controller, {
  Widget page = const UpdateSettingsPage(),
  bool television = false,
  Size size = const Size(800, 900),
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  // The shared version footers cache their PackageInfo futures across tests.
  await tester.runAsync(() => tester.pumpWidget(ProviderScope(
        overrides: [
          updateControllerProvider.overrideWith((ref) => controller),
          isTelevisionProvider.overrideWith((ref) => television),
          settingsControllerProvider
              .overrideWith(_LoadedSettingsController.new),
          appSettingsProvider.overrideWithValue(_settings),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          home: page,
        ),
      )));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

SettingsActionButton _button(WidgetTester tester, String id) => tester
    .widgetList<SettingsActionButton>(find.byType(SettingsActionButton))
    .singleWhere((button) => button.focusId == id);

TvFocusableAction _focusAction(WidgetTester tester, String id) => tester
    .widgetList<TvFocusableAction>(find.byType(TvFocusableAction))
    .singleWhere((action) => action.focusId == id);
