import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/data/app_settings_repository.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/home_settings_page.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';

void main() {
  for (final television in [false, true]) {
    testWidgets('auto play setting can be toggled, TV=$television',
        (tester) async {
      final repository = _Repository();
      final container = ProviderContainer(overrides: [
        appSettingsRepositoryProvider.overrideWithValue(repository),
        isTelevisionProvider.overrideWith((ref) => television),
      ]);
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.future);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeSettingsPage()),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Hero 自动轮播'), findsOneWidget);
      if (television) {
        final action = tester
            .widgetList<TvFocusableAction>(
              find.byType(TvFocusableAction),
            )
            .singleWhere(
                (widget) => widget.focusId == 'home-settings:hero-auto-play');
        action.focusNode!.requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      } else {
        await tester.tap(find.text('Hero 自动轮播'));
      }
      await tester.pumpAndSettle();
      expect(repository.settings.homeHeroAutoPlayEnabled, isTrue);
      final controller = container.read(settingsControllerProvider.notifier);
      await controller.setHomeHeroEnabled(false);
      await tester.pumpAndSettle();
      final tile = tester
          .widgetList<SettingsToggleTile>(
            find.byType(SettingsToggleTile),
          )
          .singleWhere((widget) => widget.title == 'Hero 自动轮播');
      expect(tile.onChanged, isNull);
      expect(repository.settings.homeHeroAutoPlayEnabled, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}

class _Repository implements AppSettingsRepository {
  AppSettings settings = SeedData.defaultSettings.copyWith(homeModules: const [
    HomeModuleConfig(
        id: HomeModuleConfig.heroModuleId,
        type: HomeModuleType.hero,
        title: 'Hero',
        enabled: true),
  ]);

  @override
  Future<AppSettings> load() async => settings;

  @override
  Future<void> save(AppSettings value) async {
    settings = AppSettings.fromCurrentJson(value.toJson());
  }
}
