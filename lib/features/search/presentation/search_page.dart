import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/navigation/page_activity_mixin.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/core/widgets/app_network_image.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/library/application/media_refresh_coordinator.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/search/data/mock_search_repository.dart';
import 'package:starflow/features/search/data/search_preferences_repository.dart';
import 'package:starflow/features/search/data/smart_strm_webhook_client.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:url_launcher/url_launcher.dart';

final _searchPageAllowedSourceIdsProvider = Provider<List<String>>((ref) {
  return ref.watch(
      appSettingsProvider.select((settings) => settings.searchSourceIds));
});

final _searchPageMediaSourcesProvider =
    Provider<List<MediaSourceConfig>>((ref) {
  return ref
      .watch(appSettingsProvider.select((settings) => settings.mediaSources));
});

final _searchPageSearchProvidersProvider =
    Provider<List<SearchProviderConfig>>((ref) {
  return ref.watch(
    appSettingsProvider.select((settings) => settings.searchProviders),
  );
});

final _searchPageNetworkStorageProvider = Provider<NetworkStorageConfig>((ref) {
  return ref
      .watch(appSettingsProvider.select((settings) => settings.networkStorage));
});

final _searchPageVisibleLocalSourcesProvider =
    Provider<List<MediaSourceConfig>>((
  ref,
) {
  final searchSourceIds = ref.watch(_searchPageAllowedSourceIdsProvider);
  final mediaSources = ref.watch(_searchPageMediaSourcesProvider);
  return _resolveVisibleLocalSources(
    searchSourceIds: searchSourceIds,
    mediaSources: mediaSources,
  );
});

final _searchPageVisibleSearchProvidersProvider =
    Provider<List<SearchProviderConfig>>((ref) {
  final searchSourceIds = ref.watch(_searchPageAllowedSourceIdsProvider);
  final searchProviders = ref.watch(_searchPageSearchProvidersProvider);
  return _resolveVisibleSearchProviders(
    searchSourceIds: searchSourceIds,
    searchProviders: searchProviders,
  );
});

List<MediaSourceConfig> _resolveVisibleLocalSources({
  required List<String> searchSourceIds,
  required List<MediaSourceConfig> mediaSources,
}) {
  final allowedIds = searchSourceIds.toSet();
  final availableSources = mediaSources
      .where(
        (source) =>
            source.enabled &&
            (source.kind == MediaSourceKind.emby ||
                source.kind == MediaSourceKind.nas ||
                (source.kind == MediaSourceKind.quark &&
                    source.hasConfiguredQuarkFolder)),
      )
      .toList(growable: false);
  if (allowedIds.isEmpty) {
    return availableSources;
  }
  final filteredSources = availableSources
      .where(
        (source) => allowedIds.contains(
          searchSourceSettingIdForMediaSource(source.id),
        ),
      )
      .toList(growable: false);
  return filteredSources.isEmpty ? availableSources : filteredSources;
}

List<SearchProviderConfig> _resolveVisibleSearchProviders({
  required List<String> searchSourceIds,
  required List<SearchProviderConfig> searchProviders,
}) {
  final allowedIds = searchSourceIds.toSet();
  final availableProviders = searchProviders
      .where((provider) => provider.enabled)
      .toList(growable: false);
  if (allowedIds.isEmpty) {
    return availableProviders;
  }
  final filteredProviders = availableProviders
      .where(
        (provider) => allowedIds.contains(
          searchSourceSettingIdForProvider(provider.id),
        ),
      )
      .toList(growable: false);
  return filteredProviders.isEmpty ? availableProviders : filteredProviders;
}

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({
    super.key,
    this.initialQuery,
    this.showBackButton = false,
  });

  final String? initialQuery;
  final bool showBackButton;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage>
    with PageActivityMixin<SearchPage> {
  static const Duration _searchUiCommitInterval = Duration(milliseconds: 120);

  late final TextEditingController _controller;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _queryFocusNode = FocusNode(debugLabel: 'search-query');
  final TvFocusMemoryController _tvFocusMemoryController =
      TvFocusMemoryController();
  List<SearchResult> _results = const [];
  List<String> _recentQueries = const [];
  bool _isSearching = false;
  Set<String> _selectedTargetIds = const {_SearchTarget.allId};
  String? _errorMessage;
  int _activeSearchRequestId = 0;
  int _totalSearchTaskCount = 0;
  int _completedSearchTaskCount = 0;
  int _filteredResultCount = 0;
  final Set<String> _savingResultIds = <String>{};
  String? _pendingAutoSearchQuery;
  Timer? _searchUiCommitTimer;
  int _pendingSearchRequestId = 0;
  List<SearchResult>? _pendingSearchResults;
  List<String>? _pendingSearchErrors;
  int _pendingSearchTotalCount = 0;
  int _pendingSearchCompletedCount = 0;
  int _pendingSearchFilteredCount = 0;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery ?? '');
    unawaited(_loadTelevisionPreferences());
    _scheduleAutoSearch(widget.initialQuery);
  }

  @override
  void didUpdateWidget(covariant SearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialQuery != widget.initialQuery) {
      final nextQuery = (widget.initialQuery ?? '').trim();
      if (nextQuery.isEmpty) {
        return;
      }
      _controller.text = nextQuery;
      _scheduleAutoSearch(nextQuery);
    }
  }

  @override
  void dispose() {
    _cancelPendingSearchUiCommit(clearState: true);
    _queryFocusNode.dispose();
    _scrollController.dispose();
    _tvFocusMemoryController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.goNamed('home');
  }

  @override
  void onPageBecameActive() {
    _runPendingAutoSearchIfNeeded();
  }

  @override
  void onPageBecameInactive() {
    _cancelSearchTasks();
  }

  Future<void> _loadTelevisionPreferences() async {
    final preferences = ref.read(searchPreferencesRepositoryProvider);
    final recentQueries = await preferences.loadRecentQueries();
    final selectedTargets = await preferences.loadSelectedTargetIds();
    if (!mounted) {
      return;
    }
    setState(() {
      _recentQueries = recentQueries
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .take(8)
          .toList(growable: false);
      if (selectedTargets.isNotEmpty) {
        _selectedTargetIds = selectedTargets
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toSet();
      }
    });
  }

  Future<void> _persistSelectedTargets() async {
    await ref.read(searchPreferencesRepositoryProvider).saveSelectedTargetIds(
          _selectedTargetIds.toList(growable: false),
        );
  }

  Future<void> _rememberQuery(String keyword) async {
    final normalizedKeyword = keyword.trim();
    if (normalizedKeyword.isEmpty) {
      return;
    }
    final nextQueries = <String>[
      normalizedKeyword,
      ..._recentQueries.where(
        (item) => item.toLowerCase() != normalizedKeyword.toLowerCase(),
      ),
    ].take(8).toList(growable: false);
    if (mounted) {
      setState(() {
        _recentQueries = nextQueries;
      });
    }
    await ref
        .read(searchPreferencesRepositoryProvider)
        .saveRecentQueries(nextQueries);
  }

  Future<void> _runRecentQuery(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return;
    }
    _controller.text = normalizedQuery;
    await _performSearch();
  }

  void _scheduleAutoSearch(String? query) {
    final normalizedQuery = query?.trim() ?? '';
    if (normalizedQuery.isEmpty) {
      return;
    }
    _pendingAutoSearchQuery = normalizedQuery;
    _runPendingAutoSearchIfNeeded();
  }

  void _runPendingAutoSearchIfNeeded() {
    final pendingQuery = _pendingAutoSearchQuery?.trim() ?? '';
    if (pendingQuery.isEmpty || !isPageVisible) {
      return;
    }
    _pendingAutoSearchQuery = null;
    if (_controller.text.trim() != pendingQuery) {
      _controller.text = pendingQuery;
    }
    unawaited(_performSearch());
  }

  void _cancelPendingSearchUiCommit({bool clearState = false}) {
    _searchUiCommitTimer?.cancel();
    _searchUiCommitTimer = null;
    if (!clearState) {
      return;
    }
    _pendingSearchRequestId = 0;
    _pendingSearchResults = null;
    _pendingSearchErrors = null;
    _pendingSearchTotalCount = 0;
    _pendingSearchCompletedCount = 0;
    _pendingSearchFilteredCount = 0;
  }

  void _flushPendingSearchUiCommit() {
    _searchUiCommitTimer = null;
    if (!mounted || _pendingSearchRequestId != _activeSearchRequestId) {
      return;
    }
    final aggregated = _pendingSearchResults;
    final errors = _pendingSearchErrors;
    if (aggregated == null || errors == null) {
      return;
    }
    final completed = _pendingSearchCompletedCount;
    final totalCount = _pendingSearchTotalCount;
    final hasFinished = completed >= totalCount;
    final sortedResults = _sortResults(aggregated);
    setState(() {
      _completedSearchTaskCount = completed;
      _filteredResultCount = _pendingSearchFilteredCount;
      _results = sortedResults;
      _isSearching = !hasFinished;
      _errorMessage = sortedResults.isEmpty && errors.isNotEmpty && hasFinished
          ? errors.join('\n')
          : null;
    });
  }

  void _scheduleSearchUiCommit({
    required int requestId,
    required List<SearchResult> aggregated,
    required List<String> errors,
    required int totalCount,
    required int completedCount,
    required int filteredCount,
    bool force = false,
  }) {
    if (!mounted || requestId != _activeSearchRequestId) {
      return;
    }
    _pendingSearchRequestId = requestId;
    _pendingSearchResults = aggregated;
    _pendingSearchErrors = errors;
    _pendingSearchTotalCount = totalCount;
    _pendingSearchCompletedCount = completedCount;
    _pendingSearchFilteredCount = filteredCount;
    if (force) {
      _cancelPendingSearchUiCommit();
      _flushPendingSearchUiCommit();
      return;
    }
    if (_searchUiCommitTimer != null) {
      return;
    }
    _searchUiCommitTimer = Timer(
      _searchUiCommitInterval,
      _flushPendingSearchUiCommit,
    );
  }

  void _cancelSearchTasks({bool clearResults = false}) {
    _activeSearchRequestId += 1;
    _cancelPendingSearchUiCommit(clearState: true);
    if (!mounted) {
      return;
    }
    final shouldUpdateState = _isSearching ||
        _totalSearchTaskCount > 0 ||
        _completedSearchTaskCount > 0 ||
        (clearResults &&
            (_results.isNotEmpty ||
                _errorMessage != null ||
                _filteredResultCount > 0));
    if (!shouldUpdateState) {
      return;
    }
    setState(() {
      _isSearching = false;
      _totalSearchTaskCount = 0;
      _completedSearchTaskCount = 0;
      if (clearResults) {
        _results = const [];
        _errorMessage = null;
        _filteredResultCount = 0;
      }
    });
  }

  Future<void> _performSearch() async {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty) {
      _cancelSearchTasks(clearResults: true);
      return;
    }
    await _rememberQuery(keyword);
    final enabledProviders =
        ref.read(_searchPageVisibleSearchProvidersProvider);
    final localSources = ref.read(_searchPageVisibleLocalSourcesProvider);
    final targets = _buildTargets(
      localSources: localSources,
      providers: enabledProviders,
    );
    if (targets.length == 1) {
      _cancelSearchTasks(clearResults: true);
      return;
    }

    final selectedTargets = _resolveSelectedTargets(targets);
    _cancelPendingSearchUiCommit(clearState: true);

    setState(() {
      _selectedTargetIds = selectedTargets.map((item) => item.id).toSet();
      _isSearching = true;
      _results = const [];
      _errorMessage = null;
      _totalSearchTaskCount = 0;
      _completedSearchTaskCount = 0;
      _filteredResultCount = 0;
    });

    final repository = ref.read(searchRepositoryProvider);
    final requestId = ++_activeSearchRequestId;
    final operations = _buildSearchOperations(
      repository: repository,
      keyword: keyword,
      targets: selectedTargets,
      localSources: localSources,
      enabledProviders: enabledProviders,
    );

    if (operations.isEmpty) {
      if (!mounted || requestId != _activeSearchRequestId) {
        return;
      }
      setState(() {
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _totalSearchTaskCount = operations.length;
      _completedSearchTaskCount = 0;
    });

    final aggregated = <SearchResult>[];
    final seenResourceKeys = <String>{};
    final errors = <String>[];
    var completed = 0;
    var filteredCount = 0;

    for (final operation in operations) {
      unawaited(
        _runSearchOperation(
          requestId: requestId,
          operation: operation,
          aggregated: aggregated,
          errors: errors,
          totalCount: operations.length,
          seenResourceKeys: seenResourceKeys,
          onCompleted: () => completed += 1,
          getCompleted: () => completed,
          onFiltered: (count) => filteredCount += count,
          getFiltered: () => filteredCount,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTelevision = ref.watch(isTelevisionProvider).valueOrNull ?? false;
    final networkStorage = ref.watch(_searchPageNetworkStorageProvider);
    final headerTopInset = kToolbarHeight;
    final enabledProviders =
        ref.watch(_searchPageVisibleSearchProvidersProvider);
    final localSources = ref.watch(_searchPageVisibleLocalSourcesProvider);
    final targets = _buildTargets(
      localSources: localSources,
      providers: enabledProviders,
    );

    return TvPageFocusScope(
      controller: _tvFocusMemoryController,
      scopeId: 'search',
      isTelevision: isTelevision,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            AppPageBackground(
              contentPadding: EdgeInsets.only(
                top: MediaQuery.paddingOf(context).top,
              ),
              child: FocusTraversalGroup(
                policy: OrderedTraversalPolicy(),
                child: ListView(
                  controller: _scrollController,
                  padding: EdgeInsets.zero,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        kAppPageHorizontalPadding,
                        headerTopInset,
                        kAppPageHorizontalPadding,
                        0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FocusTraversalOrder(
                            order: const NumericFocusOrder(1),
                            child: isTelevision
                                ? _TelevisionSearchInput(
                                    query: _controller.text.trim(),
                                    focusNode: _queryFocusNode,
                                    onEditQuery: _openTelevisionQueryDialog,
                                    onSearch: _performSearch,
                                  )
                                : TextField(
                                    controller: _controller,
                                    textInputAction: TextInputAction.search,
                                    onSubmitted: (_) => _performSearch(),
                                    decoration: InputDecoration(
                                      hintText: '搜索电影、剧集或番剧资源',
                                      suffixIcon: Padding(
                                        padding: const EdgeInsets.all(6),
                                        child: StarflowIconButton(
                                          icon: Icons.search_rounded,
                                          tooltip: '搜索',
                                          onPressed: _performSearch,
                                          variant: StarflowButtonVariant.ghost,
                                          size: 40,
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                          if (isTelevision && _recentQueries.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Text(
                              '最近搜索',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                for (var index = 0;
                                    index < _recentQueries.length;
                                    index++)
                                  _SearchHistoryChip(
                                    label: _recentQueries[index],
                                    autofocus: index == 0,
                                    focusId: 'search:recent:$index',
                                    onPressed: () =>
                                        _runRecentQuery(_recentQueries[index]),
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 10),
                          if (targets.length == 1)
                            const Text(
                              '还没有启用可搜索的来源，请先去设置页添加媒体源或搜索服务。',
                            )
                          else
                            FocusTraversalOrder(
                              order: const NumericFocusOrder(2),
                              child: isTelevision
                                  ? Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: [
                                        for (var index = 0;
                                            index < targets.length;
                                            index++)
                                          _SearchTargetChip(
                                            target: targets[index],
                                            selected: _selectedTargetIds
                                                .contains(targets[index].id),
                                            isTelevision: true,
                                            focusId:
                                                'search:target:${targets[index].id}',
                                            autofocus: index == 0 &&
                                                _recentQueries.isEmpty,
                                            onPressed: () {
                                              _toggleTargetSelection(
                                                targets[index],
                                                targets,
                                              );
                                              if (_controller.text
                                                  .trim()
                                                  .isNotEmpty) {
                                                _performSearch();
                                              }
                                            },
                                          ),
                                      ],
                                    )
                                  : SizedBox(
                                      height: 52,
                                      child: ListView.separated(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: targets.length,
                                        separatorBuilder: (context, index) =>
                                            const SizedBox(width: 8),
                                        itemBuilder: (context, index) {
                                          final target = targets[index];
                                          return _SearchTargetChip(
                                            target: target,
                                            selected: _selectedTargetIds
                                                .contains(target.id),
                                            isTelevision: false,
                                            onPressed: () {
                                              _toggleTargetSelection(
                                                target,
                                                targets,
                                              );
                                              if (_controller.text
                                                  .trim()
                                                  .isNotEmpty) {
                                                _performSearch();
                                              }
                                            },
                                          );
                                        },
                                      ),
                                    ),
                            ),
                          const SizedBox(height: 12),
                          if (_isSearching) ...[
                            LinearProgressIndicator(
                              value: _totalSearchTaskCount > 0
                                  ? _completedSearchTaskCount /
                                      _totalSearchTaskCount
                                  : null,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _results.isEmpty
                                  ? '正在搜索...'
                                  : '正在继续搜索 $_completedSearchTaskCount/$_totalSearchTaskCount',
                            ),
                            const SizedBox(height: 10),
                          ],
                          if (_controller.text.trim().isNotEmpty &&
                              (_results.isNotEmpty || _filteredResultCount > 0))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                '结果 ${_results.length} 条 · 过滤 $_filteredResultCount 条',
                              ),
                            ),
                          if (_errorMessage != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text('搜索失败：$_errorMessage'),
                            )
                          else if (_results.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                _controller.text.trim().isEmpty
                                    ? '输入关键字后开始搜索。'
                                    : _filteredResultCount > 0
                                        ? '没有可用结果，已过滤 $_filteredResultCount 条结果。'
                                        : '没有找到结果。',
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_results.isNotEmpty)
                      ..._results.asMap().entries.map(
                            (entry) => _SearchResultCard(
                              result: entry.value,
                              focusId: 'search:result:${entry.value.id}',
                              autofocus: entry.key == 0,
                              isSaving:
                                  _savingResultIds.contains(entry.value.id),
                              showSaveAction: _canSaveResultToQuark(
                                result: entry.value,
                                networkStorage: networkStorage,
                              ),
                              onSave: () => _saveResultToQuark(
                                result: entry.value,
                                networkStorage: networkStorage,
                              ),
                            ),
                          ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: OverlayToolbar(
                onBack: _handleBack,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openTelevisionQueryDialog() async {
    final controller = TextEditingController(text: _controller.text);
    final isTelevision = ref.read(isTelevisionProvider).valueOrNull ?? false;
    final queryFocusNode = FocusNode(debugLabel: 'search-query-dialog-field');
    final cancelFocusNode = FocusNode(debugLabel: 'search-query-dialog-cancel');
    final confirmFocusNode =
        FocusNode(debugLabel: 'search-query-dialog-submit');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final dialog = FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: AlertDialog(
            title: const Text('输入搜索关键字'),
            content: SizedBox(
              width: 420,
              child: FocusTraversalOrder(
                order: const NumericFocusOrder(1),
                child: wrapTelevisionDialogFieldTraversal(
                  enabled: isTelevision,
                  child: TextField(
                    controller: controller,
                    focusNode: queryFocusNode,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (value) =>
                        Navigator.of(dialogContext).pop(value),
                    decoration: const InputDecoration(
                      hintText: '电影、剧集、番剧...',
                    ),
                  ),
                ),
              ),
            ),
            actions: [
              FocusTraversalOrder(
                order: const NumericFocusOrder(2),
                child: StarflowButton(
                  label: '取消',
                  focusNode: cancelFocusNode,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  variant: StarflowButtonVariant.ghost,
                  compact: true,
                ),
              ),
              FocusTraversalOrder(
                order: const NumericFocusOrder(3),
                child: StarflowButton(
                  label: '搜索',
                  focusNode: confirmFocusNode,
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(controller.text),
                  compact: true,
                ),
              ),
            ],
          ),
        );
        return wrapTelevisionDialogBackHandling(
          enabled: isTelevision,
          dialogContext: dialogContext,
          inputFocusNodes: [queryFocusNode],
          contentFocusNodes: [queryFocusNode],
          actionFocusNodes: [confirmFocusNode, cancelFocusNode],
          child: dialog,
        );
      },
    );
    controller.dispose();
    queryFocusNode.dispose();
    cancelFocusNode.dispose();
    confirmFocusNode.dispose();
    if (!mounted || result == null) {
      return;
    }
    setState(() {
      _controller.text = result;
    });
    if (result.trim().isNotEmpty) {
      await _performSearch();
    }
  }

  List<_SearchOperation> _buildSearchOperations({
    required SearchRepository repository,
    required String keyword,
    required List<_SearchTarget> targets,
    required List<MediaSourceConfig> localSources,
    required List<SearchProviderConfig> enabledProviders,
  }) {
    final operations = <_SearchOperation>[];
    for (final target in targets) {
      switch (target.kind) {
        case _SearchTargetKind.all:
          operations.addAll([
            ...localSources.map(
              (source) => _SearchOperation(
                label: source.name,
                run: () => repository.searchLocal(
                  keyword,
                  sourceId: source.id,
                  limit: 80,
                ),
              ),
            ),
            ...enabledProviders.map(
              (provider) => _SearchOperation(
                label: provider.name,
                run: () => repository.searchOnline(
                  keyword,
                  provider: provider,
                ),
              ),
            ),
          ]);
          break;
        case _SearchTargetKind.mediaSource:
          operations.add(
            _SearchOperation(
              label: target.mediaSource!.name,
              run: () => repository.searchLocal(
                keyword,
                sourceId: target.mediaSource!.id,
                limit: 80,
              ),
            ),
          );
          break;
        case _SearchTargetKind.provider:
          operations.add(
            _SearchOperation(
              label: target.provider!.name,
              run: () => repository.searchOnline(
                keyword,
                provider: target.provider!,
              ),
            ),
          );
          break;
      }
    }
    return operations;
  }

  Future<void> _runSearchOperation({
    required int requestId,
    required _SearchOperation operation,
    required List<SearchResult> aggregated,
    required List<String> errors,
    required int totalCount,
    required Set<String> seenResourceKeys,
    required VoidCallback onCompleted,
    required int Function() getCompleted,
    required ValueChanged<int> onFiltered,
    required int Function() getFiltered,
  }) async {
    try {
      final result = await operation.run();
      if (!mounted || requestId != _activeSearchRequestId) {
        return;
      }
      var duplicateCount = 0;
      for (final item in result.items) {
        final key = normalizeSearchResourceUrl(item.resourceUrl).isEmpty
            ? item.id
            : normalizeSearchResourceUrl(item.resourceUrl);
        if (!seenResourceKeys.add(key)) {
          duplicateCount += 1;
          continue;
        }
        aggregated.add(item);
      }
      onFiltered(result.filteredCount + duplicateCount);
    } catch (error) {
      if (!mounted || requestId != _activeSearchRequestId) {
        return;
      }
      errors.add('${operation.label}: $error');
    } finally {
      if (mounted && requestId == _activeSearchRequestId) {
        onCompleted();
        final completed = getCompleted();
        final hasFinished = completed >= totalCount;
        _scheduleSearchUiCommit(
          requestId: requestId,
          aggregated: aggregated,
          errors: errors,
          totalCount: totalCount,
          completedCount: completed,
          filteredCount: getFiltered(),
          force: hasFinished,
        );
      }
    }
  }

  List<_SearchTarget> _buildTargets({
    required List<MediaSourceConfig> localSources,
    required List<SearchProviderConfig> providers,
  }) {
    return [
      const _SearchTarget.all(),
      ...localSources.map(_SearchTarget.mediaSource),
      ...providers.map(_SearchTarget.provider),
    ];
  }

  List<_SearchTarget> _resolveSelectedTargets(List<_SearchTarget> targets) {
    if (targets.isEmpty) {
      return const [];
    }

    if (_selectedTargetIds.contains(_SearchTarget.allId)) {
      return [targets.first];
    }

    final selected = targets
        .where((item) => _selectedTargetIds.contains(item.id))
        .toList(growable: false);
    if (selected.isEmpty) {
      return [targets.first];
    }
    return selected;
  }

  void _toggleTargetSelection(
    _SearchTarget target,
    List<_SearchTarget> targets,
  ) {
    final next = {..._selectedTargetIds};
    if (target.id == _SearchTarget.allId) {
      setState(() {
        _selectedTargetIds = {_SearchTarget.allId};
      });
      return;
    }

    next.remove(_SearchTarget.allId);
    if (next.contains(target.id)) {
      next.remove(target.id);
    } else {
      next.add(target.id);
    }

    setState(() {
      _selectedTargetIds = next.isEmpty ? {_SearchTarget.allId} : next;
    });
    unawaited(_persistSelectedTargets());
  }

  List<SearchResult> _sortResults(List<SearchResult> items) {
    final sorted = [...items];
    sorted.sort((left, right) {
      final localBoost = (right.detailTarget != null ? 1 : 0) -
          (left.detailTarget != null ? 1 : 0);
      if (localBoost != 0) {
        return localBoost;
      }
      return left.title.compareTo(right.title);
    });
    return sorted;
  }

  bool _canSaveResultToQuark({
    required SearchResult result,
    required NetworkStorageConfig networkStorage,
  }) {
    if (result.detailTarget != null) {
      return false;
    }
    final cloudType = detectSearchCloudTypeFromUrl(result.resourceUrl);
    if (cloudType != SearchCloudType.quark) {
      return false;
    }
    return networkStorage.quarkCookie.trim().isNotEmpty;
  }

  Future<void> _saveResultToQuark({
    required SearchResult result,
    required NetworkStorageConfig networkStorage,
  }) async {
    final storage = networkStorage;
    final cookie = storage.quarkCookie.trim();
    if (cookie.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在搜索设置里填写夸克 Cookie')),
      );
      return;
    }

    setState(() {
      _savingResultIds.add(result.id);
    });

    try {
      final response = await ref.read(quarkSaveClientProvider).saveShareLink(
            shareUrl: result.resourceUrl,
            cookie: cookie,
            toPdirFid: storage.quarkSaveFolderId,
            toPdirPath: storage.quarkSaveFolderPath,
            saveFolderName: _controller.text.trim().isNotEmpty
                ? _controller.text.trim()
                : result.title.trim(),
          );
      var triggeredTask = false;
      SmartStrmTriggerResult? smartStrmResult;
      final refreshDelaySeconds = _mediaRefreshDelaySeconds(storage);
      final smartStrmDelaySeconds = _smartStrmDelaySeconds(storage);
      if (storage.smartStrmWebhookUrl.trim().isNotEmpty &&
          storage.smartStrmTaskName.trim().isNotEmpty) {
        smartStrmResult =
            await ref.read(smartStrmWebhookClientProvider).triggerTask(
                  webhookUrl: storage.smartStrmWebhookUrl,
                  taskName: storage.smartStrmTaskName,
                  storagePath: storage.quarkSaveFolderPath == '/'
                      ? ''
                      : storage.quarkSaveFolderPath,
                  delay: smartStrmDelaySeconds,
                );
        triggeredTask = true;
      }
      final refreshSourceIds = storage.refreshMediaSourceIds
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
      if (refreshSourceIds.isNotEmpty) {
        unawaited(
          ref.read(mediaRefreshCoordinatorProvider).refreshSelectedSources(
                sourceIds: refreshSourceIds,
                delaySeconds: refreshDelaySeconds,
              ),
        );
      }
      if (!mounted) {
        return;
      }
      final message = response.taskId.isEmpty
          ? '已提交到夸克，保存 ${response.savedCount} 个文件'
          : '已提交到夸克，任务 ${response.taskId}';
      final strmMessage = triggeredTask
          ? _smartStrmSuccessMessage(
              smartStrmResult,
              delaySeconds: smartStrmDelaySeconds,
            )
          : '';
      final refreshMessage = refreshSourceIds.isEmpty
          ? ''
          : refreshDelaySeconds > 0
              ? '，$refreshDelaySeconds 秒后刷新媒体源'
              : '，即将刷新媒体源';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$message${strmMessage.isEmpty ? '' : '，$strmMessage'}$refreshMessage',
          ),
        ),
      );
    } on QuarkSaveException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } on SmartStrmWebhookException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('夸克保存成功，但 STRM 触发失败：${error.message}')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _savingResultIds.remove(result.id);
        });
      }
    }
  }

  int _mediaRefreshDelaySeconds(NetworkStorageConfig storage) {
    final configured = storage.refreshDelaySeconds;
    return configured <= 0 ? 1 : configured;
  }

  int _smartStrmDelaySeconds(NetworkStorageConfig storage) {
    final configured = storage.smartStrmDelaySeconds;
    return configured <= 0 ? 1 : configured;
  }

  String _smartStrmSuccessMessage(
    SmartStrmTriggerResult? result, {
    int delaySeconds = 0,
  }) {
    if (delaySeconds > 0) {
      return 'STRM 已延迟 $delaySeconds 秒触发';
    }
    if (result == null) {
      return '已触发 STRM 任务';
    }
    final addedCount = result.addedCount;
    if (addedCount != null) {
      return 'STRM 新增成功 $addedCount 条';
    }
    final message = result.message.trim();
    if (message.isNotEmpty) {
      return 'STRM $message';
    }
    return '已触发 STRM 任务';
  }
}

class _SearchResultCard extends ConsumerWidget {
  const _SearchResultCard({
    required this.result,
    required this.focusId,
    required this.autofocus,
    required this.isSaving,
    required this.showSaveAction,
    required this.onSave,
  });

  final SearchResult result;
  final String focusId;
  final bool autofocus;
  final bool isSaving;
  final bool showSaveAction;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isTelevision = ref.watch(isTelevisionProvider).valueOrNull ?? false;
    final posterUrl = result.posterUrl.trim();
    final resourceUri = _parseLaunchUri(result.resourceUrl);
    void onOpen() {
      if (result.detailTarget != null) {
        context.pushNamed('detail', extra: result.detailTarget);
        return;
      }
      if (resourceUri != null) {
        _openResourceUrl(context, resourceUri);
        return;
      }
      _showDetailDialog(
        context,
        result,
        isTelevision: isTelevision,
      );
    }

    final cardChild = Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: posterUrl.isEmpty
                    ? _SearchPosterPlaceholder(theme: theme)
                    : AppNetworkImage(
                        posterUrl,
                        headers: result.posterHeaders,
                        width: 72,
                        height: 102,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return _SearchPosterPlaceholder(theme: theme);
                        },
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            result.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (showSaveAction)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: isTelevision
                                ? TvAdaptiveButton(
                                    label: isSaving ? '保存中' : '保存',
                                    icon: Icons.bookmark_add_rounded,
                                    onPressed: isSaving ? null : onSave,
                                    variant: TvButtonVariant.text,
                                  )
                                : SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: StarflowIconButton(
                                      size: 32,
                                      tooltip: '保存到夸克',
                                      variant: StarflowButtonVariant.ghost,
                                      onPressed: isSaving ? null : onSave,
                                      icon: Icons.bookmark_add_rounded,
                                    ),
                                  ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      result.summary,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _MetaChip(label: result.providerName),
                        _MetaChip(label: result.quality),
                        _MetaChip(label: result.sizeLabel),
                        if (result.seeders > 0)
                          _MetaChip(label: '${result.seeders} seeders'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(
            height: 1,
            thickness: 0.5,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ],
      ),
    );

    if (isTelevision) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: TvFocusableAction(
          onPressed: onOpen,
          onContextAction: () => _showDetailDialog(
            context,
            result,
            isTelevision: isTelevision,
          ),
          focusId: focusId,
          autofocus: autofocus,
          borderRadius: BorderRadius.circular(18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh
                  .withValues(alpha: 0.74),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: cardChild,
          ),
        ),
      );
    }

    return TvFocusableAction(
      onPressed: onOpen,
      onContextAction: () => _showDetailDialog(
        context,
        result,
        isTelevision: isTelevision,
      ),
      borderRadius: BorderRadius.circular(18),
      child: cardChild,
    );
  }

  Future<void> _showDetailDialog(
    BuildContext context,
    SearchResult result, {
    required bool isTelevision,
  }) async {
    final resourceUri = _parseLaunchUri(result.resourceUrl);
    final detailLines = <String>[
      'Provider: ${result.providerName}',
      'Type: ${result.quality}',
      'Source: ${result.source.isEmpty ? '未知来源' : result.source}',
      'Password: ${result.password.isEmpty ? '无' : result.password}',
      if (result.publishedAt.isNotEmpty) 'Published At: ${result.publishedAt}',
      if (result.seeders > 0) 'Seeders: ${result.seeders}',
      if (result.summary.trim().isNotEmpty) '',
      if (result.summary.trim().isNotEmpty) result.summary,
    ];

    if (!isTelevision) {
      return showDialog<void>(
        context: context,
        builder: (context) {
          final theme = Theme.of(context);
          return AlertDialog(
            title: Text(
              result.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(detailLines.join('\n')),
                  if (result.resourceUrl.trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Resource URL:',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: resourceUri == null
                          ? null
                          : () => _openResourceUrl(context, resourceUri),
                      child: Text(
                        result.resourceUrl,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: resourceUri == null
                              ? theme.colorScheme.onSurfaceVariant
                              : theme.colorScheme.primary,
                          decoration: resourceUri == null
                              ? TextDecoration.none
                              : TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              if (resourceUri != null)
                StarflowButton(
                  label: '打开链接',
                  onPressed: () => _openResourceUrl(context, resourceUri),
                  variant: StarflowButtonVariant.secondary,
                  compact: true,
                ),
              StarflowButton(
                label: '关闭',
                onPressed: () => Navigator.of(context).pop(),
                variant: StarflowButtonVariant.ghost,
                compact: true,
              ),
            ],
          );
        },
      );
    }

    final openFocusNode = FocusNode(debugLabel: 'search-result-dialog-open');
    final closeFocusNode = FocusNode(debugLabel: 'search-result-dialog-close');
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          final theme = Theme.of(dialogContext);
          final dialog = AlertDialog(
            title: Text(
              result.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            content: FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(detailLines.join('\n')),
                    if (result.resourceUrl.trim().isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Resource URL:',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        result.resourceUrl,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              if (resourceUri != null)
                TvAdaptiveButton(
                  label: '打开链接',
                  icon: Icons.open_in_new_rounded,
                  onPressed: () => _openResourceUrl(dialogContext, resourceUri),
                  focusNode: openFocusNode,
                  autofocus: true,
                  focusId: 'search:result-dialog:open:${result.id}',
                ),
              TvAdaptiveButton(
                label: '关闭',
                icon: Icons.close_rounded,
                onPressed: () => Navigator.of(dialogContext).pop(),
                focusNode: closeFocusNode,
                autofocus: resourceUri == null,
                variant: TvButtonVariant.outlined,
                focusId: 'search:result-dialog:close:${result.id}',
              ),
            ],
          );
          return wrapTelevisionDialogBackHandling(
            enabled: isTelevision,
            dialogContext: dialogContext,
            inputFocusNodes: const <FocusNode>[],
            contentFocusNodes: const <FocusNode>[],
            actionFocusNodes: [
              if (resourceUri != null) openFocusNode,
              closeFocusNode,
            ],
            child: dialog,
          );
        },
      );
    } finally {
      openFocusNode.dispose();
      closeFocusNode.dispose();
    }
  }

  Uri? _parseLaunchUri(String rawUrl) {
    final trimmed = sanitizeSearchResourceUrl(rawUrl);
    if (trimmed.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) {
      return null;
    }
    return uri;
  }

  Future<void> _openResourceUrl(BuildContext context, Uri uri) async {
    bool launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (!context.mounted || launched) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('无法打开链接')),
    );
  }
}

class _TelevisionSearchInput extends StatelessWidget {
  const _TelevisionSearchInput({
    required this.query,
    this.focusNode,
    required this.onEditQuery,
    required this.onSearch,
  });

  final String query;
  final FocusNode? focusNode;
  final VoidCallback onEditQuery;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TvFocusableAction(
            onPressed: onEditQuery,
            focusNode: focusNode,
            focusId: 'search:query',
            autofocus: true,
            borderRadius: BorderRadius.circular(22),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '搜索关键字',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      query.isEmpty ? '按确认键输入电影、剧集或番剧资源' : query,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        TvAdaptiveButton(
          label: '搜索',
          icon: Icons.search_rounded,
          onPressed: onSearch,
          focusId: 'search:query-submit',
        ),
      ],
    );
  }
}

class _SearchHistoryChip extends StatelessWidget {
  const _SearchHistoryChip({
    required this.label,
    required this.onPressed,
    this.focusId,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback onPressed;
  final String? focusId;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return StarflowChipButton(
      label: label,
      onPressed: onPressed,
      focusId: focusId,
      autofocus: autofocus,
      selected: false,
    );
  }
}

class _SearchTargetChip extends StatelessWidget {
  const _SearchTargetChip({
    required this.target,
    required this.selected,
    required this.isTelevision,
    required this.onPressed,
    this.focusId,
    this.autofocus = false,
  });

  final _SearchTarget target;
  final bool selected;
  final bool isTelevision;
  final VoidCallback onPressed;
  final String? focusId;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return StarflowChipButton(
      label: target.label,
      selected: selected,
      onPressed: onPressed,
      focusId: focusId,
      autofocus: autofocus,
    );
  }
}

class _SearchPosterPlaceholder extends StatelessWidget {
  const _SearchPosterPlaceholder({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 102,
      color: theme.colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: const Icon(Icons.link_rounded),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .secondaryContainer
            .withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

enum _SearchTargetKind {
  all,
  mediaSource,
  provider,
}

class _SearchTarget {
  const _SearchTarget.all()
      : id = allId,
        label = '全部',
        kind = _SearchTargetKind.all,
        mediaSource = null,
        provider = null;

  _SearchTarget.mediaSource(this.mediaSource)
      : id = 'source:${mediaSource!.id}',
        label = mediaSource.name,
        kind = _SearchTargetKind.mediaSource,
        provider = null;

  _SearchTarget.provider(this.provider)
      : id = 'provider:${provider!.id}',
        label = provider.name,
        kind = _SearchTargetKind.provider,
        mediaSource = null;

  static const allId = 'all';

  final String id;
  final String label;
  final _SearchTargetKind kind;
  final MediaSourceConfig? mediaSource;
  final SearchProviderConfig? provider;
}

class _SearchOperation {
  const _SearchOperation({
    required this.label,
    required this.run,
  });

  final String label;
  final Future<SearchFetchResult> Function() run;
}
