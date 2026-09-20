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

void main() {
  for (final adaptive in [false, true]) {
    for (final keepFocusable in [false, true]) {
      testWidgets('busy text button focus: adaptive=$adaptive keep=$keepFocusable',
          (tester) async {
        final node = FocusNode();
        final busy = ValueNotifier(false);
        addTearDown(node.dispose);
        addTearDown(busy.dispose);
        var activations = 0;
        await tester.pumpWidget(ProviderScope(
          overrides: [
            isTelevisionProvider.overrideWith((ref) => true),
            appSettingsProvider.overrideWithValue(const AppSettings(
              mediaSources: [], searchProviders: [], homeModules: [],
              doubanAccount: DoubanAccountConfig(enabled: false),
            )),
          ],
          child: MaterialApp(home: Scaffold(body: ValueListenableBuilder<bool>(
            valueListenable: busy,
            builder: (context, disabled, child) => adaptive
                ? TvAdaptiveButton(
                    label: 'Action', icon: Icons.refresh,
                    focusNode: node, focusableWhenDisabled: keepFocusable,
                    onPressed: disabled ? null : () => activations++,
                  )
                : StarflowButton(
                    label: 'Action', loading: disabled,
                    focusNode: node, focusableWhenDisabled: keepFocusable,
                    onPressed: () => activations++,
                  ),
          ))),
        ));
        await tester.pumpAndSettle();
        node.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(activations, 1);
        busy.value = true;
        await tester.pump();
        await tester.pump();
        expect(node.hasPrimaryFocus, keepFocusable);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(activations, 1);
        busy.value = false;
        await tester.pumpAndSettle();
        node.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(activations, 2);
      });
    }
  }

  for (final keepFocusable in [false, true]) {
    testWidgets('disabled icon button focus opt-in: $keepFocusable',
        (tester) async {
      final node = FocusNode(debugLabel: 'busy-icon');
      final busy = ValueNotifier(false);
      addTearDown(node.dispose);
      addTearDown(busy.dispose);
      var activations = 0;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          appSettingsProvider.overrideWithValue(const AppSettings(
            mediaSources: [],
            searchProviders: [],
            doubanAccount: DoubanAccountConfig(enabled: false),
            homeModules: [],
          )),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: ValueListenableBuilder<bool>(
          valueListenable: busy,
          builder: (context, disabled, child) => StarflowIconButton(
            icon: Icons.sync,
            focusNode: node,
            focusableWhenDisabled: keepFocusable,
            onPressed: disabled ? null : () => activations++,
          ),
        ))),
      ));
      await tester.pumpAndSettle();
      node.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      expect(activations, 1);
      busy.value = true;
      await tester.pumpAndSettle();
      expect(node.hasPrimaryFocus, keepFocusable);
      expect(node.canRequestFocus, keepFocusable);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(activations, 1);
      expect(
          tester
              .widget<StarflowIconButton>(find.byType(StarflowIconButton))
              .onPressed,
          isNull);
      busy.value = false;
      await tester.pumpAndSettle();
      expect(node.canRequestFocus, isTrue);
      if (keepFocusable) expect(node.hasPrimaryFocus, isTrue);
      node.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      expect(activations, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('unlaid-out page candidate does not trigger the left boundary',
      (tester) async {
    final current = FocusNode();
    final candidate = _UnlaidOutFocusNode();
    addTearDown(current.dispose);
    addTearDown(candidate.dispose);
    var menuRequests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TvPageFocusScope(
          isTelevision: true,
          onMoveLeftOut: () => menuRequests += 1,
          child: Row(
            children: [
              Focus(
                focusNode: candidate,
                child: const SizedBox(width: 20, height: 20),
              ),
              Focus(
                focusNode: current,
                child: const SizedBox(width: 20, height: 20),
              ),
            ],
          ),
        ),
      ),
    );
    current.requestFocus();
    await tester.pump();
    candidate.unlaidOut = true;

    Actions.invoke(
      current.context!,
      const DirectionalFocusIntent(TraversalDirection.left),
    );
    await tester.pump();
    expect(menuRequests, 0);
    expect(current.hasPrimaryFocus, isTrue);

    candidate.unlaidOut = false;
    Actions.invoke(
      current.context!,
      const DirectionalFocusIntent(TraversalDirection.left),
    );
    await tester.pump();
    expect(candidate.hasPrimaryFocus, isTrue);
  });

  testWidgets('page boundary protects nested default traversal groups',
      (tester) async {
    final current = _ThrowingDirectionalFocusNode(
      StateError('RenderBox was not laid out: nested candidate'),
    );
    addTearDown(current.dispose);
    var menuRequests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TvPageFocusScope(
          isTelevision: true,
          onMoveLeftOut: () => menuRequests += 1,
          child: FocusTraversalGroup(
            child: Focus(
              focusNode: current,
              child: const SizedBox(width: 20, height: 20),
            ),
          ),
        ),
      ),
    );
    current.requestFocus();
    await tester.pump();

    expect(
      () => Actions.invoke(
        current.context!,
        const DirectionalFocusIntent(TraversalDirection.left),
      ),
      returnsNormally,
    );
    expect(menuRequests, 0);
    expect(current.hasPrimaryFocus, isTrue);
  });

  testWidgets('TV page scope installs the safe traversal policy',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: TvPageFocusScope(
          isTelevision: true,
          child: SizedBox(),
        ),
      ),
    );

    final groupFinder = find.byWidgetPredicate(
      (widget) =>
          widget is FocusTraversalGroup &&
          widget.policy is TvSafeDirectionalFocusTraversalPolicy,
    );
    expect(groupFinder, findsOneWidget);
    final group = tester.widget<FocusTraversalGroup>(groupFinder);
    expect(group.policy, isA<TvSafeDirectionalFocusTraversalPolicy>());
  });

  testWidgets('safe directional action ignores only an unlaid-out render box',
      (tester) async {
    final focusNode = _ThrowingDirectionalFocusNode(
      StateError('Bad state: RenderBox was not laid out: test'),
    );
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Focus(
          focusNode: focusNode,
          child: const SizedBox(width: 10, height: 10),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();

    expect(
      () => TvSafeDirectionalFocusAction().invoke(
        const DirectionalFocusIntent(TraversalDirection.down),
      ),
      returnsNormally,
    );
    expect(focusNode.hasPrimaryFocus, isTrue);
  });

  testWidgets('unlaid-out directional warnings are rate limited',
      (tester) async {
    final focusNode = _ThrowingDirectionalFocusNode(
      StateError('Bad state: RenderBox was not laid out: test'),
    );
    addTearDown(focusNode.dispose);
    var now = DateTime(2026, 8, 29, 22, 0);
    var warningCount = 0;
    final action = TvSafeDirectionalFocusAction(
      now: () => now,
      onIgnoredUnlaidOutCandidate: (direction, focus, error) {
        warningCount += 1;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Focus(
          focusNode: focusNode,
          child: const SizedBox(width: 10, height: 10),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();

    action.invoke(
      const DirectionalFocusIntent(TraversalDirection.left),
    );
    now = now.add(const Duration(seconds: 1));
    action.invoke(
      const DirectionalFocusIntent(TraversalDirection.down),
    );
    now = now.add(const Duration(seconds: 4));
    action.invoke(
      const DirectionalFocusIntent(TraversalDirection.right),
    );

    expect(warningCount, 2);
  });

  testWidgets('safe directional action rethrows unrelated state errors',
      (tester) async {
    final focusNode = _ThrowingDirectionalFocusNode(
      StateError('unrelated focus failure'),
    );
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Focus(
          focusNode: focusNode,
          child: const SizedBox(width: 10, height: 10),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();

    expect(
      () => TvSafeDirectionalFocusAction().invoke(
        const DirectionalFocusIntent(TraversalDirection.down),
      ),
      throwsStateError,
    );
  });

  testWidgets('StarflowChipButton keeps unified mobile geometry and selection',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => false),
        ],
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: Center(
              child: StarflowChipButton(
                key: const ValueKey<String>('unified-chip'),
                label: '媒体库',
                selected: true,
                onPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey<String>('unified-chip'))).height,
      50,
    );
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
  });

  for (final television in [false, true]) {
    for (final textScale in [1.0, 2.0]) {
      for (final hasIcon in [false, true]) {
        testWidgets(
            'chip height stays stable across selection and focus: '
            'TV=$television scale=$textScale icon=$hasIcon', (tester) async {
          final focus = FocusNode();
          final selected = ValueNotifier(false);
          addTearDown(focus.dispose);
          addTearDown(selected.dispose);
          late double minimumHeight;
          await tester.pumpWidget(ProviderScope(
            overrides: [
              isTelevisionProvider.overrideWith((ref) => television),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(
                    textScaler: TextScaler.linear(textScale),
                  ),
                  child: Center(
                    child: Builder(builder: (context) {
                      minimumHeight = StarflowChipButton.minimumHeight(context);
                      return ValueListenableBuilder<bool>(
                        valueListenable: selected,
                        builder: (context, value, child) => StarflowChipButton(
                          label: 'Library',
                          selected: value,
                          icon: hasIcon ? Icons.video_library : null,
                          focusNode: focus,
                          onPressed: () => selected.value = !selected.value,
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
          ));
          await tester.pumpAndSettle();
          final chip = find.byType(StarflowChipButton);
          final initialHeight = tester.getSize(chip).height;
          expect(initialHeight, minimumHeight);
          if (textScale == 1) {
            expect(initialHeight, 50);
          } else {
            expect(initialHeight, greaterThan(50));
          }
          await tester.tap(chip);
          await tester.pumpAndSettle();
          expect(selected.value, isTrue);
          expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
          expect(find.byIcon(Icons.video_library),
              hasIcon ? findsOneWidget : findsNothing);
          expect(tester.getSize(chip).height, initialHeight);
          if (television) {
            expect(focus.hasPrimaryFocus, isTrue);
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          } else {
            await tester.tap(chip);
          }
          await tester.pumpAndSettle();
          expect(selected.value, isFalse);
          expect(tester.getSize(chip).height, initialHeight);
          focus.unfocus();
          await tester.pumpAndSettle();
          expect(tester.getSize(chip).height, initialHeight);
          final bounds = tester.getRect(chip);
          final textBounds = tester.getRect(find.text('Library'));
          expect(textBounds.top, greaterThanOrEqualTo(bounds.top));
          expect(textBounds.bottom, lessThanOrEqualTo(bounds.bottom));
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('StarflowButton reports TV focus', (tester) async {
    final focusNode = FocusNode(debugLabel: 'test-starflow-button');
    var focusedCount = 0;
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          appSettingsProvider.overrideWithValue(
            const AppSettings(
              mediaSources: <MediaSourceConfig>[],
              searchProviders: <SearchProviderConfig>[],
              doubanAccount: DoubanAccountConfig(enabled: false),
              homeModules: <HomeModuleConfig>[],
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: StarflowButton(
              label: '确认',
              focusNode: focusNode,
              onFocused: () => focusedCount += 1,
              onPressed: () {},
            ),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();

    expect(focusedCount, 1);
  });
}

class _ThrowingDirectionalFocusNode extends FocusNode {
  _ThrowingDirectionalFocusNode(this.error);

  final StateError error;

  @override
  bool focusInDirection(TraversalDirection direction) {
    throw error;
  }
}

class _UnlaidOutFocusNode extends FocusNode {
  bool unlaidOut = false;

  @override
  Rect get rect {
    if (unlaidOut) {
      throw StateError('RenderBox was not laid out: test candidate');
    }
    return super.rect;
  }
}
