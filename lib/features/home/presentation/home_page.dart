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
                  children: sections
                      .map(
                        (section) => Padding(
                          padding: const EdgeInsets.only(bottom: 18),
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
                            child: section.items.isEmpty
                                ? _SectionEmptyState(
                                    message: section.emptyMessage)
                                : SizedBox(
                                    height: 352,
                                    child: ListView.separated(
                                      primary: false,
                                      scrollDirection: Axis.horizontal,
                                      itemCount: section.items.length,
                                      separatorBuilder: (context, index) =>
                                          const SizedBox(width: 12),
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
                      )
                      .toList(),
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stackTrace) {
                return _SectionEmptyState(message: '加载首页模块失败：$error');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHomeState extends StatelessWidget {
  const _EmptyHomeState();

  @override
  Widget build(BuildContext context) {
    return const SectionPanel(
      title: '还没有首页模块',
      subtitle: '无',
      child: _SectionEmptyState(message: '无'),
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
