import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/media_poster_tile.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/discovery/data/douban_api_client.dart';
import 'package:starflow/features/discovery/data/douban_browse_repository.dart';
import 'package:starflow/features/discovery/domain/douban_browse_models.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/discovery/presentation/douban_browse_page.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

http.Response _page(int start,
        {int count = 20, int? total = 40, String prefix = ''}) =>
    http.Response.bytes(
        utf8.encode(jsonEncode({
          'items': [
            for (var i = start; i < start + count; i++)
              {
                'id': '$prefix$i',
                'title': '作品$prefix$i',
                'type': 'movie',
                'year': '2024',
                'card_subtitle': '2024 / 中国大陆 / 惊悚 / 犯罪',
                'rating': {'value': 8.6, 'count': 200},
              }
          ],
          if (total != null) 'total': total,
        })),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'});

DoubanBrowsePageData _data(int start, {String prefix = ''}) =>
    DoubanBrowsePageData(
      entries: [
        for (var i = start; i < start + 20; i++)
          DoubanEntry(
            id: '$prefix$i',
            title: '作品$prefix$i',
            year: 2024,
            posterUrl: '',
            note: '',
            ratingLabel: '豆瓣 8.6',
            ratingCount: 200,
            subjectType: 'movie',
          ),
      ],
      start: start,
      rawCount: 20,
      total: 40,
    );

class _ControlledBrowseRepository extends DoubanBrowseRepository {
  _ControlledBrowseRepository(this.handler)
      : super(DoubanApiClient(MockClient((_) async => _page(0))));

  final Future<DoubanBrowsePageData> Function(
      DoubanBrowseQuery query, int start) handler;

  @override
  Future<DoubanBrowsePageData> fetch(
    DoubanBrowseQuery query, {
    int start = 0,
    bool refresh = false,
  }) =>
      handler(query, start);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pumpAndSettle();
}

Future<void> _mount(WidgetTester tester, MockClient client,
    {bool tv = false,
    bool enabled = true,
    DoubanBrowseRepository? repository}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = tv ? const Size(1280, 720) : const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        appSettingsProvider.overrideWithValue(AppSettings(
          mediaSources: const [],
          searchProviders: const [],
          homeModules: const [],
          doubanAccount: DoubanAccountConfig(enabled: enabled),
        )),
        isTelevisionProvider.overrideWith((ref) => tv),
        if (repository == null)
          doubanApiClientProvider.overrideWithValue(DoubanApiClient(client))
        else
          doubanBrowseRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
          theme: ThemeData.dark(), home: const DoubanBrowsePage())));
  await _settle(tester);
}

ScrollController _scroll(WidgetTester tester) =>
    tester.widget<CustomScrollView>(find.byType(CustomScrollView)).controller!;

Future<void> _bottom(WidgetTester tester) async {
  final scroll = _scroll(tester);
  scroll.jumpTo(scroll.position.maxScrollExtent);
  await _settle(tester);
}

Finder _poster(int id, {String prefix = ''}) =>
    find.byKey(ValueKey('movie:$prefix$id'));

Future<void> _sort(WidgetTester tester, String label) async {
  _scroll(tester).jumpTo(0);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('douban-filter-sort')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await _settle(tester);
}

void main() {
  testWidgets('disabled discovery does not issue requests', (tester) async {
    var requests = 0;
    await _mount(tester, MockClient((_) async {
      requests++;
      return _page(0);
    }), enabled: false);
    expect(requests, 0);
    expect(find.text('豆瓣模块已关闭'), findsOneWidget);
  });

  testWidgets('poster shows numeric rating and no pagination controls',
      (tester) async {
    await _mount(tester, MockClient((_) async => _page(0, count: 1, total: 1)));
    final poster = tester.widget<MediaPosterTile>(_poster(0));
    expect(poster.imageBadgeText, '8.6');
    expect(poster.imageTopLeftBadgeText, '2024');
    expect(poster.imageTopRightBadgeText, '惊悚');
    expect(poster.imageBottomRightBadgeText, '☆200');
    expect(poster.subtitle, isEmpty);
    expect(find.byTooltip('上一页'), findsNothing);
    expect(find.byTooltip('下一页'), findsNothing);
    expect(find.text('已显示全部结果'), findsOneWidget);
    final current = find.byKey(const ValueKey('douban-floating-page-current'));
    final total = find.byKey(const ValueKey('douban-floating-page-total'));
    expect(tester.widget<Text>(current).data, '1');
    expect(tester.widget<Text>(total).data, '1');
    expect(tester.getCenter(current).dy, lessThan(tester.getCenter(total).dy));
    expect(tester.getRect(find.text('8.6')).right,
        lessThanOrEqualTo(tester.getRect(find.text('☆200')).left));
  });

  testWidgets(
      'scroll appends once, keeps earlier results, and stops at the end',
      (tester) async {
    final starts = <int>[];
    final second = Completer<http.Response>();
    await _mount(tester, MockClient((request) {
      final start = int.parse(request.url.queryParameters['start']!);
      starts.add(start);
      return start == 0 ? Future.value(_page(0)) : second.future;
    }));
    expect(starts, [0]);
    final scroll = _scroll(tester);
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    scroll.jumpTo(scroll.offset - 1);
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    expect(starts, [0, 20]);
    final offset = scroll.offset;
    second.complete(_page(20));
    await _settle(tester);
    expect(scroll.offset, closeTo(offset, 1));
    expect(starts, [0, 20]);
    expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('douban-floating-page-total')))
            .data,
        '2');
    await _bottom(tester);
    await _bottom(tester);
    expect(starts, [0, 20]);
    expect(_poster(39), findsOneWidget);
    expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('douban-floating-page-current')))
            .data,
        '2');
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(_poster(0), findsOneWidget);
    expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('douban-floating-page-current')))
            .data,
        '1');
    expect(
        tester.widgetList<MediaPosterTile>(find.byType(MediaPosterTile)).length,
        lessThan(40));
  });

  testWidgets('TV append preserves focused poster and down reaches new results',
      (tester) async {
    final second = Completer<http.Response>();
    final starts = <int>[];
    await _mount(tester, MockClient((request) {
      final start = int.parse(request.url.queryParameters['start']!);
      starts.add(start);
      return start == 0 ? Future.value(_page(0)) : second.future;
    }), tv: true);
    final scroll = _scroll(tester);
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    final node = tester.widget<MediaPosterTile>(_poster(19)).focusNode!;
    node.requestFocus();
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    expect(starts, [0, 20]);
    second.complete(_page(20));
    await _settle(tester);
    expect(node.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final focused = tester
        .widgetList<MediaPosterTile>(find.byType(MediaPosterTile))
        .singleWhere((tile) => tile.focusNode!.hasFocus);
    expect(int.parse(focused.title.replaceFirst('作品', '')),
        greaterThanOrEqualTo(20));
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV repeated poster down/up navigation retains focus',
      (tester) async {
    await _mount(tester, MockClient((_) async => _page(0, total: 20)),
        tv: true);
    final firstPoster = tester.widget<MediaPosterTile>(_poster(0)).focusNode!;
    firstPoster.requestFocus();
    await tester.pumpAndSettle();

    Future<void> arrow(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    int focusedPosterIndex() {
      final focusedTiles = tester
          .widgetList<MediaPosterTile>(find.byType(MediaPosterTile))
          .where((tile) => tile.focusNode!.hasPrimaryFocus)
          .toList(growable: false);
      if (focusedTiles.isEmpty) {
        final mountedTitles = tester
            .widgetList<MediaPosterTile>(find.byType(MediaPosterTile))
            .map((tile) => '${tile.title}[${tile.focusNode!.hasFocus}/'
                '${tile.focusNode!.hasPrimaryFocus}]')
            .join(',');
        fail(
          'No poster has primary focus. '
          'Current focus: ${FocusManager.instance.primaryFocus?.debugLabel} '
          '(${FocusManager.instance.primaryFocus?.runtimeType}); '
          'mounted: $mountedTitles; offset: ${_scroll(tester).offset}',
        );
      }
      return int.parse(
        focusedTiles.single.title.replaceFirst('作品', ''),
      );
    }

    await arrow(LogicalKeyboardKey.arrowDown);
    expect(focusedPosterIndex(), 8);
    await arrow(LogicalKeyboardKey.arrowDown);
    expect(focusedPosterIndex(), 16);

    await arrow(LogicalKeyboardKey.arrowUp);
    await arrow(LogicalKeyboardKey.arrowUp);
    expect(focusedPosterIndex(), 0);

    await arrow(LogicalKeyboardKey.arrowDown);
    expect(focusedPosterIndex(), 8);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'douban-poster-8');

    await arrow(LogicalKeyboardKey.arrowUp);
    expect(focusedPosterIndex(), 0);
    await arrow(LogicalKeyboardKey.arrowUp);
    expect(FocusManager.instance.primaryFocus, isNotNull);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      isNot(startsWith('douban-poster-')),
    );

    await arrow(LogicalKeyboardKey.arrowDown);
    expect(focusedPosterIndex(), 0);
    await arrow(LogicalKeyboardKey.arrowDown);
    expect(focusedPosterIndex(), 8);
    expect(tester.takeException(), isNull);
  });

  testWidgets('prefetches the next batch before the append threshold',
      (tester) async {
    final starts = <int>[];
    final second = Completer<http.Response>();
    await _mount(tester, MockClient((request) {
      final start = int.parse(request.url.queryParameters['start']!);
      starts.add(start);
      return start == 0 ? Future.value(_page(0)) : second.future;
    }));
    final scroll = _scroll(tester);
    scroll.jumpTo(
      scroll.position.maxScrollExtent -
          scroll.position.viewportDimension * 1.25,
    );
    await tester.pump();
    expect(starts, [0, 20]);
    expect(_poster(20), findsNothing);

    second.complete(_page(20));
    await _settle(tester);
    expect(_poster(20), findsNothing);

    await _bottom(tester);
    expect(starts, [0, 20]);
    expect(_poster(20), findsOneWidget);
  });

  testWidgets('overlap deduplicates and repeated batches stop auto loading',
      (tester) async {
    final starts = <int>[];
    await _mount(tester, MockClient((request) async {
      final start = int.parse(request.url.queryParameters['start']!);
      starts.add(start);
      return _page(start == 0 ? 0 : 19, total: 100);
    }));
    await _bottom(tester);
    await _bottom(tester);
    await _bottom(tester);
    expect(starts, [0, 20, 40]);
    expect(find.text('已显示全部结果'), findsOneWidget);
    expect(_poster(38), findsOneWidget);
  });

  testWidgets('empty batch stops and short first batch fills the viewport',
      (tester) async {
    final starts = <int>[];
    await _mount(tester, MockClient((request) async {
      final start = int.parse(request.url.queryParameters['start']!);
      starts.add(start);
      return start == 0
          ? _page(0, count: 1, total: 40)
          : _page(20, count: 0, total: 40);
    }));
    await _settle(tester);
    await _bottom(tester);
    expect(starts, [0, 20]);
    expect(_poster(0), findsOneWidget);
  });

  testWidgets('append failure retains results and retries the same offset',
      (tester) async {
    final starts = <int>[];
    await _mount(tester, MockClient((request) async {
      final start = int.parse(request.url.queryParameters['start']!);
      starts.add(start);
      if (start == 20 && starts.length == 2) {
        return http.Response('failure', 503);
      }
      return _page(start);
    }));
    await _bottom(tester);
    await _bottom(tester);
    expect(starts, [0, 20]);
    expect(find.textContaining('请求失败'), findsOneWidget);
    expect(_poster(19), findsOneWidget);
    await tester
        .ensureVisible(find.byKey(const ValueKey('douban-load-more-retry')));
    await tester.tap(find.byKey(const ValueKey('douban-load-more-retry')));
    await _settle(tester);
    expect(starts, [0, 20, 20]);
    _scroll(tester).jumpTo(0);
    await tester.pumpAndSettle();
    expect(_poster(0), findsOneWidget);
  });

  testWidgets('changing sort discards pending append and starts a fresh list',
      (tester) async {
    final oldAppend = Completer<DoubanBrowsePageData>();
    final requests = <String>[];
    final repository = _ControlledBrowseRepository((query, start) {
      final sort = query.sort.code;
      requests.add('$sort:$start');
      if (sort == 'S' && start == 20) return oldAppend.future;
      return Future.value(_data(start, prefix: sort));
    });
    await _mount(tester, MockClient((_) async => _page(0)),
        repository: repository);
    _scroll(tester).jumpTo(_scroll(tester).position.maxScrollExtent);
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    _scroll(tester).jumpTo(0);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('douban-filter-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('近期热度').last);
    await tester.pump();
    oldAppend.complete(_data(20, prefix: 'S'));
    await _settle(tester);
    expect(requests, ['S:0', 'S:20', 'U:0']);
    await _settle(tester);
    expect(_poster(0, prefix: 'U'), findsOneWidget);
    expect(_poster(20, prefix: 'S'), findsNothing);
    expect(_scroll(tester).offset, 0);
  });

  testWidgets('sort refreshes results and keeps selected label',
      (tester) async {
    final sorts = <String>[];
    await _mount(tester, MockClient((request) async {
      sorts.add(request.url.queryParameters['sort']!);
      return _page(0, count: 1, total: 1);
    }));
    await _sort(tester, '近期热度');
    expect(sorts, ['S', 'U']);
    expect(find.text('近期热度'), findsOneWidget);
  });

  testWidgets('TV sort menu enters on its currently selected item',
      (tester) async {
    final sorts = <String>[];
    await _mount(tester, MockClient((request) async {
      sorts.add(request.url.queryParameters['sort']!);
      return _page(0, count: 1, total: 1);
    }), tv: true);

    await tester.tap(find.byKey(const ValueKey('douban-filter-sort')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await _settle(tester);

    expect(sorts, ['S', 'R']);
  });

  testWidgets('year all clears selected year and reset restores defaults',
      (tester) async {
    final tags = <String>[];
    await _mount(tester, MockClient((request) async {
      tags.add(request.url.queryParameters['tags']!);
      return _page(0, count: 1, total: 1);
    }));
    await tester.tap(find.byKey(const ValueKey('douban-filter-year')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2024').last);
    await _settle(tester);
    expect(tags.last, contains('2024'));
    await tester.tap(find.byKey(const ValueKey('douban-filter-year')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('全部').last);
    await tester.tap(find.text('全部').last);
    await _settle(tester);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('douban-filter-year')),
            matching: find.text('年份')),
        findsOneWidget);
    await _sort(tester, '近期热度');
    await tester.tap(find.byTooltip('重置筛选'));
    await _settle(tester);
    expect(find.text('排序'), findsOneWidget);
  });

  testWidgets('series and variety use distinct genre menus', (tester) async {
    final tags = <String>[];
    await _mount(tester, MockClient((request) async {
      tags.add(request.url.queryParameters['tags']!);
      return _page(0, count: 0, total: 0);
    }));
    await tester.tap(find.text('电视剧'));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('douban-filter-genre')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('悬疑').last);
    await _settle(tester);
    expect(tags.last, '电视剧,悬疑');
    await tester.tap(find.text('综艺'));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('douban-filter-genre')));
    await tester.pumpAndSettle();
    expect(find.text('悬疑'), findsNothing);
    await tester.tap(find.text('真人秀').last);
    await _settle(tester);
    expect(tags.last, '综艺,真人秀');
  });

  testWidgets('TV filter controls retain visible focus and menu return',
      (tester) async {
    await _mount(tester, MockClient((_) async => _page(0, count: 1, total: 1)),
        tv: true);
    FocusNode node(String key) => Focus.of(tester.element(find
        .descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Icon))
        .first));
    void highlighted(String key, bool value) {
      final frame = tester.widget<AnimatedContainer>(find
          .ancestor(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(AnimatedContainer))
          .first);
      final border =
          (frame.foregroundDecoration! as BoxDecoration).border! as Border;
      expect(border.top.color, value ? Colors.white : Colors.transparent);
      expect(border.top.width, 2);
    }

    tester
        .widget<StarflowChipButton>(
            find.byKey(const ValueKey('douban-category-movie')))
        .focusNode!
        .requestFocus();
    await tester.pumpAndSettle();
    final categoryFrame = tester.widget<AnimatedContainer>(find
        .descendant(
            of: find.byKey(const ValueKey('douban-category-movie')),
            matching: find.byType(AnimatedContainer))
        .first);
    final categoryBorder =
        (categoryFrame.decoration! as BoxDecoration).border! as Border;
    expect(categoryBorder.top.color, Colors.white);
    expect(categoryBorder.top.width, 3);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(node('douban-filter-year').hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(node('douban-filter-sort').hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
        tester.widget<MediaPosterTile>(_poster(0)).focusNode!.hasFocus, isTrue);

    node('douban-filter-year').requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(node('douban-filter-region').hasPrimaryFocus, isTrue);
    highlighted('douban-filter-year', false);
    for (final key in [
      'douban-filter-year',
      'douban-filter-region',
      'douban-filter-genre',
      'douban-filter-rating',
      'douban-filter-sort',
      'douban-refresh',
      'douban-clear-filters'
    ]) {
      node(key).requestFocus();
      await tester.pumpAndSettle();
      highlighted(key, true);
    }
    node('douban-filter-year').requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<String>), findsWidgets);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(node('douban-filter-year').hasPrimaryFocus, isTrue);
    highlighted('douban-filter-year', true);
  });

  for (final mode in [
    (size: const Size(390, 844), tv: false, maxWidth: 260.0),
    (size: const Size(1280, 720), tv: true, maxWidth: 360.0),
  ]) {
    testWidgets('category tabs use compact left layout on ${mode.size}',
        (tester) async {
      await _mount(
        tester,
        MockClient((_) async => _page(0, count: 1, total: 1)),
        tv: mode.tv,
      );

      final group = find.byKey(const ValueKey('douban-category-tabs-group'));
      expect(tester.getSize(group).width, mode.maxWidth);
      expect(tester.getTopLeft(group).dx, kAppPageHorizontalPadding);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('douban-category-movie')))
            .height,
        lessThan(44),
      );
      for (final label in ['电影', '电视剧', '综艺']) {
        final tab = find.widgetWithText(StarflowChipButton, label);
        final labelFinder =
            find.descendant(of: tab, matching: find.text(label));
        expect(
          tester.getCenter(labelFinder).dx,
          closeTo(tester.getCenter(tab).dx, 0.1),
        );
      }
    });
  }
}
