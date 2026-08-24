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

void main() {
  testWidgets('TV content directories expose a visible initial focus',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpSettingsPage(tester, const MediaSourceSettingsPage());
    expect(find.text('媒体源管理'), findsOneWidget);
    expect(
      _focusAction(tester, 'media-sources:match-sources').focusNode!.hasFocus,
      isTrue,
    );

    await _pumpSettingsPage(tester, const SearchServiceSettingsPage());
    expect(find.text('搜索服务管理'), findsOneWidget);
    expect(
      _focusAction(tester, 'search-services:sources').focusNode!.hasFocus,
      isTrue,
    );
  });

  testWidgets('TV network storage directory opens focused scoped editors',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpSettingsPage(tester, const NetworkStorageSettingsPage());
    expect(find.text('夸克云盘'), findsOneWidget);
    expect(find.text('SmartStrm'), findsOneWidget);
    expect(find.text('同步与索引刷新'), findsOneWidget);
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
}

Future<void> _pumpSettingsPage(WidgetTester tester, Widget page) async {
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
