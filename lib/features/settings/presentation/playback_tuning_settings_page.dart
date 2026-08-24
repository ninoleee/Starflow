import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/application/settings_slice_providers.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';

class PlaybackTuningSettingsPage extends ConsumerWidget {
  const PlaybackTuningSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsPerformanceSliceProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final theme = Theme.of(context);

    return SettingsPageScaffold(
      onBack: () => Navigator.of(context).pop(),
      children: [
        Text('MPV 调优', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          '调整内置 MPV 的性能参数。一般设备建议保持标准模式，播放高码率片源不稳定时再开启。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SettingsSectionTitle(label: '性能参数'),
        ...buildSettingsTileGroup([
          SettingsToggleTile(
            title: '激进 MPV 性能调优',
            subtitle: '使用更偏向低延迟与稳定性的 MPV 参数，可能降低部分高画质处理。',
            value: settings.aggressivePlaybackTuningEnabled,
            autofocus: true,
            focusId: 'performance-interaction:mpv-tuning',
            onChanged: controller.setPerformanceAggressivePlaybackTuningEnabled,
          ),
        ]),
      ],
    );
  }
}
