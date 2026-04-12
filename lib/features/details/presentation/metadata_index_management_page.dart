import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/app_network_image.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/home/application/home_controller.dart';
import 'package:starflow/features/library/data/nas_media_index_models.dart';
import 'package:starflow/features/library/data/nas_media_indexer.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/presentation/library_collection_page.dart';
import 'package:starflow/features/library/presentation/library_page.dart';
import 'package:starflow/features/metadata/data/metadata_match_resolver.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';
import 'package:starflow/features/metadata/data/wmdb_metadata_client.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

class MetadataIndexManagementPage extends ConsumerStatefulWidget {
  const MetadataIndexManagementPage({
    super.key,
    required this.target,
  });

  final MediaDetailTarget target;

  @override
  ConsumerState<MetadataIndexManagementPage> createState() =>
      _MetadataIndexManagementPageState();
}

class _MetadataIndexManagementPageState
    extends ConsumerState<MetadataIndexManagementPage> {
  late MediaDetailTarget _currentTarget;
  late final TextEditingController _queryController;
  late final TextEditingController _yearController;
  late final FocusNode _queryFocusNode;
  late final FocusNode _yearFocusNode;
  late final FocusNode _preferSeriesFocusNode;
  late final FocusNode _searchFocusNode;
  late bool _preferSeries;
  late Future<NasMediaIndexRecord?> _recordFuture;
  final TvFocusMemoryController _tvFocusMemoryController =
      TvFocusMemoryController();

  bool _isSearching = false;
  bool _isApplying = false;
  bool _isAutoRefreshing = false;
  List<MetadataMatchResult> _wmdbResults = const <MetadataMatchResult>[];
  List<MetadataMatchResult> _tmdbResults = const <MetadataMatchResult>[];
  String _wmdbMessage = '';
  String _tmdbMessage = '';

  @override
  void initState() {
    super.initState();
    _currentTarget = widget.target;
    _queryController = TextEditingController(
      text: _currentTarget.searchQuery.trim().isNotEmpty
          ? _currentTarget.searchQuery.trim()
          : _currentTarget.title.trim(),
    );
    _yearController = TextEditingController(
      text: _currentTarget.year > 0 ? '${_currentTarget.year}' : '',
    );
    _queryFocusNode = FocusNode(debugLabel: 'metadata-index-query');
    _yearFocusNode = FocusNode(debugLabel: 'metadata-index-year');
    _preferSeriesFocusNode =
        FocusNode(debugLabel: 'metadata-index-prefer-series');
    _searchFocusNode = FocusNode(debugLabel: 'metadata-index-search');
    final itemType = _currentTarget.itemType.trim().toLowerCase();
    _preferSeries =
        itemType == 'series' || itemType == 'season' || itemType == 'episode';
    _recordFuture = _loadRecord();
  }

  @override
  void dispose() {
    _queryController.dispose();
    _yearController.dispose();
    _queryFocusNode.dispose();
    _yearFocusNode.dispose();
    _preferSeriesFocusNode.dispose();
    _searchFocusNode.dispose();
    _tvFocusMemoryController.dispose();
    super.dispose();
  }

  Future<NasMediaIndexRecord?> _loadRecord() {
    if (!_supportsLocalMetadataIndex(_currentTarget)) {
      return Future<NasMediaIndexRecord?>.value(null);
    }
    return ref.read(nasMediaIndexerProvider).loadRecord(
          sourceId: _currentTarget.sourceId,
          resourceId: _currentTarget.itemId,
        );
  }

  bool _supportsLocalMetadataIndex(MediaDetailTarget target) {
    return (target.sourceKind == MediaSourceKind.nas ||
            target.sourceKind == MediaSourceKind.quark) &&
        target.sourceId.trim().isNotEmpty &&
        target.itemId.trim().isNotEmpty;
  }

  String _effectiveSearchQuery() {
    final manual = _queryController.text.trim();
    if (manual.isNotEmpty) {
      return manual;
    }
    final cached = _currentTarget.searchQuery.trim();
    if (cached.isNotEmpty) {
      return cached;
    }
    return _currentTarget.title.trim();
  }

  int _effectiveSearchYear() {
    return int.tryParse(_yearController.text.trim()) ?? _currentTarget.year;
  }

  Future<void> _persistResolvedTarget(
    MediaDetailTarget resolvedTarget, {
    DetailMetadataRefreshStatus? metadataRefreshStatus,
    bool closePage = false,
  }) async {
    _currentTarget = resolvedTarget;
    setState(() {
      _recordFuture = _loadRecord();
    });
    await ref.read(localStorageCacheRepositoryProvider).saveDetailTarget(
          seedTarget: widget.target,
          resolvedTarget: resolvedTarget,
          metadataRefreshStatus: metadataRefreshStatus,
        );
    _invalidateReaders();
    if (!mounted || !closePage) {
      return;
    }
    context.pop(resolvedTarget);
  }

  Future<void> _runSearch() async {
    final query = _queryController.text.trim();
    final year = int.tryParse(_yearController.text.trim()) ?? 0;
    if (query.isEmpty) {
      _showSnackBar('请先输入要搜索的片名');
      return;
    }

    setState(() {
      _isSearching = true;
      _wmdbResults = const <MetadataMatchResult>[];
      _tmdbResults = const <MetadataMatchResult>[];
      _wmdbMessage = '';
      _tmdbMessage = '';
    });

    final settings = ref.read(appSettingsProvider);
    Future<(List<MetadataMatchResult>, String)> resolveTmdb() async {
      final token = settings.tmdbReadAccessToken.trim();
      if (token.isEmpty) {
        return (const <MetadataMatchResult>[], '未配置 TMDB Read Access Token。');
      }
      try {
        final client = ref.read(tmdbMetadataClientProvider);
        final results = (await client.searchTitleMatches(
          query: query,
          readAccessToken: token,
          year: year,
          preferSeries: _preferSeries,
          maxResults: 3,
        ))
            .map(_tmdbToMetadataMatch)
            .toList(growable: false);
        return (
          results,
          results.isEmpty ? '没有匹配到 TMDB 结果。' : '',
        );
      } catch (error) {
        return (const <MetadataMatchResult>[], '$error');
      }
    }

    Future<(List<MetadataMatchResult>, String)> resolveWmdb() async {
      try {
        final results =
            await ref.read(wmdbMetadataClientProvider).searchTitleMatches(
                  query: query,
                  year: year,
                  preferSeries: _preferSeries,
                  actors: _currentTarget.actors,
                  maxResults: 3,
                );
        return (results, results.isEmpty ? '没有匹配到 WMDB 结果。' : '');
      } catch (error) {
        return (const <MetadataMatchResult>[], '$error');
      }
    }

    final tmdbResolved = await resolveTmdb();
    final wmdbResolved = await resolveWmdb();
    if (!mounted) {
      return;
    }

    setState(() {
      _isSearching = false;
      _wmdbResults = wmdbResolved.$1;
      _wmdbMessage = wmdbResolved.$2;
      _tmdbResults = tmdbResolved.$1;
      _tmdbMessage = tmdbResolved.$2;
    });
  }

  Widget _wrapTelevisionSearchField({
    required bool enabled,
    required FocusNode focusNode,
    required Widget child,
  }) {
    final wrapped = wrapTelevisionDialogFieldTraversal(
      enabled: enabled,
      child: child,
    );
    if (!enabled) {
      return wrapped;
    }
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.goBack): DismissIntent(),
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        SingleActivator(LogicalKeyboardKey.backspace): DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              focusNode.unfocus();
              if (_searchFocusNode.canRequestFocus) {
                _searchFocusNode.requestFocus();
              }
              return null;
            },
          ),
        },
        child: wrapped,
      ),
    );
  }

  MetadataMatchResult _tmdbToMetadataMatch(TmdbMetadataMatch match) {
    return MetadataMatchResult(
      provider: MetadataMatchProvider.tmdb,
      title: match.title,
      originalTitle: match.originalTitle,
      posterUrl: match.posterUrl,
      backdropUrl: match.backdropUrl,
      logoUrl: match.logoUrl,
      extraBackdropUrls: match.extraBackdropUrls,
      overview: match.overview,
      year: match.year,
      durationLabel: match.durationLabel,
      genres: match.genres,
      directors: match.directors,
      directorProfiles: match.directorProfiles
          .map(
            (item) => MetadataPersonProfile(
              name: item.name,
              avatarUrl: item.avatarUrl,
            ),
          )
          .toList(growable: false),
      actors: match.actors,
      actorProfiles: match.actorProfiles
          .map(
            (item) => MetadataPersonProfile(
              name: item.name,
              avatarUrl: item.avatarUrl,
            ),
          )
          .toList(growable: false),
      platforms: match.platforms,
      platformProfiles: match.platformProfiles
          .map(
            (item) => MetadataPersonProfile(
              name: item.name,
              avatarUrl: item.avatarUrl,
            ),
          )
          .toList(growable: false),
      ratingLabels: match.ratingLabels,
      imdbId: match.imdbId,
      tmdbId: '${match.tmdbId}',
    );
  }

  Future<void> _applyMetadataMatch(MetadataMatchResult match) async {
    if (_isApplying) {
      return;
    }
    setState(() {
      _isApplying = true;
    });

    try {
      final searchQuery = _effectiveSearchQuery();
      final updatedTarget = _supportsLocalMetadataIndex(_currentTarget)
          ? await ref.read(nasMediaIndexerProvider).applyManualMetadata(
                target: _currentTarget,
                searchQuery: searchQuery,
                metadataMatch: match,
              )
          : null;
      final resolvedTarget = _applyMetadataResultToTarget(
        (updatedTarget ?? _currentTarget).copyWith(
          searchQuery: searchQuery.isEmpty
              ? (updatedTarget ?? _currentTarget).searchQuery
              : searchQuery,
        ),
        match,
      );
      await _persistResolvedTarget(
        resolvedTarget,
        metadataRefreshStatus: DetailMetadataRefreshStatus.succeeded,
        closePage: true,
      );
    } catch (error) {
      _showSnackBar('保存信息失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _isApplying = false;
        });
      }
    }
  }

  MediaDetailTarget _applyMetadataResultToTarget(
    MediaDetailTarget target,
    MetadataMatchResult? match,
  ) {
    var nextTarget = target;
    if (match != null) {
      final directorProfiles = match.directorProfiles
          .map(
            (item) => MediaPersonProfile(
              name: item.name,
              avatarUrl: item.avatarUrl,
            ),
          )
          .toList(growable: false);
      final actorProfiles = match.actorProfiles
          .map(
            (item) => MediaPersonProfile(
              name: item.name,
              avatarUrl: item.avatarUrl,
            ),
          )
          .toList(growable: false);
      final platformProfiles = match.platformProfiles
          .map(
            (item) => MediaPersonProfile(
              name: item.name,
              avatarUrl: item.avatarUrl,
            ),
          )
          .toList(growable: false);
      nextTarget = nextTarget.copyWith(
        title: match.title.trim().isNotEmpty ? match.title : nextTarget.title,
        posterUrl: match.posterUrl.trim().isNotEmpty
            ? match.posterUrl
            : nextTarget.posterUrl,
        posterHeaders: match.posterUrl.trim().isNotEmpty
            ? const <String, String>{}
            : nextTarget.posterHeaders,
        backdropUrl: match.backdropUrl.trim().isNotEmpty
            ? match.backdropUrl
            : nextTarget.backdropUrl,
        backdropHeaders: match.backdropUrl.trim().isNotEmpty
            ? const <String, String>{}
            : nextTarget.backdropHeaders,
        logoUrl: match.logoUrl.trim().isNotEmpty
            ? match.logoUrl
            : nextTarget.logoUrl,
        logoHeaders: match.logoUrl.trim().isNotEmpty
            ? const <String, String>{}
            : nextTarget.logoHeaders,
        bannerUrl: match.bannerUrl.trim().isNotEmpty
            ? match.bannerUrl
            : nextTarget.bannerUrl,
        bannerHeaders: match.bannerUrl.trim().isNotEmpty
            ? const <String, String>{}
            : nextTarget.bannerHeaders,
        extraBackdropUrls: match.extraBackdropUrls.isNotEmpty
            ? match.extraBackdropUrls
            : nextTarget.extraBackdropUrls,
        extraBackdropHeaders: match.extraBackdropUrls.isNotEmpty
            ? const <String, String>{}
            : nextTarget.extraBackdropHeaders,
        overview: match.overview.trim().isNotEmpty
            ? match.overview
            : nextTarget.overview,
        year: match.year > 0 ? match.year : nextTarget.year,
        durationLabel: match.durationLabel.trim().isNotEmpty
            ? match.durationLabel
            : nextTarget.durationLabel,
        genres: match.genres.isNotEmpty ? match.genres : nextTarget.genres,
        directors:
            match.directors.isNotEmpty ? match.directors : nextTarget.directors,
        directorProfiles: directorProfiles.isNotEmpty
            ? directorProfiles
            : nextTarget.directorProfiles,
        actors: match.actors.isNotEmpty ? match.actors : nextTarget.actors,
        actorProfiles:
            actorProfiles.isNotEmpty ? actorProfiles : nextTarget.actorProfiles,
        platforms: match.provider == MetadataMatchProvider.tmdb
            ? match.platforms
            : (match.platforms.isNotEmpty
                ? match.platforms
                : nextTarget.platforms),
        platformProfiles: match.provider == MetadataMatchProvider.tmdb
            ? platformProfiles
            : (platformProfiles.isNotEmpty
                ? platformProfiles
                : nextTarget.platformProfiles),
        ratingLabels: _mergeLabels(nextTarget.ratingLabels, match.ratingLabels),
        doubanId: match.doubanId.trim().isNotEmpty
            ? match.doubanId
            : nextTarget.doubanId,
        imdbId:
            match.imdbId.trim().isNotEmpty ? match.imdbId : nextTarget.imdbId,
        tmdbId:
            match.tmdbId.trim().isNotEmpty ? match.tmdbId : nextTarget.tmdbId,
      );
    }
    return nextTarget;
  }

  List<String> _mergeLabels(
    List<String> primary,
    List<String> secondary,
  ) {
    final seen = <String>{};
    final merged = <String>[];
    for (final label in [...primary, ...secondary]) {
      final trimmed = label.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final normalized = trimmed.toLowerCase();
      if (!seen.add(normalized)) {
        continue;
      }
      merged.add(trimmed);
    }
    return merged;
  }

  void _invalidateReaders() {
    for (final filter in LibraryFilter.values) {
      ref.invalidate(librarySeedItemsProvider(filter));
      ref.invalidate(libraryItemsProvider(filter));
    }
    ref.invalidate(libraryCollectionItemsProvider);
    ref.invalidate(homeRecentItemsProvider);
    ref.invalidate(homeCarouselItemsProvider);
    ref.invalidate(homeSectionProvider);
    ref.invalidate(homeSectionsProvider);
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _runAutomaticRefresh() async {
    if (_isAutoRefreshing) {
      return;
    }
    setState(() {
      _isAutoRefreshing = true;
    });

    try {
      final resolvedTarget = await _resolveAutomaticRefreshTarget();
      final changed = _hasMetadataChanged(_currentTarget, resolvedTarget);
      if (!mounted) {
        return;
      }

      await _persistResolvedTarget(
        resolvedTarget,
        metadataRefreshStatus: DetailMetadataRefreshStatus.succeeded,
      );
      _showSnackBar(changed ? '已自动更新信息' : '没有可更新的信息');
    } catch (error) {
      await ref.read(localStorageCacheRepositoryProvider).saveDetailTarget(
            seedTarget: widget.target,
            resolvedTarget: _currentTarget,
            metadataRefreshStatus: DetailMetadataRefreshStatus.failed,
          );
      _showSnackBar('自动更新失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _isAutoRefreshing = false;
        });
      }
    }
  }

  Future<MediaDetailTarget> _resolveAutomaticRefreshTarget() async {
    final searchQuery = _effectiveSearchQuery();
    final searchYear = _effectiveSearchYear();
    final searchBaseTarget = _currentTarget.copyWith(
      searchQuery:
          searchQuery.isEmpty ? _currentTarget.searchQuery : searchQuery,
      year: searchYear > 0 ? searchYear : _currentTarget.year,
    );

    if (_supportsLocalMetadataIndex(searchBaseTarget)) {
      final indexedTarget = await ref
          .read(nasMediaIndexerProvider)
          .enrichDetailTargetMetadataIfNeeded(searchBaseTarget);
      if (indexedTarget != null) {
        await ref
            .read(nasMediaIndexerProvider)
            .markDetailTargetMetadataManuallyManaged(searchBaseTarget);
        return indexedTarget.copyWith(
          searchQuery:
              searchQuery.isEmpty ? indexedTarget.searchQuery : searchQuery,
          year: searchYear > 0 ? searchYear : indexedTarget.year,
        );
      }
    }

    final settings = ref.read(appSettingsProvider);
    var nextTarget = searchBaseTarget;
    final metadataMatch = await ref.read(metadataMatchResolverProvider).match(
          settings: settings,
          request: MetadataMatchRequest(
            query: searchQuery,
            doubanId: nextTarget.doubanId,
            year: searchYear,
            preferSeries: _preferSeries,
            actors: nextTarget.actors,
          ),
        );
    if (metadataMatch != null) {
      nextTarget = _applyMetadataResultToTarget(nextTarget, metadataMatch);
    }

    return nextTarget;
  }

  @override
  Widget build(BuildContext context) {
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    return TvFocusMemoryScope(
      controller: _tvFocusMemoryController,
      scopeId: 'detail:metadata-index',
      enabled: isTelevision,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AppPageBackground(
          contentPadding: appPageContentPadding(context),
          child: Stack(
            children: [
              FocusTraversalGroup(
                policy: OrderedTraversalPolicy(),
                child: FutureBuilder<NasMediaIndexRecord?>(
                  future: _recordFuture,
                  builder: (context, snapshot) {
                    return ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        SizedBox(
                          height: MediaQuery.paddingOf(context).top +
                              kToolbarHeight +
                              12,
                        ),
                        _SectionPanel(
                          title: '信息管理',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _currentTarget.title,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '所有详情页都可以在这里手动搜索 WMDB / TMDB。有本地索引时写回索引，没有本地索引时写回当前详情缓存。',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: isTelevision
                                    ? TvAdaptiveButton(
                                        label: _isAutoRefreshing
                                            ? '更新中...'
                                            : '自动更新',
                                        icon: Icons.refresh_rounded,
                                        focusId: 'detail:index:auto-refresh',
                                        onPressed: _isAutoRefreshing
                                            ? null
                                            : _runAutomaticRefresh,
                                      )
                                    : FilledButton.icon(
                                        onPressed: _isAutoRefreshing
                                            ? null
                                            : _runAutomaticRefresh,
                                        icon: _isAutoRefreshing
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                              )
                                            : const Icon(
                                                Icons.refresh_rounded,
                                              ),
                                        label: Text(
                                          _isAutoRefreshing ? '更新中...' : '自动更新',
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _SectionPanel(
                          title: _supportsLocalMetadataIndex(_currentTarget)
                              ? '当前索引'
                              : '当前缓存',
                          child: snapshot.connectionState ==
                                  ConnectionState.waiting
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: LinearProgressIndicator(),
                                )
                              : snapshot.hasError
                                  ? Text('读取索引失败：${snapshot.error}')
                                  : _CurrentIndexCard(
                                      record: snapshot.data,
                                      supportsLocalIndex:
                                          _supportsLocalMetadataIndex(
                                        _currentTarget,
                                      ),
                                    ),
                        ),
                        const SizedBox(height: 16),
                        _SectionPanel(
                          title: '手动搜索',
                          child: Column(
                            children: [
                              FocusTraversalOrder(
                                order: const NumericFocusOrder(1),
                                child: _wrapTelevisionSearchField(
                                  enabled: isTelevision,
                                  focusNode: _queryFocusNode,
                                  child: TextField(
                                    controller: _queryController,
                                    focusNode: _queryFocusNode,
                                    textInputAction: TextInputAction.search,
                                    decoration: const InputDecoration(
                                      labelText: '片名 / 搜索词',
                                      hintText: '输入要手动匹配的片名',
                                      border: OutlineInputBorder(),
                                    ),
                                    onSubmitted: (_) => _runSearch(),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  FocusTraversalOrder(
                                    order: const NumericFocusOrder(2),
                                    child: SizedBox(
                                      width: 120,
                                      child: _wrapTelevisionSearchField(
                                        enabled: isTelevision,
                                        focusNode: _yearFocusNode,
                                        child: TextField(
                                          controller: _yearController,
                                          focusNode: _yearFocusNode,
                                          keyboardType: TextInputType.number,
                                          textInputAction: TextInputAction.done,
                                          decoration: const InputDecoration(
                                            labelText: '年份',
                                            hintText: '可选',
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FocusTraversalOrder(
                                      order: const NumericFocusOrder(3),
                                      child: isTelevision
                                          ? TvFocusableAction(
                                              onPressed: () {
                                                setState(() {
                                                  _preferSeries =
                                                      !_preferSeries;
                                                });
                                              },
                                              focusNode: _preferSeriesFocusNode,
                                              focusId:
                                                  'detail:index:prefer-series',
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .surfaceContainerHighest,
                                                  borderRadius:
                                                      BorderRadius.circular(18),
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 14,
                                                  vertical: 16,
                                                ),
                                                child: Row(
                                                  children: [
                                                    const Expanded(
                                                      child: Text(
                                                        '按剧集优先匹配',
                                                      ),
                                                    ),
                                                    Icon(
                                                      _preferSeries
                                                          ? Icons
                                                              .check_circle_rounded
                                                          : Icons
                                                              .radio_button_unchecked_rounded,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            )
                                          : StarflowToggleTile(
                                              title: '按剧集优先匹配',
                                              value: _preferSeries,
                                              onChanged: (value) {
                                                setState(() {
                                                  _preferSeries = value;
                                                });
                                              },
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: FocusTraversalOrder(
                                  order: const NumericFocusOrder(4),
                                  child: isTelevision
                                      ? TvAdaptiveButton(
                                          label:
                                              _isSearching ? '搜索中...' : '开始搜索',
                                          icon: Icons.manage_search_rounded,
                                          autofocus: true,
                                          focusNode: _searchFocusNode,
                                          onPressed:
                                              _isSearching ? null : _runSearch,
                                          focusId: 'detail:index:search',
                                        )
                                      : FilledButton.icon(
                                          onPressed:
                                              _isSearching ? null : _runSearch,
                                          icon: _isSearching
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  ),
                                                )
                                              : const Icon(
                                                  Icons.manage_search_rounded,
                                                ),
                                          label: Text(
                                            _isSearching ? '搜索中...' : '开始搜索',
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _ProviderResultCard(
                          title: 'WMDB',
                          results: _wmdbResults,
                          message: _wmdbMessage,
                          actionLabel: '应用 WMDB 结果',
                          isApplying: _isApplying,
                          isTelevision: isTelevision,
                          focusIdPrefix: 'detail:index:apply:wmdb',
                          onApply: _applyMetadataMatch,
                        ),
                        const SizedBox(height: 12),
                        _ProviderResultCard(
                          title: 'TMDB',
                          results: _tmdbResults,
                          message: _tmdbMessage,
                          actionLabel: '应用 TMDB 结果',
                          isApplying: _isApplying,
                          isTelevision: isTelevision,
                          focusIdPrefix: 'detail:index:apply:tmdb',
                          onApply: _applyMetadataMatch,
                        ),
                        const SizedBox(height: 24),
                        appPageBottomSpacer(),
                      ],
                    );
                  },
                ),
              ),
              OverlayToolbar(
                onBack: () => Navigator.of(context).maybePop(_currentTarget),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _hasMetadataChanged(
  MediaDetailTarget current,
  MediaDetailTarget next,
) {
  return current.title != next.title ||
      current.posterUrl != next.posterUrl ||
      current.backdropUrl != next.backdropUrl ||
      current.logoUrl != next.logoUrl ||
      current.bannerUrl != next.bannerUrl ||
      !_sameStrings(current.extraBackdropUrls, next.extraBackdropUrls) ||
      current.overview != next.overview ||
      current.year != next.year ||
      current.durationLabel != next.durationLabel ||
      !_sameStrings(current.ratingLabels, next.ratingLabels) ||
      !_sameStrings(current.genres, next.genres) ||
      !_sameStrings(current.directors, next.directors) ||
      !_samePeople(current.directorProfiles, next.directorProfiles) ||
      !_sameStrings(current.actors, next.actors) ||
      !_samePeople(current.actorProfiles, next.actorProfiles) ||
      !_sameStrings(current.platforms, next.platforms) ||
      !_samePeople(current.platformProfiles, next.platformProfiles) ||
      current.doubanId != next.doubanId ||
      current.imdbId != next.imdbId ||
      current.tmdbId != next.tmdbId ||
      current.tvdbId != next.tvdbId ||
      current.wikidataId != next.wikidataId ||
      current.tmdbSetId != next.tmdbSetId ||
      !_sameMaps(current.providerIds, next.providerIds);
}

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

bool _samePeople(
  List<MediaPersonProfile> left,
  List<MediaPersonProfile> right,
) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index].name != right[index].name ||
        left[index].avatarUrl != right[index].avatarUrl) {
      return false;
    }
  }
  return true;
}

bool _sameMaps(
  Map<String, String> left,
  Map<String, String> right,
) {
  if (left.length != right.length) {
    return false;
  }
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

class _SectionPanel extends StatelessWidget {
  const _SectionPanel({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _CurrentIndexCard extends StatelessWidget {
  const _CurrentIndexCard({
    required this.record,
    required this.supportsLocalIndex,
  });

  final NasMediaIndexRecord? record;
  final bool supportsLocalIndex;

  @override
  Widget build(BuildContext context) {
    if (record == null) {
      return Text(
        supportsLocalIndex
            ? '没有找到当前资源的本地索引记录。你仍然可以直接搜索并写入，命中的信息会先保存到当前详情缓存。'
            : '当前资源没有本地索引能力。这里保存的结果会直接写入当前详情缓存。',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
    }

    final lines = <String>[
      '当前标题：${record!.item.title}',
      '搜索词：${record!.searchQuery.trim().isEmpty ? '无' : record!.searchQuery}',
      '识别标题：${record!.recognizedTitle.trim().isEmpty ? '无' : record!.recognizedTitle}',
      '资源路径：${record!.resourcePath}',
      '命中来源：${_matchFlags(record!)}',
      '上次刮削：${_formatTime(record!.scrapedAt)}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(line),
          ),
      ],
    );
  }

  String _matchFlags(NasMediaIndexRecord record) {
    final flags = <String>[
      if (record.sidecarMatched) 'Sidecar',
      if (record.wmdbMatched) 'WMDB',
      if (record.tmdbMatched) 'TMDB',
    ];
    return flags.isEmpty ? '无' : flags.join(' / ');
  }
}

class _ProviderResultCard extends StatelessWidget {
  const _ProviderResultCard({
    required this.title,
    required this.results,
    required this.message,
    required this.actionLabel,
    required this.isApplying,
    required this.isTelevision,
    required this.onApply,
    this.focusIdPrefix,
  });

  final String title;
  final List<MetadataMatchResult> results;
  final String message;
  final String actionLabel;
  final bool isApplying;
  final bool isTelevision;
  final Future<void> Function(MetadataMatchResult result)? onApply;
  final String? focusIdPrefix;

  @override
  Widget build(BuildContext context) {
    final visibleResults = results.take(3).toList(growable: false);
    return _SectionPanel(
      title: title,
      child: visibleResults.isEmpty
          ? Text(
              message.trim().isEmpty ? '还没有搜索结果。' : message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < visibleResults.length; index++) ...[
                  _MatchPreviewCard(
                    title: visibleResults[index].title,
                    imageUrl: visibleResults[index].posterUrl,
                    lines: [
                      '年份：${visibleResults[index].year > 0 ? visibleResults[index].year : '未知'}',
                      if (visibleResults[index].doubanId.trim().isNotEmpty)
                        '豆瓣 ID：${visibleResults[index].doubanId}',
                      if (visibleResults[index].imdbId.trim().isNotEmpty)
                        'IMDb ID：${visibleResults[index].imdbId}',
                      if (visibleResults[index].tmdbId.trim().isNotEmpty)
                        'TMDB ID：${visibleResults[index].tmdbId}',
                      if (visibleResults[index].ratingLabels.isNotEmpty)
                        '评分：${visibleResults[index].ratingLabels.join(' · ')}',
                    ],
                    overview: visibleResults[index].overview,
                  ),
                  const SizedBox(height: 12),
                  isTelevision
                      ? TvAdaptiveButton(
                          label: isApplying ? '应用中...' : actionLabel,
                          icon: Icons.save_rounded,
                          onPressed: isApplying
                              ? null
                              : () {
                                  onApply?.call(visibleResults[index]);
                                },
                          focusId: focusIdPrefix == null
                              ? null
                              : '$focusIdPrefix:$index',
                        )
                      : FilledButton.icon(
                          onPressed: isApplying
                              ? null
                              : () {
                                  onApply?.call(visibleResults[index]);
                                },
                          icon: isApplying
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_rounded),
                          label: Text(actionLabel),
                        ),
                  if (index < visibleResults.length - 1)
                    const SizedBox(height: 16),
                ],
              ],
            ),
    );
  }
}

class _MatchPreviewCard extends StatelessWidget {
  const _MatchPreviewCard({
    required this.title,
    required this.lines,
    this.imageUrl = '',
    this.overview = '',
  });

  final String title;
  final List<String> lines;
  final String imageUrl;
  final String overview;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imageUrl.trim().isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AppNetworkImage(
                imageUrl,
                width: 88,
                height: 128,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _PosterPlaceholder(title: title);
                },
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(line),
                  ),
                if (overview.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    overview,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PosterPlaceholder extends StatelessWidget {
  const _PosterPlaceholder({
    required this.title,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    final firstLetter =
        title.trim().isEmpty ? '?' : title.trim().substring(0, 1);
    return Container(
      width: 88,
      height: 128,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        firstLetter.toUpperCase(),
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

String _formatTime(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}
