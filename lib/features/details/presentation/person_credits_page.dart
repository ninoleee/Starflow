import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/navigation/page_activity_mixin.dart';
import 'package:starflow/core/navigation/retained_async_controller.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/app_network_image.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/core/widgets/media_poster_tile.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

enum PersonCreditsRole {
  director,
  actor,
}

extension PersonCreditsRoleX on PersonCreditsRole {
  String get label {
    switch (this) {
      case PersonCreditsRole.director:
        return '导演作品';
      case PersonCreditsRole.actor:
        return '演员作品';
    }
  }

  TmdbPersonCreditsRole get tmdbRole {
    switch (this) {
      case PersonCreditsRole.director:
        return TmdbPersonCreditsRole.director;
      case PersonCreditsRole.actor:
        return TmdbPersonCreditsRole.actor;
    }
  }
}

class PersonCreditsPageTarget {
  const PersonCreditsPageTarget({
    required this.person,
    required this.role,
  });

  final MediaPersonProfile person;
  final PersonCreditsRole role;
}

enum _PersonCreditsSortMode {
  newest,
  oldest,
  tmdbRating,
}

class PersonCreditsPage extends ConsumerStatefulWidget {
  const PersonCreditsPage({super.key, required this.target});

  final PersonCreditsPageTarget target;

  @override
  ConsumerState<PersonCreditsPage> createState() => _PersonCreditsPageState();
}

class _PersonCreditsPageState extends ConsumerState<PersonCreditsPage>
    with PageActivityMixin<PersonCreditsPage> {
  static const String _allCategoryLabel = '全部';
  static const String _movieCategoryLabel = '电影';
  static const String _varietyCategoryLabel = '综艺';
  static const String _seriesCategoryLabel = '剧集';

  final ScrollController _scrollController = ScrollController();
  final FocusNode _headerFocusNode =
      FocusNode(debugLabel: 'person-credits-header');
  final TvFocusMemoryController _tvFocusMemoryController =
      TvFocusMemoryController();
  final RetainedAsyncController<_PersonCreditsPageResult> _retainedResultAsync =
      RetainedAsyncController<_PersonCreditsPageResult>();
  _PersonCreditsSortMode _sortMode = _PersonCreditsSortMode.newest;
  String _selectedPrimaryCategory = _allCategoryLabel;
  String _selectedMovieGenre = _allCategoryLabel;

  @override
  void didUpdateWidget(covariant PersonCreditsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target.role != widget.target.role ||
        oldWidget.target.person.name != widget.target.person.name ||
        oldWidget.target.person.avatarUrl != widget.target.person.avatarUrl) {
      _sortMode = _PersonCreditsSortMode.newest;
      _selectedPrimaryCategory = _allCategoryLabel;
      _selectedMovieGenre = _allCategoryLabel;
      _retainedResultAsync.clear();
    }
  }

  @override
  void dispose() {
    _headerFocusNode.dispose();
    _scrollController.dispose();
    _tvFocusMemoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    final target = widget.target;
    final watchedResultAsync =
        isPageVisible ? ref.watch(_personCreditsPageProvider(target)) : null;
    final resultAsync = _retainedResultAsync.resolve(
      activeValue: watchedResultAsync,
      fallbackValue: const AsyncLoading<_PersonCreditsPageResult>(),
    );

    return TvPageFocusScope(
      controller: _tvFocusMemoryController,
      scopeId: _personCreditsFocusScopeId(target),
      isTelevision: isTelevision,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            AppPageBackground(
              child: ListView(
                controller: _scrollController,
                padding: overlayToolbarPagePadding(context),
                children: [
                  _PersonCreditsHeader(
                    target: target,
                    isTelevision: isTelevision,
                    focusNode: _headerFocusNode,
                  ),
                  const SizedBox(height: 22),
                  resultAsync.when(
                    data: (result) {
                      if (result.items.isEmpty) {
                        return _EmptyState(message: result.message);
                      }
                      final availablePrimaryCategories =
                          _collectAvailablePrimaryCategories(result.items);
                      final selectedPrimaryCategory = availablePrimaryCategories
                              .contains(_selectedPrimaryCategory)
                          ? _selectedPrimaryCategory
                          : _allCategoryLabel;
                      final availableMovieGenres =
                          _collectAvailableMovieGenres(result.items);
                      final selectedMovieGenre = selectedPrimaryCategory ==
                                  _movieCategoryLabel &&
                              availableMovieGenres.contains(_selectedMovieGenre)
                          ? _selectedMovieGenre
                          : _allCategoryLabel;
                      final visibleItems = _sortAndFilterPersonCredits(
                        items: result.items,
                        selectedPrimaryCategory: selectedPrimaryCategory,
                        selectedMovieGenre: selectedMovieGenre,
                        sortMode: _sortMode,
                      );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _PersonCreditsControls(
                            sortMode: _sortMode,
                            selectedPrimaryCategory: selectedPrimaryCategory,
                            availablePrimaryCategories:
                                availablePrimaryCategories,
                            selectedMovieGenre: selectedMovieGenre,
                            availableMovieGenres: availableMovieGenres,
                            onSortChanged: (value) {
                              if (_sortMode == value) {
                                return;
                              }
                              setState(() {
                                _sortMode = value;
                              });
                            },
                            onPrimaryCategoryChanged: (value) {
                              if (_selectedPrimaryCategory == value) {
                                return;
                              }
                              setState(() {
                                _selectedPrimaryCategory = value;
                                if (value != _movieCategoryLabel) {
                                  _selectedMovieGenre = _allCategoryLabel;
                                }
                              });
                            },
                            onMovieGenreChanged: (value) {
                              if (_selectedMovieGenre == value) {
                                return;
                              }
                              setState(() {
                                _selectedMovieGenre = value;
                              });
                            },
                          ),
                          if (visibleItems.isEmpty)
                            const _EmptyState(message: '当前筛选下没有结果')
                          else
                            _PersonCreditsGrid(items: visibleItems),
                        ],
                      );
                    },
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (error, stackTrace) => _EmptyState(
                      message: '加载关联影片失败：$error',
                    ),
                  ),
                  appPageBottomSpacer(),
                ],
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: OverlayToolbar(
                onBack: () => context.pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final _personCreditsPageProvider = FutureProvider.autoDispose
    .family<_PersonCreditsPageResult, PersonCreditsPageTarget>(
        (ref, target) async {
  final tmdbMetadataMatchEnabled = ref.read(
    appSettingsProvider.select((settings) => settings.tmdbMetadataMatchEnabled),
  );
  final token = ref
      .read(appSettingsProvider
          .select((settings) => settings.tmdbReadAccessToken))
      .trim();
  if (!tmdbMetadataMatchEnabled || token.isEmpty) {
    return const _PersonCreditsPageResult(
      items: [],
      message: '未配置 TMDB Read Access Token。',
    );
  }

  final credits = await ref.read(tmdbMetadataClientProvider).fetchPersonCredits(
        name: target.person.name,
        avatarUrl: target.person.avatarUrl,
        role: target.role.tmdbRole,
        readAccessToken: token,
      );
  if (credits.isEmpty) {
    return const _PersonCreditsPageResult(
      items: [],
      message: '没有找到关联影片。',
    );
  }

  return _PersonCreditsPageResult(
    items: credits.map(_toPersonCreditCard).toList(growable: false),
    message: '',
  );
});

class _PersonCreditsPageResult {
  const _PersonCreditsPageResult({
    required this.items,
    required this.message,
  });

  final List<_PersonCreditCardData> items;
  final String message;
}

class _PersonCreditCardData {
  const _PersonCreditCardData({
    required this.title,
    required this.subtitle,
    required this.year,
    required this.tmdbRating,
    required this.typeLabel,
    required this.primaryCategoryLabel,
    required this.genreLabels,
    required this.ratingLabel,
    required this.detailTarget,
  });

  final String title;
  final String subtitle;
  final int year;
  final double? tmdbRating;
  final String typeLabel;
  final String primaryCategoryLabel;
  final List<String> genreLabels;
  final String ratingLabel;
  final MediaDetailTarget detailTarget;
}

_PersonCreditCardData _toPersonCreditCard(TmdbPersonCredit credit) {
  final detailTarget = MediaDetailTarget(
    title: credit.title,
    posterUrl: credit.posterUrl,
    backdropUrl: credit.backdropUrl,
    bannerUrl: credit.bannerUrl,
    overview: credit.overview,
    year: credit.year,
    ratingLabels: credit.ratingLabels,
    genres: credit.genres,
    availabilityLabel: '无',
    searchQuery: credit.title,
    itemType: credit.isSeries ? 'series' : 'movie',
    sourceName: 'TMDB',
  );
  final preferredRating = _preferredRatingLabel(credit.ratingLabels);
  final preferredType = _preferredTypeLabel(credit);
  final subtitleParts = <String>[
    if (credit.year > 0) '${credit.year}',
    if (credit.subtitle.trim().isNotEmpty) credit.subtitle.trim(),
  ];
  return _PersonCreditCardData(
    title: credit.title,
    subtitle: subtitleParts.join(' · '),
    year: credit.year,
    tmdbRating: _extractTmdbRatingValue(credit.ratingLabels),
    typeLabel: preferredType,
    primaryCategoryLabel: _resolvePersonCreditPrimaryCategory(credit),
    genreLabels: _resolvePersonCreditGenres(credit),
    ratingLabel: preferredRating,
    detailTarget: detailTarget,
  );
}

double? _extractTmdbRatingValue(Iterable<String> labels) {
  for (final label in labels) {
    final trimmed = label.trim();
    if (trimmed.isEmpty || !trimmed.toLowerCase().contains('tmdb')) {
      continue;
    }
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(trimmed);
    if (match == null) {
      continue;
    }
    return double.tryParse(match.group(1)!);
  }
  return null;
}

String _preferredRatingLabel(Iterable<String> labels) {
  final normalized = labels
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  if (normalized.isEmpty) {
    return '';
  }
  for (final keyword in const ['imdb', '豆瓣', 'tmdb']) {
    for (final label in normalized) {
      if (label.toLowerCase().contains(keyword)) {
        return label;
      }
    }
  }
  return normalized.first;
}

String _preferredTypeLabel(TmdbPersonCredit credit) {
  for (final genre in credit.genres) {
    final trimmed = genre.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return credit.isSeries ? '剧集' : '电影';
}

List<String> _resolvePersonCreditGenres(TmdbPersonCredit credit) {
  final labels = <String>[];
  final seen = <String>{};

  void add(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || !seen.add(trimmed)) {
      return;
    }
    labels.add(trimmed);
  }

  for (final genre in credit.genres) {
    add(genre);
  }
  return labels;
}

String _resolvePersonCreditPrimaryCategory(TmdbPersonCredit credit) {
  final genreSignals = credit.genres.join(' ').toLowerCase();
  if (_containsAnyKeyword(genreSignals, _varietyCategoryKeywords)) {
    return _PersonCreditsPageState._varietyCategoryLabel;
  }
  if (!credit.isSeries) {
    return _PersonCreditsPageState._movieCategoryLabel;
  }
  return _PersonCreditsPageState._seriesCategoryLabel;
}

List<String> _collectAvailablePrimaryCategories(
    Iterable<_PersonCreditCardData> items) {
  final categories = items
      .map((item) => item.primaryCategoryLabel.trim())
      .where((label) => label.isNotEmpty)
      .toSet();
  return <String>[
    _PersonCreditsPageState._allCategoryLabel,
    if (categories.contains(_PersonCreditsPageState._movieCategoryLabel))
      _PersonCreditsPageState._movieCategoryLabel,
    if (categories.contains(_PersonCreditsPageState._varietyCategoryLabel))
      _PersonCreditsPageState._varietyCategoryLabel,
    if (categories.contains(_PersonCreditsPageState._seriesCategoryLabel))
      _PersonCreditsPageState._seriesCategoryLabel,
  ];
}

List<String> _collectAvailableMovieGenres(
    Iterable<_PersonCreditCardData> items) {
  final genres = <String>{};
  for (final item in items) {
    if (item.primaryCategoryLabel !=
        _PersonCreditsPageState._movieCategoryLabel) {
      continue;
    }
    genres.addAll(item.genreLabels.where((label) => label.trim().isNotEmpty));
  }
  final orderedGenres = genres.toList()..sort();
  return <String>[
    _PersonCreditsPageState._allCategoryLabel,
    ...orderedGenres,
  ];
}

List<_PersonCreditCardData> _sortAndFilterPersonCredits({
  required List<_PersonCreditCardData> items,
  required String selectedPrimaryCategory,
  required String selectedMovieGenre,
  required _PersonCreditsSortMode sortMode,
}) {
  final filtered = items.where(
    (item) {
      if (selectedPrimaryCategory ==
          _PersonCreditsPageState._allCategoryLabel) {
        return true;
      }
      if (selectedPrimaryCategory ==
          _PersonCreditsPageState._movieCategoryLabel) {
        if (item.primaryCategoryLabel !=
            _PersonCreditsPageState._movieCategoryLabel) {
          return false;
        }
        if (selectedMovieGenre == _PersonCreditsPageState._allCategoryLabel) {
          return true;
        }
        return item.genreLabels.contains(selectedMovieGenre);
      }
      return item.primaryCategoryLabel == selectedPrimaryCategory;
    },
  ).toList();
  filtered.sort((a, b) {
    if (sortMode == _PersonCreditsSortMode.tmdbRating) {
      final aRating = a.tmdbRating;
      final bRating = b.tmdbRating;
      if (aRating == null && bRating != null) {
        return 1;
      }
      if (aRating != null && bRating == null) {
        return -1;
      }
      if (aRating != null && bRating != null) {
        final ratingCompare = bRating.compareTo(aRating);
        if (ratingCompare != 0) {
          return ratingCompare;
        }
      }
      final yearCompare = b.year.compareTo(a.year);
      if (yearCompare != 0) {
        return yearCompare;
      }
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    }
    final aUnknownYear = a.year <= 0;
    final bUnknownYear = b.year <= 0;
    if (aUnknownYear != bUnknownYear) {
      return aUnknownYear ? 1 : -1;
    }
    final yearCompare = switch (sortMode) {
      _PersonCreditsSortMode.newest => b.year.compareTo(a.year),
      _PersonCreditsSortMode.oldest => a.year.compareTo(b.year),
      _PersonCreditsSortMode.tmdbRating => 0,
    };
    if (yearCompare != 0) {
      return yearCompare;
    }
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  return filtered;
}

bool _containsAnyKeyword(String value, List<String> keywords) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) {
    return false;
  }
  for (final keyword in keywords) {
    if (normalized.contains(keyword)) {
      return true;
    }
  }
  return false;
}

const List<String> _varietyCategoryKeywords = [
  '综艺',
  '音乐',
  '真人秀',
  '脱口秀',
  '选秀',
  'variety',
  'music',
  'musical',
  'concert',
  'talk show',
];

String _personCreditsFocusScopeId(PersonCreditsPageTarget target) {
  return buildTvFocusScopeId(
    prefix: 'person-credits',
    segments: [
      target.role.name,
      target.person.name,
      target.person.avatarUrl,
    ],
  );
}

List<AppNetworkImageSource> _buildPosterFallbackSources(
    MediaDetailTarget target) {
  final sources = <AppNetworkImageSource>[];
  final seen = <String>{target.posterUrl.trim()};

  void add(
    String url,
    Map<String, String> headers,
    AppNetworkImageCachePolicy cachePolicy,
  ) {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty || !seen.add(trimmedUrl)) {
      return;
    }
    sources.add(
      AppNetworkImageSource(
        url: trimmedUrl,
        headers: headers,
        cachePolicy: cachePolicy,
      ),
    );
  }

  add(
    target.bannerUrl,
    target.bannerHeaders,
    AppNetworkImageCachePolicy.persistent,
  );
  add(
    target.backdropUrl,
    target.backdropHeaders,
    AppNetworkImageCachePolicy.persistent,
  );
  for (final url in target.extraBackdropUrls) {
    add(
      url,
      target.extraBackdropHeaders,
      AppNetworkImageCachePolicy.networkOnly,
    );
  }
  return sources;
}

class _PersonCreditsHeader extends StatelessWidget {
  const _PersonCreditsHeader({
    required this.target,
    required this.isTelevision,
    this.focusNode,
  });

  final PersonCreditsPageTarget target;
  final bool isTelevision;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _PersonAvatar(person: target.person, size: 72),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                target.person.name,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                target.role.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF90A0BD),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    if (!isTelevision) {
      return content;
    }
    return TvFocusableAction(
      onPressed: () => FocusScope.of(context).nextFocus(),
      focusNode: focusNode,
      focusId: 'person-credits:header',
      borderRadius: BorderRadius.circular(20),
      child: content,
    );
  }
}

class _PersonAvatar extends StatelessWidget {
  const _PersonAvatar({
    required this.person,
    this.size = 74,
  });

  final MediaPersonProfile person;
  final double size;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = person.avatarUrl.trim();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF162233),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: avatarUrl.isEmpty
          ? Center(
              child: Text(
                _personInitial(person.name),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.32,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : AppNetworkImage(
              avatarUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Center(
                  child: Text(
                    _personInitial(person.name),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: size * 0.32,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

String _personInitial(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    return '?';
  }
  return trimmed.characters.first.toUpperCase();
}

class _PersonCreditsGrid extends StatelessWidget {
  const _PersonCreditsGrid({required this.items});

  final List<_PersonCreditCardData> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        final maxWidth = constraints.maxWidth;
        final crossAxisCount =
            math.max(2, ((maxWidth + spacing) / 150).floor());
        final itemWidth =
            (maxWidth - (crossAxisCount - 1) * spacing) / crossAxisCount;
        final itemHeight = itemWidth / 0.7 + 54;
        final childAspectRatio = itemWidth / itemHeight;

        return GridView.builder(
          padding: const EdgeInsets.symmetric(vertical: 10),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          clipBehavior: Clip.none,
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: childAspectRatio,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return MediaPosterTile(
              focusId:
                  'person-credits:${item.detailTarget.itemId.isNotEmpty ? item.detailTarget.itemId : item.title}',
              autofocus: index == 0,
              tvPosterFocusOutlineOnly: true,
              tvPosterFocusShowBorder: false,
              tvPosterFocusScale: 1.06,
              title: item.title,
              subtitle: item.subtitle,
              imageBadgeText: item.ratingLabel,
              imageTopRightBadgeText: item.typeLabel,
              posterUrl: item.detailTarget.posterUrl,
              posterCachePolicy:
                  item.detailTarget.sourceKind == MediaSourceKind.emby
                      ? AppNetworkImageCachePolicy.networkOnly
                      : AppNetworkImageCachePolicy.persistent,
              posterHeaders: item.detailTarget.posterHeaders,
              posterFallbackSources: _buildPosterFallbackSources(
                item.detailTarget,
              ),
              width: null,
              onTap: () {
                context.pushNamed(
                  'detail',
                  extra: item.detailTarget,
                );
              },
            );
          },
        );
      },
    );
  }
}

class _PersonCreditsControls extends StatelessWidget {
  const _PersonCreditsControls({
    required this.sortMode,
    required this.selectedPrimaryCategory,
    required this.availablePrimaryCategories,
    required this.selectedMovieGenre,
    required this.availableMovieGenres,
    required this.onSortChanged,
    required this.onPrimaryCategoryChanged,
    required this.onMovieGenreChanged,
  });

  final _PersonCreditsSortMode sortMode;
  final String selectedPrimaryCategory;
  final List<String> availablePrimaryCategories;
  final String selectedMovieGenre;
  final List<String> availableMovieGenres;
  final ValueChanged<_PersonCreditsSortMode> onSortChanged;
  final ValueChanged<String> onPrimaryCategoryChanged;
  final ValueChanged<String> onMovieGenreChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PersonCreditsControlSection(
            title: '排序',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                StarflowChipButton(
                  label: '最新',
                  icon: Icons.south_rounded,
                  selected: sortMode == _PersonCreditsSortMode.newest,
                  onPressed: () => onSortChanged(_PersonCreditsSortMode.newest),
                  focusId: 'person-credits:sort:newest',
                ),
                StarflowChipButton(
                  label: '最旧',
                  icon: Icons.north_rounded,
                  selected: sortMode == _PersonCreditsSortMode.oldest,
                  onPressed: () => onSortChanged(_PersonCreditsSortMode.oldest),
                  focusId: 'person-credits:sort:oldest',
                ),
                StarflowChipButton(
                  label: 'TMDB评分',
                  icon: Icons.star_rounded,
                  selected: sortMode == _PersonCreditsSortMode.tmdbRating,
                  onPressed: () =>
                      onSortChanged(_PersonCreditsSortMode.tmdbRating),
                  focusId: 'person-credits:sort:tmdb-rating',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _PersonCreditsControlSection(
            title: '类别',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: availablePrimaryCategories
                  .map(
                    (category) => StarflowChipButton(
                      label: category,
                      selected: selectedPrimaryCategory == category,
                      onPressed: () => onPrimaryCategoryChanged(category),
                      focusId: 'person-credits:category:$category',
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
          if (selectedPrimaryCategory ==
                  _PersonCreditsPageState._movieCategoryLabel &&
              availableMovieGenres.length > 1) ...[
            const SizedBox(height: 14),
            _PersonCreditsControlSection(
              title: '电影类型',
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: availableMovieGenres
                    .map(
                      (genre) => StarflowChipButton(
                        label: genre,
                        selected: selectedMovieGenre == genre,
                        onPressed: () => onMovieGenreChanged(genre),
                        focusId: 'person-credits:movie-genre:$genre',
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PersonCreditsControlSection extends StatelessWidget {
  const _PersonCreditsControlSection({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            color: const Color(0xFF90A0BD),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Center(
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF90A0BD),
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}
