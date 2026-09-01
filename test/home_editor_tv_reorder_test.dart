import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
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
    final heroToggle = tester
        .widgetList<StarflowButton>(find.byType(StarflowButton))
        .singleWhere(
          (button) =>
              button.focusId ==
              'home-editor:${HomeModuleConfig.heroModuleId}:toggle',
        );
    expect(heroToggle.focusNode?.hasPrimaryFocus, isTrue);
  });

  testWidgets('TV home editor keeps focus on reorder and recovers after remove',
      (tester) async {
    final settingsProvider = StateProvider<AppSettings>((ref) {
      return SeedData.defaultSettings.copyWith(
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
        ],
      );
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          appSettingsProvider.overrideWith(
            (ref) => ref.watch(settingsProvider),
          ),
          homeEditorCollectionsProvider.overrideWith((ref) async => []),
        ],
        child: const MaterialApp(home: HomeEditorPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    StarflowButton toggle(String moduleId) => tester
        .widgetList<StarflowButton>(find.byType(StarflowButton))
        .singleWhere(
          (button) => button.focusId == 'home-editor:$moduleId:toggle',
        );

    final moduleBToggle = toggle('module-b');
    moduleBToggle.focusNode!.requestFocus();
    await tester.pump();
    expect(moduleBToggle.focusNode?.hasPrimaryFocus, isTrue);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeEditorPage)),
    );
    final current = container.read(settingsProvider);
    container.read(settingsProvider.notifier).state = current.copyWith(
      homeModules: const [
        HomeModuleConfig(
          id: HomeModuleConfig.heroModuleId,
          type: HomeModuleType.hero,
          title: 'Hero',
          enabled: true,
        ),
        HomeModuleConfig(
          id: 'module-b',
          type: HomeModuleType.recentPlayback,
          title: 'B',
          enabled: true,
        ),
        HomeModuleConfig(
          id: 'module-a',
          type: HomeModuleType.recentlyAdded,
          title: 'A',
          enabled: true,
        ),
      ],
    );
    await tester.pump();
    await tester.pump();
    expect(moduleBToggle.focusNode?.hasPrimaryFocus, isTrue);

    container.read(settingsProvider.notifier).state = current.copyWith(
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
      ],
    );
    await tester.pump();
    await tester.pump();

    expect(
      toggle(HomeModuleConfig.heroModuleId).focusNode?.hasPrimaryFocus,
      isTrue,
    );
  });

  testWidgets('TV home editor leaves a move button that becomes disabled',
      (tester) async {
    final settingsProvider = StateProvider<AppSettings>((ref) {
      return SeedData.defaultSettings.copyWith(
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
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          appSettingsProvider.overrideWith(
            (ref) => ref.watch(settingsProvider),
          ),
          homeEditorCollectionsProvider.overrideWith((ref) async => []),
        ],
        child: const MaterialApp(home: HomeEditorPage()),
      ),
    );
    await tester.pumpAndSettle();

    final moveDown = tester.widget<TvFocusableAction>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TvFocusableAction &&
            widget.focusId == 'home-editor:module-b:move-down',
      ),
    );
    moveDown.focusNode!.requestFocus();
    await tester.pump();
    expect(moveDown.focusNode?.hasPrimaryFocus, isTrue);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeEditorPage)),
    );
    final current = container.read(settingsProvider);
    container.read(settingsProvider.notifier).state = current.copyWith(
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
          id: 'module-c',
          type: HomeModuleType.doubanList,
          title: 'C',
          enabled: true,
        ),
        HomeModuleConfig(
          id: 'module-b',
          type: HomeModuleType.recentPlayback,
          title: 'B',
          enabled: true,
        ),
      ],
    );
    await tester.pumpAndSettle();

    final moduleBToggle = tester
        .widgetList<StarflowButton>(find.byType(StarflowButton))
        .singleWhere(
          (button) => button.focusId == 'home-editor:module-b:toggle',
        );
    expect(moduleBToggle.focusNode?.hasPrimaryFocus, isTrue);
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

  testWidgets('home editor exposes per-module display style', (tester) async {
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
          title: '最近新增',
          enabled: true,
        ),
      ],
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

    expect(find.text('竖版海报'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    expect(find.text('展示样式'), findsOneWidget);
    expect(find.text('竖版海报'), findsAtLeastNWidgets(1));
  });

  testWidgets('TV home editor restores focus after a module sheet closes',
      (tester) async {
    final settings = SeedData.defaultSettings.copyWith(
      homeModules: const [
        HomeModuleConfig(
          id: HomeModuleConfig.heroModuleId,
          type: HomeModuleType.hero,
          title: 'Hero',
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
        child: const MaterialApp(home: HomeEditorPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    final heroToggle = tester
        .widgetList<StarflowButton>(find.byType(StarflowButton))
        .singleWhere(
          (button) =>
              button.focusId ==
              'home-editor:${HomeModuleConfig.heroModuleId}:toggle',
        );
    heroToggle.focusNode!.requestFocus();
    await tester.pump();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('选择来源分类'), findsOneWidget);
    final sourceSheetAction = tester.widget<TvFocusableAction>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TvFocusableAction &&
            widget.focusId == 'home-editor:add:内置',
      ),
    );
    expect(sourceSheetAction.focusNode?.hasPrimaryFocus, isTrue);

    sourceSheetAction.onPressed!.call();
    await tester.pumpAndSettle();
    final firstSheetAction = tester.widget<TvFocusableAction>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TvFocusableAction &&
            widget.focusId == 'home-editor:add:最近新增',
      ),
    );
    expect(firstSheetAction.focusNode?.hasPrimaryFocus, isTrue);

    Navigator.of(tester.element(find.text('内置模块'))).pop();
    await tester.pumpAndSettle();

    expect(heroToggle.focusNode?.hasPrimaryFocus, isTrue);
  });
}
