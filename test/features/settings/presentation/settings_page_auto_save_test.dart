import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/search/data/smart_strm_webhook_client.dart';
import 'package:starflow/features/settings/presentation/network_storage_settings_page.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_text_input_field.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/data/app_settings_repository.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/douban_account_editor_page.dart';
import 'package:starflow/features/settings/presentation/mpv_settings_page.dart';
import 'package:starflow/features/settings/presentation/subtitle_settings_page.dart';

void main() {
  for (final is115 in [false, true]) {
    testWidgets('Drive page saves and tests its own STRM task: $is115',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final initial = SeedData.defaultSettings.copyWith(
          networkStorage: const NetworkStorageConfig(
        smartStrmWebhookUrl: 'https://strm.test/webhook',
        smartStrmTaskName: 'quark-task',
        cloud115SmartStrmTaskName: '115-task',
        quarkSaveFolderPath: '/quark',
        cloud115SaveFolderPath: '/115',
      ));
      final repository = _MemorySettingsRepository(initial);
      final requests = <Map<String, dynamic>>[];
      await tester.pumpWidget(ProviderScope(
          overrides: [
            appSettingsRepositoryProvider.overrideWithValue(repository),
            appSettingsProvider.overrideWithValue(initial),
            smartStrmWebhookClientProvider.overrideWithValue(
                SmartStrmWebhookClient(MockClient((request) async {
              requests.add(jsonDecode(request.body) as Map<String, dynamic>);
              return http.Response('{"success":true}', 200);
            }))),
          ],
          child: MaterialApp(
              home: NetworkStorageEditorPage(
                  initial: initial.networkStorage,
                  section: is115
                      ? NetworkStorageEditorSection.cloud115
                      : NetworkStorageEditorSection.quark))));
      await tester.pumpAndSettle();
      final fields = tester
          .widgetList<SettingsTextInputField>(
              find.byType(SettingsTextInputField))
          .toList();
      final drive = is115 ? '115' : '夸克';
      final field = fields
          .singleWhere((field) => field.labelText == '$drive SmartStrm 任务名');
      field.controller.text = 'new-task';
      expect(
          fields.where((field) =>
              field.labelText == '${is115 ? '夸克' : '115'} SmartStrm 任务名'),
          isEmpty);
      await tester.pump(const Duration(seconds: 1));
      expect(repository.settings.networkStorage.smartStrmTaskName,
          is115 ? 'quark-task' : 'new-task');
      expect(repository.settings.networkStorage.cloud115SmartStrmTaskName,
          is115 ? 'new-task' : '115-task');
      await tester.ensureVisible(find.text('测试 $drive STRM 任务'));
      await tester.tap(find.text('测试 $drive STRM 任务'));
      await tester.pumpAndSettle();
      expect(requests.map((request) => request['task']), [
        {'name': 'new-task', 'storage_path': is115 ? '/115' : '/quark'},
      ]);
      await tester.ensureVisible(find.text('同步删除$drive目录'));
      await tester.tap(find.text('同步删除$drive目录'));
      await tester.pump(const Duration(seconds: 1));
      expect(repository.settings.networkStorage.syncDelete115Enabled, is115);
      expect(repository.settings.networkStorage.syncDeleteQuarkEnabled, !is115);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Shared STRM page only contains common configuration',
      (tester) async {
    final initial = SeedData.defaultSettings;
    await tester.pumpWidget(ProviderScope(
        overrides: [
          appSettingsRepositoryProvider
              .overrideWithValue(_MemorySettingsRepository(initial)),
          appSettingsProvider.overrideWithValue(initial),
        ],
        child: MaterialApp(
            home: NetworkStorageEditorPage(
                initial: initial.networkStorage,
                section: NetworkStorageEditorSection.smartStrm))));
    await tester.pumpAndSettle();
    expect(find.text('115 SmartStrm 任务名'), findsNothing);
    expect(find.text('测试 115 STRM 任务'), findsNothing);
    expect(find.text('夸克 SmartStrm 任务名'), findsNothing);
    expect(find.text('Webhook 地址'), findsOneWidget);
  });

  testWidgets('MPV setting auto-saves when system back immediately pops page',
      (tester) async {
    final initial = SeedData.defaultSettings.copyWith(
      playbackMpvDoubleTapToSeekEnabled: false,
    );
    final repository = _MemorySettingsRepository(initial);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsRepositoryProvider.overrideWithValue(repository),
          appSettingsProvider.overrideWithValue(initial),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const MpvSettingsPage(),
                  ),
                ),
                child: const Text('打开 MPV 设置'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('打开 MPV 设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('双击快进/快退'));
    await tester.pump();

    unawaited(tester.binding.handlePopRoute());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.text('打开 MPV 设置'), findsOneWidget);
    expect(find.text('保存修改？'), findsNothing);
    expect(repository.settings.playbackMpvDoubleTapToSeekEnabled, isTrue);
  });

  testWidgets('account editor flushes the latest text when page pops',
      (tester) async {
    final initial = SeedData.defaultSettings.copyWith(
      doubanAccount: const DoubanAccountConfig(enabled: false),
    );
    final repository = _MemorySettingsRepository(initial);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsRepositoryProvider.overrideWithValue(repository),
          appSettingsProvider.overrideWithValue(initial),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => DoubanAccountEditorPage(
                      initial: initial.doubanAccount,
                    ),
                  ),
                ),
                child: const Text('打开豆瓣设置'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('打开豆瓣设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(
      find.widgetWithText(TextField, 'Douban User ID'),
      'updated-user',
    );
    await tester.pump();

    unawaited(tester.binding.handlePopRoute());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.text('打开豆瓣设置'), findsOneWidget);
    expect(repository.settings.doubanAccount.userId, 'updated-user');
  });

  testWidgets('default subtitle and dual languages save immediately',
      (tester) async {
    final initial = SeedData.defaultSettings.copyWith(
      playbackDefaultSubtitle: PlaybackDefaultSubtitle.systemLanguage,
    );
    final repository = _MemorySettingsRepository(initial);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsRepositoryProvider.overrideWithValue(repository),
          appSettingsProvider.overrideWithValue(initial),
        ],
        child: const MaterialApp(home: SubtitleSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('默认字幕'));
    await tester.pumpAndSettle();

    for (final label in const [
      '双字幕',
      '简体中文',
      '繁体中文',
      '英语',
      '日语',
      '系统语言',
    ]) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.text('双字幕'));
    await tester.pumpAndSettle();

    expect(
      repository.settings.playbackDefaultSubtitle,
      PlaybackDefaultSubtitle.dual,
    );
    expect(find.text('双字幕主字幕语言'), findsOneWidget);
    expect(find.text('双字幕副字幕语言'), findsOneWidget);

    await tester.tap(find.text('双字幕主字幕语言'));
    await tester.pumpAndSettle();
    expect(find.text('韩语'), findsNothing);
    await tester.tap(find.text('日语'));
    await tester.pumpAndSettle();

    expect(
      repository.settings.playbackDualSubtitlePrimaryLanguage,
      PlaybackSubtitleLanguage.japanese,
    );
  });
}

class _MemorySettingsRepository implements AppSettingsRepository {
  _MemorySettingsRepository(this.settings);

  AppSettings settings;

  @override
  Future<AppSettings> load() async => settings;

  @override
  Future<void> save(AppSettings settings) async {
    this.settings = settings;
  }
}
