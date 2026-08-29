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

void main() {
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
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
  });

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
