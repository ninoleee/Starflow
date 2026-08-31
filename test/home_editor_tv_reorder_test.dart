import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/home/presentation/home_editor_page.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  testWidgets('TV home editor exposes boundary-safe module move buttons',
      (tester) async {
    final settings = SeedData.defaultSettings.copyWith(
      homeModules: const [
        HomeModuleConfig(
          id: HomeModuleConfig.heroModuleId,
          type: HomeModuleType.hero,
          title: 'Hero',
          enabled: true,
        ),
        HomeModuleConfig(
          id: 'module-a',
          type: HomeModuleType.recentlyAdded,
          title: 'A',
          enabled: true,
        ),
        HomeModuleConfig(
          id: 'module-b',
          type: HomeModuleType.recentPlayback,
          title: 'B',
          enabled: true,
        ),
        HomeModuleConfig(
          id: 'module-c',
          type: HomeModuleType.doubanList,
          title: 'C',
          enabled: true,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          appSettingsProvider.overrideWithValue(settings),
          homeEditorCollectionsProvider.overrideWith((ref) async => []),
        ],
        child: const MaterialApp(
          home: HomeEditorPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final buttons = tester
        .widgetList<StarflowIconButton>(find.byType(StarflowIconButton))
        .toList();
    final upButtons = buttons
        .where((button) => button.icon == Icons.arrow_upward_rounded)
        .toList();
    final downButtons = buttons
        .where((button) => button.icon == Icons.arrow_downward_rounded)
        .toList();

    expect(upButtons.length, 3);
    expect(downButtons.length, 3);
    expect(upButtons.first.onPressed, isNull);
    expect(downButtons.last.onPressed, isNull);
    expect(upButtons.last.onPressed, isNotNull);
    expect(downButtons.first.onPressed, isNotNull);
  });

  testWidgets('home editor offers the full NAS root without collections',
      (tester) async {
    final settings = SeedData.defaultSettings.copyWith(
      mediaSources: const [
        MediaSourceConfig(
          id: 'nas-main',
          name: '家庭 NAS',
          kind: MediaSourceKind.nas,
          endpoint: 'https://nas.example.com/dav/',
          enabled: true,
        ),
      ],
      homeModules: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => false),
          appSettingsProvider.overrideWithValue(settings),
          homeEditorCollectionsProvider.overrideWith((ref) async => []),
        ],
        child: const MaterialApp(home: HomeEditorPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('家庭 NAS'));
    await tester.pumpAndSettle();

    expect(find.text('全部内容'), findsOneWidget);
  });
}
