import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/person_credits_page.dart';
import 'package:starflow/features/discovery/data/discovery_repository.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/home/presentation/home_module_collection_page.dart';
import 'package:starflow/features/library/application/library_cached_items.dart';
import 'package:starflow/features/library/domain/library_collection_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/presentation/library_collection_page.dart';
import 'package:starflow/features/library/presentation/library_resource_deletion.dart';
import 'package:starflow/features/library/presentation/widgets/library_paged_grid.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  testWidgets('TV resource deletion initially focuses cancel', (tester) async {
    final item = MediaItem(
      id: 'https://example.com/movie.mkv',
      title: 'Movie',
      overview: '',
      posterUrl: '',
      year: 2026,
      durationLabel: '',
      genres: const [],
      sourceId: 'nas',
      sourceName: 'NAS',
      sourceKind: MediaSourceKind.nas,
      streamUrl: '',
      addedAt: DateTime(2026),
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [isTelevisionProvider.overrideWith((ref) => true)],
      child: MaterialApp(
          home: Scaffold(
              body: Consumer(
        builder: (context, ref, _) => TextButton(
          onPressed: () => confirmLibraryResourceDeletion(context, ref, item),
          child: const Text('Delete'),
        ),
      ))),
    ));
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    final cancel = find.widgetWithText(StarflowButton, '取消');
    final focus = tester
        .widget<FocusableActionDetector>(find.descendant(
          of: cancel,
          matching: find.byType(FocusableActionDetector),
        ))
        .focusNode!;
    expect(focus.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  for (final fail in [false, true]) {
    for (final library in [false, true]) {
      testWidgets(
          'TV collection has focus during loading and empty/error: '
          'library=$library fail=$fail', (tester) async {
        final discovery = _Discovery();
        final pending = Completer<LibraryVisiblePageItemsResult>();
        await tester.pumpWidget(ProviderScope(
          overrides: [
            isTelevisionProvider.overrideWith((ref) => true),
            appSettingsProvider.overrideWithValue(AppSettings.fromJson({})),
            discoveryRepositoryProvider.overrideWithValue(discovery),
            libraryCollectionVisiblePageItemsProvider
                .overrideWith((ref, request) => pending.future),
          ],
          child: MaterialApp(
            home: library
                ? const LibraryCollectionPage(
                    target: LibraryCollectionTarget(
                    title: 'Collection',
                    sourceId: 'nas',
                    sourceName: 'NAS',
                    sourceKind: MediaSourceKind.nas,
                  ))
                : const HomeModuleCollectionPage(
                    module: HomeModuleConfig(
                    id: 'list',
                    type: HomeModuleType.doubanList,
                    title: 'Collection',
                    enabled: true,
                  )),
          ),
        ));
        await tester.pump();
        await tester.pump();
        final label =
            library ? 'library-collection-header' : 'home-module-header';
        expect(FocusManager.instance.primaryFocus?.debugLabel, label);
        if (library) {
          if (fail) {
            pending.completeError(StateError('unavailable'));
          } else {
            pending.complete(
                const LibraryVisiblePageItemsResult(totalItems: 0, items: []));
          }
        } else {
          if (fail) {
            discovery.pending.completeError(StateError('unavailable'));
          } else {
            discovery.pending.complete([]);
          }
        }
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus?.debugLabel, label);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('TV person page has focus even without configured metadata',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        isTelevisionProvider.overrideWith((ref) => true),
        appSettingsProvider.overrideWithValue(AppSettings.fromJson({})),
      ],
      child: const MaterialApp(
          home: PersonCreditsPage(
        target: PersonCreditsPageTarget(
          person: MediaPersonProfile(name: 'Person'),
          role: PersonCreditsRole.actor,
        ),
      )),
    ));
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel,
        'person-credits-header');
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV library pager retains focus when reaching the final page',
      (tester) async {
    final page = ValueNotifier(0);
    addTearDown(page.dispose);
    var changes = 0;
    await tester.pumpWidget(ProviderScope(
      overrides: [isTelevisionProvider.overrideWith((ref) => true)],
      child: MaterialApp(
          home: Scaffold(
              body: ValueListenableBuilder<int>(
        valueListenable: page,
        builder: (_, current, child) => LibraryPagedGrid(
          pageItems: const [],
          totalItems: 48,
          currentPage: current,
          isTelevision: true,
          onPageChanged: (next) {
            changes++;
            page.value = next;
          },
        ),
      ))),
    ));
    await tester.pumpAndSettle();
    final action = find.byWidgetPredicate(
        (w) => w is TvFocusableAction && w.focusId == 'library:pager:top:next');
    final node = tester
        .widget<FocusableActionDetector>(find.descendant(
          of: action,
          matching: find.byType(FocusableActionDetector),
        ))
        .focusNode!;
    node.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(page.value, 1);
    expect(node.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(changes, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(node.hasPrimaryFocus, isFalse);
    expect(hasActionableTvFocus(), isTrue);
  });
}

class _Discovery implements DiscoveryRepository {
  final pending = Completer<List<DoubanEntry>>();
  @override
  Future<List<DoubanEntry>> fetchEntries(HomeModuleConfig module,
          {int page = 1, int? pageSize}) =>
      pending.future;
  @override
  Future<List<DoubanCarouselEntry>> fetchCarouselItems() async => [];
}
