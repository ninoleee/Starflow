import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/data/app_settings_repository.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/douban_account_editor_page.dart';
import 'package:starflow/features/settings/presentation/mpv_settings_page.dart';
import 'package:starflow/features/settings/presentation/subtitle_settings_page.dart';

void main() {
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

  testWidgets('default subtitle exposes seven options and saves immediately',
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
      '韩语',
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
