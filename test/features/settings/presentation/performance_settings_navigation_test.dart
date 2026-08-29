import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/interface_settings_page.dart';
import 'package:starflow/features/settings/presentation/metadata_match_settings_page.dart';
import 'package:starflow/features/settings/presentation/mpv_settings_page.dart';
import 'package:starflow/features/settings/presentation/task_scheduling_settings_page.dart';

void main() {
  testWidgets('TV split setting categories expose their own initial focus',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpPage(tester, const InterfaceSettingsPage());
    expect(find.text('界面效果'), findsOneWidget);
    expect(find.text('简化界面特效'), findsOneWidget);
    expect(
      _focusAction(
        tester,
        'performance-interface:simplified-effects',
      ).focusNode!.hasFocus,
      isTrue,
    );

    expect(find.text('单击首页时清理后台任务'), findsOneWidget);

    await _pumpPage(tester, const MpvSettingsPage());
    expect(find.text('MPV'), findsOneWidget);
    expect(find.text('激进性能调优'), findsOneWidget);
    expect(find.text('自动匹配本地资源'), findsNothing);
    expect(
      _focusAction(
        tester,
        'mpv-settings:double-tap-seek',
      ).focusNode!.hasFocus,
      isTrue,
    );

    await _pumpPage(tester, const TaskSchedulingSettingsPage());
    expect(find.text('启动时自动刷新首页'), findsOneWidget);
    expect(find.text('自动更新卡片信息'), findsNothing);
    expect(
      _focusAction(
        tester,
        'performance-background:startup-refresh',
      ).focusNode!.hasFocus,
      isTrue,
    );

    await _pumpPage(tester, const MetadataMatchSettingsPage());
    expect(find.text('自动匹配本地资源'), findsOneWidget);
    expect(
      _focusAction(tester, 'metadata-match:auto-library-match')
          .focusNode!
          .hasFocus,
      isTrue,
    );
  });
}

Future<void> _pumpPage(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isTelevisionProvider.overrideWith((ref) => true),
        appSettingsProvider.overrideWithValue(_settings),
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

const _settings = AppSettings(
  mediaSources: <MediaSourceConfig>[],
  searchProviders: <SearchProviderConfig>[],
  doubanAccount: DoubanAccountConfig(enabled: false),
  homeModules: <HomeModuleConfig>[],
);
