import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
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
  const DoubanBrowsePage({super.key});

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
  int _start = 0;
  int _generation = 0;
  Future<void>? _pendingLoad;
  bool _loading = false;
  bool _preferencesLoaded = false;
  bool _queryTouched = false;
  bool _enabled = false;
  bool _pageLimitReached = false;
  String? _error;
  final _firstPageForId = <String, int>{};
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
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
    _scroll.dispose();
    super.dispose();
  }

  @override
  void onPageBecameActive() {
    if (_preferencesLoaded && _page == null && !_loading && _error == null) {
      unawaited(_scheduleLoad(0));
    }
  }

  @override
  void onPageBecameInactive() {
    _generation++;
    if (_loading) setState(() => _loading = false);
  }

  Future<void> _scheduleLoad(int start, {bool refresh = false}) async {
    final intent = _generation;
    final previous = _pendingLoad;
    if (previous != null) await previous;
    if (!mounted || !isPageActive || intent != _generation) return;
    final next = _load(start, refresh: refresh);
    _pendingLoad = next;
    await next;
    if (identical(_pendingLoad, next)) _pendingLoad = null;
  }

  Future<void> _load(int start, {bool refresh = false}) async {
    if (_loading || !isPageActive || !_enabled) {
      return;
    }
    if (start == 0 && !refresh && _page == null && _error != null) {
      // Explicit retry is handled by the refresh path.
      return;
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
            _query,
            start: start,
            refresh: refresh,
          );
      if (!mounted || !isPageActive || request != _generation) return;
      if (result.genres.isNotEmpty) _genres[_query.category] = result.genres;
      if (result.regions.isNotEmpty) {
        _regions[_query.category] = result.regions;
      }
      if (start == 0 && refresh) _firstPageForId.clear();
      final seenOnPage = <String>{};
      final unique = result.entries.where((entry) {
        final id = '${_query.category.value}:${entry.id}';
        if (!seenOnPage.add(id)) return false;
        final firstPage = _firstPageForId.putIfAbsent(id, () => start);
        return firstPage == start;
      }).toList(growable: false);
      final page = DoubanBrowsePageData(
        entries: unique,
        start: result.start,
        rawCount: result.rawCount,
        total: result.total,
        genres: result.genres,
        regions: result.regions,
      );
      setState(() {
        _page = page;
        _start = start;
        _pageLimitReached = start >= 980;
        _loading = false;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } catch (error) {
      if (!mounted || !isPageActive || request != _generation) return;
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
      _start = 0;
      _firstPageForId.clear();
      _pageLimitReached = false;
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

  Widget _menu<T>({
    Key? key,
    required String label,
    required T value,
    required List<T> values,
    required String Function(T) text,
    required bool Function(T) isDefault,
    required ValueChanged<T> onSelected,
  }) {
    final initialValue = values.contains(value) ? value : values.first;
    final displayText = isDefault(value) ? label : text(value);
    return PopupMenuButton<T>(
      key: key,
      tooltip: label,
      initialValue: initialValue,
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
          Text(displayText, maxLines: 1, overflow: TextOverflow.ellipsis),
          const Icon(Icons.arrow_drop_down),
        ]),
      ),
    );
  }

  Widget _pageButton({
    Key? key,
    required bool tv,
    required String tooltip,
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      key: key,
      message: tooltip,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          minimumSize: Size(0, tv ? 44 : 32),
          padding: EdgeInsets.symmetric(
            horizontal: tv ? 10 : 5,
            vertical: tv ? 6 : 2,
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: tv ? VisualDensity.standard : VisualDensity.compact,
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label, style: Theme.of(context).textTheme.bodySmall),
      ),
    );
  }

  Widget _paginationControls({
    required String keyPrefix,
    required bool tv,
    bool includeActions = false,
    bool showLoading = true,
  }) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 2,
      runSpacing: 2,
      children: [
        _pageButton(
          key: ValueKey('$keyPrefix-page-previous'),
          tv: tv,
          tooltip: '上一页',
          label: '上一页',
          icon: Icons.chevron_left,
          onPressed:
              _start > 0 && !_loading ? () => _scheduleLoad(_start - 20) : null,
        ),
        Text(
          _pageLabel,
          key: ValueKey('$keyPrefix-page-label'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        _pageButton(
          key: ValueKey('$keyPrefix-page-next'),
          tv: tv,
          tooltip: '下一页',
          label: '下一页',
          icon: Icons.chevron_right,
          onPressed: _page?.hasNext == true && !_pageLimitReached && !_loading
              ? () => _scheduleLoad(_start + 20)
              : null,
        ),
        if (showLoading && _loading)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        if (includeActions) ...[
          IconButton(
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
          IconButton(
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
        ],
      ],
    );
  }

  String get _pageLabel {
    final page = _start ~/ 20 + 1;
    final total = _page?.total;
    if (total == null || total <= 0) return '$page';
    final totalPages = math.min(50, ((total + 19) ~/ 20).clamp(1, 50));
    return '$page/$totalPages';
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
          child: ListView(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(
                kAppPageHorizontalPadding,
                MediaQuery.paddingOf(context).top + 74,
                kAppPageHorizontalPadding,
                MediaQuery.paddingOf(context).bottom),
            children: [
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<DoubanBrowseCategory>(
                  showSelectedIcon: false,
                  expandedInsets: EdgeInsets.zero,
                  segments: const [
                    ButtonSegment(
                        value: DoubanBrowseCategory.movie, label: Text('电影')),
                    ButtonSegment(
                        value: DoubanBrowseCategory.series, label: Text('电视剧')),
                    ButtonSegment(
                        value: DoubanBrowseCategory.variety, label: Text('综艺')),
                  ],
                  selected: {_query.category},
                  onSelectionChanged: (value) => _select(
                      _queries[value.single] ??
                          DoubanBrowseQuery(category: value.single)),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _menu<String>(
                      key: const ValueKey('douban-filter-year'),
                      label: '年份',
                      value: _query.year?.toString() ?? '',
                      values: [
                        '',
                        ...doubanBrowseYearOptions(selectedYear: _query.year)
                            .map((year) => '$year'),
                      ],
                      text: (value) => value.isEmpty ? '全部' : value,
                      isDefault: (value) => value.isEmpty,
                      onSelected: (value) {
                        if (value.isEmpty) {
                          _select(_query.copyWith(clearYear: true));
                        } else {
                          _select(_query.copyWith(year: int.parse(value)));
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
                      text: (value) => value == 0 ? '不限' : '$value 分以上',
                      isDefault: (value) => value == 0,
                      onSelected: (value) =>
                          _select(_query.copyWith(minRating: value))),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: _paginationControls(
                      keyPrefix: 'top',
                      tv: tv,
                      includeActions: true,
                    ),
                  ),
                  const SizedBox(width: 4),
                  _menu<DoubanBrowseSort>(
                      key: const ValueKey('douban-filter-sort'),
                      label: '排序',
                      value: _query.sort,
                      values: DoubanBrowseSort.values,
                      text: (value) => value.labelFor(_query.mediaType),
                      isDefault: (value) => value == DoubanBrowseSort.rating,
                      onSelected: (value) =>
                          _select(_query.copyWith(sort: value))),
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
              ] else if (_page != null) ...[
                if (_error != null) Text(_error!),
                if (_page!.entries.isEmpty)
                  const Text('没有符合条件的作品')
                else
                  LayoutBuilder(builder: (context, constraints) {
                    const gap = 12.0;
                    final columns = math.max(
                        2, ((constraints.maxWidth + gap) / 150).floor());
                    final width =
                        (constraints.maxWidth - (columns - 1) * gap) / columns;
                    final titleHeight = MediaQuery.textScalerOf(context).scale(
                            Theme.of(context).textTheme.titleSmall?.fontSize ??
                                16) *
                        1.22;
                    final tileBottomSlack = tv ? 8.0 : 2.0;
                    return GridView.builder(
                      shrinkWrap: true,
                      primary: false,
                      padding: EdgeInsets.zero,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _page!.entries.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: gap,
                        mainAxisSpacing: gap,
                        mainAxisExtent:
                            width / .7 + 4 + titleHeight + tileBottomSlack,
                      ),
                      itemBuilder: (context, index) {
                        final entry = _page!.entries[index];
                        return MediaPosterTile(
                          key:
                              ValueKey('${_query.mediaType.value}:${entry.id}'),
                          title: entry.title,
                          subtitle: '',
                          posterUrl: entry.posterUrl,
                          imageTopLeftBadgeText:
                              entry.year == 0 ? '' : '${entry.year}',
                          imageBadgeText: entry.ratingLabel,
                          imageTopRightBadgeText: _query.category.label,
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
                        );
                      },
                    );
                  }),
                if (_pageLimitReached) const Text('已达到本机分页上限，请缩小筛选范围'),
                if (_page!.entries.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.center,
                    child: _paginationControls(
                      keyPrefix: 'bottom',
                      tv: tv,
                      showLoading: false,
                    ),
                  ),
                ],
              ],
              appPageBottomSpacer(height: 64),
            ],
          ),
        ),
      ),
    );
  }
}
