import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/navigation/page_activity_mixin.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/utils/media_rating_labels.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/core/widgets/media_poster_tile.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/discovery/data/douban_api_client.dart';
import 'package:starflow/features/discovery/data/douban_browse_repository.dart';
import 'package:starflow/features/discovery/data/douban_network_guard.dart';
import 'package:starflow/features/discovery/domain/douban_browse_models.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/search/data/search_preferences_repository.dart';

class DoubanBrowsePage extends ConsumerStatefulWidget {
  const DoubanBrowsePage({
    super.key,
    this.topContent,
    this.scrollController,
  });

  final Widget? topContent;
  final ScrollController? scrollController;

  @override
  ConsumerState<DoubanBrowsePage> createState() => _DoubanBrowsePageState();
}

class _DoubanBrowsePageState extends ConsumerState<DoubanBrowsePage>
    with PageActivityMixin<DoubanBrowsePage> {
  DoubanBrowseQuery _query = const DoubanBrowseQuery();
  final _queries = <DoubanBrowseCategory, DoubanBrowseQuery>{};
  final _genres = <DoubanBrowseCategory, List<String>>{};
  final _regions = <DoubanBrowseCategory, List<String>>{};
  DoubanBrowsePageData? _page;
  int _generation = 0;
  Future<void>? _pendingLoad;
  bool _loading = false;
  bool _preferencesLoaded = false;
  bool _queryTouched = false;
  bool _enabled = false;
  bool _pageLimitReached = false;
  bool _hasMore = false;
  int? _prefetchStart;
  String? _error;
  late final ScrollController _scroll;
  late final bool _ownsScroll;
  final _posterFocusNodes = <FocusNode>[];
  final _gridKey = GlobalKey();
  int _posterColumns = 1;
  double _posterItemExtent = 0;
  int _currentVisiblePage = 1;
  bool _visiblePageUpdateScheduled = false;
  final _yearFocusTargetKey = GlobalKey();
  final _sortFocusTargetKey = GlobalKey();
  final _movieCategoryFocus = FocusNode(debugLabel: 'douban-category-movie');
  final _seriesCategoryFocus = FocusNode(debugLabel: 'douban-category-series');
  final _varietyCategoryFocus =
      FocusNode(debugLabel: 'douban-category-variety');

  @override
  void initState() {
    super.initState();
    _scroll = widget.scrollController ?? ScrollController();
    _ownsScroll = widget.scrollController == null;
    _scroll.addListener(_handleScroll);
    _restoreQuery();
  }

  Future<void> _restoreQuery() async {
    final repository = ref.read(searchPreferencesRepositoryProvider);
    final movie = await repository.loadBrowseQuery(DoubanBrowseCategory.movie);
    final series =
        await repository.loadBrowseQuery(DoubanBrowseCategory.series);
    final variety =
        await repository.loadBrowseQuery(DoubanBrowseCategory.variety);
    final lastType = await repository.loadBrowseType();
    if (!mounted || _preferencesLoaded) return;
    setState(() {
      _queries.putIfAbsent(DoubanBrowseCategory.movie, () => movie);
      _queries.putIfAbsent(DoubanBrowseCategory.series, () => series);
      _queries.putIfAbsent(DoubanBrowseCategory.variety, () => variety);
      if (!_queryTouched) {
        _query = _queries[lastType]!;
      }
      _preferencesLoaded = true;
    });
    if (isPageActive && _page == null && !_loading) unawaited(_scheduleLoad(0));
  }

  @override
  void dispose() {
    _generation++;
    _scroll.removeListener(_handleScroll);
    if (_ownsScroll) {
      _scroll.dispose();
    }
    for (final node in _posterFocusNodes) {
      node.dispose();
    }
    _movieCategoryFocus.dispose();
    _seriesCategoryFocus.dispose();
    _varietyCategoryFocus.dispose();
    super.dispose();
  }

  @override
  void onPageBecameActive() {
    if (_preferencesLoaded && _page == null && !_loading && _error == null) {
      unawaited(_scheduleLoad(0));
    }
    _scheduleViewportCheck();
  }

  @override
  void onPageBecameInactive() {
    _generation++;
    _prefetchStart = null;
    if (_loading) setState(() => _loading = false);
  }

  Future<void> _scheduleLoad(
    int start, {
    bool refresh = false,
  }) async {
    final intent = _generation;
    final previous = _pendingLoad;
    if (previous != null) await previous;
    if (!mounted || !isPageActive || intent != _generation) return;
    final next = _load(start, refresh: refresh);
    _pendingLoad = next;
    await next;
    if (identical(_pendingLoad, next)) {
      _pendingLoad = null;
      _scheduleViewportCheck();
    }
  }

  void _scheduleViewportCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadMoreIfNeeded();
        _scheduleVisiblePageUpdate();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _handleScroll() {
    _loadMoreIfNeeded();
    _scheduleVisiblePageUpdate();
  }

  void _scheduleVisiblePageUpdate() {
    if (_visiblePageUpdateScheduled) return;
    _visiblePageUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visiblePageUpdateScheduled = false;
      if (!mounted || _posterFocusNodes.isEmpty) return;
      int? firstVisibleIndex;
      final render = _gridKey.currentContext?.findRenderObject();
      if (render is RenderSliverGrid && _posterItemExtent > 0) {
        final rowExtent = _posterItemExtent + 12;
        final row = (render.constraints.scrollOffset / rowExtent).floor();
        firstVisibleIndex = math.max(0, row) * _posterColumns;
      }
      if (firstVisibleIndex == null) {
        final viewport = MediaQuery.sizeOf(context);
        final top = MediaQuery.paddingOf(context).top;
        for (var index = 0; index < _posterFocusNodes.length; index++) {
          final node = _posterFocusNodes[index];
          if (node.context == null) continue;
          final rect = node.rect;
          if (rect.bottom <= top || rect.top >= viewport.height) continue;
          firstVisibleIndex = index;
          break;
        }
      }
      if (firstVisibleIndex == null) return;
      final page = firstVisibleIndex ~/ 20 + 1;
      if (page != _currentVisiblePage) {
        setState(() => _currentVisiblePage = page);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _loadMoreIfNeeded({bool lastRowFocused = false}) {
    if (!mounted ||
        !isPageActive ||
        !_enabled ||
        !_hasMore ||
        _loading ||
        _pendingLoad != null ||
        _error != null ||
        !_scroll.hasClients) {
      return;
    }
    if (lastRowFocused || _scroll.position.extentAfter <= 200) {
      unawaited(_scheduleLoad(_page!.start + 20));
      return;
    }
    _prefetchNextPageIfNeeded();
  }

  void _prefetchNextPageIfNeeded() {
    if (!mounted ||
        !isPageActive ||
        !_enabled ||
        !_hasMore ||
        _page == null ||
        _loading ||
        _pendingLoad != null ||
        _error != null ||
        !_scroll.hasClients) {
      return;
    }
    final nextStart = _page!.start + 20;
    if (_prefetchStart == nextStart) return;
    final prefetchThreshold = math.max(
      320.0,
      _scroll.position.viewportDimension * 1.5,
    );
    if (_scroll.position.extentAfter > prefetchThreshold) return;
    _prefetchStart = nextStart;
    final query = _query;
    unawaited(
      ref
          .read(doubanBrowseRepositoryProvider)
          .fetch(query, start: nextStart)
          .then<void>(
            (_) {},
            onError: (Object _, StackTrace __) {},
          ),
    );
  }

  Future<void> _load(
    int start, {
    bool refresh = false,
  }) async {
    if (_loading || !isPageActive || !_enabled) {
      return;
    }
    if (start == 0 && !refresh && _page == null && _error != null) {
      // Explicit retry is handled by the refresh path.
      return;
    }
    final query = _query;
    if (refresh && start == 0) {
      ref.read(doubanBrowseRepositoryProvider).invalidateQuery(query);
      _prefetchStart = null;
    }
    final request = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (refresh) {
        ref.read(doubanNetworkGuardProvider).allowManualProbe(
              reason: 'manual-douban-browse-refresh',
            );
      }
      final result = await ref.read(doubanBrowseRepositoryProvider).fetch(
            query,
            start: start,
            refresh: refresh,
          );
      if (!mounted || !isPageActive || request != _generation) return;
      if (result.genres.isNotEmpty) _genres[query.category] = result.genres;
      if (result.regions.isNotEmpty) {
        _regions[query.category] = result.regions;
      }
      final previousEntries =
          start == 0 ? const <DoubanEntry>[] : _page!.entries;
      final seenOnPage = previousEntries.map((entry) => entry.id).toSet();
      final unique = result.entries.where((entry) {
        return seenOnPage.add(entry.id);
      }).toList(growable: false);
      final page = DoubanBrowsePageData(
        entries: [...previousEntries, ...unique],
        start: start,
        rawCount: result.rawCount,
        total: result.total,
        genres: result.genres,
        regions: result.regions,
      );
      setState(() {
        _page = page;
        _pageLimitReached = start >= 980;
        _hasMore = result.hasNext && unique.isNotEmpty && !_pageLimitReached;
        _loading = false;
      });
      if (start == 0 && _scroll.hasClients) _scroll.jumpTo(0);
    } catch (error) {
      if (!mounted || !isPageActive || request != _generation) return;
      if (start > 0) _hasMore = false;
      setState(() {
        _error = error is DoubanApiException ? error.message : '豆瓣选片暂时不可用';
        _loading = false;
      });
    }
  }

  void _select(DoubanBrowseQuery next) {
    if (next.cacheKey == _query.cacheKey) return;
    final typeChanged = next.category != _query.category;
    _queryTouched = true;
    _preferencesLoaded = true;
    _generation++;
    setState(() {
      _query = next;
      _queries[next.category] = next;
      _page = null;
      _hasMore = false;
      _prefetchStart = null;
      _pageLimitReached = false;
      _currentVisiblePage = 1;
      _loading = false;
      _error = null;
    });
    unawaited(ref
        .read(searchPreferencesRepositoryProvider)
        .saveBrowseQuery(next)
        .catchError((Object _) {}));
    if (typeChanged) {
      unawaited(ref
          .read(searchPreferencesRepositoryProvider)
          .saveBrowseType(next.category)
          .catchError((Object _) {}));
    }
    unawaited(_scheduleLoad(0));
  }

  void _selectCategory(DoubanBrowseCategory category) {
    final next = _queries[category] ?? DoubanBrowseQuery(category: category);
    _select(next);
  }

  Widget _menu<T>({
    Key? key,
    Key? textKey,
    required String label,
    required T value,
    required List<T> values,
    required String Function(T) text,
    required bool Function(T) isDefault,
    required ValueChanged<T> onSelected,
  }) {
    final initialValue = values.contains(value) ? value : values.first;
    final selectedIndex = values.indexOf(initialValue);
    final displayText = isDefault(value) ? label : text(value);
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    return _BrowseControlFocusFrame(
      isTelevision: isTelevision,
      child: PopupMenuButton<T>(
        key: key,
        tooltip: label,
        initialValue: initialValue,
        onOpened: isTelevision
            ? () => _focusMenuSelection(selectedIndex, values.length)
            : null,
        constraints: const BoxConstraints(maxHeight: 440, minWidth: 180),
        onSelected: onSelected,
        itemBuilder: (context) => values
            .map((item) => PopupMenuItem<T>(
                  value: item,
                  child: Text(text(item),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ))
            .toList(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(displayText,
                key: textKey, maxLines: 1, overflow: TextOverflow.ellipsis),
            const Icon(Icons.arrow_drop_down),
          ]),
        ),
      ),
    );
  }

  void _focusMenuSelection(
    int selectedIndex,
    int expectedCount, {
    int attempt = 0,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scope = FocusManager.instance.primaryFocus;
      final scopeContext = scope?.context;
      if (scope == null || scopeContext == null || !scopeContext.mounted) {
        return;
      }
      final candidates = scope.traversalDescendants.toList(growable: false);
      if (candidates.length != expectedCount ||
          selectedIndex < 0 ||
          selectedIndex >= candidates.length) {
        if (attempt < 2) {
          _focusMenuSelection(
            selectedIndex,
            expectedCount,
            attempt: attempt + 1,
          );
        }
        return;
      }
      candidates[selectedIndex].requestFocus();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool _focusTarget(GlobalKey key) {
    final targetContext = key.currentContext;
    if (targetContext == null) return false;
    final focus = Focus.of(targetContext);
    if (!focus.canRequestFocus) return false;
    focus.requestFocus();
    return true;
  }

  void _focusFirstPoster() {
    for (final node in _posterFocusNodes) {
      if (node.context == null || !node.canRequestFocus) continue;
      node.requestFocus();
      unawaited(Scrollable.ensureVisible(node.context!));
      return;
    }
  }

  bool _handlePosterDirection(
    int index,
    TraversalDirection direction,
  ) {
    final rowDelta = switch (direction) {
      TraversalDirection.up => -1,
      TraversalDirection.down => 1,
      TraversalDirection.left || TraversalDirection.right => null,
    };
    if (rowDelta == null) return false;

    final entryCount = _page?.entries.length ?? 0;
    final targetIndex = index + rowDelta * _posterColumns;
    if (targetIndex < 0) return false;
    if (targetIndex >= entryCount) {
      if (rowDelta < 0) return false;
      if (_error != null && !_loading) {
        return false;
      }
      _loadMoreIfNeeded(lastRowFocused: true);
      return true;
    }
    _focusPosterAtIndex(targetIndex, rowDelta);
    return true;
  }

  void _focusPosterAtIndex(
    int index,
    int rowDelta, {
    int remainingAttempts = 2,
  }) {
    if (!mounted || index < 0 || index >= _posterFocusNodes.length) return;
    final focusNode = _posterFocusNodes[index];
    final focusContext = focusNode.context;
    if (focusContext != null && focusNode.canRequestFocus) {
      focusNode.requestFocus();
      unawaited(Scrollable.ensureVisible(focusContext));
      return;
    }
    if (remainingAttempts <= 0 ||
        !_scroll.hasClients ||
        _posterItemExtent <= 0) {
      return;
    }

    final position = _scroll.position;
    final targetOffset = (position.pixels + rowDelta * (_posterItemExtent + 12))
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((targetOffset - position.pixels).abs() < 0.5) return;
    _scroll.jumpTo(targetOffset);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusPosterAtIndex(
        index,
        rowDelta,
        remainingAttempts: remainingAttempts - 1,
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _focusSelectedCategory() {
    final focusNode = switch (_query.category) {
      DoubanBrowseCategory.movie => _movieCategoryFocus,
      DoubanBrowseCategory.series => _seriesCategoryFocus,
      DoubanBrowseCategory.variety => _varietyCategoryFocus,
    };
    if (focusNode.canRequestFocus) {
      focusNode.requestFocus();
    }
  }

  Widget _actionButtons({required bool tv}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BrowseControlFocusFrame(
          isTelevision: tv,
          child: IconButton(
            key: const ValueKey('douban-refresh'),
            visualDensity: VisualDensity.compact,
            constraints: BoxConstraints.tightFor(
              width: tv ? 48 : 36,
              height: tv ? 48 : 36,
            ),
            tooltip: '刷新',
            icon: Icon(Icons.refresh, size: tv ? 24 : 20),
            onPressed: _enabled && !_loading
                ? () => _scheduleLoad(0, refresh: true)
                : null,
          ),
        ),
        _BrowseControlFocusFrame(
          isTelevision: tv,
          child: IconButton(
            key: const ValueKey('douban-clear-filters'),
            visualDensity: VisualDensity.compact,
            constraints: BoxConstraints.tightFor(
              width: tv ? 48 : 36,
              height: tv ? 48 : 36,
            ),
            tooltip: '重置筛选',
            icon: Icon(Icons.filter_alt_off, size: tv ? 24 : 20),
            onPressed: () =>
                _select(DoubanBrowseQuery(category: _query.category)),
          ),
        ),
      ],
    );
  }

  int get _currentPage => _currentVisiblePage;

  int get _totalPages {
    final total = _page?.total;
    final calculated =
        total == null || total <= 0 ? _currentPage : (total + 19) ~/ 20;
    return math.max(_currentPage, math.min(50, calculated));
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(appSettingsProvider
        .select((settings) => settings.doubanAccount.enabled));
    ref.listen<bool>(
      appSettingsProvider.select((settings) => settings.doubanAccount.enabled),
      (previous, next) {
        _enabled = next;
        if (!next) {
          _generation++;
          ref.read(doubanBrowseRepositoryProvider).clear();
          setState(() {
            _page = null;
            _prefetchStart = null;
            _loading = false;
            _error = null;
          });
        } else if (isPageActive && _preferencesLoaded && _page == null) {
          unawaited(_scheduleLoad(0));
        }
      },
    );
    _enabled = enabled;
    final tv = ref.watch(isTelevisionProvider).value ?? false;
    final categoryGenres = _genres[_query.category];
    final categoryRegions = _regions[_query.category];
    final genres = [
      '全部',
      ...categoryGenres?.isNotEmpty == true
          ? categoryGenres!
          : _query.category == DoubanBrowseCategory.variety
              ? const ['真人秀', '脱口秀', '音乐', '歌舞']
              : const ['剧情', '喜剧', '动作', '爱情', '科幻', '悬疑', '动画', '纪录片']
    ];
    final regions = [
      '全部',
      ...categoryRegions?.isNotEmpty == true
          ? categoryRegions!
          : const ['中国大陆', '美国', '日本', '韩国', '中国香港', '英国', '法国']
    ];
    return TvPageFocusScope(
      isTelevision: tv,
      child: Scaffold(
        body: AppPageBackground(
          child: Stack(children: [
            CustomScrollView(
              controller: _scroll,
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                      kAppPageHorizontalPadding,
                      MediaQuery.paddingOf(context).top + 8,
                      kAppPageHorizontalPadding,
                      MediaQuery.paddingOf(context).bottom),
                  sliver: SliverMainAxisGroup(slivers: [
                    SliverList.list(children: [
                      if (widget.topContent != null)
                        TvDirectionalActionPanel(
                          enabled: tv,
                          onMoveDown: _focusSelectedCategory,
                          child: widget.topContent!,
                        ),
                      TvDirectionalActionPanel(
                        enabled: tv,
                        onMoveDown: () => _focusTarget(_yearFocusTargetKey),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints:
                                BoxConstraints(maxWidth: tv ? 360 : 260),
                            child: StarflowSingleSelectTabBar<
                                DoubanBrowseCategory>(
                              key: const ValueKey('douban-category-tabs-group'),
                              spacing: 2,
                              compact: true,
                              selectedValue: _query.category,
                              onSelected: _selectCategory,
                              items: [
                                StarflowTabItem(
                                  value: DoubanBrowseCategory.movie,
                                  widgetKey:
                                      const ValueKey('douban-category-movie'),
                                  focusId: 'douban-category-movie',
                                  focusNode: _movieCategoryFocus,
                                  label: '电影',
                                ),
                                StarflowTabItem(
                                  value: DoubanBrowseCategory.series,
                                  widgetKey:
                                      const ValueKey('douban-category-series'),
                                  focusId: 'douban-category-series',
                                  focusNode: _seriesCategoryFocus,
                                  label: '电视剧',
                                ),
                                StarflowTabItem(
                                  value: DoubanBrowseCategory.variety,
                                  widgetKey:
                                      const ValueKey('douban-category-variety'),
                                  focusId: 'douban-category-variety',
                                  focusNode: _varietyCategoryFocus,
                                  label: '综艺',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TvDirectionalActionPanel(
                        enabled: tv,
                        onMoveDown: () => _focusTarget(_sortFocusTargetKey),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _menu<String>(
                                key: const ValueKey('douban-filter-year'),
                                textKey: _yearFocusTargetKey,
                                label: '年份',
                                value: _query.year?.toString() ?? '',
                                values: [
                                  '',
                                  ...doubanBrowseYearOptions(
                                          selectedYear: _query.year)
                                      .map((year) => '$year'),
                                ],
                                text: (value) => value.isEmpty ? '全部' : value,
                                isDefault: (value) => value.isEmpty,
                                onSelected: (value) {
                                  if (value.isEmpty) {
                                    _select(_query.copyWith(clearYear: true));
                                  } else {
                                    _select(_query.copyWith(
                                        year: int.parse(value)));
                                  }
                                }),
                            _menu<String>(
                                key: const ValueKey('douban-filter-region'),
                                label: '地区',
                                value: _query.region,
                                values: {
                                  '',
                                  _query.region,
                                  ...regions.where((v) => v != '全部')
                                }.toList(),
                                text: (value) => value.isEmpty ? '全部' : value,
                                isDefault: (value) => value.isEmpty,
                                onSelected: (value) =>
                                    _select(_query.copyWith(region: value))),
                            _menu<String>(
                                key: const ValueKey('douban-filter-genre'),
                                label: '类型',
                                value: _query.genre,
                                values: {
                                  '',
                                  _query.genre,
                                  ...genres.where((v) => v != '全部')
                                }.toList(),
                                text: (value) => value.isEmpty ? '全部' : value,
                                isDefault: (value) => value.isEmpty,
                                onSelected: (value) =>
                                    _select(_query.copyWith(genre: value))),
                            _menu<int>(
                                key: const ValueKey('douban-filter-rating'),
                                label: '评分',
                                value: _query.minRating,
                                values: const [0, 6, 7, 8, 9],
                                text: (value) =>
                                    value == 0 ? '不限' : '$value 分以上',
                                isDefault: (value) => value == 0,
                                onSelected: (value) =>
                                    _select(_query.copyWith(minRating: value))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: TvDirectionalActionPanel(
                                enabled: tv,
                                onMoveDown: _focusFirstPoster,
                                child: _menu<DoubanBrowseSort>(
                                    key: const ValueKey('douban-filter-sort'),
                                    textKey: _sortFocusTargetKey,
                                    label: '排序',
                                    value: _query.sort,
                                    values: DoubanBrowseSort.values,
                                    text: (value) =>
                                        value.labelFor(_query.mediaType),
                                    isDefault: (value) =>
                                        value == DoubanBrowseSort.rating,
                                    onSelected: (value) =>
                                        _select(_query.copyWith(sort: value))),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: _actionButtons(tv: tv),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (!enabled)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('豆瓣模块已关闭'),
                            TextButton(
                              onPressed: () => context.pushNamed('home-editor'),
                              child: const Text('前往首页编辑启用豆瓣模块'),
                            ),
                          ],
                        )
                      else if (_page == null && _loading)
                        const Center(child: CircularProgressIndicator())
                      else if (_page == null && _error != null) ...[
                        Text(_error!),
                        TextButton(
                            onPressed: () => _scheduleLoad(0, refresh: true),
                            child: const Text('重试')),
                      ] else if (_page?.entries.isEmpty == true)
                        const Text('没有符合条件的作品'),
                    ]),
                    if (_page?.entries.isNotEmpty == true)
                      SliverLayoutBuilder(builder: (context, constraints) {
                        const gap = 12.0;
                        final columns = math.max(
                            2,
                            ((constraints.crossAxisExtent + gap) / 150)
                                .floor());
                        _posterColumns = columns;
                        while (
                            _posterFocusNodes.length < _page!.entries.length) {
                          final index = _posterFocusNodes.length;
                          final node =
                              FocusNode(debugLabel: 'douban-poster-$index');
                          node.addListener(() {
                            final count = _page?.entries.length ?? 0;
                            if (node.hasFocus &&
                                count > 0 &&
                                index >=
                                    ((count - 1) ~/ _posterColumns) *
                                        _posterColumns) {
                              _loadMoreIfNeeded(lastRowFocused: true);
                            }
                          });
                          _posterFocusNodes.add(node);
                        }
                        final width = (constraints.crossAxisExtent -
                                (columns - 1) * gap) /
                            columns;
                        final titleHeight = MediaQuery.textScalerOf(context)
                                .scale(Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.fontSize ??
                                    16) *
                            1.22;
                        final tileBottomSlack = tv ? 8.0 : 2.0;
                        _posterItemExtent =
                            width / .7 + 4 + titleHeight + tileBottomSlack;
                        return SliverGrid.builder(
                          key: _gridKey,
                          itemCount: _page!.entries.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            crossAxisSpacing: gap,
                            mainAxisSpacing: gap,
                            mainAxisExtent: _posterItemExtent,
                          ),
                          itemBuilder: (context, index) {
                            final entry = _page!.entries[index];
                            return TvDirectionalActionPanel(
                              enabled: tv,
                              onDirection: (direction) =>
                                  _handlePosterDirection(index, direction),
                              child: MediaPosterTile(
                                focusNode: _posterFocusNodes[index],
                                key: ValueKey(
                                    '${_query.mediaType.value}:${entry.id}'),
                                title: entry.title,
                                subtitle: '',
                                posterUrl: entry.posterUrl,
                                imageTopLeftBadgeText:
                                    entry.year == 0 ? '' : '${entry.year}',
                                imageBadgeText: entry.ratingLabel
                                    .replaceFirst('豆瓣', '')
                                    .trim(),
                                imageTopRightBadgeText: entry.genres.isNotEmpty
                                    ? entry.genres.first
                                    : '',
                                imageBottomRightBadgeText:
                                    buildRatingCountLabel(entry.ratingCount),
                                width: null,
                                onTap: () => context.pushNamed('detail',
                                    extra: MediaDetailTarget(
                                      title: entry.title,
                                      overview: '',
                                      posterUrl: entry.posterUrl,
                                      year: entry.year,
                                      ratingLabels: entry.ratingLabel.isEmpty
                                          ? const []
                                          : [entry.ratingLabel],
                                      ratingCount: entry.ratingCount,
                                      availabilityLabel: '无',
                                      searchQuery: entry.title,
                                      itemType: _query.mediaType ==
                                              DoubanSuggestionMediaType.movie
                                          ? 'movie'
                                          : 'series',
                                      doubanId: entry.id,
                                      sourceName: '豆瓣',
                                    )),
                              ),
                            );
                          },
                        );
                      }),
                    SliverToBoxAdapter(
                        child: Column(children: [
                      if (_page != null) ...[
                        if (_loading)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(),
                          )
                        else if (_error != null) ...[
                          Text(_error!),
                          TvAdaptiveButton(
                            key: const ValueKey('douban-load-more-retry'),
                            label: '重试',
                            icon: Icons.refresh,
                            onPressed: () =>
                                _scheduleLoad(_page!.start + 20, refresh: true),
                          ),
                        ] else if (_pageLimitReached)
                          const Text('已达到加载上限，请缩小筛选范围')
                        else if (!_hasMore && _page!.entries.isNotEmpty)
                          const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('已显示全部结果')),
                      ],
                      appPageBottomSpacer(height: 64),
                    ])),
                  ]),
                )
              ],
            ),
            if (enabled && _page?.entries.isNotEmpty == true)
              Positioned(
                top: 0,
                right: 6,
                bottom: 0,
                child: IgnorePointer(
                  child: Center(
                    child: _FloatingPageIndicator(
                      currentPage: _currentPage,
                      totalPages: _totalPages,
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _FloatingPageIndicator extends StatelessWidget {
  const _FloatingPageIndicator({
    required this.currentPage,
    required this.totalPages,
  });

  final int currentPage;
  final int totalPages;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$currentPage',
              key: const ValueKey('douban-floating-page-current'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$totalPages',
              key: const ValueKey('douban-floating-page-total'),
              style: theme.textTheme.bodySmall?.copyWith(height: 1),
            ),
          ],
        ),
      ),
    );
  }
}

// Observe the native control's focus without adding another traversal stop.
class _BrowseControlFocusFrame extends StatefulWidget {
  const _BrowseControlFocusFrame({
    required this.isTelevision,
    required this.child,
  });

  final bool isTelevision;
  final Widget child;

  @override
  State<_BrowseControlFocusFrame> createState() =>
      _BrowseControlFocusFrameState();
}

class _BrowseControlFocusFrameState extends State<_BrowseControlFocusFrame> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.isTelevision) return widget.child;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return TvRemoteShortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
      },
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          constraints: const BoxConstraints(minHeight: 44),
          decoration: BoxDecoration(
            color: _focused
                ? (dark
                    ? Colors.white.withValues(alpha: 0.18)
                    : scheme.primaryContainer)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _focused
                  ? (dark ? Colors.white : scheme.primary)
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
