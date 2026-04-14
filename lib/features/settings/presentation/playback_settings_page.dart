import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/no_animation_page_route.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';

class PlaybackSettingsPage extends ConsumerStatefulWidget {
  const PlaybackSettingsPage({
    super.key,
    required this.initialTimeoutSeconds,
    required this.initialDefaultSpeed,
    required this.initialSubtitlePreference,
    required this.initialSubtitleScale,
    required this.initialOnlineSubtitleSources,
    required this.initialBackgroundPlaybackEnabled,
    required this.initialPlaybackEngine,
    required this.initialPlaybackDecodeMode,
    required this.initialPlaybackMpvQualityPreset,
    required this.initialPlaybackMpvDoubleTapToSeekEnabled,
    required this.initialPlaybackMpvSwipeToSeekEnabled,
    required this.initialPlaybackMpvLongPressSpeedBoostEnabled,
    required this.initialPlaybackMpvStallAutoRecoveryEnabled,
  });

  final int initialTimeoutSeconds;
  final double initialDefaultSpeed;
  final PlaybackSubtitlePreference initialSubtitlePreference;
  final PlaybackSubtitleScale initialSubtitleScale;
  final List<OnlineSubtitleSource> initialOnlineSubtitleSources;
  final bool initialBackgroundPlaybackEnabled;
  final PlaybackEngine initialPlaybackEngine;
  final PlaybackDecodeMode initialPlaybackDecodeMode;
  final PlaybackMpvQualityPreset initialPlaybackMpvQualityPreset;
  final bool initialPlaybackMpvDoubleTapToSeekEnabled;
  final bool initialPlaybackMpvSwipeToSeekEnabled;
  final bool initialPlaybackMpvLongPressSpeedBoostEnabled;
  final bool initialPlaybackMpvStallAutoRecoveryEnabled;

  @override
  ConsumerState<PlaybackSettingsPage> createState() =>
      _PlaybackSettingsPageState();
}

class _PlaybackSettingsPageState extends ConsumerState<PlaybackSettingsPage> {
  static const _speedOptions = <double>[0.75, 1.0, 1.25, 1.5, 2.0];

  late final TextEditingController _timeoutController;
  late double _draftPlaybackSpeed;
  late PlaybackSubtitlePreference _draftSubtitlePreference;
  late PlaybackSubtitleScale _draftSubtitleScale;
  late List<OnlineSubtitleSource> _draftOnlineSubtitleSources;
  late bool _draftBackgroundPlaybackEnabled;
  late PlaybackEngine _draftPlaybackEngine;
  late PlaybackDecodeMode _draftPlaybackDecodeMode;
  late PlaybackMpvQualityPreset _draftPlaybackMpvQualityPreset;
  late final bool _initialMpvDoubleTapToSeekEnabled;
  late final bool _initialMpvSwipeToSeekEnabled;
  late final bool _initialMpvLongPressSpeedBoostEnabled;
  late final bool _initialMpvStallAutoRecoveryEnabled;
  late bool _draftMpvDoubleTapToSeekEnabled;
  late bool _draftMpvSwipeToSeekEnabled;
  late bool _draftMpvLongPressSpeedBoostEnabled;
  late bool _draftMpvStallAutoRecoveryEnabled;
  bool _skipAutoSaveOnPop = false;

  @override
  void initState() {
    super.initState();
    _timeoutController = TextEditingController(
      text: '${widget.initialTimeoutSeconds.clamp(1, 600)}',
    );
    _draftPlaybackSpeed = widget.initialDefaultSpeed.clamp(0.75, 2.0);
    _draftSubtitlePreference = widget.initialSubtitlePreference;
    _draftSubtitleScale = widget.initialSubtitleScale;
    _draftOnlineSubtitleSources =
        widget.initialOnlineSubtitleSources.toList(growable: false);
    _draftBackgroundPlaybackEnabled = widget.initialBackgroundPlaybackEnabled;
    _draftPlaybackEngine = widget.initialPlaybackEngine;
    _draftPlaybackDecodeMode = widget.initialPlaybackDecodeMode;
    _draftPlaybackMpvQualityPreset = widget.initialPlaybackMpvQualityPreset;
    _initialMpvDoubleTapToSeekEnabled =
        widget.initialPlaybackMpvDoubleTapToSeekEnabled;
    _initialMpvSwipeToSeekEnabled = widget.initialPlaybackMpvSwipeToSeekEnabled;
    _initialMpvLongPressSpeedBoostEnabled =
        widget.initialPlaybackMpvLongPressSpeedBoostEnabled;
    _initialMpvStallAutoRecoveryEnabled =
        widget.initialPlaybackMpvStallAutoRecoveryEnabled;
    _draftMpvDoubleTapToSeekEnabled = _initialMpvDoubleTapToSeekEnabled;
    _draftMpvSwipeToSeekEnabled = _initialMpvSwipeToSeekEnabled;
    _draftMpvLongPressSpeedBoostEnabled = _initialMpvLongPressSpeedBoostEnabled;
    _draftMpvStallAutoRecoveryEnabled = _initialMpvStallAutoRecoveryEnabled;
  }

  @override
  void dispose() {
    _timeoutController.dispose();
    super.dispose();
  }

  int _draftSeconds() {
    final parsed = int.tryParse(_timeoutController.text.trim()) ?? 20;
    return parsed.clamp(1, 600);
  }

  Future<void> _saveDraft({bool popAfterSave = true}) async {
    await ref.read(settingsControllerProvider.notifier).savePlaybackPreferences(
          openTimeoutSeconds: _draftSeconds(),
          defaultSpeed: _draftPlaybackSpeed,
          subtitlePreference: _draftSubtitlePreference,
          subtitleScale: _draftSubtitleScale,
          onlineSubtitleSources: _draftOnlineSubtitleSources,
          backgroundPlaybackEnabled: _draftBackgroundPlaybackEnabled,
          playbackEngine: _draftPlaybackEngine,
          playbackDecodeMode: _draftPlaybackDecodeMode,
          playbackMpvQualityPreset: _draftPlaybackMpvQualityPreset,
          playbackMpvDoubleTapToSeekEnabled: _draftMpvDoubleTapToSeekEnabled,
          playbackMpvSwipeToSeekEnabled: _draftMpvSwipeToSeekEnabled,
          playbackMpvLongPressSpeedBoostEnabled:
              _draftMpvLongPressSpeedBoostEnabled,
          playbackMpvStallAutoRecoveryEnabled:
              _draftMpvStallAutoRecoveryEnabled,
        );
    if (popAfterSave && mounted) {
      _skipAutoSaveOnPop = true;
      Navigator.of(context).pop();
    }
  }

  bool _hasUnsavedChanges() {
    return _draftSeconds() != widget.initialTimeoutSeconds.clamp(1, 600) ||
        (_draftPlaybackSpeed - widget.initialDefaultSpeed).abs() > 0.0001 ||
        _draftSubtitlePreference != widget.initialSubtitlePreference ||
        _draftSubtitleScale != widget.initialSubtitleScale ||
        !_sameSubtitleSources(
          _draftOnlineSubtitleSources,
          widget.initialOnlineSubtitleSources,
        ) ||
        _draftBackgroundPlaybackEnabled !=
            widget.initialBackgroundPlaybackEnabled ||
        _draftPlaybackEngine != widget.initialPlaybackEngine ||
        _draftPlaybackDecodeMode != widget.initialPlaybackDecodeMode ||
        _draftPlaybackMpvQualityPreset !=
            widget.initialPlaybackMpvQualityPreset ||
        _draftMpvDoubleTapToSeekEnabled != _initialMpvDoubleTapToSeekEnabled ||
        _draftMpvSwipeToSeekEnabled != _initialMpvSwipeToSeekEnabled ||
        _draftMpvLongPressSpeedBoostEnabled !=
            _initialMpvLongPressSpeedBoostEnabled ||
        _draftMpvStallAutoRecoveryEnabled !=
            _initialMpvStallAutoRecoveryEnabled;
  }

  Future<void> _discardAndClose() async {
    _skipAutoSaveOnPop = true;
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleCloseRequest() async {
    if (_skipAutoSaveOnPop) {
      return;
    }
    if (!_hasUnsavedChanges()) {
      await _discardAndClose();
      return;
    }
    final action = await showSettingsCloseConfirmDialog(context);
    if (action == SettingsCloseAction.discard) {
      await _discardAndClose();
    } else if (action == SettingsCloseAction.save) {
      await _saveDraft();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _skipAutoSaveOnPop) {
          return;
        }
        _handleCloseRequest();
      },
      child: SettingsPageScaffold(
        onBack: _handleCloseRequest,
        trailing: SettingsToolbarButton(
          label: '保存',
          icon: Icons.save_rounded,
          onPressed: _saveDraft,
        ),
        children: [
          Text(
            '默认偏好会在每次打开播放器时自动生效。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 18),
          SettingsSelectionTile(
            title: '最大超时时间（秒）',
            value: '${_draftSeconds()} 秒',
            onPressed: _openTimeoutPicker,
          ),
          const SizedBox(height: 18),
          SettingsSelectionTile(
            title: '播放器内核',
            value: _draftPlaybackEngine.label,
            onPressed: _openPlaybackEnginePicker,
          ),
          const SizedBox(height: 8),
          Text(
            _draftPlaybackEngine.description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 18),
          SettingsSelectionTile(
            title: '解码模式',
            value: _draftPlaybackDecodeMode.label,
            onPressed: _openPlaybackDecodeModePicker,
          ),
          const SizedBox(height: 8),
          Text(
            _buildPlaybackDecodeModeDescription(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 18),
          SettingsSelectionTile(
            title: 'MPV 画质策略',
            value: _draftPlaybackMpvQualityPreset.label,
            onPressed: _openPlaybackMpvQualityPresetPicker,
          ),
          const SizedBox(height: 8),
          Text(
            _buildPlaybackMpvQualityPresetDescription(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 18),
          Text(
            'MPV 触屏交互',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          ...buildSettingsTileGroup(
            [
              SettingsToggleTile(
                title: '双击快进/快退',
                subtitle: '双击屏幕左右两侧按步进快进或快退。',
                value: _draftMpvDoubleTapToSeekEnabled,
                onChanged: (value) {
                  setState(() {
                    _draftMpvDoubleTapToSeekEnabled = value;
                  });
                },
              ),
              SettingsToggleTile(
                title: '左右滑动调进度',
                subtitle: '横向滑动直接调整播放进度，适合触屏拖拽。',
                value: _draftMpvSwipeToSeekEnabled,
                onChanged: (value) {
                  setState(() {
                    _draftMpvSwipeToSeekEnabled = value;
                  });
                },
              ),
              SettingsToggleTile(
                title: '长按临时 2 倍速',
                subtitle: '长按时临时加速，松手恢复正常速度。',
                value: _draftMpvLongPressSpeedBoostEnabled,
                onChanged: (value) {
                  setState(() {
                    _draftMpvLongPressSpeedBoostEnabled = value;
                  });
                },
              ),
            ],
            spacing: 12,
          ),
          const SizedBox(height: 8),
          Text(
            _draftPlaybackEngine == PlaybackEngine.embeddedMpv
                ? '以上交互仅作用于内置 MPV。'
                : '当前不是内置 MPV，以上交互项暂不生效。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 18),
          SettingsToggleTile(
            title: 'MPV 卡顿自动恢复',
            subtitle: '缓冲卡住时自动尝试恢复播放，降低“卡住不动”的概率。',
            value: _draftMpvStallAutoRecoveryEnabled,
            onChanged: (value) {
              setState(() {
                _draftMpvStallAutoRecoveryEnabled = value;
              });
            },
          ),
          const SizedBox(height: 8),
          Text(
            _draftPlaybackEngine == PlaybackEngine.embeddedMpv
                ? '建议保持开启，除非你在排查特殊兼容问题。'
                : '当前不是内置 MPV，此项暂不生效。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 18),
          if (isTelevision)
            _PlaybackSettingsInfoBox(
              title: '后台播放',
              description: 'TV 端已固定禁用后台播放，不提供小窗或后台音频继续播放。',
            )
          else
            SettingsToggleTile(
              title: '后台播放',
              subtitle: 'Android 切后台会进入小窗继续播放；iOS 会继续后台播放音频。',
              value: _draftBackgroundPlaybackEnabled,
              onChanged: (value) {
                setState(() {
                  _draftBackgroundPlaybackEnabled = value;
                });
              },
            ),
          const SizedBox(height: 18),
          SettingsSelectionTile(
            title: '默认倍速',
            value: _formatSpeedLabel(_draftPlaybackSpeed),
            onPressed: _openSpeedPicker,
          ),
          const SizedBox(height: 18),
          SettingsSelectionTile(
            title: '字幕',
            subtitle: _subtitleSettingsSummary(),
            value: '编辑',
            onPressed: _openSubtitleSettingsPage,
          ),
        ],
      ),
    );
  }

  Future<void> _openTimeoutPicker() async {
    final options = <int>[5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 300, 600];
    final selection = await showSettingsOptionDialog<int>(
      context: context,
      title: '选择最大超时时间',
      options: options,
      currentValue: _draftSeconds(),
      labelBuilder: (seconds) => '$seconds 秒',
    );
    if (selection == null) {
      return;
    }
    setState(() {
      _timeoutController.text = '$selection';
    });
  }

  Future<void> _openSpeedPicker() async {
    final selection = await showSettingsOptionDialog<double>(
      context: context,
      title: '选择默认倍速',
      options: _speedOptions,
      currentValue: _draftPlaybackSpeed,
      labelBuilder: _formatSpeedLabel,
    );
    if (selection == null) {
      return;
    }
    setState(() {
      _draftPlaybackSpeed = selection;
    });
  }

  Future<void> _openSubtitleSettingsPage() async {
    final result = await Navigator.of(context).push<_PlaybackSubtitleDraft>(
      NoAnimationMaterialPageRoute<_PlaybackSubtitleDraft>(
        builder: (context) => PlaybackSubtitleSettingsPage(
          initialSubtitlePreference: _draftSubtitlePreference,
          initialSubtitleScale: _draftSubtitleScale,
          initialOnlineSubtitleSources: _draftOnlineSubtitleSources,
        ),
      ),
    );
    if (result == null) {
      return;
    }
    setState(() {
      _draftSubtitlePreference = result.preference;
      _draftSubtitleScale = result.scale;
      _draftOnlineSubtitleSources =
          result.onlineSubtitleSources.toList(growable: false);
    });
  }

  Future<void> _openPlaybackEnginePicker() async {
    final selection = await showSettingsOptionDialog<PlaybackEngine>(
      context: context,
      title: '选择播放器内核',
      options: PlaybackEngine.values,
      currentValue: _draftPlaybackEngine,
      labelBuilder: (engine) => engine.label,
    );
    if (selection == null) {
      return;
    }
    setState(() {
      _draftPlaybackEngine = selection;
    });
  }

  Future<void> _openPlaybackDecodeModePicker() async {
    final selection = await showSettingsOptionDialog<PlaybackDecodeMode>(
      context: context,
      title: '选择解码模式',
      options: PlaybackDecodeMode.values,
      currentValue: _draftPlaybackDecodeMode,
      labelBuilder: (mode) => mode.label,
    );
    if (selection == null) {
      return;
    }
    setState(() {
      _draftPlaybackDecodeMode = selection;
    });
  }

  Future<void> _openPlaybackMpvQualityPresetPicker() async {
    final selection = await showSettingsOptionDialog<PlaybackMpvQualityPreset>(
      context: context,
      title: '选择 MPV 画质策略',
      options: PlaybackMpvQualityPreset.values,
      currentValue: _draftPlaybackMpvQualityPreset,
      labelBuilder: (preset) => preset.label,
    );
    if (selection == null) {
      return;
    }
    setState(() {
      _draftPlaybackMpvQualityPreset = selection;
    });
  }

  static String _formatSpeedLabel(double speed) {
    if (speed == speed.roundToDouble()) {
      return '${speed.toStringAsFixed(0)}x';
    }
    return '${speed.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')}x';
  }

  String _subtitleSettingsSummary() {
    final sourceLabel = _draftOnlineSubtitleSources.isEmpty
        ? '未启用在线字幕源'
        : _draftOnlineSubtitleSources.map((item) => item.label).join(' / ');
    return '${_draftSubtitlePreference.label} · ${_draftSubtitleScale.label} · $sourceLabel';
  }

  String _buildPlaybackDecodeModeDescription() {
    final buffer = StringBuffer(_draftPlaybackDecodeMode.description);
    if (_draftPlaybackEngine == PlaybackEngine.systemPlayer) {
      buffer.write(' 当前选择的是外部系统播放器，此设置不会生效。');
    } else if (_draftPlaybackEngine == PlaybackEngine.nativeContainer) {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        buffer.write(' iOS 原生容器页走系统 AVPlayer 解码链路，此设置当前不会生效。');
      } else {
        buffer.write(' 作用于 App 内原生播放器容器页。');
      }
    } else {
      buffer.write(' 作用于内置 MPV。');
    }
    return buffer.toString();
  }

  String _buildPlaybackMpvQualityPresetDescription() {
    final buffer = StringBuffer(_draftPlaybackMpvQualityPreset.description);
    if (_draftPlaybackEngine != PlaybackEngine.embeddedMpv) {
      buffer.write(' 当前只作用于内置 MPV，切到原生或外部系统播放器时不会生效。');
    } else {
      buffer.write(' 也可以在播放器内的“播放设置”里临时切换。');
    }
    return buffer.toString();
  }
}

class _PlaybackSettingsInfoBox extends StatelessWidget {
  const _PlaybackSettingsInfoBox({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PlaybackSubtitleSettingsPage extends ConsumerStatefulWidget {
  const PlaybackSubtitleSettingsPage({
    super.key,
    required this.initialSubtitlePreference,
    required this.initialSubtitleScale,
    required this.initialOnlineSubtitleSources,
  });

  final PlaybackSubtitlePreference initialSubtitlePreference;
  final PlaybackSubtitleScale initialSubtitleScale;
  final List<OnlineSubtitleSource> initialOnlineSubtitleSources;

  @override
  ConsumerState<PlaybackSubtitleSettingsPage> createState() =>
      _PlaybackSubtitleSettingsPageState();
}

class _PlaybackSubtitleSettingsPageState
    extends ConsumerState<PlaybackSubtitleSettingsPage> {
  late PlaybackSubtitlePreference _draftSubtitlePreference;
  late PlaybackSubtitleScale _draftSubtitleScale;
  late List<OnlineSubtitleSource> _draftOnlineSubtitleSources;
  bool _closingWithResult = false;

  @override
  void initState() {
    super.initState();
    _draftSubtitlePreference = widget.initialSubtitlePreference;
    _draftSubtitleScale = widget.initialSubtitleScale;
    _draftOnlineSubtitleSources =
        widget.initialOnlineSubtitleSources.toList(growable: false);
  }

  _PlaybackSubtitleDraft _buildDraft() {
    return _PlaybackSubtitleDraft(
      preference: _draftSubtitlePreference,
      scale: _draftSubtitleScale,
      onlineSubtitleSources: _draftOnlineSubtitleSources,
    );
  }

  void _closeWithResult() {
    if (_closingWithResult || !mounted) {
      return;
    }
    _closingWithResult = true;
    Navigator.of(context).pop(_buildDraft());
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _closingWithResult) {
          return;
        }
        _closeWithResult();
      },
      child: SettingsPageScaffold(
        onBack: _closeWithResult,
        trailing: SettingsToolbarButton(
          label: '完成',
          icon: Icons.check_rounded,
          onPressed: _closeWithResult,
        ),
        children: [
          Text(
            '字幕',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            '把默认字幕策略和默认字幕大小统一放在这里，播放器打开时会按这里的偏好先应用。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 18),
          SettingsSelectionTile(
            title: '默认字幕策略',
            value: _draftSubtitlePreference.label,
            onPressed: _openSubtitlePreferencePicker,
          ),
          const SizedBox(height: 8),
          Text(
            _draftSubtitlePreference.description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 18),
          SettingsSelectionTile(
            title: '字幕大小',
            value: _draftSubtitleScale.label,
            onPressed: _openSubtitleScalePicker,
          ),
          const SizedBox(height: 18),
          Text(
            '在线字幕来源',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          ...buildSettingsTileGroup(
            [
              for (final source in OnlineSubtitleSource.values)
                SettingsToggleTile(
                  title: source.label,
                  subtitle: source.description,
                  value: _draftOnlineSubtitleSources.contains(source),
                  onChanged: (value) {
                    setState(() {
                      final next = _draftOnlineSubtitleSources.toSet();
                      if (value) {
                        next.add(source);
                      } else {
                        next.remove(source);
                      }
                      _draftOnlineSubtitleSources =
                          next.toList(growable: false);
                    });
                  },
                ),
            ],
            spacing: 12,
          ),
        ],
      ),
    );
  }

  Future<void> _openSubtitlePreferencePicker() async {
    final selection =
        await showSettingsOptionDialog<PlaybackSubtitlePreference>(
      context: context,
      title: '选择默认字幕策略',
      options: PlaybackSubtitlePreference.values,
      currentValue: _draftSubtitlePreference,
      labelBuilder: (preference) => preference.label,
    );
    if (selection == null) {
      return;
    }
    setState(() {
      _draftSubtitlePreference = selection;
    });
  }

  Future<void> _openSubtitleScalePicker() async {
    final selection = await showSettingsOptionDialog<PlaybackSubtitleScale>(
      context: context,
      title: '选择字幕大小',
      options: PlaybackSubtitleScale.values,
      currentValue: _draftSubtitleScale,
      labelBuilder: (scale) => scale.label,
    );
    if (selection == null) {
      return;
    }
    setState(() {
      _draftSubtitleScale = selection;
    });
  }
}

class _PlaybackSubtitleDraft {
  const _PlaybackSubtitleDraft({
    required this.preference,
    required this.scale,
    required this.onlineSubtitleSources,
  });

  final PlaybackSubtitlePreference preference;
  final PlaybackSubtitleScale scale;
  final List<OnlineSubtitleSource> onlineSubtitleSources;
}

bool _sameSubtitleSources(
  List<OnlineSubtitleSource> left,
  List<OnlineSubtitleSource> right,
) {
  if (left.length != right.length) {
    return false;
  }
  final leftSet = left.toSet();
  final rightSet = right.toSet();
  if (leftSet.length != rightSet.length) {
    return false;
  }
  return leftSet.containsAll(rightSet);
}
