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
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF0F172A),
                    Color(0xFF1D4ED8),
                    Color(0xFF93C5FD)
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '把想看的、能播的、还缺资源的，放在同一个首页。',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    '豆瓣推荐会自动尝试关联你的 Emby 或 NAS 资源；没有资源时，直接跳去在线搜索。',
                    style: TextStyle(color: Color(0xFFE0ECFF), height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
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
      subtitle: '去设置里启用你想展示的模块',
      child: _SectionEmptyState(message: '启用豆瓣、媒体源或首页模块后，这里会自动组装。'),
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
