import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/home/application/home_controller.dart';
import 'package:starflow/features/home/application/home_metadata_auto_refresh.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  for (final fromWidget in [true, false]) {
    testWidgets(
        'home refresh dispatch has no artificial wait (widget=$fromWidget)',
        (tester) async {
      late WidgetRef widgetRef;
      final refProvider = Provider<Ref>((ref) => ref);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          homeEnabledModulesProvider
              .overrideWithValue(const <HomeModuleConfig>[]),
        ],
        child: Consumer(builder: (context, ref, _) {
          widgetRef = ref;
          return const SizedBox.shrink();
        }),
      ));
      final container =
          ProviderScope.containerOf(tester.element(find.byType(Consumer)));
      final controller = container.read(homePageControllerProvider);
      final beforeExplicit =
          container.read(homeExplicitRefreshRevisionProvider);
      final beforeMetadata =
          container.read(homeMetadataAutoRefreshRevisionProvider);
      var completed = false;
      final future = fromWidget
          ? controller.refreshModules(widgetRef)
          : controller.refreshModulesFromRef(container.read(refProvider));
      future.then((_) => completed = true);
      await tester.pump();
      expect(completed, isTrue);
      expect(container.read(homeExplicitRefreshRevisionProvider),
          beforeExplicit + 1);
      expect(container.read(homeMetadataAutoRefreshRevisionProvider),
          beforeMetadata + 1);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
