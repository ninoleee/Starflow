import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/application/settings_slice_providers.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';

/// MPV 设置一级页。
///
/// 内置 MPV 的触屏交互、卡顿恢复与性能调优集中在这里，
/// 只通过 [savePlaybackMpvPreferences] 更新，不会覆盖播放页的其它偏好。
class MpvSettingsPage extends ConsumerStatefulWidget {
  const MpvSettingsPage({super.key});

  @override
  ConsumerState<MpvSettingsPage> createState() => _MpvSettingsPageState();
}

class _MpvSettingsPageState extends ConsumerState<MpvSettingsPage> {
  late bool _draftDoubleTapToSeekEnabled;
  late bool _draftSwipeToSeekEnabled;
  late bool _draftLongPressSpeedBoostEnabled;
  late bool _draftStallAutoRecoveryEnabled;
  late bool _draftAggressiveTuningEnabled;
  Timer? _autoSaveTimer;
  Future<void> _saveQueue = Future<void>.value();
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    final playbackSlice = ref.read(settingsPlaybackSliceProvider);
    final performanceSlice = ref.read(settingsPerformanceSliceProvider);
    _draftDoubleTapToSeekEnabled =
        playbackSlice.playbackMpvDoubleTapToSeekEnabled;
    _draftSwipeToSeekEnabled = playbackSlice.playbackMpvSwipeToSeekEnabled;
    _draftLongPressSpeedBoostEnabled =
        playbackSlice.playbackMpvLongPressSpeedBoostEnabled;
    _draftStallAutoRecoveryEnabled =
        playbackSlice.playbackMpvStallAutoRecoveryEnabled;
    _draftAggressiveTuningEnabled =
        performanceSlice.aggressivePlaybackTuningEnabled;
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    super.dispose();
  }

  Future<void> _persistDraft() async {
    await ref
        .read(settingsControllerProvider.notifier)
        .savePlaybackMpvPreferences(
          doubleTapToSeekEnabled: _draftDoubleTapToSeekEnabled,
          swipeToSeekEnabled: _draftSwipeToSeekEnabled,
          longPressSpeedBoostEnabled: _draftLongPressSpeedBoostEnabled,
          stallAutoRecoveryEnabled: _draftStallAutoRecoveryEnabled,
          aggressiveTuningEnabled: _draftAggressiveTuningEnabled,
        );
  }

  void _scheduleAutoSave() {
    if (!mounted || _closing) {
      return;
    }
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 250), _enqueueSave);
  }

  void _enqueueSave() {
    _autoSaveTimer = null;
    _saveQueue = _saveQueue.then((_) => _persistDraft());
  }

  Future<void> _handleCloseRequest() async {
    if (_closing) {
      return;
    }
    _closing = true;
    _autoSaveTimer?.cancel();
    _enqueueSave();
    try {
      await _saveQueue;
    } finally {
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _closing) {
          return;
        }
        unawaited(_handleCloseRequest());
      },
      child: SettingsPageScaffold(
        onBack: () => unawaited(_handleCloseRequest()),
        children: [
          Text(
            'MPV',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          const SettingsSectionTitle(label: '触屏交互'),
          ...buildSettingsTileGroup(
            [
              SettingsToggleTile(
                title: '双击快进/快退',
                subtitle: '双击屏幕左右两侧按步进快进或快退。',
                value: _draftDoubleTapToSeekEnabled,
                autofocus: true,
                focusId: 'mpv-settings:double-tap-seek',
                onChanged: (value) {
                  setState(() {
                    _draftDoubleTapToSeekEnabled = value;
                  });
                  _scheduleAutoSave();
                },
              ),
              SettingsToggleTile(
                title: '左右滑动调进度',
                subtitle: '横向滑动直接调整播放进度，适合触屏拖拽。',
                value: _draftSwipeToSeekEnabled,
                onChanged: (value) {
                  setState(() {
                    _draftSwipeToSeekEnabled = value;
                  });
                  _scheduleAutoSave();
                },
              ),
              SettingsToggleTile(
                title: '长按临时 2 倍速',
                subtitle: '长按时临时加速，松手恢复正常速度。',
                value: _draftLongPressSpeedBoostEnabled,
                onChanged: (value) {
                  setState(() {
                    _draftLongPressSpeedBoostEnabled = value;
                  });
                  _scheduleAutoSave();
                },
              ),
            ],
            spacing: 12,
          ),
          const SettingsSectionTitle(label: '播放稳定性'),
          SettingsToggleTile(
            title: '卡顿自动恢复',
            subtitle: '缓冲卡住时自动尝试恢复播放，降低“卡住不动”的概率。建议保持开启，除非你在排查特殊兼容问题。',
            value: _draftStallAutoRecoveryEnabled,
            onChanged: (value) {
              setState(() {
                _draftStallAutoRecoveryEnabled = value;
              });
              _scheduleAutoSave();
            },
          ),
          const SettingsSectionTitle(label: '性能参数'),
          SettingsToggleTile(
            title: '激进性能调优',
            subtitle: '使用更偏向低延迟与稳定性的 MPV 参数，可能降低部分高画质处理。',
            value: _draftAggressiveTuningEnabled,
            onChanged: (value) {
              setState(() {
                _draftAggressiveTuningEnabled = value;
              });
              _scheduleAutoSave();
            },
          ),
          const SizedBox(height: 12),
          Text(
            '以上设置只作用于内置 MPV；当前播放器内核不是内置 MPV 时不会生效。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
