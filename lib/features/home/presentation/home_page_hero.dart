part of 'home_page.dart';

List<_FeaturedHeroItem> _fallbackFeaturedItems(
  List<HomeSectionViewModel> sections,
) {
  for (final section in sections) {
    if (section.items.isNotEmpty) {
      return section.items.take(5).map(_FeaturedHeroItem.fromPoster).toList();
    }
  }
  return const [];
}

HomeSectionViewModel? _pickHeroSectionCandidate({
  required List<HomeSectionViewModel> resolvedSections,
}) {
  for (final section in resolvedSections) {
    if (section.layout == HomeSectionLayout.carousel &&
        section.carouselItems.isNotEmpty) {
      return section;
    }
  }

  for (final section in resolvedSections) {
    if (section.items.isNotEmpty || section.carouselItems.isNotEmpty) {
      return section;
    }
  }
  return null;
}

bool _sectionHasHeroContent(HomeSectionViewModel? section) {
  if (section == null) {
    return false;
  }
  return section.items.isNotEmpty || section.carouselItems.isNotEmpty;
}

List<_FeaturedHeroItem> _buildFeaturedItems({
  required HomeSectionViewModel? featuredSection,
  required List<HomeSectionViewModel> resolvedSections,
  required String preferredModuleId,
}) {
  if (featuredSection == null) {
    return const [];
  }
  if (featuredSection.layout == HomeSectionLayout.carousel &&
      featuredSection.carouselItems.isNotEmpty) {
    return featuredSection.carouselItems
        .take(5)
        .map(_FeaturedHeroItem.fromCarousel)
        .toList();
  }
  if (featuredSection.items.isNotEmpty) {
    return featuredSection.items
        .take(5)
        .map(_FeaturedHeroItem.fromPoster)
        .toList();
  }
  if (preferredModuleId.trim().isNotEmpty) {
    return _fallbackFeaturedItems(
      resolvedSections
          .where((section) => section.id != preferredModuleId)
          .toList(),
    );
  }
  return _fallbackFeaturedItems(resolvedSections);
}

class _HomeHeroSelection {
  const _HomeHeroSelection({
    required this.heroId,
    required this.imageUrl,
    required this.imageHeaders,
  });

  const _HomeHeroSelection.empty()
      : heroId = '',
        imageUrl = '',
        imageHeaders = const {};

  final String heroId;
  final String imageUrl;
  final Map<String, String> imageHeaders;

  bool matches(_HomeHeroSelection other) {
    return heroId == other.heroId &&
        imageUrl == other.imageUrl &&
        mapEquals(imageHeaders, other.imageHeaders);
  }
}

extension _HomeHeroDisplayModeLayoutX on HomeHeroDisplayMode {
  EdgeInsets heroPadding(BuildContext context) {
    return switch (this) {
      HomeHeroDisplayMode.normal => EdgeInsets.fromLTRB(
          12,
          MediaQuery.paddingOf(context).top + 6,
          12,
          5,
        ),
      HomeHeroDisplayMode.borderless => const EdgeInsets.fromLTRB(0, 0, 0, 5),
    };
  }

  double get heroHeight => switch (this) {
        HomeHeroDisplayMode.borderless => 500,
        HomeHeroDisplayMode.normal => 440,
      };

  double get viewportFraction => switch (this) {
        HomeHeroDisplayMode.borderless => 1,
        HomeHeroDisplayMode.normal => 0.78,
      };

  double get cardGap => switch (this) {
        HomeHeroDisplayMode.borderless => 0,
        HomeHeroDisplayMode.normal => 12,
      };

  double get cardBorderRadius => switch (this) {
        HomeHeroDisplayMode.borderless => 0,
        HomeHeroDisplayMode.normal => 30,
      };

  bool get showShadow => this != HomeHeroDisplayMode.borderless;

  bool get usesFrostedBackdrop => this == HomeHeroDisplayMode.borderless;

  EdgeInsets get textPadding => switch (this) {
        HomeHeroDisplayMode.normal => const EdgeInsets.fromLTRB(22, 24, 22, 24),
        HomeHeroDisplayMode.borderless =>
          const EdgeInsets.fromLTRB(20, 28, 20, 22),
      };
}

double _resolveHeroTextWidthFactor(HomeHeroDisplayMode displayMode) {
  return switch (displayMode) {
    HomeHeroDisplayMode.normal => 0.92,
    HomeHeroDisplayMode.borderless => 0.62,
  };
}

double _resolveHeroTitleFontSize(HomeHeroDisplayMode displayMode) {
  return switch (displayMode) {
    HomeHeroDisplayMode.normal => 30,
    HomeHeroDisplayMode.borderless => 36,
  };
}

BoxConstraints _resolveHeroLogoConstraints(HomeHeroDisplayMode displayMode) {
  final useLargeLogo = displayMode == HomeHeroDisplayMode.borderless;
  return BoxConstraints(
    maxWidth: useLargeLogo ? 360 : 320,
    maxHeight: useLargeLogo ? 96 : 84,
  );
}

class _FeaturedHeroItem {
  const _FeaturedHeroItem({
    required this.id,
    required this.title,
    required this.landscapeImage,
    required this.portraitImage,
    required this.backgroundImage,
    required this.metadata,
    required this.overview,
    required this.detailTarget,
  });

  final String id;
  final String title;
  final _FeaturedHeroImage landscapeImage;
  final _FeaturedHeroImage portraitImage;
  final _FeaturedHeroImage backgroundImage;
  final String metadata;
  final String overview;
  final MediaDetailTarget detailTarget;

  factory _FeaturedHeroItem.fromCarousel(HomeCarouselItemViewModel item) {
    final fallbackImage = item.imageUrl.trim().isEmpty
        ? _FeaturedHeroImage(
            url: item.detailTarget.posterUrl,
            headers: item.detailTarget.posterHeaders,
            preferContain: true,
          )
        : _FeaturedHeroImage(url: item.imageUrl);
    final landscapeImage = _resolveFeaturedHeroLandscapeImage(
      target: item.detailTarget,
      fallbackImage: fallbackImage,
    );
    final portraitImage = _resolveFeaturedHeroPortraitImage(
      target: item.detailTarget,
      fallbackImage: fallbackImage,
      landscapeImage: landscapeImage,
    );
    return _FeaturedHeroItem(
      id: item.id,
      title: item.title,
      landscapeImage: landscapeImage,
      portraitImage: portraitImage,
      backgroundImage: _resolveFeaturedHeroBackgroundImage(
        target: item.detailTarget,
        fallbackImage: landscapeImage,
      ),
      metadata: _buildHeroMetadata(item.detailTarget, fallback: item.subtitle),
      overview: item.detailTarget.overview.trim().isEmpty
          ? item.subtitle
          : item.detailTarget.overview,
      detailTarget: item.detailTarget,
    );
  }

  factory _FeaturedHeroItem.fromPoster(HomeCardViewModel item) {
    final fallbackImage = _FeaturedHeroImage(
      url: item.posterUrl,
      headers: item.detailTarget.posterHeaders,
      preferContain: true,
    );
    final landscapeImage = _resolveFeaturedHeroLandscapeImage(
      target: item.detailTarget,
      fallbackImage: fallbackImage,
    );
    final portraitImage = _resolveFeaturedHeroPortraitImage(
      target: item.detailTarget,
      fallbackImage: fallbackImage,
      landscapeImage: landscapeImage,
    );
    return _FeaturedHeroItem(
      id: item.id,
      title: item.title,
      landscapeImage: landscapeImage,
      portraitImage: portraitImage,
      backgroundImage: _resolveFeaturedHeroBackgroundImage(
        target: item.detailTarget,
        fallbackImage: landscapeImage,
      ),
      metadata: _buildHeroMetadata(
        item.detailTarget,
        fallback: item.subtitle,
      ),
      overview: item.detailTarget.overview,
      detailTarget: item.detailTarget,
    );
  }
}

class _FeaturedHeroOverlayRequest {
  _FeaturedHeroOverlayRequest(this.item)
      : identity = jsonEncode({
          'id': item.id,
          'title': item.title,
          'metadata': item.metadata,
          'overview': item.overview,
          'detailTarget': item.detailTarget.toJson(),
          'landscape': item.landscapeImage.url,
          'portrait': item.portraitImage.url,
          'background': item.backgroundImage.url,
        });

  final _FeaturedHeroItem item;
  final String identity;

  LocalStorageDetailCacheScope get cacheScope => LocalStorageDetailCacheScope(
        lookupKeys: {
          ...LocalStorageCacheRepository.buildLookupKeys(item.detailTarget),
        },
      );

  @override
  bool operator ==(Object other) {
    return other is _FeaturedHeroOverlayRequest && other.identity == identity;
  }

  @override
  int get hashCode => identity.hashCode;
}

final _featuredHeroItemOverlayProvider = Provider.autoDispose
    .family<_FeaturedHeroItem, _FeaturedHeroOverlayRequest>((
  ref,
  request,
) {
  final liveOverlayEnabled = ref.watch(
    effectivePerformanceLiveItemHeroOverlayEnabledProvider,
  );
  if (!liveOverlayEnabled) {
    return request.item;
  }
  final cacheScope = request.cacheScope;
  if (!cacheScope.isEmpty) {
    ref.watch(
      localStorageDetailCacheChangeProvider.select(
        (state) => state.revisionForScope(
          cacheScope,
          changedFields: _homePresentationCacheChangedFields,
        ),
      ),
    );
  }
  final cachedTarget = ref
      .read(localStorageCacheRepositoryProvider)
      .peekDetailTarget(request.item.detailTarget);
  if (cachedTarget == null) {
    return request.item;
  }
  final mergedTarget = mergeCachedHomeDetailTarget(
    seed: request.item.detailTarget,
    cached: cachedTarget,
  );
  return _overlayFeaturedHeroItem(
    seed: request.item,
    mergedTarget: mergedTarget,
  );
});

_FeaturedHeroItem _overlayFeaturedHeroItem({
  required _FeaturedHeroItem seed,
  required MediaDetailTarget mergedTarget,
}) {
  if (identical(mergedTarget, seed.detailTarget)) {
    return seed;
  }
  final landscapeImage = _resolveFeaturedHeroLandscapeImage(
    target: mergedTarget,
    fallbackImage: seed.landscapeImage,
  );
  final portraitImage = _resolveFeaturedHeroPortraitImage(
    target: mergedTarget,
    fallbackImage: seed.portraitImage.preferContain
        ? seed.portraitImage
        : seed.landscapeImage,
    landscapeImage: landscapeImage,
  );
  return _FeaturedHeroItem(
    id: seed.id,
    title:
        mergedTarget.title.trim().isNotEmpty ? mergedTarget.title : seed.title,
    landscapeImage: landscapeImage,
    portraitImage: portraitImage,
    backgroundImage: _resolveFeaturedHeroBackgroundImage(
      target: mergedTarget,
      fallbackImage: seed.backgroundImage,
    ),
    metadata: _buildHeroMetadata(mergedTarget, fallback: seed.metadata),
    overview: mergedTarget.overview.trim().isNotEmpty
        ? mergedTarget.overview
        : seed.overview,
    detailTarget: mergedTarget,
  );
}

String _featuredHeroVisualFingerprint(_FeaturedHeroItem item) {
  return [
    item.id,
    item.title,
    item.metadata,
    item.overview,
    item.landscapeImage.url,
    item.portraitImage.url,
    item.backgroundImage.url,
    item.detailTarget.logoUrl,
  ].join('|');
}

class _FeaturedHeroImage {
  const _FeaturedHeroImage({
    required this.url,
    this.headers = const {},
    this.preferContain = false,
  });

  final String url;
  final Map<String, String> headers;
  final bool preferContain;
}

_FeaturedHeroImage _resolveFeaturedHeroLandscapeImage({
  required MediaDetailTarget target,
  required _FeaturedHeroImage fallbackImage,
}) {
  final wideCandidates = <_FeaturedHeroImage>[
    if (target.backdropUrl.trim().isNotEmpty &&
        !_isHomeDetailOnlyEpisodeBackdrop(target))
      _FeaturedHeroImage(
        url: target.backdropUrl,
        headers: target.backdropHeaders,
      ),
    if (target.bannerUrl.trim().isNotEmpty)
      _FeaturedHeroImage(
        url: target.bannerUrl,
        headers: target.bannerHeaders,
      ),
    if (fallbackImage.url.trim().isNotEmpty &&
        fallbackImage.url.trim() != target.posterUrl.trim())
      fallbackImage,
  ];

  if (wideCandidates.isNotEmpty) {
    return wideCandidates.first;
  }

  if (target.posterUrl.trim().isNotEmpty) {
    return _FeaturedHeroImage(
      url: target.posterUrl,
      headers: target.posterHeaders,
      preferContain: true,
    );
  }

  if (fallbackImage.url.trim().isNotEmpty) {
    return _FeaturedHeroImage(
      url: fallbackImage.url,
      headers: fallbackImage.headers,
      preferContain: true,
    );
  }

  return const _FeaturedHeroImage(url: '');
}

_FeaturedHeroImage _resolveFeaturedHeroPortraitImage({
  required MediaDetailTarget target,
  required _FeaturedHeroImage fallbackImage,
  required _FeaturedHeroImage landscapeImage,
}) {
  if (target.posterUrl.trim().isNotEmpty) {
    return _FeaturedHeroImage(
      url: target.posterUrl,
      headers: target.posterHeaders,
      preferContain: true,
    );
  }

  if (fallbackImage.url.trim().isNotEmpty && fallbackImage.preferContain) {
    return _FeaturedHeroImage(
      url: fallbackImage.url,
      headers: fallbackImage.headers,
      preferContain: true,
    );
  }

  if (landscapeImage.url.trim().isNotEmpty) {
    return landscapeImage;
  }

  if (fallbackImage.url.trim().isNotEmpty) {
    return fallbackImage;
  }

  return const _FeaturedHeroImage(url: '');
}

_FeaturedHeroImage _resolveFeaturedHeroBackgroundImage({
  required MediaDetailTarget target,
  required _FeaturedHeroImage fallbackImage,
}) {
  if (target.backdropUrl.trim().isNotEmpty &&
      !_isHomeDetailOnlyEpisodeBackdrop(target)) {
    return _FeaturedHeroImage(
      url: target.backdropUrl,
      headers: target.backdropHeaders,
    );
  }
  if (target.bannerUrl.trim().isNotEmpty) {
    return _FeaturedHeroImage(
      url: target.bannerUrl,
      headers: target.bannerHeaders,
    );
  }
  if (target.posterUrl.trim().isNotEmpty) {
    return _FeaturedHeroImage(
      url: target.posterUrl,
      headers: target.posterHeaders,
      preferContain: true,
    );
  }
  return fallbackImage;
}

String _buildHeroMetadata(
  MediaDetailTarget target, {
  String fallback = '',
}) {
  final entries = <String>[
    if (target.year > 0) '${target.year}',
    if (target.durationLabel.trim().isNotEmpty) target.durationLabel,
    ...target.genres.take(2).where((item) => item.trim().isNotEmpty),
  ];

  if (entries.isEmpty && fallback.trim().isNotEmpty) {
    entries.add(fallback.trim());
  }
  return entries.join(' · ');
}

class _FeaturedHero extends ConsumerStatefulWidget {
  const _FeaturedHero({
    super.key,
    required this.items,
    required this.displayMode,
    required this.isTelevision,
    required this.staticModeEnabled,
    required this.lightweightVisualEnabled,
    required this.showPagerButtons,
    required this.logoTitleEnabled,
    required this.translucentEffectsEnabled,
    required this.focusScopePrefix,
    this.onFocusBelowControl,
    this.onFocusedItemChanged,
  });

  final List<_FeaturedHeroItem> items;
  final HomeHeroDisplayMode displayMode;
  final bool isTelevision;
  final bool staticModeEnabled;
  final bool lightweightVisualEnabled;
  final bool showPagerButtons;
  final bool logoTitleEnabled;
  final bool translucentEffectsEnabled;
  final String focusScopePrefix;
  final VoidCallback? onFocusBelowControl;
  final ValueChanged<_FeaturedHeroItem>? onFocusedItemChanged;

  @override
  ConsumerState<_FeaturedHero> createState() => _FeaturedHeroState();
}

class _FeaturedHeroState extends ConsumerState<_FeaturedHero> {
  late PageController _controller;
  final ValueNotifier<double> _pageNotifier = ValueNotifier<double>(0);
  final Map<String, FocusNode> _cardFocusNodes = <String, FocusNode>{};
  final FocusNode _previousPagerButtonFocusNode =
      FocusNode(debugLabel: 'home-hero-prev');
  final FocusNode _nextPagerButtonFocusNode =
      FocusNode(debugLabel: 'home-hero-next');
  double _page = 0;
  int _lastReportedIndex = -1;
  String _lastReportedItemId = '';
  String _lastReportedVisualFingerprint = '';

  @override
  void initState() {
    super.initState();
    _syncCardFocusNodes();
    _controller = _buildController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyFocusedItem(0);
    });
  }

  @override
  void didUpdateWidget(covariant _FeaturedHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncCardFocusNodes();
    final oldLength = oldWidget.items.length;
    final newLength = widget.items.length;
    if (oldWidget.displayMode != widget.displayMode) {
      final int nextPage = widget.items.isEmpty
          ? 0
          : _page.round().clamp(0, widget.items.length - 1);
      _controller
        ..removeListener(_handlePageChange)
        ..dispose();
      _controller = _buildController(initialPage: nextPage);
      _page = nextPage.toDouble();
      _pageNotifier.value = _page;
      _lastReportedIndex = -1;
      _lastReportedItemId = '';
      _lastReportedVisualFingerprint = '';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _notifyFocusedItem(nextPage);
      });
      return;
    }

    if (oldLength != newLength) {
      _syncCurrentPageToVisibleItems();
      return;
    }

    if (newLength > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.items.isEmpty) {
          return;
        }
        _notifyFocusedItem(_currentPageIndex);
      });
    }
  }

  @override
  void dispose() {
    for (final focusNode in _cardFocusNodes.values) {
      focusNode.dispose();
    }
    _previousPagerButtonFocusNode.dispose();
    _nextPagerButtonFocusNode.dispose();
    _controller
      ..removeListener(_handlePageChange)
      ..dispose();
    _pageNotifier.dispose();
    super.dispose();
  }

  int get _currentPageIndex => widget.items.isEmpty
      ? 0
      : _page.round().clamp(0, widget.items.length - 1);

  void _syncCardFocusNodes() {
    final validIds = widget.items
        .map((item) => item.id)
        .where((item) => item.trim().isNotEmpty)
        .toSet();
    final obsoleteIds = _cardFocusNodes.keys
        .where((item) => !validIds.contains(item))
        .toList(growable: false);
    for (final id in obsoleteIds) {
      _cardFocusNodes.remove(id)?.dispose();
    }
  }

  FocusNode _focusNodeForItem(String itemId) {
    return _cardFocusNodes.putIfAbsent(
      itemId,
      () => FocusNode(debugLabel: 'home-hero-card:$itemId'),
    );
  }

  PageController _buildController({int initialPage = 0}) {
    return PageController(
      initialPage: initialPage,
      viewportFraction: widget.displayMode.viewportFraction,
    )..addListener(_handlePageChange);
  }

  void _handlePageChange() {
    if (!mounted) {
      return;
    }
    final double page = _controller.hasClients ? _controller.page ?? 0.0 : 0.0;
    _commitPageChange(page);
  }

  void _commitPageChange(double page) {
    if (!mounted) {
      return;
    }
    _notifyFocusedItem(page.round());
    if ((_page - page).abs() < 0.0001) {
      return;
    }
    _page = page;
    _pageNotifier.value = page;
  }

  void _notifyFocusedItem(int index) {
    if (index < 0 || index >= widget.items.length) {
      return;
    }
    final currentItem = ref.read(
      _featuredHeroItemOverlayProvider(
        _FeaturedHeroOverlayRequest(widget.items[index]),
      ),
    );
    final visualFingerprint = _featuredHeroVisualFingerprint(currentItem);
    if (_lastReportedIndex == index &&
        _lastReportedItemId == currentItem.id &&
        _lastReportedVisualFingerprint == visualFingerprint) {
      return;
    }
    _lastReportedIndex = index;
    _lastReportedItemId = currentItem.id;
    _lastReportedVisualFingerprint = visualFingerprint;
    widget.onFocusedItemChanged?.call(currentItem);
  }

  void _syncCurrentPageToVisibleItems() {
    if (widget.items.isEmpty) {
      _page = 0;
      _pageNotifier.value = _page;
      _lastReportedIndex = -1;
      _lastReportedItemId = '';
      _lastReportedVisualFingerprint = '';
      return;
    }
    final maxPage = (widget.items.length - 1).toDouble();
    _page = _page.clamp(0.0, maxPage);
    _pageNotifier.value = _page;
    if (!_controller.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients || widget.items.isEmpty) {
          return;
        }
        _controller.jumpToPage(_currentPageIndex);
        _notifyFocusedItem(_currentPageIndex);
      });
      return;
    }
    final currentControllerPage = _controller.page ?? _page;
    final boundedControllerPage = currentControllerPage.clamp(0.0, maxPage);
    if ((boundedControllerPage - currentControllerPage).abs() >= 0.0001) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients || widget.items.isEmpty) {
          return;
        }
        _controller.jumpToPage(_currentPageIndex);
        _notifyFocusedItem(_currentPageIndex);
      });
      return;
    }
    _notifyFocusedItem(_currentPageIndex);
  }

  Future<void> _moveToIndex(int index) async {
    if (index < 0 || index >= widget.items.length) {
      return;
    }
    if (widget.staticModeEnabled) {
      _controller.jumpToPage(index);
      return;
    }
    await _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _focusPagerButton(FocusNode focusNode) {
    if (!focusNode.canRequestFocus) {
      return;
    }
    focusNode.requestFocus();
  }

  void _focusCurrentCard() {
    if (widget.items.isEmpty) {
      return;
    }
    final node = _focusNodeForItem(widget.items[_currentPageIndex].id);
    if (!node.canRequestFocus) {
      return;
    }
    node.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final simplifyVisualEffects = widget.lightweightVisualEnabled;
    final selectedOverlayItem = widget.items.isEmpty
        ? null
        : ref.watch(
            _featuredHeroItemOverlayProvider(
              _FeaturedHeroOverlayRequest(widget.items[_currentPageIndex]),
            ),
          );
    if (selectedOverlayItem != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _notifyFocusedItem(_currentPageIndex);
      });
    }

    return Column(
      children: [
        SizedBox(
          height: widget.displayMode.heroHeight,
          child: Stack(
            children: [
              Focus(
                canRequestFocus: false,
                skipTraversal: true,
                descendantsAreFocusable: true,
                child: PageView.builder(
                  controller: _controller,
                  physics: widget.isTelevision
                      ? const NeverScrollableScrollPhysics()
                      : const PageScrollPhysics(),
                  itemCount: widget.items.length,
                  itemBuilder: (context, index) {
                    final item = widget.items[index];
                    return Padding(
                      padding: EdgeInsets.only(
                        right: index == widget.items.length - 1
                            ? 0
                            : widget.displayMode.cardGap,
                      ),
                      child: _FeaturedHeroCard(
                        item: item,
                        displayMode: widget.displayMode,
                        isTelevision: widget.isTelevision,
                        logoTitleEnabled: widget.logoTitleEnabled,
                        translucentEffectsEnabled:
                            widget.translucentEffectsEnabled,
                        simplifyVisualEffects: simplifyVisualEffects,
                        focusNode: _focusNodeForItem(item.id),
                        focusId: '${widget.focusScopePrefix}:${item.id}',
                        autofocus: index == _currentPageIndex,
                        onFocusPreviousControl: () =>
                            _focusPagerButton(_previousPagerButtonFocusNode),
                        onFocusNextControl: () =>
                            _focusPagerButton(_nextPagerButtonFocusNode),
                        onFocusBelowControl: widget.onFocusBelowControl,
                      ),
                    );
                  },
                ),
              ),
              if (widget.showPagerButtons && widget.items.length > 1)
                ValueListenableBuilder<double>(
                  valueListenable: _pageNotifier,
                  builder: (context, page, child) {
                    final currentIndex =
                        page.round().clamp(0, widget.items.length - 1);
                    return Stack(
                      children: [
                        Positioned(
                          left: 16,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: _HeroPagerButton(
                              isTelevision: widget.isTelevision,
                              staticModeEnabled: widget.staticModeEnabled,
                              icon: Icons.chevron_left_rounded,
                              focusNode: _previousPagerButtonFocusNode,
                              focusId: '${widget.focusScopePrefix}:pager-prev',
                              enabled: currentIndex > 0,
                              onMoveRight: _focusCurrentCard,
                              onFocusBelowControl: widget.onFocusBelowControl,
                              onPressed: currentIndex > 0
                                  ? () => _moveToIndex(currentIndex - 1)
                                  : null,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 16,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: _HeroPagerButton(
                              isTelevision: widget.isTelevision,
                              staticModeEnabled: widget.staticModeEnabled,
                              icon: Icons.chevron_right_rounded,
                              focusNode: _nextPagerButtonFocusNode,
                              focusId: '${widget.focusScopePrefix}:pager-next',
                              enabled: currentIndex < widget.items.length - 1,
                              onMoveLeft: _focusCurrentCard,
                              onFocusBelowControl: widget.onFocusBelowControl,
                              onPressed: currentIndex < widget.items.length - 1
                                  ? () => _moveToIndex(currentIndex + 1)
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
        if (widget.items.length > 1) ...[
          const SizedBox(height: 12),
          ValueListenableBuilder<double>(
            valueListenable: _pageNotifier,
            builder: (context, page, child) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.items.length, (index) {
                  final isActive = (page - index).abs() < 0.5;
                  return AnimatedContainer(
                    duration: widget.staticModeEnabled
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    width: isActive ? 18 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: isActive
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.34),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  );
                }),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _HeroPagerButton extends StatelessWidget {
  const _HeroPagerButton({
    required this.isTelevision,
    required this.staticModeEnabled,
    required this.icon,
    this.focusNode,
    this.focusId,
    required this.enabled,
    this.onMoveLeft,
    this.onMoveRight,
    this.onFocusBelowControl,
    this.onPressed,
  });

  final bool isTelevision;
  final bool staticModeEnabled;
  final IconData icon;
  final FocusNode? focusNode;
  final String? focusId;
  final bool enabled;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;
  final VoidCallback? onFocusBelowControl;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final child = AnimatedOpacity(
      duration:
          staticModeEnabled ? Duration.zero : const Duration(milliseconds: 180),
      opacity: enabled ? 0.92 : 0.35,
      child: Material(
        color: Colors.black.withValues(alpha: 0.26),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 54,
          height: 54,
          child: Icon(icon, color: Colors.white, size: 30),
        ),
      ),
    );

    if (!isTelevision) {
      return Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: child,
        ),
      );
    }

    return TvDirectionalActionPanel(
      enabled: isTelevision,
      onMoveLeft: onMoveLeft,
      onMoveRight: onMoveRight,
      onMoveDown: onFocusBelowControl,
      child: TvFocusableAction(
        onPressed: onPressed ?? () {},
        focusNode: focusNode,
        focusId: focusId,
        borderRadius: BorderRadius.circular(999),
        child: child,
      ),
    );
  }
}

class _FeaturedHeroCard extends ConsumerWidget {
  const _FeaturedHeroCard({
    required this.item,
    required this.displayMode,
    required this.isTelevision,
    required this.logoTitleEnabled,
    required this.translucentEffectsEnabled,
    required this.simplifyVisualEffects,
    this.focusNode,
    required this.focusId,
    required this.autofocus,
    this.onFocusPreviousControl,
    this.onFocusNextControl,
    this.onFocusBelowControl,
  });

  final _FeaturedHeroItem item;
  final HomeHeroDisplayMode displayMode;
  final bool isTelevision;
  final bool logoTitleEnabled;
  final bool translucentEffectsEnabled;
  final bool simplifyVisualEffects;
  final FocusNode? focusNode;
  final String focusId;
  final bool autofocus;
  final VoidCallback? onFocusPreviousControl;
  final VoidCallback? onFocusNextControl;
  final VoidCallback? onFocusBelowControl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolvedItem = ref.watch(
      _featuredHeroItemOverlayProvider(_FeaturedHeroOverlayRequest(item)),
    );
    final usesCompositeBackdrop =
        !simplifyVisualEffects && displayMode.usesFrostedBackdrop;
    final borderRadius = BorderRadius.circular(displayMode.cardBorderRadius);
    final Gradient contentGradient = simplifyVisualEffects
        ? LinearGradient(
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.16),
              Colors.black.withValues(alpha: 0.62),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0, 0.56, 1],
          )
        : RadialGradient(
            center: const Alignment(-0.92, 0.96),
            radius: 1.1,
            colors: [
              Colors.black.withValues(alpha: 0.82),
              Colors.black.withValues(alpha: 0.52),
              Colors.black.withValues(alpha: 0.18),
              Colors.transparent,
            ],
            stops: const [0, 0.36, 0.72, 1],
          );

    final card = Ink(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: usesCompositeBackdrop
            ? Colors.white.withValues(
                alpha: translucentEffectsEnabled ? 0.04 : 0.02,
              )
            : const Color(0xFF0B1628),
        boxShadow: !simplifyVisualEffects && displayMode.showShadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 34,
                  offset: const Offset(0, 18),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (usesCompositeBackdrop)
              ClipRect(
                child: translucentEffectsEnabled
                    ? BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0.08),
                                const Color(0xFF0A1628).withValues(alpha: 0.22),
                                const Color(0xFF07111E).withValues(alpha: 0.32),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      )
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0.03),
                              const Color(0xFF0A1628).withValues(alpha: 0.14),
                              const Color(0xFF07111E).withValues(alpha: 0.24),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
              ),
            _FeaturedHeroArtwork(
              item: resolvedItem,
              displayMode: displayMode,
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: IgnorePointer(
                child: FractionallySizedBox(
                  widthFactor: _resolveHeroTextWidthFactor(displayMode),
                  heightFactor: 0.72,
                  alignment: Alignment.bottomLeft,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: contentGradient,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: displayMode.textPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  if (resolvedItem.metadata.trim().isNotEmpty)
                    Text(
                      resolvedItem.metadata,
                      style: const TextStyle(
                        color: Color(0xFFDCE7FF),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (resolvedItem.metadata.trim().isNotEmpty)
                    const SizedBox(height: 10),
                  _HeroTitle(
                    item: resolvedItem,
                    displayMode: displayMode,
                    logoTitleEnabled: logoTitleEnabled,
                    simplifyVisualEffects: simplifyVisualEffects,
                  ),
                  const SizedBox(height: 10),
                  if (resolvedItem.overview.trim().isNotEmpty)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Text(
                        resolvedItem.overview,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xFFE4ECFF),
                          fontSize: 15,
                          height: 1.45,
                          shadows: simplifyVisualEffects
                              ? null
                              : const [
                                  Shadow(
                                    color: Color(0x9A000000),
                                    blurRadius: 16,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (!isTelevision) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: () =>
              context.pushNamed('detail', extra: resolvedItem.detailTarget),
          child: card,
        ),
      );
    }

    return FocusableActionDetector(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowLeft):
            DirectionalFocusIntent(TraversalDirection.left),
        SingleActivator(LogicalKeyboardKey.arrowRight):
            DirectionalFocusIntent(TraversalDirection.right),
        SingleActivator(LogicalKeyboardKey.arrowDown):
            DirectionalFocusIntent(TraversalDirection.down),
      },
      actions: <Type, Action<Intent>>{
        DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
          onInvoke: (intent) {
            if (intent.direction == TraversalDirection.left) {
              final focusPreviousControl = onFocusPreviousControl;
              if (focusPreviousControl != null) {
                focusPreviousControl();
              } else {
                TvMenuButtonScope.maybeOf(context)?.onMenuButtonPressed();
              }
            } else if (intent.direction == TraversalDirection.right) {
              onFocusNextControl?.call();
            } else if (intent.direction == TraversalDirection.down) {
              final focusBelowControl = onFocusBelowControl;
              if (focusBelowControl != null) {
                focusBelowControl();
              } else {
                FocusManager.instance.primaryFocus?.focusInDirection(
                  TraversalDirection.down,
                );
              }
            }
            return null;
          },
        ),
      },
      child: TvFocusableAction(
        onPressed: () =>
            context.pushNamed('detail', extra: resolvedItem.detailTarget),
        focusNode: focusNode,
        focusId: focusId,
        autofocus: autofocus,
        borderRadius: borderRadius,
        child: card,
      ),
    );
  }
}

class _FeaturedHeroArtwork extends StatelessWidget {
  const _FeaturedHeroArtwork({
    required this.item,
    required this.displayMode,
  });

  final _FeaturedHeroItem item;
  final HomeHeroDisplayMode displayMode;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenSize = MediaQuery.sizeOf(context);
        final isPortraitScreen = screenSize.height > screenSize.width;
        final selectedImage = isPortraitScreen
            ? (item.portraitImage.url.trim().isNotEmpty
                ? item.portraitImage
                : item.landscapeImage)
            : (item.landscapeImage.url.trim().isNotEmpty
                ? item.landscapeImage
                : item.portraitImage);

        if (selectedImage.url.trim().isEmpty) {
          return const SizedBox.shrink();
        }
        final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
        final cacheWidth = _resolveCacheDimension(
          constraints.maxWidth,
          devicePixelRatio,
          max: 1920,
        );
        final cacheHeight = _resolveCacheDimension(
          constraints.maxHeight,
          devicePixelRatio,
          max: 1200,
        );

        if (!selectedImage.preferContain) {
          return AppNetworkImage(
            selectedImage.url,
            headers: selectedImage.headers,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            cacheWidth: cacheWidth,
            cacheHeight: cacheHeight,
          );
        }

        if (isPortraitScreen) {
          return AppNetworkImage(
            selectedImage.url,
            headers: selectedImage.headers,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            cacheWidth: cacheWidth,
            cacheHeight: cacheHeight,
          );
        }

        final useCenteredContainLayout = selectedImage.preferContain;
        final topPadding =
            displayMode == HomeHeroDisplayMode.normal ? 22.0 : 28.0;
        final sidePadding =
            displayMode == HomeHeroDisplayMode.normal ? 22.0 : 28.0;
        final bottomPadding =
            displayMode == HomeHeroDisplayMode.normal ? 22.0 : 28.0;

        return Align(
          alignment: useCenteredContainLayout
              ? Alignment.center
              : Alignment.centerRight,
          child: FractionallySizedBox(
            widthFactor:
                displayMode == HomeHeroDisplayMode.normal ? 0.54 : 0.42,
            child: Padding(
              padding: useCenteredContainLayout
                  ? EdgeInsets.fromLTRB(
                      sidePadding,
                      topPadding,
                      sidePadding,
                      bottomPadding,
                    )
                  : EdgeInsets.fromLTRB(
                      0,
                      topPadding,
                      displayMode == HomeHeroDisplayMode.normal ? 18 : 24,
                      bottomPadding,
                    ),
              child: AppNetworkImage(
                selectedImage.url,
                headers: selectedImage.headers,
                fit: BoxFit.contain,
                alignment: useCenteredContainLayout
                    ? Alignment.center
                    : Alignment.centerRight,
                cacheWidth: cacheWidth,
                cacheHeight: cacheHeight,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HeroTitle extends StatelessWidget {
  const _HeroTitle({
    required this.item,
    required this.displayMode,
    required this.logoTitleEnabled,
    required this.simplifyVisualEffects,
  });

  final _FeaturedHeroItem item;
  final HomeHeroDisplayMode displayMode;
  final bool logoTitleEnabled;
  final bool simplifyVisualEffects;

  @override
  Widget build(BuildContext context) {
    final hasLogo =
        logoTitleEnabled && item.detailTarget.logoUrl.trim().isNotEmpty;
    if (hasLogo) {
      return ConstrainedBox(
        constraints: _resolveHeroLogoConstraints(displayMode),
        child: AppNetworkImage(
          item.detailTarget.logoUrl,
          headers: item.detailTarget.logoHeaders,
          fit: BoxFit.contain,
          alignment: Alignment.centerLeft,
          errorBuilder: (context, error, stackTrace) {
            return _HeroTitleText(
              item: item,
              displayMode: displayMode,
              simplifyVisualEffects: simplifyVisualEffects,
            );
          },
        ),
      );
    }
    return _HeroTitleText(
      item: item,
      displayMode: displayMode,
      simplifyVisualEffects: simplifyVisualEffects,
    );
  }
}

class _HeroTitleText extends StatelessWidget {
  const _HeroTitleText({
    required this.item,
    required this.displayMode,
    required this.simplifyVisualEffects,
  });

  final _FeaturedHeroItem item;
  final HomeHeroDisplayMode displayMode;
  final bool simplifyVisualEffects;

  @override
  Widget build(BuildContext context) {
    return Text(
      item.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: _resolveHeroTitleFontSize(displayMode),
            height: 1.05,
            shadows: simplifyVisualEffects
                ? null
                : [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
    );
  }
}
