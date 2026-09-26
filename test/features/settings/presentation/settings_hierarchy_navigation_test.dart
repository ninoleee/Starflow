import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/media_source_settings_page.dart';
import 'package:starflow/features/settings/presentation/network_storage_settings_page.dart';
import 'package:starflow/features/settings/presentation/search_service_settings_page.dart';
import 'package:starflow/features/settings/presentation/settings_page.dart';

void main() {
  for (final hidden in [false, true]) {
    for (final keepFocus in [false, true]) {
      testWidgets('delayed TV detection: hidden=$hidden existing=$keepFocus',
          (tester) async {
        final detected = Completer<bool>();
        final otherFocus = FocusNode(debugLabel: 'existing-action');
        addTearDown(otherFocus.dispose);
        await tester.pumpWidget(ProviderScope(
          overrides: [
            isTelevisionProvider.overrideWith((ref) => detected.future),
            settingsControllerProvider
                .overrideWith(_LoadedSettingsController.new),
            appSettingsProvider.overrideWithValue(_settings),
          ],
          child: MaterialApp(
              home: Focus(
            focusNode: otherFocus,
            child: TickerMode(enabled: !hidden, child: const SettingsPage()),
          )),
        ));
        await tester.pumpAndSettle();
        if (keepFocus) {
          otherFocus.requestFocus();
          await tester.pumpAndSettle();
        }
        detected.complete(true);
        await tester.pumpAndSettle();
        if (!hidden) {
          final header = _focusAction(tester, 'settings:header').focusNode!;
          expect(header.hasPrimaryFocus, !keepFocus);
        }
        if (keepFocus) expect(otherFocus.hasPrimaryFocus, isTrue);
        if (hidden && !keepFocus) expect(hasActionableTvFocus(), isFalse);
      });
    }
  }

  for (final keepFocus in [false, true]) {
    testWidgets(
        'idle settings activation restores only missing focus: $keepFocus',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final otherFocus = FocusNode(debugLabel: 'settings-existing-action');
      addTearDown(otherFocus.dispose);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          settingsControllerProvider
              .overrideWith(_LoadedSettingsController.new),
          appSettingsProvider.overrideWithValue(_settings),
        ],
        child: MaterialApp(
          home: Focus(focusNode: otherFocus, child: const SettingsPage()),
        ),
      ));
      await tester.pumpAndSettle();
      final header = _focusAction(tester, 'settings:header').focusNode!;
      if (keepFocus) {
        otherFocus.requestFocus();
        await tester.pumpAndSettle();
      } else {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        expect(hasActionableTvFocus(), isFalse);
      }
      final previous = FocusManager.instance.primaryFocus;
      expect(tester.binding.hasScheduledFrame, isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.idle();
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pumpAndSettle();
      expect(header.hasPrimaryFocus, !keepFocus);
      if (keepFocus) {
        expect(FocusManager.instance.primaryFocus, same(previous));
      }
    });
  }

  testWidgets('TV settings root focuses its visible header', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          appSettingsProvider.overrideWithValue(_settings),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      _focusAction(tester, 'settings:header').focusNode!.hasPrimaryFocus,
      isTrue,
      reason: describeTvFocusNode(FocusManager.instance.primaryFocus),
    );
  });

  testWidgets('TV content directories expose a visible initial focus',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpSettingsPage(tester, const MediaSourceSettingsPage());
    expect(find.text('媒体源管理'), findsOneWidget);
    expect(
      _focusAction(tester, 'media-sources:add-empty').focusNode!.hasFocus,
      isTrue,
    );
    expect(
      tester.getTopLeft(find.text('新增媒体源')).dy,
      lessThan(tester.getTopLeft(find.text('详情页匹配来源')).dy),
    );

    await _pumpSettingsPage(tester, const SearchServiceSettingsPage());
    expect(find.text('搜索服务管理'), findsOneWidget);
    expect(
      _focusAction(tester, 'search-services:sources').focusNode!.hasFocus,
      isTrue,
    );
  });

  testWidgets('TV media source list precedes matching and focuses first edit',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpSettingsPage(
      tester,
      const MediaSourceSettingsPage(),
      settings: _settings.copyWith(mediaSources: const [_source]),
    );
    expect(
      _focusAction(tester, 'media-sources:nas:edit').focusNode!.hasFocus,
      isTrue,
    );
    expect(
      tester.getTopLeft(find.text(_source.name)).dy,
      lessThan(tester.getTopLeft(find.text('详情页匹配来源')).dy),
    );
    await _activateTvAction(tester, 'media-sources:match-sources');
    expect(find.text('选择匹配来源'), findsOneWidget);
    expect(find.text('全部已启用来源'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV cloud storage directory separates accounts and processing',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpSettingsPage(tester, const NetworkStorageSettingsPage());
    expect(find.text('网盘与转存'), findsOneWidget);
    expect(find.text('网盘账号'), findsOneWidget);
    expect(find.text('公共配置'), findsOneWidget);
    expect(find.text('夸克云盘'), findsOneWidget);
    expect(find.text('115 网盘'), findsOneWidget);
    expect(find.text('通用设置'), findsOneWidget);
    expect(find.text('同步与索引刷新'), findsNothing);
    expect(
      tester.getTopLeft(find.text('115 网盘')).dy,
      lessThan(tester.getTopLeft(find.text('公共配置')).dy),
    );
    expect(
      tester.getTopLeft(find.text('公共配置')).dy,
      lessThan(tester.getTopLeft(find.text('通用设置')).dy),
    );
    expect(
      _focusAction(tester, 'network-storage:quark').focusNode!.hasFocus,
      isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('夸克 Cookie'), findsOneWidget);
    expect(
      _focusAction(tester, 'network-storage-quark:cookie').focusNode!.hasFocus,
      isTrue,
    );
  });

  for (final entry in [
    (
      title: '115 网盘',
      section: NetworkStorageEditorSection.cloud115,
      entryFocusId: 'network-storage:115',
      field: '115 Cookie',
      focusId: 'network-storage-quark:cookie',
    ),
    (
      title: '通用设置',
      section: NetworkStorageEditorSection.common,
      entryFocusId: 'network-storage:common',
      field: 'Webhook 地址',
      focusId: 'network-storage-smart-strm:webhook',
    ),
  ]) {
    testWidgets('TV cloud storage opens scoped editor: ${entry.title}',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pumpSettingsPage(tester, const NetworkStorageSettingsPage());
      await _activateTvAction(tester, entry.entryFocusId);
      expect(
        tester
            .widget<NetworkStorageEditorPage>(
              find.byType(NetworkStorageEditorPage),
            )
            .section,
        entry.section,
      );
      expect(find.text(entry.field), findsOneWidget);
      expect(_focusAction(tester, entry.focusId).focusNode!.hasFocus, isTrue);
      if (entry.section != NetworkStorageEditorSection.common) {
        expect(find.text('通用设置'), findsNothing);
      }
      if (entry.section != NetworkStorageEditorSection.cloud115) {
        expect(find.text('同步删除夸克目录'), findsNothing);
        expect(find.text('同步删除115目录'), findsNothing);
        expect(find.text('夸克 SmartStrm 任务名'), findsNothing);
        expect(find.text('115 SmartStrm 任务名'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Cloud storage groups fit a narrow mobile viewport',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpSettingsPage(
      tester,
      const NetworkStorageSettingsPage(),
      isTelevision: false,
      settings: _settings.copyWith(
        networkStorage: const NetworkStorageConfig(
          smartStrmWebhookUrl: 'https://strm.test/webhook',
          smartStrmTaskName: 'quark-task',
          cloud115SmartStrmTaskName: '115-task',
          smartStrmDelaySeconds: 3,
          refreshDelaySeconds: 10,
        ),
      ),
    );
    expect(find.text('通用设置'), findsOneWidget);
    expect(find.textContaining('quark-task'), findsNothing);
    await tester.ensureVisible(find.text('通用设置'));
    await tester.tap(find.text('通用设置'));
    await tester.pumpAndSettle();
    expect(find.text('索引刷新等待时间'), findsOneWidget);
    expect(find.text('10 秒'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _LoadedSettingsController extends SettingsController {
  @override
  Future<AppSettings> build() async => _settings;
}

Future<void> _pumpSettingsPage(
  WidgetTester tester,
  Widget page, {
  AppSettings settings = _settings,
  bool isTelevision = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isTelevisionProvider.overrideWith((ref) => isTelevision),
        appSettingsProvider.overrideWithValue(settings),
      ],
      child: MaterialApp(home: page),
    ),
  );
  await tester.pumpAndSettle();
}

TvFocusableAction _focusAction(WidgetTester tester, String focusId) {
  return tester
      .widgetList<TvFocusableAction>(find.byType(TvFocusableAction))
      .singleWhere((action) => action.focusId == focusId);
}

Future<void> _activateTvAction(WidgetTester tester, String focusId) async {
  _focusAction(tester, focusId).focusNode!.requestFocus();
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
}

const _settings = AppSettings(
  mediaSources: <MediaSourceConfig>[],
  searchProviders: <SearchProviderConfig>[],
  doubanAccount: DoubanAccountConfig(enabled: false),
  homeModules: <HomeModuleConfig>[],
);

const _source = MediaSourceConfig(
  id: 'nas',
  name: 'Living Room NAS',
  kind: MediaSourceKind.nas,
  endpoint: 'https://nas.test/dav/',
  enabled: true,
);
