import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

class PlaybackSettingsPage extends ConsumerStatefulWidget {
  const PlaybackSettingsPage({
    super.key,
    required this.initialTimeoutSeconds,
    required this.initialDefaultSpeed,
    required this.initialSubtitlePreference,
    required this.initialSubtitleScale,
    required this.initialBackgroundPlaybackEnabled,
    required this.initialPlaybackEngine,
    required this.initialPlaybackDecodeMode,
  });

  final int initialTimeoutSeconds;
  final double initialDefaultSpeed;
  final PlaybackSubtitlePreference initialSubtitlePreference;
  final PlaybackSubtitleScale initialSubtitleScale;
  final bool initialBackgroundPlaybackEnabled;
  final PlaybackEngine initialPlaybackEngine;
  final PlaybackDecodeMode initialPlaybackDecodeMode;

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
  late bool _draftBackgroundPlaybackEnabled;
  late PlaybackEngine _draftPlaybackEngine;
  late PlaybackDecodeMode _draftPlaybackDecodeMode;
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
    _draftBackgroundPlaybackEnabled = widget.initialBackgroundPlaybackEnabled;
    _draftPlaybackEngine = widget.initialPlaybackEngine;
    _draftPlaybackDecodeMode = widget.initialPlaybackDecodeMode;
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
          backgroundPlaybackEnabled: _draftBackgroundPlaybackEnabled,
          playbackEngine: _draftPlaybackEngine,
          playbackDecodeMode: _draftPlaybackDecodeMode,
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
        _draftBackgroundPlaybackEnabled !=
            widget.initialBackgroundPlaybackEnabled ||
        _draftPlaybackEngine != widget.initialPlaybackEngine ||
        _draftPlaybackDecodeMode != widget.initialPlaybackDecodeMode;
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
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('保存修改？'),
        content: const Text('当前页面有未保存的修改，返回前要怎么处理？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('cancel'),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('discard'),
            child: const Text('不保存'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('save'),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (action == 'discard') {
      await _discardAndClose();
    } else if (action == 'save') {
      await _saveDraft();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTelevision = ref.watch(isTelevisionProvider).valueOrNull ?? false;
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _skipAutoSaveOnPop) {
          return;
        }
        _handleCloseRequest();
      },
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            ListView(
              padding: overlayToolbarPagePadding(context),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                Text(
                  '默认偏好会在每次打开播放器时自动生效。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 18),
                if (isTelevision)
                  TvSelectionTile(
                    title: '最大超时时间（秒）',
                    value: '${_draftSeconds()} 秒',
                    onPressed: _openTimeoutPicker,
                  )
                else
                  TextField(
                    controller: _timeoutController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: '最大超时时间（秒）',
                      hintText: '20',
                    ),
                  ),
                const SizedBox(height: 18),
                if (isTelevision)
                  TvSelectionTile(
                    title: '播放器内核',
                    value: _draftPlaybackEngine.label,
                    onPressed: _openPlaybackEnginePicker,
                  )
                else
                  DropdownButtonFormField<PlaybackEngine>(
                    initialValue: _draftPlaybackEngine,
                    decoration: const InputDecoration(
                      labelText: '播放器内核',
                    ),
                    items: [
                      for (final engine in PlaybackEngine.values)
                        DropdownMenuItem<PlaybackEngine>(
                          value: engine,
                          child: Text(engine.label),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _draftPlaybackEngine = value;
                      });
                    },
                  ),
                const SizedBox(height: 8),
                Text(
                  _draftPlaybackEngine.description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 18),
                if (isTelevision)
                  TvSelectionTile(
                    title: '解码模式',
                    value: _draftPlaybackDecodeMode.label,
                    onPressed: _openPlaybackDecodeModePicker,
                  )
                else
                  DropdownButtonFormField<PlaybackDecodeMode>(
                    initialValue: _draftPlaybackDecodeMode,
                    decoration: const InputDecoration(
                      labelText: '解码模式',
                    ),
                    items: [
                      for (final mode in PlaybackDecodeMode.values)
                        DropdownMenuItem<PlaybackDecodeMode>(
                          value: mode,
                          child: Text(mode.label),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _draftPlaybackDecodeMode = value;
                      });
                    },
                  ),
                const SizedBox(height: 8),
                Text(
                  _buildPlaybackDecodeModeDescription(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 18),
                if (isTelevision)
                  TvSelectionTile(
                    title: '后台播放',
                    value: _draftBackgroundPlaybackEnabled ? '已开启' : '已关闭',
                    onPressed: () {
                      setState(() {
                        _draftBackgroundPlaybackEnabled =
                            !_draftBackgroundPlaybackEnabled;
                      });
                    },
                  )
                else
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('后台播放'),
                    subtitle: const Text('Android 切后台会进入小窗继续播放；iOS 会继续后台播放音频。'),
                    value: _draftBackgroundPlaybackEnabled,
                    onChanged: (value) {
                      setState(() {
                        _draftBackgroundPlaybackEnabled = value;
                      });
                    },
                  ),
                const SizedBox(height: 18),
                if (isTelevision)
                  TvSelectionTile(
                    title: '默认倍速',
                    value: _formatSpeedLabel(_draftPlaybackSpeed),
                    onPressed: _openSpeedPicker,
                  )
                else
                  DropdownButtonFormField<double>(
                    initialValue: _draftPlaybackSpeed,
                    decoration: const InputDecoration(
                      labelText: '默认倍速',
                    ),
                    items: [
                      for (final speed in _speedOptions)
                        DropdownMenuItem<double>(
                          value: speed,
                          child: Text(_formatSpeedLabel(speed)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _draftPlaybackSpeed = value;
                      });
                    },
                  ),
                const SizedBox(height: 18),
                if (isTelevision)
                  TvSelectionTile(
                    title: '字幕',
                    value: _subtitleSettingsSummary(),
                    onPressed: _openSubtitleSettingsPage,
                  )
                else
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('字幕'),
                    subtitle: Text(_subtitleSettingsSummary()),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _openSubtitleSettingsPage,
                  ),
                const SizedBox(height: kBottomReservedSpacing),
              ],
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: OverlayToolbar(
                onBack: _handleCloseRequest,
                trailing: isTelevision
                    ? Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: TvAdaptiveButton(
                          label: '保存',
                          icon: Icons.save_rounded,
                          onPressed: _saveDraft,
                          variant: TvButtonVariant.text,
                        ),
                      )
                    : TextButton(
                        onPressed: _saveDraft,
                        child: const Text('保存'),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openTimeoutPicker() async {
    final options = <int>[5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 300, 600];
    final selection = await showDialog<int>(
      context: context,
      builder: (context) {
        final current = _draftSeconds();
        return SimpleDialog(
          title: const Text('选择最大超时时间'),
          children: [
            for (final seconds in options)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(seconds),
                child: Text(
                  seconds == current ? '$seconds 秒  当前' : '$seconds 秒',
                ),
              ),
          ],
        );
      },
    );
    if (selection == null) {
      return;
    }
    setState(() {
      _timeoutController.text = '$selection';
    });
  }

  Future<void> _openSpeedPicker() async {
    final selection = await showDialog<double>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('选择默认倍速'),
          children: [
            for (final speed in _speedOptions)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(speed),
                child: Text(
                  speed == _draftPlaybackSpeed
                      ? '${_formatSpeedLabel(speed)}  当前'
                      : _formatSpeedLabel(speed),
                ),
              ),
          ],
        );
      },
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
      MaterialPageRoute<_PlaybackSubtitleDraft>(
        builder: (context) => PlaybackSubtitleSettingsPage(
          initialSubtitlePreference: _draftSubtitlePreference,
          initialSubtitleScale: _draftSubtitleScale,
        ),
      ),
    );
    if (result == null) {
      return;
    }
    setState(() {
      _draftSubtitlePreference = result.preference;
      _draftSubtitleScale = result.scale;
    });
  }

  Future<void> _openPlaybackEnginePicker() async {
    final selection = await showDialog<PlaybackEngine>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('选择播放器内核'),
          children: [
            for (final engine in PlaybackEngine.values)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(engine),
                child: Text(
                  engine == _draftPlaybackEngine
                      ? '${engine.label}  当前'
                      : engine.label,
                ),
              ),
          ],
        );
      },
    );
    if (selection == null) {
      return;
    }
    setState(() {
      _draftPlaybackEngine = selection;
    });
  }

  Future<void> _openPlaybackDecodeModePicker() async {
    final selection = await showDialog<PlaybackDecodeMode>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('选择解码模式'),
          children: [
            for (final mode in PlaybackDecodeMode.values)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(mode),
                child: Text(
                  mode == _draftPlaybackDecodeMode
                      ? '${mode.label}  当前'
                      : mode.label,
                ),
              ),
          ],
        );
      },
    );
    if (selection == null) {
      return;
    }
    setState(() {
      _draftPlaybackDecodeMode = selection;
    });
  }

  static String _formatSpeedLabel(double speed) {
    if (speed == speed.roundToDouble()) {
      return '${speed.toStringAsFixed(0)}x';
    }
    return '${speed.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')}x';
  }

  String _subtitleSettingsSummary() {
    return '${_draftSubtitlePreference.label} · ${_draftSubtitleScale.label}';
  }

  String _buildPlaybackDecodeModeDescription() {
    final buffer = StringBuffer(_draftPlaybackDecodeMode.description);
    if (_draftPlaybackEngine == PlaybackEngine.systemPlayer) {
      buffer.write(' 当前选择的是系统播放器，此设置不会生效。');
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
}

class PlaybackSubtitleSettingsPage extends ConsumerStatefulWidget {
  const PlaybackSubtitleSettingsPage({
    super.key,
    required this.initialSubtitlePreference,
    required this.initialSubtitleScale,
  });

  final PlaybackSubtitlePreference initialSubtitlePreference;
  final PlaybackSubtitleScale initialSubtitleScale;

  @override
  ConsumerState<PlaybackSubtitleSettingsPage> createState() =>
      _PlaybackSubtitleSettingsPageState();
}

class _PlaybackSubtitleSettingsPageState
    extends ConsumerState<PlaybackSubtitleSettingsPage> {
  late PlaybackSubtitlePreference _draftSubtitlePreference;
  late PlaybackSubtitleScale _draftSubtitleScale;
  bool _closingWithResult = false;

  @override
  void initState() {
    super.initState();
    _draftSubtitlePreference = widget.initialSubtitlePreference;
    _draftSubtitleScale = widget.initialSubtitleScale;
  }

  _PlaybackSubtitleDraft _buildDraft() {
    return _PlaybackSubtitleDraft(
      preference: _draftSubtitlePreference,
      scale: _draftSubtitleScale,
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
    final isTelevision = ref.watch(isTelevisionProvider).valueOrNull ?? false;
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _closingWithResult) {
          return;
        }
        _closeWithResult();
      },
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            ListView(
              padding: overlayToolbarPagePadding(context),
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
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 18),
                if (isTelevision)
                  TvSelectionTile(
                    title: '默认字幕策略',
                    value: _draftSubtitlePreference.label,
                    onPressed: _openSubtitlePreferencePicker,
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SegmentedButton<PlaybackSubtitlePreference>(
                        showSelectedIcon: false,
                        segments: [
                          for (final preference
                              in PlaybackSubtitlePreference.values)
                            ButtonSegment<PlaybackSubtitlePreference>(
                              value: preference,
                              label: Text(preference.label),
                            ),
                        ],
                        selected: {_draftSubtitlePreference},
                        onSelectionChanged: (selection) {
                          if (selection.isEmpty) {
                            return;
                          }
                          setState(() {
                            _draftSubtitlePreference = selection.first;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _draftSubtitlePreference.description,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                const SizedBox(height: 18),
                if (isTelevision)
                  TvSelectionTile(
                    title: '字幕大小',
                    value: _draftSubtitleScale.label,
                    onPressed: _openSubtitleScalePicker,
                  )
                else
                  DropdownButtonFormField<PlaybackSubtitleScale>(
                    initialValue: _draftSubtitleScale,
                    decoration: const InputDecoration(
                      labelText: '字幕大小',
                    ),
                    items: [
                      for (final scale in PlaybackSubtitleScale.values)
                        DropdownMenuItem<PlaybackSubtitleScale>(
                          value: scale,
                          child: Text(scale.label),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _draftSubtitleScale = value;
                      });
                    },
                  ),
                const SizedBox(height: kBottomReservedSpacing),
              ],
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: OverlayToolbar(
                onBack: _closeWithResult,
                trailing: isTelevision
                    ? Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: TvAdaptiveButton(
                          label: '完成',
                          icon: Icons.check_rounded,
                          onPressed: _closeWithResult,
                          variant: TvButtonVariant.text,
                        ),
                      )
                    : TextButton(
                        onPressed: _closeWithResult,
                        child: const Text('完成'),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSubtitlePreferencePicker() async {
    final selection = await showDialog<PlaybackSubtitlePreference>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('选择默认字幕策略'),
          children: [
            for (final preference in PlaybackSubtitlePreference.values)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(preference),
                child: Text(
                  preference == _draftSubtitlePreference
                      ? '${preference.label}  当前'
                      : preference.label,
                ),
              ),
          ],
        );
      },
    );
    if (selection == null) {
      return;
    }
    setState(() {
      _draftSubtitlePreference = selection;
    });
  }

  Future<void> _openSubtitleScalePicker() async {
    final selection = await showDialog<PlaybackSubtitleScale>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('选择字幕大小'),
          children: [
            for (final scale in PlaybackSubtitleScale.values)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(scale),
                child: Text(
                  scale == _draftSubtitleScale
                      ? '${scale.label}  当前'
                      : scale.label,
                ),
              ),
          ],
        );
      },
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
  });

  final PlaybackSubtitlePreference preference;
  final PlaybackSubtitleScale scale;
}
