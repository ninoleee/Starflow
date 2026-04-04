import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/core/widgets/media_poster_tile.dart';
import 'package:starflow/core/widgets/section_panel.dart';
import 'package:starflow/features/home/application/home_controller.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sectionsAsync = ref.watch(homeSectionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Starflow')),
      body: RefreshIndicator(
        onRefresh: () async {
          final future = ref.refresh(homeSectionsProvider.future);
          await future;
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            sectionsAsync.when(
              data: (sections) {
                if (sections.isEmpty) {
                  return const _EmptyHomeState();
                }

                return Column(
                  children: [
                    ...sections.map(
                      (section) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: SectionPanel(
                          title: section.title,
                          subtitle: section.subtitle,
                          actionLabel:
                              section.viewAllTarget == null ? null : '查看全部',
                          onActionPressed: section.viewAllTarget == null
                              ? null
                              : () {
                                  context.pushNamed(
                                    'collection',
                                    extra: section.viewAllTarget,
                                  );
                                },
                          child: section.layout == HomeSectionLayout.carousel
                              ? _HomeCarousel(items: section.carouselItems)
                              : section.items.isEmpty
                                  ? _SectionEmptyState(
                                      message: section.emptyMessage)
                                  : SizedBox(
                                      height: 312,
                                      child: ListView.separated(
                                        primary: false,
                                        scrollDirection: Axis.horizontal,
                                        itemCount: section.items.length,
                                        separatorBuilder: (context, index) =>
                                            const SizedBox(width: 8),
                                        itemBuilder: (context, index) {
                                          final item = section.items[index];
                                          return MediaPosterTile(
                                            title: item.title,
                                            subtitle: item.subtitle,
                                            posterUrl: item.posterUrl,
                                            badges: item.badges,
                                            caption: item.caption,
                                            actionLabel: item.actionLabel,
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
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const _HomeEditButton(),
                  ],
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stackTrace) {
                return Column(
                  children: [
                    _SectionEmptyState(message: '加载首页模块失败：$error'),
                    const SizedBox(height: 12),
                    const _HomeEditButton(),
                  ],
                );
              },
            ),
          ],
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
      height: 210,
      child: PageView.builder(
        controller: PageController(viewportFraction: 0.92),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return Padding(
            padding: EdgeInsets.only(right: index == items.length - 1 ? 0 : 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () {
                context.pushNamed('detail', extra: item.detailTarget);
              },
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  color: const Color(0xFF0B1631),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (item.imageUrl.trim().isNotEmpty)
                      Image.network(
                        item.imageUrl,
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
                      padding: const EdgeInsets.all(18),
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
                                .headlineSmall
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
    return Center(
      child: Opacity(
        opacity: 0.46,
        child: TextButton.icon(
          onPressed: () => context.pushNamed('home-editor'),
          icon: const Icon(Icons.tune_rounded, size: 14),
          label: const Text('编辑首页'),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
            textStyle: Theme.of(context).textTheme.labelMedium,
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
    return const Column(
      children: [
        SectionPanel(
          title: '还没有首页模块',
          subtitle: '从底部的小入口开始配置首页',
          child: _SectionEmptyState(message: '无'),
        ),
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
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFE),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Text(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
