import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/widgets/media_poster_tile.dart';
import 'package:starflow/features/home/presentation/home_page.dart';

void main() {
  test('hero prefetch retries on startup boundary', () {
    const decision = HomeHeroPrefetchDecision(
      shouldSchedule: true,
      forceMetadataRefresh: true,
    );
    expect(
      resolveHomeHeroPrefetchDecision(
        isPageVisible: true,
        featuredItemCount: 5,
        heroListChanged: true,
        scheduledMetadataRevision: 0,
        currentMetadataRevision: 1,
        scheduledExplicitRevision: 0,
        currentExplicitRevision: 0,
      ).shouldSchedule,
      decision.shouldSchedule,
    );
    expect(
      resolveHomeHeroPrefetchDecision(
        isPageVisible: true,
        featuredItemCount: 5,
        heroListChanged: true,
        scheduledMetadataRevision: 0,
        currentMetadataRevision: 1,
        scheduledExplicitRevision: 0,
        currentExplicitRevision: 0,
      ).forceMetadataRefresh,
      decision.forceMetadataRefresh,
    );
  });

  test('hero prefetch retries on explicit refresh boundary', () {
    final decision = resolveHomeHeroPrefetchDecision(
      isPageVisible: true,
      featuredItemCount: 5,
      heroListChanged: false,
      scheduledMetadataRevision: 1,
      currentMetadataRevision: 2,
      scheduledExplicitRevision: 0,
      currentExplicitRevision: 1,
    );
    expect(decision.shouldSchedule, isTrue);
    expect(decision.forceMetadataRefresh, isTrue);
  });

  test('hero prefetch stays idle when nothing changed', () {
    final decision = resolveHomeHeroPrefetchDecision(
      isPageVisible: true,
      featuredItemCount: 5,
      heroListChanged: false,
      scheduledMetadataRevision: 2,
      currentMetadataRevision: 2,
      scheduledExplicitRevision: 1,
      currentExplicitRevision: 1,
    );
    expect(decision.shouldSchedule, isFalse);
    expect(decision.forceMetadataRefresh, isFalse);
  });

  testWidgets('hero backdrop animation is skipped in simplified mode',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HomeHeroBackdrop(
          imageUrl: '',
          translucentEffectsEnabled: true,
          simplifyVisualEffects: true,
        ),
      ),
    );
    expect(find.byType(AnimatedSwitcher), findsNothing);

    await tester.pumpWidget(
      const MaterialApp(
        home: HomeHeroBackdrop(
          imageUrl: '',
          translucentEffectsEnabled: true,
          simplifyVisualEffects: false,
        ),
      ),
    );
    expect(find.byType(AnimatedSwitcher), findsOne);
  });

  testWidgets('media poster placeholder avoids animated icon', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: MediaPosterTile(
              title: 'title',
              subtitle: 'subtitle',
              posterUrl: '',
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.movie_creation_outlined), findsNothing);
  });
}
