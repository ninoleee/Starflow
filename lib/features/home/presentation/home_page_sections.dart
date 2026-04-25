part of 'home_page.dart';

const double _kHomePosterRailFocusOverflowPadding = 10;
const double _kHomeCarouselFocusOverflowPadding = 10;

class _HomeSectionSlot extends ConsumerStatefulWidget {
  const _HomeSectionSlot({
    super.key,
    required this.module,
    required this.isPageVisible,
    required this.useHeroNextSectionFocusNode,
    required this.heroNextSectionFocusNode,
    required this.homeMetadataAutoRefreshRevision,
  });

  final HomeModuleConfig module;
  final bool isPageVisible;
  final bool useHeroNextSectionFocusNode;
  final FocusNode heroNextSectionFocusNode;
  final int homeMetadataAutoRefreshRevision;

  @override
  ConsumerState<_HomeSectionSlot> createState() => _HomeSectionSlotState();
}

class _HomeSectionSlotState extends ConsumerState<_HomeSectionSlot>
    with AutomaticKeepAliveClientMixin<_HomeSectionSlot> {
  AsyncValue<HomeSectionViewModel?>? _cachedState;
  final DetailRatingPrefetchCoordinator _ratingPrefetchCoordinator =
      DetailRatingPrefetchCoordinator();
  int _observedHomeMetadataAutoRefreshRevision = 0;
  int _scheduledHomeMetadataAutoRefreshRevision = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(covariant _HomeSectionSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isPageVisible && widget.isPageVisible) {
      _ratingPrefetchCoordinator.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final activeState = widget.isPageVisible
        ? ref.watch(homeSectionProvider(widget.module.id))
        : null;
    final state = resolveRetainedAsyncValue(
      activeValue: activeState,
      cachedValue: _cachedState,
      cacheValue: (value) => _cachedState = value,
      fallbackValue: const AsyncLoading<HomeSectionViewModel?>(),
    );
    final section = state.value;
    if (section != null) {
      return _buildResolvedSection(context, section);
    }

    if (state.hasError) {
      return _HomeSection(
        title: widget.module.title,
        child: const _SectionEmptyState(message: '加载失败'),
      );
    }

    return _HomeSectionLoading(
      title: widget.module.title,
      layout: widget.module.type == HomeModuleType.doubanCarousel
          ? HomeSectionLayout.carousel
          : HomeSectionLayout.posterRail,
    );
  }

  Widget _buildResolvedSection(
    BuildContext context,
    HomeSectionViewModel section,
  ) {
    if (widget.homeMetadataAutoRefreshRevision !=
        _observedHomeMetadataAutoRefreshRevision) {
      _ratingPrefetchCoordinator.reset();
      _observedHomeMetadataAutoRefreshRevision =
          widget.homeMetadataAutoRefreshRevision;
    }
    if (widget.isPageVisible &&
        section.layout == HomeSectionLayout.posterRail &&
        section.items.isNotEmpty &&
        _scheduledHomeMetadataAutoRefreshRevision !=
            widget.homeMetadataAutoRefreshRevision) {
      _ratingPrefetchCoordinator.schedulePrefetch(
        ref: ref,
        targets: section.items.map((item) => item.detailTarget),
        isPageActive: () => mounted && widget.isPageVisible,
        preferDoubanOnly: _isHomeDoubanPosterModule(widget.module),
      );
      _scheduledHomeMetadataAutoRefreshRevision =
          widget.homeMetadataAutoRefreshRevision;
    }
    final viewAllTarget = section.viewAllTarget;
    final openViewAll = viewAllTarget == null
        ? null
        : () {
            context.pushNamed(
              viewAllTarget.routeName,
              extra: viewAllTarget.extra,
            );
          };
    return _HomeSection(
      title: section.title,
      child: section.layout == HomeSectionLayout.carousel
          ? _HomeCarousel(
              items: section.carouselItems,
              focusScopePrefix: 'home:carousel:${section.id}',
              firstItemFocusNode: widget.useHeroNextSectionFocusNode
                  ? widget.heroNextSectionFocusNode
                  : null,
            )
          : section.items.isEmpty
              ? _SectionEmptyState(message: section.emptyMessage)
              : SizedBox(
                  height: 246 + _kHomePosterRailFocusOverflowPadding,
                  child: DesktopHorizontalPager(
                    builder: (context, controller) => ListView.separated(
                      controller: controller,
                      primary: false,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        12,
                        _kHomePosterRailFocusOverflowPadding,
                        12,
                        0,
                      ),
                      clipBehavior: Clip.none,
                      scrollDirection: Axis.horizontal,
                      itemCount:
                          section.items.length + (openViewAll == null ? 0 : 1),
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        if (index >= section.items.length) {
                          return _HomeSectionViewAllTile(
                            focusId: 'home:section:${section.id}:view-all',
                            onTap: openViewAll!,
                          );
                        }
                        final item = section.items[index];
                        return _HomePosterTile(
                          module: widget.module,
                          item: item,
                          focusNode:
                              widget.useHeroNextSectionFocusNode && index == 0
                                  ? widget.heroNextSectionFocusNode
                                  : null,
                          focusId:
                              'home:section:${section.id}:item:${item.detailTarget.itemId.isNotEmpty ? item.detailTarget.itemId : item.title}',
                          autofocus:
                              widget.useHeroNextSectionFocusNode && index == 0,
                        );
                      },
                    ),
                  ),
                ),
    );
  }
}

bool _isHomeDoubanPosterModule(HomeModuleConfig module) {
  return switch (module.type) {
    HomeModuleType.doubanInterest => true,
    HomeModuleType.doubanSuggestion => true,
    HomeModuleType.doubanList => true,
    HomeModuleType.doubanCarousel => true,
    _ => false,
  };
}

String _resolveHomePosterBadgeText({
  required HomeModuleConfig module,
  required HomeCardViewModel item,
}) {
  return resolvePreferredPosterRatingLabel(
    item.detailTarget.ratingLabels,
    preferDoubanOnly: _isHomeDoubanPosterModule(module),
  );
}

class _HomePosterTile extends StatelessWidget {
  const _HomePosterTile({
    required this.module,
    required this.item,
    this.focusNode,
    this.focusId,
    required this.autofocus,
  });

  final HomeModuleConfig module;
  final HomeCardViewModel item;
  final FocusNode? focusNode;
  final String? focusId;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return MediaPosterTile(
      title: item.title,
      subtitle: item.subtitle,
      posterUrl: item.posterUrl,
      imageBadgeText: _resolveHomePosterBadgeText(
        module: module,
        item: item,
      ),
      tvPosterFocusOutlineOnly: true,
      tvPosterFocusShowBorder: false,
      tvPosterFocusScale: 1.06,
      tvPosterAnimateFocus: false,
      focusNode: focusNode,
      focusId: focusId,
      autofocus: autofocus,
      posterHeaders: item.detailTarget.posterHeaders,
      posterFallbackSources: _buildPosterFallbackSources(item.detailTarget),
      titleColor: Colors.white,
      subtitleColor: const Color(0xFF98A7C2),
      onTap: () {
        context.pushNamed(
          'detail',
          extra: item.detailTarget,
        );
      },
    );
  }
}

class _HomeShell extends StatelessWidget {
  const _HomeShell({
    required this.backgroundImageUrl,
    this.backgroundImageHeaders = const {},
    this.translucentEffectsEnabled = true,
    this.simplifyHeroBackdrop = false,
    required this.child,
  });

  final String backgroundImageUrl;
  final Map<String, String> backgroundImageHeaders;
  final bool translucentEffectsEnabled;
  final bool simplifyHeroBackdrop;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final verticalInsets = EdgeInsets.only(
      top: appPageTopInset(context),
      bottom: appPageBottomInset(
        context,
        includeBottomNavigationBar: true,
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: _DynamicHeroBackdrop(
            imageUrl: backgroundImageUrl,
            imageHeaders: backgroundImageHeaders,
            translucentEffectsEnabled: translucentEffectsEnabled,
            simplifyVisualEffects: simplifyHeroBackdrop,
          ),
        ),
        const RepaintBoundary(
          child: _HomeShellForegroundMask(),
        ),
        Padding(
          padding: verticalInsets,
          child: child,
        ),
      ],
    );
  }
}

class _HomeShellForegroundMask extends StatelessWidget {
  const _HomeShellForegroundMask();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.black.withValues(alpha: 0.08),
            const Color(0x7A07111D),
            const Color(0x52030914),
            Colors.transparent,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.42, 0.82, 1],
        ),
      ),
    );
  }
}

class _DynamicHeroBackdrop extends StatelessWidget {
  const _DynamicHeroBackdrop({
    required this.imageUrl,
    this.imageHeaders = const {},
    this.translucentEffectsEnabled = true,
    this.simplifyVisualEffects = false,
  });

  final String imageUrl;
  final Map<String, String> imageHeaders;
  final bool translucentEffectsEnabled;
  final bool simplifyVisualEffects;

  @override
  Widget build(BuildContext context) {
    final layer = _DynamicHeroBackdropLayer(
      key: ValueKey(imageUrl.trim().isEmpty ? 'empty' : imageUrl),
      imageUrl: imageUrl,
      imageHeaders: imageHeaders,
      translucentEffectsEnabled: translucentEffectsEnabled,
      simplifyVisualEffects: simplifyVisualEffects,
    );
    if (!translucentEffectsEnabled || simplifyVisualEffects) {
      return IgnorePointer(child: layer);
    }

    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 550),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: layer,
      ),
    );
  }
}

@visibleForTesting
class HomeHeroBackdrop extends StatelessWidget {
  const HomeHeroBackdrop({
    super.key,
    required this.imageUrl,
    this.imageHeaders = const {},
    this.translucentEffectsEnabled = true,
    this.simplifyVisualEffects = false,
  });

  final String imageUrl;
  final Map<String, String> imageHeaders;
  final bool translucentEffectsEnabled;
  final bool simplifyVisualEffects;

  @override
  Widget build(BuildContext context) {
    return _DynamicHeroBackdrop(
      imageUrl: imageUrl,
      imageHeaders: imageHeaders,
      translucentEffectsEnabled: translucentEffectsEnabled,
      simplifyVisualEffects: simplifyVisualEffects,
    );
  }
}

class _DynamicHeroBackdropLayer extends StatelessWidget {
  const _DynamicHeroBackdropLayer({
    super.key,
    required this.imageUrl,
    this.imageHeaders = const {},
    this.translucentEffectsEnabled = true,
    this.simplifyVisualEffects = false,
  });

  final String imageUrl;
  final Map<String, String> imageHeaders;
  final bool translucentEffectsEnabled;
  final bool simplifyVisualEffects;

  @override
  Widget build(BuildContext context) {
    final viewportSize = MediaQuery.sizeOf(context);
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final backdropScale = simplifyVisualEffects ? 1.0 : 1.16;
    final cacheWidth = _resolveCacheDimension(
      viewportSize.width,
      devicePixelRatio,
      scale: backdropScale,
      max: simplifyVisualEffects ? 1440 : 1920,
    );
    final cacheHeight = _resolveCacheDimension(
      viewportSize.height,
      devicePixelRatio,
      scale: backdropScale,
      max: simplifyVisualEffects ? 900 : 1200,
    );
    final trimmedUrl = imageUrl.trim();
    Widget? backgroundImage;
    if (trimmedUrl.isNotEmpty) {
      final image = AppNetworkImage(
        trimmedUrl,
        headers: imageHeaders,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
      );
      if (simplifyVisualEffects) {
        backgroundImage = Opacity(
          opacity: 0.64,
          child: image,
        );
      } else if (translucentEffectsEnabled) {
        backgroundImage = Transform.scale(
          scale: backdropScale,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Opacity(
              opacity: 0.72,
              child: image,
            ),
          ),
        );
      } else {
        backgroundImage = Opacity(
          opacity: 0.12,
          child: image,
        );
      }
    }

    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF030914)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (backgroundImage != null) backgroundImage,
          if (!translucentEffectsEnabled && !simplifyVisualEffects)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF07111D).withValues(alpha: 0.32),
                    const Color(0xFF07111D).withValues(alpha: 0.64),
                    const Color(0xFF030914).withValues(alpha: 0.82),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0x26000000),
                  Colors.black.withValues(alpha: 0.16),
                  Colors.black.withValues(alpha: 0.14),
                  Colors.transparent,
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.48, 0.84, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeHeroPlaceholder extends StatelessWidget {
  const _HomeHeroPlaceholder({required this.displayMode});

  final HomeHeroDisplayMode displayMode;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(displayMode.cardBorderRadius);

    return SizedBox(
      height: displayMode.heroHeight,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            gradient: LinearGradient(
              colors: [
                const Color(0xFF142235),
                const Color(0xFF0C1626),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _HomeSectionLoading extends StatelessWidget {
  const _HomeSectionLoading({
    required this.title,
    required this.layout,
  });

  final String title;
  final HomeSectionLayout layout;

  @override
  Widget build(BuildContext context) {
    return _HomeSection(
      title: title,
      child: layout == HomeSectionLayout.carousel
          ? Container(
              height: 184,
              decoration: BoxDecoration(
                color: const Color(0xFF0B1631).withValues(alpha: 0.56),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          : SizedBox(
              height: 246 + _kHomePosterRailFocusOverflowPadding,
              child: ListView.separated(
                primary: false,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  12,
                  _kHomePosterRailFocusOverflowPadding,
                  12,
                  0,
                ),
                clipBehavior: Clip.none,
                scrollDirection: Axis.horizontal,
                itemCount: 3,
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  return const _PosterPlaceholderCard();
                },
              ),
            ),
    );
  }
}

class _PosterPlaceholderCard extends StatelessWidget {
  const _PosterPlaceholderCard();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 154,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!constraints.hasBoundedHeight) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 206,
                  decoration: BoxDecoration(
                    color: const Color(0xFF112036).withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  height: 14,
                  width: 118,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 12,
                  width: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ],
            );
          }

          const detailsReservedHeight = 42.0;
          final availablePosterHeight =
              (constraints.maxHeight - detailsReservedHeight)
                  .clamp(0.0, constraints.maxHeight)
                  .toDouble();
          final naturalPosterHeight =
              constraints.hasBoundedWidth ? constraints.maxWidth / 0.7 : 0.0;
          final posterHeight = naturalPosterHeight < availablePosterHeight
              ? naturalPosterHeight
              : availablePosterHeight;

          return ClipRect(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: posterHeight,
                  width: double.infinity,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF112036).withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ClipRect(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            height: 14,
                            width: 118,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            height: 12,
                            width: 44,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HomeSection extends StatelessWidget {
  const _HomeSection({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final titleWidget = Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: titleWidget,
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _HomeSectionViewAllTile extends ConsumerWidget {
  const _HomeSectionViewAllTile({
    required this.onTap,
    this.focusId,
  });

  final VoidCallback onTap;
  final String? focusId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    final content = SizedBox(
      width: 140,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const detailsReservedHeight = 42.0;
          final availablePosterHeight =
              (constraints.maxHeight - detailsReservedHeight)
                  .clamp(0.0, constraints.maxHeight)
                  .toDouble();
          final naturalPosterHeight =
              constraints.hasBoundedWidth ? constraints.maxWidth / 0.7 : 0.0;
          final posterHeight = naturalPosterHeight < availablePosterHeight
              ? naturalPosterHeight
              : availablePosterHeight;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: posterHeight,
                width: double.infinity,
                child: Center(
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 42,
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Expanded(child: SizedBox.shrink()),
            ],
          );
        },
      ),
    );

    if (isTelevision) {
      return TvFocusableAction(
        onPressed: onTap,
        focusId: focusId,
        borderRadius: BorderRadius.circular(18),
        visualStyle: TvFocusVisualStyle.floating,
        child: content,
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: content,
    );
  }
}

class _HomeCarousel extends ConsumerStatefulWidget {
  const _HomeCarousel({
    required this.items,
    required this.focusScopePrefix,
    this.firstItemFocusNode,
  });

  final List<HomeCarouselItemViewModel> items;
  final String focusScopePrefix;
  final FocusNode? firstItemFocusNode;

  @override
  ConsumerState<_HomeCarousel> createState() => _HomeCarouselState();
}

class _HomeCarouselState extends ConsumerState<_HomeCarousel> {
  late final PageController _mobilePageController =
      PageController(viewportFraction: 0.96);

  @override
  void didUpdateWidget(covariant _HomeCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length == widget.items.length) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_mobilePageController.hasClients ||
          widget.items.isEmpty) {
        return;
      }
      final currentPage = _mobilePageController.page ?? 0;
      final maxPage = (widget.items.length - 1).toDouble();
      final boundedPage = currentPage.clamp(0.0, maxPage);
      if ((boundedPage - currentPage).abs() < 0.0001) {
        return;
      }
      _mobilePageController.jumpToPage(boundedPage.round());
    });
  }

  @override
  void dispose() {
    _mobilePageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    final items = widget.items;
    if (items.isEmpty) {
      return const _SectionEmptyState(message: '无');
    }

    if (isTelevision) {
      return SizedBox(
        height: 184 + _kHomeCarouselFocusOverflowPadding,
        child: ListView.separated(
          padding: const EdgeInsets.only(
            top: _kHomeCarouselFocusOverflowPadding,
          ),
          clipBehavior: Clip.none,
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (context, index) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final item = items[index];
            return SizedBox(
              width: 320,
              child: _HomeCarouselTile(
                item: item,
                isTelevision: true,
                focusId:
                    '${widget.focusScopePrefix}:${item.detailTarget.itemId.isNotEmpty ? item.detailTarget.itemId : item.title}',
                focusNode: index == 0 ? widget.firstItemFocusNode : null,
                autofocus: widget.firstItemFocusNode != null && index == 0,
              ),
            );
          },
        ),
      );
    }

    return SizedBox(
      height: 184,
      child: PageView.builder(
        controller: _mobilePageController,
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return Padding(
            padding: EdgeInsets.only(right: index == items.length - 1 ? 0 : 6),
            child: _HomeCarouselTile(
              item: item,
              isTelevision: false,
            ),
          );
        },
      ),
    );
  }
}

class _HomeCarouselTile extends StatelessWidget {
  const _HomeCarouselTile({
    required this.item,
    required this.isTelevision,
    this.focusId,
    this.focusNode,
    this.autofocus = false,
  });

  final HomeCarouselItemViewModel item;
  final bool isTelevision;
  final String? focusId;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    if (isTelevision) {
      return TvFocusableAction(
        focusId: focusId,
        focusNode: focusNode,
        autofocus: autofocus,
        onPressed: () {
          context.pushNamed('detail', extra: item.detailTarget);
        },
        borderRadius: BorderRadius.circular(18),
        visualStyle: TvFocusVisualStyle.none,
        focusScale: 1.06,
        child: _HomeCarouselCard(item: item),
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        context.pushNamed('detail', extra: item.detailTarget);
      },
      child: _HomeCarouselCard(item: item),
    );
  }
}

class _HomeCarouselCard extends StatelessWidget {
  const _HomeCarouselCard({required this.item});

  final HomeCarouselItemViewModel item;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
        final cacheWidth = _resolveCacheDimension(
          constraints.maxWidth,
          devicePixelRatio,
          max: 1400,
        );
        final cacheHeight = _resolveCacheDimension(
          constraints.maxHeight,
          devicePixelRatio,
          max: 900,
        );
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: const Color(0xFF0B1631),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (item.imageUrl.trim().isNotEmpty)
                AppNetworkImage(
                  item.imageUrl,
                  fit: BoxFit.cover,
                  cacheWidth: cacheWidth,
                  cacheHeight: cacheHeight,
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.18),
                      Colors.black.withValues(alpha: 0.72),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Spacer(),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.subtitle.trim().isEmpty ? '点击查看详情' : item.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFE5EDFF),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HomeEditButton extends ConsumerWidget {
  const _HomeEditButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: kBottomReservedSpacing),
      child: Center(
        child: Opacity(
          opacity: 0.46,
          child: isTelevision
              ? TvAdaptiveButton(
                  label: '编辑首页',
                  icon: Icons.tune_rounded,
                  onPressed: () => context.pushNamed('home-editor'),
                  variant: TvButtonVariant.text,
                )
              : TextButton.icon(
                  onPressed: () => context.pushNamed('home-editor'),
                  icon: const Icon(Icons.tune_rounded, size: 14),
                  label: const Text('编辑首页'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF8FA0BD),
                    textStyle:
                        Theme.of(context).textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                    minimumSize: const Size(0, 32),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
        ),
      ),
    );
  }
}

class _EmptyHomeState extends StatelessWidget {
  const _EmptyHomeState();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StarflowLogo(
                    iconSize: 112,
                    showWordmark: true,
                    wordmarkSize: 34,
                  ),
                  SizedBox(height: 18),
                  _HomeEditButton(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

List<AppNetworkImageSource> _buildPosterFallbackSources(
  MediaDetailTarget target,
) {
  final sources = <AppNetworkImageSource>[];
  final seen = <String>{target.posterUrl.trim()};

  void add(String url, Map<String, String> headers) {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty || !seen.add(trimmedUrl)) {
      return;
    }
    sources.add(
      AppNetworkImageSource(
        url: trimmedUrl,
        headers: headers,
      ),
    );
  }

  add(target.bannerUrl, target.bannerHeaders);
  if (!_isHomeDetailOnlyEpisodeBackdrop(target)) {
    add(target.backdropUrl, target.backdropHeaders);
  }
  return sources;
}

bool _isHomeDetailOnlyEpisodeBackdrop(MediaDetailTarget target) {
  final itemType = target.itemType.trim().toLowerCase();
  if (itemType != 'episode') {
    return false;
  }
  final backdropUrl = target.backdropUrl.trim();
  final bannerUrl = target.bannerUrl.trim();
  return backdropUrl.isNotEmpty &&
      bannerUrl.isNotEmpty &&
      backdropUrl != bannerUrl;
}

int? _resolveCacheDimension(
  double logicalSize,
  double devicePixelRatio, {
  double scale = 1,
  int max = 2048,
}) {
  if (!logicalSize.isFinite || logicalSize <= 0) {
    return null;
  }
  final pixelSize = (logicalSize * devicePixelRatio * scale).round();
  if (pixelSize <= 0) {
    return null;
  }
  if (pixelSize > max) {
    return max;
  }
  return pixelSize;
}

class _SectionEmptyState extends StatelessWidget {
  const _SectionEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF90A0BD),
            ),
      ),
    );
  }
}
