import 'package:flutter/material.dart';
import 'package:starflow/core/widgets/section_panel.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key, required this.target});

  final PlaybackTarget target;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(target.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Container(
            height: 240,
            decoration: BoxDecoration(
              color: const Color(0xFF081120),
              borderRadius: BorderRadius.circular(32),
              gradient: const LinearGradient(
                colors: [Color(0xFF020617), Color(0xFF1E3A8A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.play_circle_fill_rounded,
                    color: Colors.white,
                    size: 72,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '播放器适配层预留位',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '后续接真实播放器时，只需要替换这个页面的实现',
                    style: TextStyle(color: Color(0xFFDCE6FF)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          SectionPanel(
            title: '播放目标',
            subtitle: '这一层已经把 Emby/NAS 的条目统一成了可播放模型',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(label: '来源', value: '${target.sourceKind.label} · ${target.sourceName}'),
                const SizedBox(height: 12),
                _InfoRow(label: '流地址', value: target.streamUrl),
                if (target.subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _InfoRow(label: '简介', value: target.subtitle),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        SelectableText(
          value,
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
        ),
      ],
    );
  }
}
