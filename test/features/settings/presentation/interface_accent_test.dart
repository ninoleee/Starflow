import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/app/theme/app_colors.dart';
import 'package:starflow/app/theme/app_theme.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/data/app_settings_repository.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/interface_settings_page.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    testWidgets('accent picker persists and updates the theme at $size',
        (tester) async {
      final repository = await _pump(tester, size: size);
      for (final accent in AppAccent.values) {
        await tester.tap(find.text('强调色'));
        await tester.pumpAndSettle();
        expect(find.byType(SimpleDialog), findsOneWidget);
        for (final option in AppAccent.values) {
          expect(
            find.descendant(
              of: find.byType(SimpleDialog),
              matching: find.text(option.label),
            ),
            findsOneWidget,
          );
        }
        await tester.tap(find.descendant(
          of: find.byType(SimpleDialog),
          matching: find.text(accent.label),
        ));
        await tester.pumpAndSettle();
        expect(find.byType(SimpleDialog), findsNothing);
        expect(repository.settings.appAccent, accent);
        final theme = Theme.of(
          tester.element(find.byType(InterfaceSettingsPage)),
        );
        expect(AppActionColors.of(theme).primary, accent.primary);
        expect(theme.colorScheme.surface, AppColors.neutral1);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.text('强调色'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(repository.settings.appAccent, AppAccent.values.last);
    });
  }

  testWidgets('TV picker supports directional selection', (tester) async {
    final repository = await _pump(
      tester,
      size: const Size(1920, 1080),
      television: true,
    );
    final entry = tester
        .widgetList<TvFocusableAction>(find.byType(TvFocusableAction))
        .singleWhere((widget) => widget.focusId == 'interface:accent');
    entry.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(SimpleDialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(repository.settings.appAccent, AppAccent.indigo);
    expect(find.byType(SimpleDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<_Repository> _pump(
  WidgetTester tester, {
  required Size size,
  bool television = false,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final repository = _Repository();
  final container = ProviderContainer(overrides: [
    appSettingsRepositoryProvider.overrideWithValue(repository),
    isTelevisionProvider.overrideWith((ref) => television),
  ]);
  addTearDown(container.dispose);
  await container.read(settingsControllerProvider.future);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: Consumer(builder: (context, ref, child) {
      final accent = ref.watch(
        appSettingsProvider.select((settings) => settings.appAccent),
      );
      return MaterialApp(
        theme: AppTheme.dark(accent: accent),
        home: const InterfaceSettingsPage(),
      );
    }),
  ));
  await tester.pumpAndSettle();
  return repository;
}

class _Repository implements AppSettingsRepository {
  AppSettings settings = SeedData.defaultSettings;

  @override
  Future<AppSettings> load() async => settings;

  @override
  Future<void> save(AppSettings settings) async {
    this.settings = AppSettings.fromJson(settings.toJson());
  }
}
