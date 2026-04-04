import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/core/widgets/section_panel.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';

class MediaDetailPage extends StatelessWidget {
  const MediaDetailPage({super.key, required this.target});

  final MediaDetailTarget target;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chips = <String>[
      if (target.year > 0) '${target.year}',
      if (target.durationLabel.trim().isNotEmpty) target.durationLabel,
      ...target.genres.where((item) => item.trim().isNotEmpty),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('详情')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          SectionPanel(
            title: target.title,
            subtitle: target.availabilityLabel.trim().isEmpty
                ? '查看条目详情'
                : target.availabilityLabel,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final useColumn = constraints.maxWidth < 520;
                final poster = _PosterCard(posterUrl: target.posterUrl);
                final info = _HeaderInfo(target: target, chips: chips);
                if (useColumn) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(child: poster),
                      const SizedBox(height: 18),
                      info,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    poster,
                    const SizedBox(width: 18),
                    Expanded(child: info),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 18),
          if (target.overview.trim().isNotEmpty)
            SectionPanel(
              title: '剧情简介',
              subtitle: '把影片的核心信息先放在前面',
              child: Text(
                target.overview,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
              ),
            ),
          if (target.overview.trim().isNotEmpty) const SizedBox(height: 18),
          if (target.directors.isNotEmpty)
            SectionPanel(
              title: '导演',
              subtitle: '创作主导信息',
              child: _NameWrap(names: target.directors),
            ),
          if (target.directors.isNotEmpty) const SizedBox(height: 18),
          if (target.actors.isNotEmpty)
            SectionPanel(
              title: '演员',
              subtitle: '主要出演阵容',
              child: _NameWrap(names: target.actors),
            ),
          if (target.actors.isNotEmpty) const SizedBox(height: 18),
          SectionPanel(
            title: '操作',
            subtitle: target.isPlayable ? '资源已就绪，可以直接播放' : '无',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (target.isPlayable)
                  FilledButton.icon(
                    onPressed: () {
                      context.pushNamed('player', extra: target.playbackTarget);
                    },
                    icon: const Icon(Icons.play_circle_fill_rounded),
                    label: const Text('立即播放'),
                  ),
                if (!target.isPlayable && target.searchQuery.trim().isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () {
                      context.goNamed(
                        'search',
                        queryParameters: {'q': target.searchQuery},
                      );
                    },
                    icon: const Icon(Icons.search_rounded),
                    label: const Text('搜索资源'),
                  ),
                if (target.sourceKind != null &&
                    target.sourceName.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    '资源来源：${target.sourceKind!.label} · ${target.sourceName}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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

class _PosterCard extends StatelessWidget {
  const _PosterCard({required this.posterUrl});

  final String posterUrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: 180,
        height: 260,
        color: const Color(0xFFDCE6FF),
        child: Image.network(
          posterUrl,
          fit: BoxFit.cover,
          cacheWidth: 540,
          filterQuality: FilterQuality.low,
          errorBuilder: (context, error, stackTrace) {
            return const Center(
              child: Icon(Icons.movie_creation_outlined, size: 42),
            );
          },
        ),
      ),
    );
  }
}

class _HeaderInfo extends StatelessWidget {
  const _HeaderInfo({
    required this.target,
    required this.chips,
  });

  final MediaDetailTarget target;
  final List<String> chips;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          target.title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        if (chips.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: chips
                .map(
                  (item) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      item,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        if (chips.isNotEmpty) const SizedBox(height: 14),
        if (target.directors.isNotEmpty)
          Text(
            '导演：${target.directors.join(' / ')}',
            style: theme.textTheme.bodyLarge,
          ),
        if (target.directors.isNotEmpty) const SizedBox(height: 8),
        if (target.actors.isNotEmpty)
          Text(
            '演员：${target.actors.take(6).join(' / ')}',
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
      ],
    );
  }
}

class _NameWrap extends StatelessWidget {
  const _NameWrap({required this.names});

  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: names
          .where((item) => item.trim().isNotEmpty)
          .map(
            (item) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFE),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                item,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
