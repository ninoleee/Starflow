import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/utils/network_image_headers.dart';
import 'package:starflow/core/widgets/media_poster_tile.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/home/application/home_controller.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  String _focusedHeroId = '';

  @override
  Widget build(BuildContext context) {
    final enabledModules = ref.watch(homeEnabledModulesProvider);
    final sectionStates = <String, AsyncValue<HomeSectionViewModel?>>{
      for (final module in enabledModules)
        module.id: ref.watch(homeSectionProvider(module.id)),
    };
    final heroStyle = ref.watch(
      appSettingsProvider.select((settings) => settings.homeHeroStyle),
    );
    final resolvedSections = <HomeSectionViewModel>[];
    var hasPendingSections = false;

    for (final module in enabledModules) {
      final state = sectionStates[module.id];
      final section = state?.valueOrNull;
      if (section != null) {
        resolvedSections.add(section);
      }
      if (state?.isLoading ?? false) {
        hasPendingSections = true;
      }
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: enabledModules.isEmpty
          ? const _HomeShell(
              backgroundImageUrl: '',
              child: _EmptyHomeState(),
            )
          : _buildLoadedHome(
              context: context,
              enabledModules: enabledModules,
              sectionStates: sectionStates,
              resolvedSections: resolvedSections,
              hasPendingSections: hasPendingSections,
              heroStyle: heroStyle,
            ),
    );
  }

  Widget _buildLoadedHome({
    required BuildContext context,
    required List<HomeModuleConfig> enabledModules,
    required Map<String, AsyncValue<HomeSectionViewModel?>> sectionStates,
    required List<HomeSectionViewModel> resolvedSections,
    required bool hasPendingSections,
    required HomeHeroStyle heroStyle,
  }) {
    HomeSectionViewModel? featuredSection;
    for (final section in resolvedSections) {
      if (section.layout == HomeSectionLayout.carousel &&
          section.carouselItems.isNotEmpty) {
        featuredSection = section;
        break;
      }
    }

    final featuredItems = featuredSection != null
        ? featuredSection.carouselItems
            .take(5)
            .map(_FeaturedHeroItem.fromCarousel)
            .toList()
        : _fallbackFeaturedItems(resolvedSections);
    final activeHero = _resolveActiveHeroItem(featuredItems);
    final featuredSectionId = featuredSection?.id;

    return _HomeShell(
      backgroundImageUrl: activeHero?.imageUrl ?? '',
      child: RefreshIndicator(
        color: Colors.white,
        backgroundColor: const Color(0xFF102033),
        onRefresh: () => refreshHomeModules(ref),
        child: ListView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: EdgeInsets.zero,
          children: [
            if (featuredItems.isNotEmpty)
              Padding(
                padding: heroStyle.heroPadding(context),
                child: _FeaturedHero(
                  items: featuredItems,
                  style: heroStyle,
                  onFocusedItemChanged: _handleFocusedHeroChanged,
                ),
              )
            else if (hasPendingSections)
              Padding(
                padding: heroStyle.heroPadding(context),
                child: _HomeHeroPlaceholder(style: heroStyle),
              ),
            ...enabledModules.map((module) {
              final state = sectionStates[module.id] ??
                  const AsyncLoading<HomeSectionViewModel?>();
              return Padding(
                padding: const EdgeInsets.only(bottom: 26),
                child: _buildSectionSlot(
                  context: context,
                  module: module,
                  state: state,
                  featuredSectionId: featuredSectionId,
                ),
              );
            }),
            const SizedBox(height: 6),
            const _HomeEditButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionSlot({
    required BuildContext context,
    required HomeModuleConfig module,
    required AsyncValue<HomeSectionViewModel?> state,
    required String? featuredSectionId,
  }) {
    final section = state.valueOrNull;
    if (section != null) {
      if (section.id == featuredSectionId) {
        return const SizedBox.shrink();
      }
      return _buildResolvedSection(context, section);
    }

    if (state.hasError) {
      return _HomeSection(
        title: module.title,
        child: const _SectionEmptyState(message: '加载失败'),
      );
    }

    return _HomeSectionLoading(
      title: module.title,
      layout: module.type == HomeModuleType.doubanCarousel
          ? HomeSectionLayout.carousel
          : HomeSectionLayout.posterRail,
    );
  }

  Widget _buildResolvedSection(
    BuildContext context,
    HomeSectionViewModel section,
  ) {
    return _HomeSection(
      title: section.title,
      onTitleTap: section.viewAllTarget == null
          ? null
          : () {
              context.pushNamed(
                section.viewAllTarget!.routeName,
                extra: section.viewAllTarget!.extra,
              );
            },
      child: section.layout == HomeSectionLayout.carousel
          ? _HomeCarousel(items: section.carouselItems)
          : section.items.isEmpty
              ? _SectionEmptyState(message: section.emptyMessage)
              : SizedBox(
                  height: 246,
                  child: ListView.separated(
                    primary: false,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    scrollDirection: Axis.horizontal,
                    itemCount: section.items.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final item = section.items[index];
                      return MediaPosterTile(
                        title: item.title,
                        subtitle: item.subtitle,
                        posterUrl: item.posterUrl,
                        titleColor: Colors.white,
                        subtitleColor: const Color(0xFF98A7C2),
                        onTap: () {
                          context.pushNamed(
                            'detail',
                            extra: item.detailTarget,
                          );
                        },
                      );
                    },
                  ),
                ),
    );
  }

  _FeaturedHeroItem? _resolveActiveHeroItem(List<_FeaturedHeroItem> items) {
    if (items.isEmpty) {
      return null;
    }
    for (final item in items) {
      if (item.id == _focusedHeroId) {
        return item;
      }
    }
    return items.first;
  }

  void _handleFocusedHeroChanged(_FeaturedHeroItem item) {
    if (_focusedHeroId == item.id) {
      return;
    }
    setState(() {
      _focusedHeroId = item.id;
    });
  }
}

List<_FeaturedHeroItem> _fallbackFeaturedItems(
    List<HomeSectionViewModel> sections) {
  for (final section in sections) {
    if (section.items.isNotEmpty) {
      return section.items.take(5).map(_FeaturedHeroItem.fromPoster).toList();
    }
  }
  return const [];
}

extension _HomeHeroStyleLayoutX on HomeHeroStyle {
  EdgeInsets heroPadding(BuildContext context) {
    return EdgeInsets.fromLTRB(
      this == HomeHeroStyle.normal ? 12 : 0,
      this == HomeHeroStyle.normal ? MediaQuery.paddingOf(context).top + 6 : 0,
      this == HomeHeroStyle.normal ? 12 : 0,
      24,
    );
  }

  double get heroHeight => this == HomeHeroStyle.normal ? 430 : 500;

  double get viewportFraction => this == HomeHeroStyle.normal ? 0.94 : 1;

  double get cardGap => this == HomeHeroStyle.normal ? 10 : 0;

  double get cardBorderRadius => this == HomeHeroStyle.normal ? 30 : 0;

  bool get showShadow => this == HomeHeroStyle.normal;

  double get textWidthFactor => this == HomeHeroStyle.normal ? 0.84 : 0.9;

  EdgeInsets get textPadding => this == HomeHeroStyle.normal
      ? const EdgeInsets.fromLTRB(26, 28, 26, 26)
      : const EdgeInsets.fromLTRB(20, 28, 20, 22);

  double get titleFontSize => this == HomeHeroStyle.normal ? 34 : 38;
}

class _HomeShell extends StatelessWidget {
  const _HomeShell({
    required this.backgroundImageUrl,
    required this.child,
  });

  final String backgroundImageUrl;
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
        _DynamicHeroBackdrop(imageUrl: backgroundImageUrl),
        DecoratedBox(
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
        ),
        Padding(
          padding: verticalInsets,
          child: child,
        ),
      ],
    );
  }
}

class _DynamicHeroBackdrop extends StatelessWidget {
  const _DynamicHeroBackdrop({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 550),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: _DynamicHeroBackdropLayer(
          key: ValueKey(imageUrl.trim().isEmpty ? 'empty' : imageUrl),
          imageUrl: imageUrl,
        ),
      ),
    );
  }
}

class _DynamicHeroBackdropLayer extends StatelessWidget {
  const _DynamicHeroBackdropLayer({
    super.key,
    required this.imageUrl,
  });

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF030914)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl.trim().isNotEmpty)
            Transform.scale(
              scale: 1.16,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Opacity(
                  opacity: 0.72,
                  child: Image.network(
                    imageUrl,
                    headers: networkImageHeadersForUrl(imageUrl),
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    errorBuilder: (context, error, stackTrace) {
                      return const SizedBox.shrink();
                    },
                  ),
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
  const _HomeHeroPlaceholder({required this.style});

  final HomeHeroStyle style;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(style.cardBorderRadius);

    return SizedBox(
      height: style.heroHeight,
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
              height: 246,
              child: ListView.separated(
                primary: false,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 12),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
      ),
    );
  }
}

class _HomeSection extends StatelessWidget {
  const _HomeSection({
    required this.title,
    required this.child,
    this.onTitleTap,
  });

  final String title;
  final Widget child;
  final VoidCallback? onTitleTap;

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
        if (onTitleTap == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: titleWidget,
          )
        else
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTitleTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: titleWidget),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: const Color(0xFF95A4C0),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _FeaturedHeroItem {
  const _FeaturedHeroItem({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.metadata,
    required this.overview,
    required this.detailTarget,
  });

  final String id;
  final String title;
  final String imageUrl;
  final String metadata;
  final String overview;
  final MediaDetailTarget detailTarget;

  factory _FeaturedHeroItem.fromCarousel(HomeCarouselItemViewModel item) {
    return _FeaturedHeroItem(
      id: item.id,
      title: item.title,
      imageUrl: item.imageUrl.trim().isEmpty
          ? item.detailTarget.posterUrl
          : item.imageUrl,
      metadata: _buildHeroMetadata(item.detailTarget, fallback: item.subtitle),
      overview: item.detailTarget.overview.trim().isEmpty
          ? item.subtitle
          : item.detailTarget.overview,
      detailTarget: item.detailTarget,
    );
  }

  factory _FeaturedHeroItem.fromPoster(HomeCardViewModel item) {
    return _FeaturedHeroItem(
      id: item.id,
      title: item.title,
      imageUrl: item.posterUrl,
      metadata: _buildHeroMetadata(
        item.detailTarget,
        fallback: item.subtitle,
      ),
      overview: item.detailTarget.overview,
      detailTarget: item.detailTarget,
    );
  }
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

class _FeaturedHero extends StatefulWidget {
  const _FeaturedHero({
    required this.items,
    required this.style,
    this.onFocusedItemChanged,
  });

  final List<_FeaturedHeroItem> items;
  final HomeHeroStyle style;
  final ValueChanged<_FeaturedHeroItem>? onFocusedItemChanged;

  @override
  State<_FeaturedHero> createState() => _FeaturedHeroState();
}

class _FeaturedHeroState extends State<_FeaturedHero> {
  late PageController _controller;
  double _page = 0;
  int _lastReportedIndex = -1;

  @override
  void initState() {
    super.initState();
    _controller = _buildController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyFocusedItem(0);
    });
  }

  @override
  void didUpdateWidget(covariant _FeaturedHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.style != widget.style) {
      final int nextPage = widget.items.isEmpty
          ? 0
          : _page.round().clamp(0, widget.items.length - 1);
      _controller
        ..removeListener(_handlePageChange)
        ..dispose();
      _controller = _buildController(initialPage: nextPage);
      _page = nextPage.toDouble();
      _lastReportedIndex = -1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _notifyFocusedItem(nextPage);
      });
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handlePageChange)
      ..dispose();
    super.dispose();
  }

  PageController _buildController({int initialPage = 0}) {
    return PageController(
      initialPage: initialPage,
      viewportFraction: widget.style.viewportFraction,
    )..addListener(_handlePageChange);
  }

  void _handlePageChange() {
    if (!mounted) {
      return;
    }
    final double page = _controller.hasClients ? _controller.page ?? 0.0 : 0.0;
    _notifyFocusedItem(page.round());
    setState(() {
      _page = page;
    });
  }

  void _notifyFocusedItem(int index) {
    if (index < 0 || index >= widget.items.length) {
      return;
    }
    if (_lastReportedIndex == index) {
      return;
    }
    _lastReportedIndex = index;
    widget.onFocusedItemChanged?.call(widget.items[index]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: widget.style.heroHeight,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.items.length,
            itemBuilder: (context, index) {
              final item = widget.items[index];
              return Padding(
                padding: EdgeInsets.only(
                  right: index == widget.items.length - 1
                      ? 0
                      : widget.style.cardGap,
                ),
                child: _FeaturedHeroCard(
                  item: item,
                  style: widget.style,
                ),
              );
            },
          ),
        ),
        if (widget.items.length > 1) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.items.length, (index) {
              final isActive = (_page.round() == index);
              return AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: isActive ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isActive
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(999),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}

class _FeaturedHeroCard extends StatelessWidget {
  const _FeaturedHeroCard({
    required this.item,
    required this.style,
  });

  final _FeaturedHeroItem item;
  final HomeHeroStyle style;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(style.cardBorderRadius);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: () => context.pushNamed('detail', extra: item.detailTarget),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            color: const Color(0xFF0B1628),
            boxShadow: style.showShadow
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
                if (item.imageUrl.trim().isNotEmpty)
                  Image.network(
                    item.imageUrl,
                    headers: networkImageHeadersForUrl(item.imageUrl),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.shrink(),
                  ),
                Align(
                  alignment: Alignment.bottomLeft,
                  child: IgnorePointer(
                    child: FractionallySizedBox(
                      widthFactor: style.textWidthFactor,
                      heightFactor: 0.72,
                      alignment: Alignment.bottomLeft,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(-0.92, 0.96),
                            radius: 1.1,
                            colors: [
                              Colors.black.withValues(alpha: 0.82),
                              Colors.black.withValues(alpha: 0.52),
                              Colors.black.withValues(alpha: 0.18),
                              Colors.transparent,
                            ],
                            stops: const [0, 0.36, 0.72, 1],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: style.textPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Spacer(),
                      if (item.metadata.trim().isNotEmpty)
                        Text(
                          item.metadata,
                          style: const TextStyle(
                            color: Color(0xFFDCE7FF),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (item.metadata.trim().isNotEmpty)
                        const SizedBox(height: 10),
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: style.titleFontSize,
                          height: 1.05,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.45),
                              blurRadius: 20,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (item.overview.trim().isNotEmpty)
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 460),
                          child: Text(
                            item.overview,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFE4ECFF),
                              fontSize: 15,
                              height: 1.45,
                              shadows: [
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
        ),
      ),
    );
  }
}

class _HomeCarousel extends StatelessWidget {
  const _HomeCarousel({required this.items});

  final List<HomeCarouselItemViewModel> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _SectionEmptyState(message: '无');
    }

    return SizedBox(
      height: 184,
      child: PageView.builder(
        controller: PageController(viewportFraction: 0.96),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return Padding(
            padding: EdgeInsets.only(right: index == items.length - 1 ? 0 : 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                context.pushNamed('detail', extra: item.detailTarget);
              },
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: const Color(0xFF0B1631),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (item.imageUrl.trim().isNotEmpty)
                      Image.network(
                        item.imageUrl,
                        headers: networkImageHeadersForUrl(item.imageUrl),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox.shrink(),
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
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item.subtitle.trim().isEmpty
                                ? '点击查看详情'
                                : item.subtitle,
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
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HomeEditButton extends StatelessWidget {
  const _HomeEditButton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Center(
        child: Opacity(
          opacity: 0.46,
          child: TextButton.icon(
            onPressed: () => context.pushNamed('home-editor'),
            icon: const Icon(Icons.tune_rounded, size: 14),
            label: const Text('编辑首页'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF8FA0BD),
              textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: const [
        Text(
          '还没有首页模块',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 10),
        _SectionEmptyState(message: '无'),
        SizedBox(height: 12),
        _HomeEditButton(),
      ],
    );
  }
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
