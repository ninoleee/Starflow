import 'package:starflow/core/logging/app_logger.dart';
import 'dart:async';

export 'package:starflow/features/details/presentation/detail_page_providers.dart'
    show enrichedDetailTargetProvider;

import 'package:flutter/foundation.dart';
import 'package:starflow/features/details/application/detail_metadata_service.dart';
import 'package:flutter/material.dart';
import 'package:starflow/app/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/navigation/page_activity_mixin.dart';
import 'package:starflow/core/navigation/retained_async_controller.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/application/detail_enrichment_settings.dart';
import 'package:starflow/features/details/application/detail_external_episode_variant_service.dart';
import 'package:starflow/features/details/application/detail_library_match_service.dart';
import 'package:starflow/features/details/application/detail_library_match_coordinator.dart';
import 'package:starflow/features/details/application/detail_online_resource_update_service.dart';
import 'package:starflow/features/details/application/detail_page_actions.dart';
import 'package:starflow/features/details/application/detail_page_controller.dart';
import 'package:starflow/features/details/application/detail_target_resolver.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/detail_page_providers.dart';
import 'package:starflow/features/details/presentation/person_credits_page.dart';
import 'package:starflow/features/details/presentation/widgets/detail_episode_browser.dart';
import 'package:starflow/features/details/presentation/widgets/detail_overview_section.dart';
import 'package:starflow/features/details/presentation/widgets/detail_hero_section.dart';
import 'package:starflow/features/details/presentation/widgets/detail_resource_info_section.dart';
import 'package:starflow/features/details/presentation/widgets/detail_shared_widgets.dart';
import 'package:starflow/features/details/presentation/widgets/detail_television_picker_dialog.dart';
import 'package:starflow/features/discovery/data/douban_api_client.dart';
import 'package:starflow/features/library/data/media_server_client.dart';
import 'package:starflow/features/library/data/media_repository.dart';
import 'package:starflow/features/library/data/nas_media_indexer.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/metadata/data/metadata_match_resolver.dart';
import 'package:starflow/features/metadata/application/metadata_prefetch_concurrency_limiter.dart';
import 'package:starflow/features/metadata/data/metadata_network_guard.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';
import 'package:starflow/features/metadata/data/wmdb_metadata_client.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';
import 'package:starflow/features/playback/application/playback_session.dart';
import 'package:starflow/features/playback/application/playback_engine_support.dart';
import 'package:starflow/features/search/application/cloud_save_dispatcher.dart';
import 'package:starflow/features/search/domain/cloud_save_feedback.dart';
import 'package:starflow/features/search/presentation/cloud_save_feedback_controller.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/search/data/cloud115_save_client.dart';
import 'package:starflow/features/search/data/search_preferences_repository.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

const DetailLibraryMatchService _detailLibraryMatchService =
    DetailLibraryMatchService();
final DetailCachedStateRestorer _detailCachedStateRestorer =
    DetailCachedStateRestorer();

String _detailMetadataQuery(MediaDetailTarget target) {
  final raw =
      target.searchQuery.trim().isEmpty ? target.title : target.searchQuery;
  return raw.trim();
}

bool _prefersSeriesMetadata(MediaDetailTarget target) {
  final itemType = target.itemType.trim().toLowerCase();
  return itemType == 'series' || itemType == 'season' || itemType == 'episode';
}

bool _isOverviewMetadataRefreshTarget(MediaDetailTarget target) {
  final itemType = target.itemType.trim().toLowerCase();
  if (itemType == 'episode' || itemType == 'season') {
    return false;
  }
  if (target.episodeNumber != null && target.episodeNumber! > 0) {
    return false;
  }
  return true;
}

bool _canAttemptDetailMetadataRefresh({
  required DetailEnrichmentSettings settings,
  required MediaDetailTarget target,
}) {
  final query = _detailMetadataQuery(target);
  final doubanId = target.doubanId.trim();
  final canUseWmdb = settings.wmdbMetadataMatchEnabled &&
      (query.isNotEmpty || doubanId.isNotEmpty);
  final canUseTmdb = settings.tmdbMetadataMatchEnabled &&
      settings.tmdbReadAccessToken.trim().isNotEmpty &&
      query.isNotEmpty;
  return canUseWmdb || canUseTmdb;
}

bool _hasExistingMetadataRefreshMarker(MediaDetailTarget target) {
  if (target.doubanId.trim().isNotEmpty ||
      target.imdbId.trim().isNotEmpty ||
      target.tmdbId.trim().isNotEmpty ||
      target.tvdbId.trim().isNotEmpty ||
      target.wikidataId.trim().isNotEmpty ||
      target.tmdbSetId.trim().isNotEmpty ||
      target.providerIds.isNotEmpty) {
    return true;
  }
  return !target.needsMetadataMatch && !target.needsImdbRatingMatch;
}

bool _shouldAutoRefreshOverviewMetadata({
  required MediaDetailTarget pageTarget,
  required MediaDetailTarget currentTarget,
  required DetailEnrichmentSettings settings,
  required DetailMetadataRefreshStatus refreshStatus,
}) {
  if (refreshStatus != DetailMetadataRefreshStatus.never) {
    return false;
  }
  if (!_isOverviewMetadataRefreshTarget(pageTarget) ||
      !_isOverviewMetadataRefreshTarget(currentTarget)) {
    return false;
  }
  final shouldRefreshPersonProfiles = settings.tmdbMetadataMatchEnabled &&
      settings.tmdbReadAccessToken.trim().isNotEmpty &&
      (pageTarget.needsPersonProfileMatch ||
          currentTarget.needsPersonProfileMatch);
  if (!shouldRefreshPersonProfiles &&
      (_hasExistingMetadataRefreshMarker(pageTarget) ||
          _hasExistingMetadataRefreshMarker(currentTarget))) {
    return false;
  }
  return _canAttemptDetailMetadataRefresh(
    settings: settings,
    target: currentTarget,
  );
}

String _detailTraceKey(MediaDetailTarget target) {
  final id = [
    target.title.trim(),
    target.searchQuery.trim(),
    target.sourceId.trim(),
    target.itemId.trim(),
    target.doubanId.trim(),
    target.tmdbId.trim(),
  ].where((item) => item.isNotEmpty).join('|');
  return id.isEmpty ? 'detail' : id;
}

String _detailResourceTraceTarget(MediaDetailTarget? target) {
  if (target == null) {
    return '';
  }
  final playback = target.playbackTarget;
  final path = _detailLibraryMatchService.normalizeLibraryMatchPath(
    playback?.actualAddress ?? target.resourcePath,
  );
  final stream = _detailLibraryMatchService
      .normalizeLibraryMatchPath(playback?.streamUrl ?? '');
  final identity = path.isNotEmpty ? path : stream;
  return [
    target.sourceName.trim().isEmpty ? '-' : target.sourceName.trim(),
    target.itemType.trim().isEmpty ? '-' : target.itemType.trim(),
    target.itemId.trim().isEmpty ? '-' : target.itemId.trim(),
    target.isPlayable ? 'playable' : 'not-playable',
    target.sectionName.trim().isEmpty ? '-' : target.sectionName.trim(),
    identity.isEmpty ? '-' : identity,
  ].join(' | ');
}

bool _hasMetadataChanged(
  MediaDetailTarget current,
  MediaDetailTarget next,
) {
  return current.posterUrl != next.posterUrl ||
      current.backdropUrl != next.backdropUrl ||
      current.logoUrl != next.logoUrl ||
      current.bannerUrl != next.bannerUrl ||
      !listEquals(current.extraBackdropUrls, next.extraBackdropUrls) ||
      current.overview != next.overview ||
      current.year != next.year ||
      current.durationLabel != next.durationLabel ||
      !listEquals(current.ratingLabels, next.ratingLabels) ||
      current.ratingCount != next.ratingCount ||
      !listEquals(current.genres, next.genres) ||
      !listEquals(current.directors, next.directors) ||
      !_samePeople(
        current.directorProfiles,
        next.directorProfiles,
      ) ||
      !listEquals(current.actors, next.actors) ||
      !_samePeople(
        current.actorProfiles,
        next.actorProfiles,
      ) ||
      !listEquals(current.platforms, next.platforms) ||
      !_samePeople(
        current.platformProfiles,
        next.platformProfiles,
      ) ||
      current.doubanId != next.doubanId ||
      current.imdbId != next.imdbId ||
      current.tmdbId != next.tmdbId ||
      current.tvdbId != next.tvdbId ||
      current.wikidataId != next.wikidataId ||
      current.tmdbSetId != next.tmdbSetId ||
      !mapEquals(current.providerIds, next.providerIds);
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

Future<MetadataMatchResult?> _tryPreferredMetadataMatch({
  required MetadataMatchResolver metadataMatchResolver,
  required AppSettings settings,
  required MediaDetailTarget target,
  required String query,
}) async {
  try {
    return await metadataMatchResolver.match(
      settings: settings,
      request: MetadataMatchRequest(
        query: query,
        doubanId: target.doubanId,
        year: target.year,
        preferSeries: _prefersSeriesMetadata(target),
        actors: target.actors,
      ),
    );
  } catch (error, stackTrace) {
    appLogError('detail-resource', 'resource.match.metadata.error',
        fields: {
          'target': target.title,
          'query': query,
        },
        error: error,
        stackTrace: stackTrace);
    return null;
  }
}

List<MediaDetailTarget> _mergeExpandedLibraryChoices(
  Iterable<MediaDetailTarget> choices,
) {
  final merged = <MediaDetailTarget>[];
  final seenKeys = <String>{};
  for (final choice in choices) {
    final key = _libraryMatchTargetKey(choice);
    if (!seenKeys.add(key)) {
      continue;
    }
    merged.add(choice);
  }
  return merged;
}

String _detailLibrarySourceKey(MediaDetailTarget target) {
  final kind = (target.sourceKind ?? MediaSourceKind.nas).name;
  final sourceId = target.sourceId.trim();
  if (sourceId.isNotEmpty) {
    return '$kind|id:$sourceId';
  }
  return '$kind|name:${target.sourceName.trim().toLowerCase()}';
}

List<MediaDetailTarget> _buildDetailSourceChoices(
  DetailLibraryMatchViewState viewData,
) {
  final choices = viewData.choices;
  if (choices.length <= 1) {
    return choices;
  }

  final grouped = <String, List<MediaDetailTarget>>{};
  for (final choice in choices) {
    grouped.putIfAbsent(_detailLibrarySourceKey(choice), () => []).add(choice);
  }
  final selectedChoice = choices[viewData.effectiveSelectedIndex];
  final selectedSourceKey = _detailLibrarySourceKey(selectedChoice);
  return [
    for (final entry in grouped.entries)
      entry.key == selectedSourceKey ? selectedChoice : entry.value.first,
  ];
}

DetailLibraryMatchViewState _buildDetailSourceView(
  DetailLibraryMatchViewState viewData,
) {
  final choices = _buildDetailSourceChoices(viewData);
  if (choices.isEmpty) {
    return viewData.copyWith(choices: choices, selectedIndex: 0);
  }
  final selectedSourceKey = _detailLibrarySourceKey(
    viewData.choices[viewData.effectiveSelectedIndex],
  );
  final selectedIndex = choices.indexWhere(
    (choice) => _detailLibrarySourceKey(choice) == selectedSourceKey,
  );
  return viewData.copyWith(
    choices: choices,
    selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
  );
}

DetailLibraryMatchViewState _buildDetailPlayableVariantView(
  DetailLibraryMatchViewState viewData,
) {
  if (viewData.choices.isEmpty) {
    return viewData;
  }
  final selectedChoice = viewData.choices[viewData.effectiveSelectedIndex];
  final selectedSourceKey = _detailLibrarySourceKey(selectedChoice);
  final choices = viewData.choices
      .where(
        (choice) =>
            choice.isPlayable &&
            _detailLibrarySourceKey(choice) == selectedSourceKey,
      )
      .toList(growable: false);
  if (choices.isEmpty) {
    return viewData.copyWith(choices: choices, selectedIndex: 0);
  }
  final selectedChoiceKey = _libraryMatchTargetKey(selectedChoice);
  final selectedIndex = choices.indexWhere(
    (choice) => _libraryMatchTargetKey(choice) == selectedChoiceKey,
  );
  return viewData.copyWith(
    choices: choices,
    selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
  );
}

int _resolveExpandedLibraryMatchIndex({
  required MediaDetailTarget target,
  required List<MediaDetailTarget> choices,
}) {
  if (choices.isEmpty) {
    return 0;
  }

  final targetMediaSourceId =
      target.playbackTarget?.preferredMediaSourceId.trim() ?? '';
  if (targetMediaSourceId.isNotEmpty) {
    final byMediaSourceId = choices.indexWhere(
      (choice) =>
          choice.playbackTarget?.preferredMediaSourceId.trim() ==
          targetMediaSourceId,
    );
    if (byMediaSourceId >= 0) {
      return byMediaSourceId;
    }
  }

  final targetKey = _libraryMatchTargetKey(target);
  final byKey = choices.indexWhere(
    (choice) => _libraryMatchTargetKey(choice) == targetKey,
  );
  if (byKey >= 0) {
    return byKey;
  }

  final targetPath = _detailLibraryMatchService.normalizeLibraryMatchPath(
    target.playbackTarget?.actualAddress ?? target.resourcePath,
  );
  if (targetPath.isNotEmpty) {
    final byPath = choices.indexWhere(
      (choice) =>
          _detailLibraryMatchService.normalizeLibraryMatchPath(
            choice.playbackTarget?.actualAddress ?? choice.resourcePath,
          ) ==
          targetPath,
    );
    if (byPath >= 0) {
      return byPath;
    }
  }

  final targetItemId = target.itemId.trim();
  if (targetItemId.isNotEmpty) {
    final byItemId = choices.indexWhere(
      (choice) => choice.itemId.trim() == targetItemId,
    );
    if (byItemId >= 0) {
      return byItemId;
    }
  }

  return 0;
}

String _libraryMatchTargetKey(MediaDetailTarget target) {
  final playback = target.playbackTarget;
  final normalizedAddress =
      _detailLibraryMatchService.normalizeLibraryMatchPath(
    playback?.actualAddress ?? target.resourcePath,
  );
  final normalizedStreamUrl =
      _detailLibraryMatchService.normalizeLibraryMatchPath(
    playback?.streamUrl ?? '',
  );
  final variantIdentity =
      normalizedAddress.isNotEmpty ? normalizedAddress : normalizedStreamUrl;
  return [
    (target.sourceKind ?? MediaSourceKind.nas).name,
    target.sourceId.trim(),
    target.itemId.trim(),
    playback?.itemId.trim() ?? '',
    playback?.preferredMediaSourceId.trim() ?? '',
    variantIdentity,
  ].join('|');
}

class MediaDetailPage extends ConsumerStatefulWidget {
  const MediaDetailPage({super.key, required this.target});

  final MediaDetailTarget target;

  @override
  ConsumerState<MediaDetailPage> createState() => _MediaDetailPageState();
}

class _MediaDetailPageState extends ConsumerState<MediaDetailPage>
    with PageActivityMixin<MediaDetailPage> {
  bool _isRefreshingMetadata = false;
  bool _isCheckingOnlineResourceUpdate = false;
  bool _onlineResourceUpdateInProgress = false;
  bool _isSavingOnlineResourceUpdate = false;
  late final _saveFeedback = CloudSaveFeedbackController(
    () => mounted ? context : null,
    isActive: () => isPageActive,
  );
  bool _showDeferredDetailContent = false;
  bool _detailEnrichmentReady = false;
  bool _seriesSourceReady = false;
  late MediaDetailTarget _initialDisplayTarget;
  Future<CachedDetailState?>? _initialDetailCacheFuture;
  int _initialDetailCacheGeneration = 0;
  MediaDetailTarget? _retainedTargetSeed;
  DetailSeriesBrowserRequest? _retainedSeriesRequest;
  DetailSeriesBrowserRequest? _selectedSeasonRequest;
  bool _deferredDetailContentScheduled = false;
  List<SearchResult> _favoriteSearchResults = const <SearchResult>[];
  DetailLibraryMatchTaskController? _activeLibraryMatchController;
  late final DetailPageController _pageController;
  final ValueNotifier<String> _selectedSeasonIdNotifier =
      ValueNotifier<String>('');
  final ScrollController _scrollController = ScrollController();
  final FocusNode _heroArtworkFocusNode =
      FocusNode(debugLabel: 'detail-hero-artwork');
  final FocusNode _heroPlayFocusNode =
      FocusNode(debugLabel: 'detail-hero-play');
  final RetainedAsyncController<MediaDetailTarget> _retainedTargetAsync =
      RetainedAsyncController<MediaDetailTarget>();
  final RetainedAsyncController<DetailSeriesBrowserState?>
      _retainedSeriesAsync =
      RetainedAsyncController<DetailSeriesBrowserState?>();

  int get _detailSessionId => _pageController.detailSessionId;
  MediaDetailTarget? get _manualOverrideTarget =>
      _pageController.manualOverrideTarget;
  bool get _isMatchingLocalResource => _pageController.isMatchingLocalResource;
  List<MediaDetailTarget> get _libraryMatchChoices =>
      _pageController.libraryMatchChoices;
  int get _selectedLibraryMatchIndex =>
      _pageController.selectedLibraryMatchIndex;

  @override
  void initState() {
    super.initState();
    _pageController = DetailPageController();
    _prepareInitialDetailCache();
    _scrollController.addListener(_deferPrefetchForForegroundInteraction);
  }

  @override
  void didUpdateWidget(covariant MediaDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target.sourceId != widget.target.sourceId ||
        oldWidget.target.sourceKind != widget.target.sourceKind ||
        oldWidget.target.itemId != widget.target.itemId ||
        oldWidget.target.itemType != widget.target.itemType ||
        oldWidget.target.seasonNumber != widget.target.seasonNumber ||
        oldWidget.target.episodeNumber != widget.target.episodeNumber ||
        oldWidget.target.title != widget.target.title ||
        oldWidget.target.searchQuery != widget.target.searchQuery) {
      _cancelDetailTasks(
        additionalTargets: [oldWidget.target],
      );
      _selectedSeasonIdNotifier.value = '';
      _isRefreshingMetadata = false;
      _showDeferredDetailContent = false;
      _detailEnrichmentReady = false;
      _seriesSourceReady = false;
      _retainedTargetSeed = null;
      _deferredDetailContentScheduled = false;
      _pageController.resetForTargetChange();
      _retainedTargetAsync.clear();
      _retainedSeriesAsync.clear();
      _prepareInitialDetailCache();
      if (isPageVisible) {
        _startDetailTasks();
      }
    }
  }

  void _prepareInitialDetailCache() {
    final generation = ++_initialDetailCacheGeneration;
    final seed = widget.target;
    final cache = ref.read(localStorageCacheRepositoryProvider);
    final cachedState = cache.peekDetailState(
      seed,
      allowStructuralMismatch: true,
    );
    if (cachedState != null) {
      _initialDisplayTarget = _buildInitialDisplayTarget(seed, cachedState);
      _initialDetailCacheFuture = Future.value(cachedState);
      return;
    }

    // Do not request seed artwork until the local cache has been checked.
    _initialDisplayTarget = seed.copyWith(
      posterUrl: '',
      posterHeaders: const {},
      backdropUrl: '',
      backdropHeaders: const {},
      logoUrl: '',
      logoHeaders: const {},
      bannerUrl: '',
      bannerHeaders: const {},
      extraBackdropUrls: const [],
      extraBackdropHeaders: const {},
    );
    _initialDetailCacheFuture = Future<CachedDetailState?>.sync(
      () => cache.loadDetailState(seed, allowStructuralMismatch: true),
    ).catchError((Object error, StackTrace stackTrace) {
      appLogError('detail-resource', 'cache.initial.error',
          fields: {'target': _detailResourceTraceTarget(seed)},
          error: error,
          stackTrace: stackTrace);
      return null;
    }).then((state) {
      if (mounted && generation == _initialDetailCacheGeneration) {
        setState(() {
          _initialDisplayTarget = _buildInitialDisplayTarget(seed, state);
        });
      }
      return state;
    });
  }

  MediaDetailTarget _buildInitialDisplayTarget(
    MediaDetailTarget seed,
    CachedDetailState? cachedState,
  ) {
    if (cachedState == null) {
      return seed;
    }
    final plan = _detailCachedStateRestorer.buildPlan(
      pageSeedTarget: seed,
      cachedState: cachedState,
    );
    return plan.manualOverrideTarget ??
        mergeCachedDetailArtwork(seed, cachedState.target);
  }

  @override
  void dispose() {
    _cancelActiveLibraryMatch();
    _saveFeedback.dispose();
    _pageController.dispose();
    _selectedSeasonIdNotifier.dispose();
    _heroArtworkFocusNode.dispose();
    _heroPlayFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void onPageBecameActive() {
    _deferPrefetchForForegroundInteraction(reason: 'detail.page-active');
    unawaited(_loadFavoriteSearchResults());
    _startDetailTasks();
  }

  void _deferPrefetchForForegroundInteraction({
    String reason = 'detail.scroll',
  }) {
    if (!mounted || !isPageVisible) {
      return;
    }
    ref
        .read(metadataPrefetchConcurrencyLimiterProvider)
        .deferForForegroundInteraction(
          reason: reason,
          resumeDelay: Duration(
            milliseconds: ref
                .read(appSettingsProvider)
                .metadataPrefetchForegroundResumeDelayMs,
          ),
        );
  }

  @override
  void onPageBecameInactive() {
    _cancelDetailTasks(
      invalidateProviders: false,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isRefreshingMetadata = false;
      _isCheckingOnlineResourceUpdate = false;
      _deferredDetailContentScheduled = false;
    });
    _updateLibraryMatchView(isMatching: false);
  }

  void _scheduleDeferredDetailContent() {
    if (_showDeferredDetailContent || _deferredDetailContentScheduled) {
      return;
    }
    _deferredDetailContentScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 180), () {
        if (!mounted || !isPageVisible || _showDeferredDetailContent) {
          _deferredDetailContentScheduled = false;
          return;
        }
        setState(() {
          _showDeferredDetailContent = true;
          _deferredDetailContentScheduled = false;
        });
      });
    });
  }

  void _scrollDetailHeroToTop() {
    void scrollToTop() {
      if (!_scrollController.hasClients) {
        return;
      }
      final targetOffset = _scrollController.position.minScrollExtent;
      if ((_scrollController.offset - targetOffset).abs() < 1) {
        return;
      }
      _scrollController.jumpTo(targetOffset);
    }

    if (!_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          scrollToTop();
        }
      });
      return;
    }
    scrollToTop();
  }

  Future<void> _loadFavoriteSearchResults() async {
    final favorites = await ref
        .read(searchPreferencesRepositoryProvider)
        .loadFavoriteResults();
    if (!mounted) {
      return;
    }
    setState(() {
      _favoriteSearchResults = favorites;
    });
  }

  Future<void> _checkFavoriteOnlineResourceUpdate(
    MediaDetailTarget target,
  ) async {
    if (_onlineResourceUpdateInProgress || _isSavingOnlineResourceUpdate) {
      return;
    }
    _onlineResourceUpdateInProgress = true;
    final pageTarget = widget.target;
    final overrideTarget = _manualOverrideTarget;
    bool isCurrent() =>
        mounted &&
        identical(widget.target, pageTarget) &&
        identical(_manualOverrideTarget, overrideTarget) &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    setState(() {
      _isCheckingOnlineResourceUpdate = true;
    });
    try {
      await _loadFavoriteSearchResults();
      if (!mounted || !isCurrent()) return;
      final service = ref.read(detailOnlineResourceUpdateServiceProvider);
      final networkStorage = ref.read(
        appSettingsProvider.select((settings) => settings.networkStorage),
      );
      final matches = service.resolveFavoriteMatches(
        target: target,
        favorites: _favoriteSearchResults,
      );
      if (matches.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('还没有可用于检查更新的在线收藏资源')),
        );
        return;
      }
      if (matches.length > 1) {
        setState(() => _isCheckingOnlineResourceUpdate = false);
      }
      final favoriteMatch = matches.length == 1
          ? matches.single
          : await showDetailTelevisionPickerDialog<
              DetailFavoriteSearchResourceMatch>(
              context: context,
              enabled: ref.read(isTelevisionProvider).value ?? false,
              title: '选择更新来源',
              options: [
                for (var index = 0; index < matches.length; index++)
                  DetailTelevisionPickerOption(
                    value: matches[index],
                    title:
                        '${matches[index].drive.label} · ${matches[index].result.title}',
                    subtitle: matches[index].hasConfiguredCookie(networkStorage)
                        ? '保存目录：${matches[index].folderName}'
                        : '未配置此网盘 Cookie',
                    focusId: 'detail:update-source:$index',
                    icon: Icons.cloud_outlined,
                  ),
              ],
              selectedValue: null,
              optionDebugLabelPrefix: 'detail-update-source',
              closeFocusDebugLabel: 'detail-update-source-close',
              closeFocusId: 'detail:update-source:close',
            );
      if (favoriteMatch == null || !isCurrent()) return;
      setState(() => _isCheckingOnlineResourceUpdate = true);
      final result = await service.checkForUpdates(
        target: target,
        favoriteMatch: favoriteMatch,
        networkStorage: networkStorage,
        quarkSaveClient: ref.read(quarkSaveClientProvider),
        cloud115SaveClient: ref.read(cloud115SaveClientProvider),
      );
      if (!isCurrent()) return;
      setState(() => _isCheckingOnlineResourceUpdate = false);
      final shouldSave = await _showOnlineResourceUpdateDialog(
        title: result.hasUpdates ? '发现更新' : '检查更新',
        message: result.buildDialogMessage(),
        canSave: result.hasUpdates,
        drive: favoriteMatch.drive,
      );
      if (!isCurrent() || !shouldSave) {
        return;
      }
      await _saveFavoriteOnlineResourceUpdate(
        favoriteMatch: result.favoriteMatch,
        networkStorage: networkStorage,
      );
    } catch (error, stackTrace) {
      appLogError('detail-resource', 'online-update.check.error',
          fields: <String, Object?>{
            'target': _detailResourceTraceTarget(target),
          },
          error: error,
          stackTrace: stackTrace);
      if (!mounted || !isCurrent()) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('检查更新失败：$error')),
      );
    } finally {
      _onlineResourceUpdateInProgress = false;
      if (mounted) {
        setState(() {
          _isCheckingOnlineResourceUpdate = false;
        });
      }
    }
  }

  Future<bool> _showOnlineResourceUpdateDialog({
    required String title,
    required String message,
    required CloudSaveDrive drive,
    bool canSave = false,
  }) async {
    final isTelevision = ref.read(isTelevisionProvider).value ?? false;
    final saveFocusNode = FocusNode(debugLabel: 'detail-update-save');
    final closeFocusNode = FocusNode(debugLabel: 'detail-update-close');
    var dialogClosed = false;
    var initialFocusRequested = false;
    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          if (isTelevision && !initialFocusRequested) {
            initialFocusRequested = true;
            scheduleTelevisionDialogInitialFocus(
              enabled: true,
              focusNode: canSave ? saveFocusNode : closeFocusNode,
              dialogFocusNodes: [if (canSave) saveFocusNode, closeFocusNode],
              isActive: () => !dialogClosed,
            );
          }
          final dialog = AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(
              child: SelectableText(message),
            ),
            actions: [
              if (canSave)
                if (isTelevision)
                  TvAdaptiveButton(
                    label:
                        '保存到${drive == CloudSaveDrive.cloud115 ? ' 115' : '夸克'}',
                    icon: Icons.bookmark_add_rounded,
                    focusNode: saveFocusNode,
                    autofocus: true,
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    focusId: 'detail:update-dialog:save',
                  )
                else
                  TextButton.icon(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    icon: const Icon(Icons.bookmark_add_rounded),
                    label: Text(
                        '保存到${drive == CloudSaveDrive.cloud115 ? ' 115' : '夸克'}'),
                  ),
              if (isTelevision)
                TvAdaptiveButton(
                  label: '关闭',
                  icon: Icons.close_rounded,
                  focusNode: closeFocusNode,
                  autofocus: !canSave,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  focusId: 'detail:update-dialog:close',
                  variant: TvButtonVariant.outlined,
                )
              else
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('关闭'),
                ),
            ],
          );
          return wrapTelevisionDialogBackHandling(
            enabled: isTelevision,
            dialogContext: dialogContext,
            inputFocusNodes: const <FocusNode>[],
            contentFocusNodes: const <FocusNode>[],
            actionFocusNodes: isTelevision
                ? [
                    if (canSave) saveFocusNode,
                    closeFocusNode,
                  ]
                : const <FocusNode>[],
            child: dialog,
          );
        },
      );
      return result == true;
    } finally {
      dialogClosed = true;
      saveFocusNode.dispose();
      closeFocusNode.dispose();
    }
  }

  Future<void> _saveFavoriteOnlineResourceUpdate({
    required DetailFavoriteSearchResourceMatch favoriteMatch,
    required NetworkStorageConfig networkStorage,
  }) async {
    if (_isSavingOnlineResourceUpdate) {
      return;
    }

    final drive = favoriteMatch.drive;
    if (!favoriteMatch.hasConfiguredCookie(networkStorage)) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请先在网盘与转存设置中配置${drive.label} Cookie')),
      );
      return;
    }

    setState(() {
      _isSavingOnlineResourceUpdate = true;
    });

    final feedback = _saveFeedback.start();

    try {
      final outcome = await ref.read(cloudSaveDispatcherProvider).save(
            result: favoriteMatch.result,
            saveFolderName: favoriteMatch.folderName,
            networkStorage: networkStorage,
            onProgress: feedback.showProgress,
            onBackgroundRefreshFailure: feedback.showRefreshFailure,
          );
      if (!outcome.isSuccess) {
        appLogError('detail-resource', 'online-update.save.error',
            fields: <String, Object?>{
              'favoriteId': favoriteMatch.result.id,
              'errorType': outcome.failureKind?.name,
            },
            error: outcome.error,
            stackTrace: outcome.stackTrace);
        feedback.fail(outcome.message);
        return;
      }
      feedback.complete(outcome.message);
    } catch (error, stackTrace) {
      appLogError('detail-resource', 'online-update.save.error',
          fields: <String, Object?>{
            'favoriteId': favoriteMatch.result.id,
            'errorType': 'unexpected',
          },
          error: error,
          stackTrace: stackTrace);
      feedback.fail('保存失败：$error');
    } finally {
      feedback.closeProgress();
      if (mounted) {
        setState(() {
          _isSavingOnlineResourceUpdate = false;
        });
      }
    }
  }

  void _cancelActiveLibraryMatch() {
    _activeLibraryMatchController?.cancel();
    _activeLibraryMatchController = null;
  }

  void _cancelDetailTasks({
    bool invalidateProviders = true,
    Iterable<MediaDetailTarget> additionalTargets = const [],
  }) {
    _cancelActiveLibraryMatch();
    _pageController.startNewSession();
    if (!invalidateProviders) {
      return;
    }
    _invalidateDetailProviders(additionalTargets: additionalTargets);
  }

  void _invalidateDetailProviders({
    Iterable<MediaDetailTarget> additionalTargets = const [],
  }) {
    final targets = dedupeDetailInvalidationTargets(
      seedTarget: widget.target,
      manualOverrideTarget: _manualOverrideTarget,
      additionalTargets: additionalTargets,
    );
    for (final target in targets) {
      ref.invalidate(enrichedDetailTargetProvider(target));
      if (target.isSeries) {
        ref.invalidate(
          detailSeriesBrowserProvider(
            DetailSeriesBrowserRequest.fromTarget(target),
          ),
        );
      }
    }
  }

  void _updateLibraryMatchView({
    List<MediaDetailTarget>? choices,
    int? selectedIndex,
    bool? isMatching,
  }) {
    _pageController.updateLibraryMatchView(
      choices: choices,
      selectedIndex: selectedIndex,
      isMatching: isMatching,
    );
  }

  void _startDetailTasks() {
    final initialPlan = buildDetailStartupPlan(
      isPageVisible: isPageVisible,
      backgroundWorkSuspended: ref.read(backgroundEnrichmentSuspendedProvider),
      pageSeedTarget: widget.target,
      manualOverrideTarget: _manualOverrideTarget,
      detailAutoLibraryMatchEnabled: false,
    );
    if (!initialPlan.shouldStart) {
      return;
    }
    final sessionId = _pageController.startNewSession();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isSessionActive(sessionId)) {
        return;
      }
      final foregroundLease = ref
          .read(metadataPrefetchConcurrencyLimiterProvider)
          .beginForegroundWork(
            reason: 'detail.startup',
            resumeDelay: Duration(
              milliseconds: ref
                  .read(appSettingsProvider)
                  .metadataPrefetchForegroundResumeDelayMs,
            ),
          );
      unawaited(
        _runDeferredDetailStartup(sessionId)
            .whenComplete(foregroundLease.release)
            .catchError(
          (Object error, StackTrace stackTrace) {
            if (_isSessionActive(sessionId) && !_detailEnrichmentReady) {
              setState(() {
                _detailEnrichmentReady = true;
                _seriesSourceReady = true;
              });
            }
            appLogError('detail-resource', 'startup.error',
                fields: <String, Object?>{
                  'sessionId': sessionId,
                  'target': _detailResourceTraceTarget(widget.target),
                },
                error: error,
                stackTrace: stackTrace);
          },
        ),
      );
    });
  }

  Future<void> _runDeferredDetailStartup(int sessionId) async {
    final isTelevision = ref.read(isTelevisionProvider).value ?? false;
    if (isTelevision) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!_isSessionActive(sessionId)) {
        return;
      }
    }
    await Future<void>.delayed(Duration.zero);
    if (!_isSessionActive(sessionId)) {
      return;
    }

    final initialPlan = buildDetailStartupPlan(
      isPageVisible: isPageVisible,
      backgroundWorkSuspended: ref.read(backgroundEnrichmentSuspendedProvider),
      pageSeedTarget: widget.target,
      manualOverrideTarget: _manualOverrideTarget,
      detailAutoLibraryMatchEnabled: false,
    );
    if (!initialPlan.shouldStart) {
      return;
    }

    if (!_isSessionActive(sessionId)) {
      return;
    }

    final hasInMemoryDetailState =
        _manualOverrideTarget != null || _libraryMatchChoices.isNotEmpty;
    var restoredMetadataRefreshStatus = DetailMetadataRefreshStatus.never;
    if (!hasInMemoryDetailState) {
      restoredMetadataRefreshStatus = await _restoreCachedDetailState(
        sessionId,
      );
      if (!_isSessionActive(sessionId)) {
        return;
      }

      final restoredTarget = _manualOverrideTarget ?? widget.target;
      await _restoreIndexedEpisodeVariantChoices(
        sessionId,
        restoredTarget,
      );
      if (!_isSessionActive(sessionId)) {
        return;
      }
    }

    final detailAutoLibraryMatchEnabled = ref.read(
      appSettingsProvider.select(
        (settings) => settings.detailAutoLibraryMatchEnabled,
      ),
    );
    // Browsing needs restored source identity, not online metadata.
    if (!_seriesSourceReady) {
      setState(() => _seriesSourceReady = true);
    }
    final runtimePlan = buildDetailStartupPlan(
      isPageVisible: isPageVisible,
      backgroundWorkSuspended: ref.read(backgroundEnrichmentSuspendedProvider),
      pageSeedTarget: widget.target,
      manualOverrideTarget: _manualOverrideTarget,
      detailAutoLibraryMatchEnabled: detailAutoLibraryMatchEnabled,
    );
    var currentTarget = runtimePlan.effectiveTarget;
    final enrichmentSettings = ref.read(detailEnrichmentSettingsProvider);
    if (_shouldAutoRefreshOverviewMetadata(
      pageTarget: widget.target,
      currentTarget: currentTarget,
      settings: enrichmentSettings,
      refreshStatus: restoredMetadataRefreshStatus,
    )) {
      await _refreshMetadata(
        currentTarget,
        sessionId: sessionId,
        showFeedback: false,
      );
      if (!_isSessionActive(sessionId)) {
        return;
      }
      currentTarget = _manualOverrideTarget ?? currentTarget;
    }

    // Restore and refresh before subscribing to enrichment, so startup does
    // not race a second resolver against the cache being restored.
    if (!_detailEnrichmentReady) {
      setState(() => _detailEnrichmentReady = true);
    }

    if (!runtimePlan.shouldAttemptAutoLibraryMatch) {
      return;
    }

    final resolved = await ref.read(
      enrichedDetailTargetProvider(currentTarget).future,
    );
    final shouldAutoMatchSeriesSources = shouldAutoMatchSeriesOverviewSources(
      pageSeedTarget: widget.target,
      libraryMatchChoices: _libraryMatchChoices,
    );
    if (!_isSessionActive(sessionId) ||
        (_manualOverrideTarget != null && !shouldAutoMatchSeriesSources) ||
        ref.read(backgroundEnrichmentSuspendedProvider)) {
      return;
    }
    final autoMatchTarget = shouldAutoMatchSeriesSources
        ? buildSeriesOverviewSourceMatchSeed(
            pageSeedTarget: widget.target,
            resolvedTarget: resolved,
          )
        : resolved;
    if (!shouldAutoMatchDetailLocalResource(autoMatchTarget) &&
        !shouldAutoMatchSeriesSources) {
      return;
    }
    await _matchLocalResource(
      autoMatchTarget,
      sessionId: sessionId,
      showFeedback: false,
    );
  }

  bool _isSessionActive(int sessionId) {
    return _pageController.isSessionActive(
      sessionId,
      isMounted: mounted,
      isPageVisible: isPageVisible,
    );
  }

  bool _isLibraryMatchActive(
    int sessionId,
    DetailLibraryMatchTaskController controller,
  ) {
    return _isSessionActive(sessionId) &&
        identical(_activeLibraryMatchController, controller) &&
        !controller.cancelled;
  }

  Future<DetailMetadataRefreshStatus> _restoreCachedDetailState(
    int sessionId,
  ) async {
    final cachedState = await (_initialDetailCacheFuture ??
        ref.read(localStorageCacheRepositoryProvider).loadDetailState(
              widget.target,
              allowStructuralMismatch: true,
            ));
    if (!_isSessionActive(sessionId)) {
      return DetailMetadataRefreshStatus.never;
    }
    _initialDetailCacheFuture = null;
    if (cachedState == null) {
      return DetailMetadataRefreshStatus.never;
    }
    final restorePlan = _detailCachedStateRestorer.buildPlan(
      pageSeedTarget: widget.target,
      cachedState: cachedState,
    );
    _updateLibraryMatchView(
      choices: restorePlan.libraryMatchChoices,
      selectedIndex: restorePlan.selectedLibraryMatchIndex,
      isMatching: false,
    );
    final manualOverrideTarget = restorePlan.manualOverrideTarget;
    if (manualOverrideTarget == null) {
      return cachedState.metadataRefreshStatus;
    }
    _pageController.setManualOverrideTarget(manualOverrideTarget);
    return cachedState.metadataRefreshStatus;
  }

  Future<void> _restoreIndexedEpisodeVariantChoices(
    int sessionId,
    MediaDetailTarget currentTarget,
  ) async {
    if (currentTarget.isSeries) {
      return;
    }
    final expandedState = await _expandEpisodeLikeLibraryMatchChoices(
      baseChoices:
          _libraryMatchChoices.isEmpty ? [currentTarget] : _libraryMatchChoices,
      selectedTarget: currentTarget,
      isActive: () => _isSessionActive(sessionId),
    );
    if (!_isSessionActive(sessionId) ||
        expandedState == null ||
        expandedState.choices.length <= 1) {
      return;
    }

    final selectedIndex = expandedState.selectedIndex.clamp(
      0,
      expandedState.choices.length - 1,
    );
    final selectedTarget = expandedState.choices[selectedIndex];
    _updateLibraryMatchView(
      choices: expandedState.choices,
      selectedIndex: selectedIndex,
      isMatching: false,
    );
    if (!_isSessionActive(sessionId)) return;
    _pageController.setManualOverrideTarget(selectedTarget);
    if (!_isSessionActive(sessionId)) return;
    await ref.read(localStorageCacheRepositoryProvider).saveDetailTarget(
          seedTarget: widget.target,
          resolvedTarget: selectedTarget,
          libraryMatchChoices: expandedState.choices,
          selectedLibraryMatchIndex: selectedIndex,
        );
  }

  Future<DetailExternalEpisodeVariantState?>
      _expandEpisodeLikeLibraryMatchChoices({
    required List<MediaDetailTarget> baseChoices,
    required MediaDetailTarget selectedTarget,
    required bool Function() isActive,
  }) async {
    if (!isActive()) return null;
    if (selectedTarget.isSeries) {
      return null;
    }
    final initialChoices = _mergeExpandedLibraryChoices([
      ...baseChoices,
      selectedTarget,
    ]);
    if (initialChoices.isEmpty) {
      return null;
    }

    final settings = ref.read(appSettingsProvider);
    final nasMediaIndexer = ref.read(nasMediaIndexerProvider);
    final variantService =
        ref.read(detailExternalEpisodeVariantServiceProvider);
    final expandedChoices = <MediaDetailTarget>[];
    var expandedSelectedTarget = selectedTarget;
    final selectedTargetKey = _libraryMatchTargetKey(selectedTarget);

    for (final choice in initialChoices) {
      if (!isActive()) return null;
      DetailExternalEpisodeVariantState? variantState;
      try {
        variantState = await variantService.loadChoices(
          target: choice,
          settings: settings,
          nasMediaIndexer: nasMediaIndexer,
          embyApiClient: ref.read(mediaServerClientProvider(
            choice.sourceKind == MediaSourceKind.fntv
                ? MediaSourceKind.fntv
                : MediaSourceKind.emby,
          )),
        );
      } catch (error, stackTrace) {
        variantState = null;
        appLogError('detail-resource', 'variant.expand.error',
            fields: {
              'choice': _detailResourceTraceTarget(choice),
            },
            error: error,
            stackTrace: stackTrace);
      }
      if (!isActive()) return null;
      final resolvedChoices =
          variantState == null || variantState.choices.length <= 1
              ? [choice]
              : variantState.choices;
      if (_libraryMatchTargetKey(choice) == selectedTargetKey &&
          resolvedChoices.isNotEmpty) {
        if (variantState != null && variantState.choices.isNotEmpty) {
          final variantIndex = variantState.selectedIndex.clamp(
            0,
            variantState.choices.length - 1,
          );
          expandedSelectedTarget = variantState.choices[variantIndex];
        } else {
          expandedSelectedTarget = resolvedChoices.first;
        }
      }
      expandedChoices.addAll(resolvedChoices);
    }

    final mergedChoices = _mergeExpandedLibraryChoices(expandedChoices);
    if (mergedChoices.length <= 1) {
      return null;
    }

    final resolvedSelectedIndex = _resolveExpandedLibraryMatchIndex(
      target: expandedSelectedTarget,
      choices: mergedChoices,
    );
    return DetailExternalEpisodeVariantState(
      choices: mergedChoices,
      selectedIndex: resolvedSelectedIndex,
    );
  }

  Future<void> _matchLocalResource(
    MediaDetailTarget currentTarget, {
    int? sessionId,
    bool showFeedback = true,
  }) async {
    final activeSessionId = sessionId ?? _detailSessionId;
    if (_isMatchingLocalResource || !_isSessionActive(activeSessionId)) {
      return;
    }

    final controller = DetailLibraryMatchTaskController();
    _cancelActiveLibraryMatch();
    _activeLibraryMatchController = controller;
    _updateLibraryMatchView(
      choices: const [],
      selectedIndex: 0,
      isMatching: true,
    );

    try {
      final settings = ref.read(appSettingsProvider);
      final query = currentTarget.searchQuery.trim().isEmpty
          ? currentTarget.title
          : currentTarget.searchQuery;
      final metadataMatch = await _tryPreferredMetadataMatch(
        metadataMatchResolver: ref.read(metadataMatchResolverProvider),
        settings: settings,
        target: currentTarget,
        query: query,
      );
      controller.throwIfCancelled();
      if (!_isLibraryMatchActive(activeSessionId, controller)) {
        throw const DetailLibraryMatchCancelledException();
      }
      final allowedSources =
          _detailLibraryMatchService.resolveLibraryMatchSources(settings);
      final preferredSources =
          DetailLibraryMatchCoordinator.resolvePreferredSources(
        pageSeedTarget: widget.target,
        allowedSources: allowedSources,
      );
      final skipPreferredSourceSearch = !widget.target.isSeries &&
          resolvePreferredEntryLibraryChoice(
                pageSeedTarget: widget.target,
                currentTarget: currentTarget,
              ) !=
              null &&
          preferredSources.isNotEmpty;

      final coordinator = DetailLibraryMatchCoordinator(
        mediaRepository: ref.read(mediaRepositoryProvider),
        nasMediaIndexer: ref.read(nasMediaIndexerProvider),
      );
      final candidates = await coordinator.findCandidates(
        allowedSources: allowedSources,
        controller: controller,
        pageSeedTarget: widget.target,
        target: currentTarget,
        query: query,
        sourceQuery: _detailMetadataQuery(currentTarget),
        skipPreferredSourceSearch: skipPreferredSourceSearch,
        metadataMatch: metadataMatch,
        onProgress: (partialCandidates) {
          if (!_isLibraryMatchActive(activeSessionId, controller)) {
            return;
          }
          final partialMerged =
              _detailLibraryMatchService.candidatesToMergedTargets(
            currentTarget,
            partialCandidates,
            query,
          );
          final preferredPartial = prioritizeDetailLibraryMatchChoices(
            pageSeedTarget: widget.target,
            choices: partialMerged,
            includePreferredEntryChoice: true,
            currentTarget: currentTarget,
          );
          final partialChoices = preferredPartial.choices;
          if (partialChoices.isEmpty) {
            return;
          }
          _updateLibraryMatchView(
            choices: partialChoices.length > 1
                ? partialChoices
                : const <MediaDetailTarget>[],
            selectedIndex: preferredPartial.selectedIndex,
            isMatching: true,
          );
          if (!_isLibraryMatchActive(activeSessionId, controller)) return;
          _pageController.setManualOverrideTarget(
            partialChoices[preferredPartial.selectedIndex],
          );
        },
      );

      controller.throwIfCancelled();
      if (!_isLibraryMatchActive(activeSessionId, controller)) {
        throw const DetailLibraryMatchCancelledException();
      }

      final merged = prioritizeDetailLibraryMatchChoices(
        pageSeedTarget: widget.target,
        choices: _detailLibraryMatchService.candidatesToMergedTargets(
          currentTarget,
          candidates,
          query,
        ),
        includePreferredEntryChoice: true,
        currentTarget: currentTarget,
      ).choices;
      final expandedVariantState = currentTarget.isSeries
          ? null
          : await _expandEpisodeLikeLibraryMatchChoices(
              baseChoices: merged,
              selectedTarget: merged.isEmpty ? currentTarget : merged.first,
              isActive: () =>
                  _isLibraryMatchActive(activeSessionId, controller),
            );
      if (!_isLibraryMatchActive(activeSessionId, controller)) {
        throw const DetailLibraryMatchCancelledException();
      }
      final preferredEffective = prioritizeDetailLibraryMatchChoices(
        pageSeedTarget: widget.target,
        choices: expandedVariantState?.choices ?? merged,
        fallbackSelectedIndex: expandedVariantState?.selectedIndex ?? 0,
      );
      final effectiveChoices = preferredEffective.choices;
      final effectiveSelectedIndex = preferredEffective.selectedIndex.clamp(
        0,
        effectiveChoices.isEmpty ? 0 : effectiveChoices.length - 1,
      );

      _updateLibraryMatchView(
        choices: effectiveChoices.length > 1
            ? effectiveChoices
            : const <MediaDetailTarget>[],
        selectedIndex: effectiveSelectedIndex,
        isMatching: false,
      );
      if (effectiveChoices.isNotEmpty) {
        if (!_isLibraryMatchActive(activeSessionId, controller)) return;
        _pageController.setManualOverrideTarget(
          effectiveChoices[effectiveSelectedIndex],
        );
      }

      if (!_isLibraryMatchActive(activeSessionId, controller)) return;
      unawaited(
        ref.read(localStorageCacheRepositoryProvider).saveDetailTarget(
              seedTarget: currentTarget,
              resolvedTarget: effectiveChoices.isEmpty
                  ? currentTarget
                  : effectiveChoices[effectiveSelectedIndex],
              libraryMatchChoices: effectiveChoices.length > 1
                  ? effectiveChoices
                  : const <MediaDetailTarget>[],
              selectedLibraryMatchIndex: effectiveSelectedIndex,
            ),
      );

      if (!_isLibraryMatchActive(activeSessionId, controller) ||
          !showFeedback) {
        return;
      }

      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      if (effectiveChoices.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('没有找到可匹配的本地资源')),
        );
        return;
      }

      if (effectiveChoices.length == 1) {
        final matched = effectiveChoices.first;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              matched.availabilityLabel.trim().isNotEmpty
                  ? '已匹配到 ${_detailLibraryMatchService.availabilityFeedbackLabel(matched.availabilityLabel)}'
                  : '已匹配到 ${matched.sourceKind?.label ?? '资源'} · ${matched.sourceName}',
            ),
          ),
        );
        return;
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text('匹配到 ${effectiveChoices.length} 个本地资源，可在下方选择'),
        ),
      );
    } on DetailLibraryMatchCancelledException {
      return;
    } catch (error, stackTrace) {
      appLogError('detail-resource', 'resource.match.error',
          fields: {
            'target': _detailResourceTraceTarget(currentTarget),
            'sessionId': activeSessionId,
          },
          error: error,
          stackTrace: stackTrace);
      if (_isLibraryMatchActive(activeSessionId, controller) && showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('匹配本地资源失败：$error')),
        );
      }
      return;
    } finally {
      final isCurrentController =
          identical(_activeLibraryMatchController, controller);
      if (isCurrentController) {
        _activeLibraryMatchController = null;
      }
      if (mounted && isCurrentController && _isMatchingLocalResource) {
        _updateLibraryMatchView(isMatching: false);
      }
    }
  }

  Future<void> _refreshMetadata(
    MediaDetailTarget currentTarget, {
    int? sessionId,
    bool showFeedback = true,
  }) async {
    final activeSessionId = sessionId ?? _detailSessionId;
    if (_isRefreshingMetadata || !_isSessionActive(activeSessionId)) {
      return;
    }

    _isRefreshingMetadata = true;
    if (showFeedback) {
      ref
          .read(metadataNetworkGuardProvider)
          .allowManualProbe(reason: 'manual-detail-metadata-refresh');
    }
    final foregroundLease = ref
        .read(metadataPrefetchConcurrencyLimiterProvider)
        .beginForegroundWork(
          reason: 'detail.metadata-refresh',
          resumeDelay: Duration(
            milliseconds: ref
                .read(appSettingsProvider)
                .metadataPrefetchForegroundResumeDelayMs,
          ),
        );

    var changed = false;
    var refreshOutcome = DetailMetadataOutcome.skipped;
    try {
      final settings = ref.read(detailEnrichmentSettingsProvider);
      final doubanAccount = ref.read(appSettingsProvider).doubanAccount;
      final result = await resolveDetailMetadata(
        settings: settings,
        target: currentTarget,
        wmdbMetadataClient: ref.read(wmdbMetadataClientProvider),
        tmdbMetadataClient: ref.read(tmdbMetadataClientProvider),
        doubanApiClient: ref.read(doubanApiClientProvider),
        doubanCookie:
            doubanAccount.enabled ? doubanAccount.sessionCookie.trim() : '',
        forceSearch: true,
        forceReplace: true,
        traceKey: _detailTraceKey(currentTarget),
      );
      final nextTarget = result.target;
      refreshOutcome = result.outcome;
      changed = _hasMetadataChanged(currentTarget, nextTarget);

      if (!_isSessionActive(activeSessionId)) {
        return;
      }

      if (changed) {
        _pageController.setManualOverrideTarget(nextTarget);
      }

      await ref.read(localStorageCacheRepositoryProvider).saveDetailTarget(
            seedTarget: widget.target,
            resolvedTarget: nextTarget,
            metadataRefreshStatus:
                result.outcome == DetailMetadataOutcome.skipped
                    ? null
                    : result.hasFailure
                        ? DetailMetadataRefreshStatus.failed
                        : DetailMetadataRefreshStatus.succeeded,
          );
    } catch (error, stackTrace) {
      appLogError('detail-resource', 'metadata.refresh.error',
          fields: <String, Object?>{
            'sessionId': activeSessionId,
            'target': _detailResourceTraceTarget(currentTarget),
          },
          error: error,
          stackTrace: stackTrace);
      if (_isSessionActive(activeSessionId)) {
        await ref.read(localStorageCacheRepositoryProvider).saveDetailTarget(
              seedTarget: widget.target,
              resolvedTarget: currentTarget,
              metadataRefreshStatus: DetailMetadataRefreshStatus.failed,
            );
      }
      if (!_isSessionActive(activeSessionId) || !showFeedback || !mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('更新影片信息失败：$error')),
      );
      return;
    } finally {
      foregroundLease.release();
      if (_isSessionActive(activeSessionId) && _isRefreshingMetadata) {
        _isRefreshingMetadata = false;
      }
    }

    if (!_isSessionActive(activeSessionId) || !showFeedback || !mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(switch (refreshOutcome) {
          DetailMetadataOutcome.failed => '更新影片信息失败，请稍后重试',
          DetailMetadataOutcome.partialFailure => '部分信息源更新失败，已保留可用信息',
          _ => changed ? '已更新影片信息' : '没有可更新的信息',
        }),
      ),
    );
  }

  Future<void> _openMetadataIndexManager(
      MediaDetailTarget currentTarget) async {
    if (!shouldShowDetailMetadataManagerEntry(currentTarget)) {
      return;
    }
    final updatedTarget = await context.pushNamed<MediaDetailTarget>(
      'metadata-index',
      extra: currentTarget,
    );
    if (!mounted || updatedTarget == null) {
      return;
    }

    _pageController.setManualOverrideTarget(updatedTarget);

    unawaited(
      ref.read(localStorageCacheRepositoryProvider).saveDetailTarget(
            seedTarget: widget.target,
            resolvedTarget: updatedTarget,
          ),
    );
  }

  void _applySelectedLibraryChoice(MediaDetailTarget choice) {
    if (_libraryMatchChoices.isEmpty) {
      return;
    }
    final index = _resolveExpandedLibraryMatchIndex(
      target: choice,
      choices: _libraryMatchChoices,
    );
    _applySelectedLibraryMatchIndex(index);
  }

  void _applySelectedSourceIndex(int index) {
    final sourceView = _buildDetailSourceView(
      _pageController.libraryMatchView,
    );
    if (index < 0 || index >= sourceView.choices.length) {
      return;
    }
    _applySelectedLibraryChoice(sourceView.choices[index]);
  }

  void _applySelectedPlayableVariantIndex(int index) {
    final variantView = _buildDetailPlayableVariantView(
      _pageController.libraryMatchView,
    );
    if (index < 0 || index >= variantView.choices.length) {
      return;
    }
    _applySelectedLibraryChoice(variantView.choices[index]);
  }

  void _applySelectedLibraryMatchIndex(int index) {
    final resolvedTarget =
        _pageController.applySelectedLibraryMatchIndex(index);
    if (resolvedTarget == null) {
      return;
    }
    final resolvedIndex = _selectedLibraryMatchIndex;
    unawaited(
      ref.read(localStorageCacheRepositoryProvider).saveDetailTarget(
            seedTarget: widget.target,
            resolvedTarget: resolvedTarget,
            libraryMatchChoices: _libraryMatchChoices,
            selectedLibraryMatchIndex: resolvedIndex,
          ),
    );
  }

  Future<void> _openPlaybackEnginePicker(PlaybackEngine currentEngine) async {
    final supportedEngines = supportedPlaybackEngines(
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    );
    final effectiveEngine = supportedEngines.contains(currentEngine)
        ? currentEngine
        : PlaybackEngine.embeddedMpv;
    final selection = await showDetailTelevisionPickerDialog<PlaybackEngine>(
      context: context,
      enabled: ref.read(isTelevisionProvider).value ?? false,
      title: '选择播放器',
      selectedValue: effectiveEngine,
      optionDebugLabelPrefix: 'detail-playback-engine-option',
      closeFocusDebugLabel: 'detail-playback-engine-close',
      closeFocusId: 'detail:resource:playback-engine-close',
      options: [
        for (final engine in supportedEngines)
          DetailTelevisionPickerOption<PlaybackEngine>(
            value: engine,
            title: playbackEnginePlatformLabel(
              engine,
              platform: defaultTargetPlatform,
            ),
            subtitle: engine.description,
            focusId: 'detail:resource:playback-engine:${engine.name}',
          ),
      ],
    );
    if (selection == null) {
      return;
    }
    await _setPlaybackEngine(selection, currentEngine: currentEngine);
  }

  Future<void> _setPlaybackEngine(
    PlaybackEngine selection, {
    required PlaybackEngine currentEngine,
  }) async {
    if (selection == currentEngine) {
      return;
    }
    await ref.read(settingsControllerProvider.notifier).setPlaybackEngine(
          selection,
        );
  }

  Future<void> _openTelevisionLibraryMatchPicker() async {
    await _openTelevisionLibraryMatchPickerDialog(
      title: '选择本地资源',
      labelBuilder: detailLibrarySourceOptionLabel,
      viewData: _buildDetailSourceView(_pageController.libraryMatchView),
      onSelected: _applySelectedSourceIndex,
    );
  }

  Future<void> _openTelevisionPlayableVariantPicker() async {
    await _openTelevisionLibraryMatchPickerDialog(
      title: '选择播放版本',
      labelBuilder: detailPlayableVariantOptionLabel,
      subtitleBuilder: detailMovieVariantOptionSubtitle,
      viewData: _buildDetailPlayableVariantView(
        _pageController.libraryMatchView,
      ),
      onSelected: _applySelectedPlayableVariantIndex,
    );
  }

  Future<void> _openTelevisionLibraryMatchPickerDialog({
    required String title,
    required String Function(MediaDetailTarget target) labelBuilder,
    String Function(MediaDetailTarget target)? subtitleBuilder,
    required DetailLibraryMatchViewState viewData,
    required ValueChanged<int> onSelected,
  }) async {
    if (viewData.choices.length <= 1 || _isMatchingLocalResource) {
      return;
    }

    final selectedIndex = viewData.effectiveSelectedIndex;
    final nextIndex = await showDetailTelevisionPickerDialog<int>(
      context: context,
      enabled: ref.read(isTelevisionProvider).value ?? false,
      title: title,
      selectedValue: selectedIndex,
      optionDebugLabelPrefix: 'detail-library-match-option',
      closeFocusDebugLabel: 'detail-library-match-close',
      closeFocusId: 'detail:resource:library-close',
      options: [
        for (var index = 0; index < viewData.choices.length; index++)
          DetailTelevisionPickerOption<int>(
            value: index,
            title: labelBuilder(viewData.choices[index]),
            subtitle: subtitleBuilder?.call(viewData.choices[index]) ??
                viewData.choices[index].availabilityLabel,
            focusId: 'detail:resource:library-option:$index',
          ),
      ],
    );
    if (!mounted || nextIndex == null || nextIndex == selectedIndex) {
      return;
    }
    onSelected(nextIndex);
  }

  Widget _buildSeriesSection(
    MediaDetailTarget target,
    AsyncValue<DetailSeriesBrowserState?> seriesAsync,
  ) {
    if (seriesAsync.hasValue &&
        (seriesAsync.value == null || seriesAsync.value!.groups.isEmpty)) {
      return const SizedBox.shrink();
    }
    final content = seriesAsync.when(
      skipLoadingOnReload: true,
      data: (browser) {
        if (browser == null || browser.groups.isEmpty) {
          return const SizedBox.shrink();
        }
        return ValueListenableBuilder<String>(
          valueListenable: _selectedSeasonIdNotifier,
          builder: (context, selectedSeasonId, _) {
            final selectedGroup = resolveSelectedEpisodeGroup(
              groups: browser.groups,
              selectedGroupId: selectedSeasonId.isEmpty ||
                      _selectedSeasonRequest !=
                          DetailSeriesBrowserRequest.fromTarget(target)
                  ? browser.initialGroupId
                  : selectedSeasonId,
            );
            return DetailEpisodeBrowser(
              key: ValueKey(DetailSeriesBrowserRequest.fromTarget(target)),
              seriesTarget: target,
              groups: browser.groups,
              lastPlayedTarget: browser.lastPlayedTarget,
              selectedGroupId: selectedGroup.id,
              onSeasonSelected: (groupId) {
                _selectedSeasonRequest =
                    DetailSeriesBrowserRequest.fromTarget(target);
                if (_selectedSeasonIdNotifier.value == groupId) {
                  return;
                }
                _selectedSeasonIdNotifier.value = groupId;
              },
            );
          },
        );
      },
      loading: () => const SizedBox(
        height: 360,
        child: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      ),
      error: (error, stackTrace) => Text(
        '加载剧集失败：$error',
        style: const TextStyle(
          color: AppColors.foregroundMuted,
          fontSize: 14,
        ),
      ),
    );
    if (target.hasMatchedResource) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 26),
        child: content,
      );
    }
    return DetailBlock(title: '剧集', child: content);
  }

  Widget _buildResourceInfoBlock({
    required MediaDetailTarget target,
    required bool isTelevision,
    required PlaybackEngine playbackEngine,
    required bool canCheckFavoriteOnlineResourceUpdate,
  }) {
    return ValueListenableBuilder<DetailLibraryMatchViewState>(
      valueListenable: _pageController.libraryMatchViewListenable,
      builder: (context, libraryMatchView, _) {
        final sourceView = _buildDetailSourceView(libraryMatchView);
        return DetailBlock(
          title: '资源信息',
          child: DetailResourceInfoSection(
            target: target,
            isTelevision: isTelevision,
            playbackEngine: playbackEngine,
            libraryView: sourceView,
            onSearchOnline: () {
              context.pushNamed(
                'detail-search',
                queryParameters: {
                  'q': target.searchQuery,
                },
              );
            },
            onLibraryMatchSelected: _applySelectedSourceIndex,
            onOpenTelevisionLibraryMatchPicker:
                _openTelevisionLibraryMatchPicker,
            onMatchLocalResource: libraryMatchView.isMatching
                ? null
                : () {
                    _matchLocalResource(target);
                  },
            onCheckOnlineResourceUpdate: canCheckFavoriteOnlineResourceUpdate
                ? () => _checkFavoriteOnlineResourceUpdate(target)
                : null,
            isCheckingOnlineResourceUpdate: _isCheckingOnlineResourceUpdate,
            onOpenPlaybackEnginePicker: () =>
                _openPlaybackEnginePicker(playbackEngine),
            onPlaybackEngineSelected: (selection) {
              unawaited(
                _setPlaybackEngine(
                  selection,
                  currentEngine: playbackEngine,
                ),
              );
            },
            onOpenMetadataIndexManager: () {
              _openMetadataIndexManager(target);
            },
          ),
        );
      },
    );
  }

  Widget _buildOverviewContent({
    required MediaDetailTarget target,
    required bool isTelevision,
  }) {
    return DetailOverviewSection(
      title: resolveDetailPrimaryTitle(
        currentTarget: target,
        pageTarget: widget.target,
        emptyFallback: '剧情简介',
      ),
      overview: target.overview,
      episodeTitle: resolveDetailEpisodeTitleLine(
        currentTarget: target,
        pageTarget: widget.target,
      ),
      isTelevision: isTelevision,
      focusId: buildTvFocusId(
        prefix: 'detail:overview',
        segments: [
          target.sourceKind?.name,
          target.sourceId,
          target.itemId,
          target.seasonNumber,
          target.episodeNumber,
          target.title,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    final pageRenderingEnabled = TickerMode.of(context);
    final slimDetailHeroEnabled = ref.watch(
      appSettingsProvider.select(
        (settings) => settings.effectiveSlimDetailHeroEnabled(
          isTelevision: isTelevision,
        ),
      ),
    );
    final networkStorage = ref.watch(
      appSettingsProvider.select((settings) => settings.networkStorage),
    );
    final playbackEngine = ref.watch(
      appSettingsProvider.select((settings) => settings.playbackEngine),
    );

    return AppPrimaryScrollController(
      controller: _scrollController,
      child: TvPageFocusScope(
        isTelevision: isTelevision,
        child: Scaffold(
          backgroundColor: AppColors.neutral0,
          body: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.neutral1,
                      AppColors.neutral1,
                      AppColors.neutral0,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: ValueListenableBuilder<MediaDetailTarget?>(
                  valueListenable:
                      _pageController.manualOverrideTargetListenable,
                  builder: (context, manualOverrideTarget, _) {
                    final seedTarget = manualOverrideTarget ?? widget.target;
                    final displayTarget =
                        manualOverrideTarget ?? _initialDisplayTarget;
                    if (!identical(_retainedTargetSeed, seedTarget)) {
                      _retainedTargetSeed = seedTarget;
                      _retainedTargetAsync.clear();
                    }
                    final watchedTargetAsync = pageRenderingEnabled &&
                            _detailEnrichmentReady
                        ? ref.watch(enrichedDetailTargetProvider(seedTarget))
                        : null;
                    final targetAsync = _retainedTargetAsync.resolve(
                      activeValue: watchedTargetAsync,
                      fallbackValue: AsyncValue.data(displayTarget),
                    );
                    final target = targetAsync.value ?? displayTarget;
                    final seriesRequest = target.isSeries
                        ? DetailSeriesBrowserRequest.fromTarget(target)
                        : null;
                    if (_retainedSeriesRequest != seriesRequest) {
                      _retainedSeriesRequest = seriesRequest;
                      _retainedSeriesAsync.clear();
                    }
                    // Keep mounted content when a player route covers details.
                    // TickerMode controls background work, not content lifetime.
                    final showDeferredDetailContent =
                        !isTelevision || _showDeferredDetailContent;
                    if (isTelevision &&
                        pageRenderingEnabled &&
                        !_showDeferredDetailContent) {
                      _scheduleDeferredDetailContent();
                    }
                    final favoriteOnlineResourceMatches = ref
                        .read(detailOnlineResourceUpdateServiceProvider)
                        .resolveFavoriteMatches(
                          target: target,
                          favorites: _favoriteSearchResults,
                        );
                    final canCheckFavoriteOnlineResourceUpdate =
                        favoriteOnlineResourceMatches.any((match) =>
                            match.hasConfiguredCookie(networkStorage));
                    final galleryImages = showDeferredDetailContent
                        ? buildDetailGalleryImages(target)
                        : const <DetailImageAsset>[];

                    return ListView(
                      controller: _scrollController,
                      padding: EdgeInsets.zero,
                      children: [
                        DetailHeroSection(
                          target: target,
                          simplifyVisualEffects: slimDetailHeroEnabled,
                          isTelevision: isTelevision,
                          artworkFocusNode: _heroArtworkFocusNode,
                          playFocusNode: _heroPlayFocusNode,
                          onHeroFocused: _scrollDetailHeroToTop,
                        ),
                        ValueListenableBuilder<DetailLibraryMatchViewState>(
                          valueListenable:
                              _pageController.libraryMatchViewListenable,
                          builder: (context, libraryMatchView, _) {
                            final variantView = _buildDetailPlayableVariantView(
                              libraryMatchView,
                            );
                            if (!shouldShowDetailPlayableVariantSwitcher(
                              target,
                              variantView,
                            )) {
                              return const SizedBox.shrink();
                            }
                            final selectedVariant = variantView
                                .choices[variantView.effectiveSelectedIndex];
                            final displayedSelectedTarget =
                                _libraryMatchTargetKey(target) ==
                                        _libraryMatchTargetKey(selectedVariant)
                                    ? target
                                    : selectedVariant;
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(
                                kAppPageHorizontalPadding,
                                0,
                                kAppPageHorizontalPadding,
                                8,
                              ),
                              child: DetailPlayableVariantSelector(
                                isTelevision: isTelevision,
                                televisionOnPressed:
                                    _openTelevisionPlayableVariantPicker,
                                viewData: variantView,
                                selectedTarget: displayedSelectedTarget,
                                onSelected: _applySelectedPlayableVariantIndex,
                              ),
                            );
                          },
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: kAppPageHorizontalPadding,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (showDeferredDetailContent && target.isSeries)
                                Consumer(
                                  builder: (context, seriesRef, _) {
                                    final watchedSeriesAsync =
                                        _seriesSourceReady &&
                                                pageRenderingEnabled &&
                                                isPageVisible
                                            ? seriesRef.watch(
                                                detailSeriesBrowserProvider(
                                                    seriesRequest!))
                                            : null;
                                    final seriesAsync =
                                        _retainedSeriesAsync.resolve(
                                      activeValue: watchedSeriesAsync,
                                      fallbackValue: const AsyncLoading<
                                          DetailSeriesBrowserState?>(),
                                    );
                                    return _buildSeriesSection(
                                        target, seriesAsync);
                                  },
                                ),
                              if (showDeferredDetailContent)
                                _buildOverviewContent(
                                  target: target,
                                  isTelevision: isTelevision,
                                ),
                              if (showDeferredDetailContent &&
                                  galleryImages.isNotEmpty)
                                DetailBlock(
                                  title: '剧照',
                                  child: DetailImageGallery(
                                    images: galleryImages,
                                  ),
                                ),
                              if (showDeferredDetailContent &&
                                  (target.resolvedDirectorProfiles.isNotEmpty ||
                                      target.resolvedActorProfiles.isNotEmpty))
                                DetailBlock(
                                  title: '演职员',
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (target.resolvedDirectorProfiles
                                          .isNotEmpty) ...[
                                        const InfoLabel('导演'),
                                        const SizedBox(height: 10),
                                        PersonRail(
                                          people:
                                              target.resolvedDirectorProfiles,
                                          focusScopePrefix: 'detail:director',
                                          onPersonTap: (person) {
                                            context.pushNamed(
                                              'person-credits',
                                              extra: PersonCreditsPageTarget(
                                                person: person,
                                                role:
                                                    PersonCreditsRole.director,
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                      if (target.resolvedDirectorProfiles
                                              .isNotEmpty &&
                                          target
                                              .resolvedActorProfiles.isNotEmpty)
                                        const SizedBox(height: 18),
                                      if (target.resolvedActorProfiles
                                          .isNotEmpty) ...[
                                        const InfoLabel('演员'),
                                        const SizedBox(height: 10),
                                        PersonRail(
                                          people: target.resolvedActorProfiles,
                                          focusScopePrefix: 'detail:actor',
                                          onPersonTap: (person) {
                                            context.pushNamed(
                                              'person-credits',
                                              extra: PersonCreditsPageTarget(
                                                person: person,
                                                role: PersonCreditsRole.actor,
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              if (showDeferredDetailContent &&
                                  (shouldShowDetailResourceInfo(target) ||
                                      canCheckFavoriteOnlineResourceUpdate))
                                _buildResourceInfoBlock(
                                  target: target,
                                  isTelevision: isTelevision,
                                  playbackEngine: playbackEngine,
                                  canCheckFavoriteOnlineResourceUpdate:
                                      canCheckFavoriteOnlineResourceUpdate,
                                ),
                              if (showDeferredDetailContent &&
                                  target.resolvedPlatformProfiles.isNotEmpty)
                                DetailBlock(
                                  title: '公司',
                                  child: PlatformRail(
                                    platforms: target.resolvedPlatformProfiles,
                                  ),
                                ),
                              appPageBottomSpacer(),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: OverlayToolbar(
                  leadingColor: Colors.white,
                  onBack: () => context.pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
