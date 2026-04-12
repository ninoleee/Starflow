import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/widgets/media_poster_tile.dart';
import 'package:starflow/features/home/presentation/home_page.dart';

void main() {
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

  testWidgets('media poster placeholder avoids animated icon',
      (tester) async {
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
