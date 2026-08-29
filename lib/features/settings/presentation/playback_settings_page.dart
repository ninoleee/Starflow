import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/features/playback/application/playback_engine_support.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';

class PlaybackSettingsPage extends ConsumerStatefulWidget {
  const PlaybackSettingsPage({
    super.key,
    required this.initialTimeoutSeconds,
    required this.initialDefaultSpeed,
    required this.initialBackgroundPlaybackEnabled,
    required this.initialPlaybackEngine,
    required this.initialPlaybackDecodeMode,
    required this.initialNativeAudioOutputMode,
  });

  final int initialTimeoutSeconds;
  final double initialDefaultSpeed;
  final bool initialBackgroundPlaybackEnabled;
  final PlaybackEngine initialPlaybackEngine;
  final PlaybackDecodeMode initialPlaybackDecodeMode;
  final NativeAudioOutputMode initialNativeAudioOutputMode;

  @override
  ConsumerState<PlaybackSettingsPage> createState() =>
      _PlaybackSettingsPageState();
}

class _PlaybackSettingsPageState extends ConsumerState<PlaybackSettingsPage> {
  static const _speedOptions = <double>[0.75, 1.0, 1.25, 1.5, 2.0];

  late final TextEditingController _timeoutController;
  late double _draftPlaybackSpeed;
  late bool _draftBackgroundPlaybackEnabled;
  late PlaybackEngine _draftPlaybackEngine;
  late PlaybackDecodeMode _draftPlaybackDecodeMode;
  late NativeAudioOutputMode _draftNativeAudioOutputMode;
  Timer? _autoSaveTimer;
  Future<void> _saveQueue = Future<void>.value();
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _timeoutController = TextEditingController(
      text: '${widget.initialTimeoutSeconds.clamp(1, 600)}',
    );
    _draftPlaybackSpeed = widget.initialDefaultSpeed.clamp(0.75, 2.0);
    _draftBackgroundPlaybackEnabled = widget.initialBackgroundPlaybackEnabled;
    _draftPlaybackEngine = effectivePlaybackEngine(
      selected: widget.initialPlaybackEngine,
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    );
    _draftPlaybackDecodeMode = widget.initialPlaybackDecodeMode;
    _draftNativeAudioOutputMode = widget.initialNativeAudioOutputMode;
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _timeoutController.dispose();
    super.dispose();
  }

  int _draftSeconds() {
    final parsed = int.tryParse(_timeoutController.text.trim()) ?? 20;
    return parsed.clamp(1, 600);
  }

  Future<void> _persistDraft() async {
    await ref.read(settingsControllerProvider.notifier).savePlaybackPreferences(
          openTimeoutSeconds: _draftSeconds(),
          defaultSpeed: _draftPlaybackSpeed,
          backgroundPlaybackEnabled: _draftBackgroundPlaybackEnabled,
          playbackEngine: _draftPlaybackEngine,
          playbackDecodeMode: _draftPlaybackDecodeMode,
          nativeAudioOutputMode: _draftNativeAudioOutputMode,
        );
  }

  void _scheduleAutoSave() {
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
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
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
            '播放设置',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 18),
          SettingsSelectionTile(
            title: '最大超时时间（秒）',
            value: '${_draftSeconds()} 秒',
            autofocus: true,
            focusId: 'playback-settings:timeout',
            onPressed: _openTimeoutPicker,
          ),
          const SizedBox(height: 18),
          SettingsSelectionTile(
            title: '播放器内核',
            value: playbackEnginePlatformLabel(
              _draftPlaybackEngine,
              platform: defaultTargetPlatform,
            ),
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
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ...[
            const SizedBox(height: 18),
            SettingsSelectionTile(
              title: 'ExoPlayer 音频输出',
              value: _draftNativeAudioOutputMode.label,
              onPressed: _openNativeAudioOutputModePicker,
            ),
            const SizedBox(height: 8),
            Text(
              _buildNativeAudioOutputModeDescription(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
          const SizedBox(height: 18),
          if (isTelevision)
            _PlaybackSettingsInfoBox(
              title: '后台播放',
              description: 'TV 端已固定禁用后台播放，不提供小窗或后台音频继续播放。',
            )
          else
            SettingsToggleTile(
              title: '后台播放',
              subtitle: 'Android 切后台进入小窗；iOS 继续后台音频，并在锁屏 / 控制中心显示封面。',
              value: _draftBackgroundPlaybackEnabled,
              onChanged: (value) {
                setState(() {
                  _draftBackgroundPlaybackEnabled = value;
                });
                _scheduleAutoSave();
              },
            ),
          const SizedBox(height: 18),
          SettingsSelectionTile(
            title: '默认倍速',
            value: _formatSpeedLabel(_draftPlaybackSpeed),
            onPressed: _openSpeedPicker,
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
    _scheduleAutoSave();
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
    _scheduleAutoSave();
  }

  Future<void> _openPlaybackEnginePicker() async {
    final selection = await showSettingsOptionDialog<PlaybackEngine>(
      context: context,
      title: '选择播放器内核',
      options: supportedPlaybackEngines(
        isWeb: kIsWeb,
        platform: defaultTargetPlatform,
      ),
      currentValue: _draftPlaybackEngine,
      labelBuilder: (engine) => playbackEnginePlatformLabel(
        engine,
        platform: defaultTargetPlatform,
      ),
    );
    if (selection == null) {
      return;
    }
    setState(() {
      _draftPlaybackEngine = selection;
    });
    _scheduleAutoSave();
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
    _scheduleAutoSave();
  }

  Future<void> _openNativeAudioOutputModePicker() async {
    final selection = await showSettingsOptionDialog<NativeAudioOutputMode>(
      context: context,
      title: '选择 ExoPlayer 音频输出',
      options: NativeAudioOutputMode.values,
      currentValue: _draftNativeAudioOutputMode,
      labelBuilder: (mode) => mode.label,
    );
    if (selection == null) {
      return;
    }
    setState(() {
      _draftNativeAudioOutputMode = selection;
    });
    _scheduleAutoSave();
  }

  static String _formatSpeedLabel(double speed) {
    if (speed == speed.roundToDouble()) {
      return '${speed.toStringAsFixed(0)}x';
    }
    return '${speed.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')}x';
  }

  String _buildPlaybackDecodeModeDescription() {
    final buffer = StringBuffer(_draftPlaybackDecodeMode.description);
    if (_draftPlaybackEngine == PlaybackEngine.systemPlayer) {
      buffer.write(' 当前选择的是外部系统播放器，此设置不会生效。');
    } else if (_draftPlaybackEngine == PlaybackEngine.nativeContainer) {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        buffer.write(' iOS 原生播放器走系统 AVPlayer 解码链路，此设置当前不会生效。');
      } else {
        buffer.write(' 作用于 Android 原生播放器。');
      }
    } else {
      buffer.write(' 作用于内置 MPV。');
    }
    return buffer.toString();
  }

  String _buildNativeAudioOutputModeDescription() {
    final buffer = StringBuffer(_draftNativeAudioOutputMode.description);
    if (_draftPlaybackEngine != PlaybackEngine.nativeContainer) {
      buffer.write(' 只作用于 ExoPlayer（原生），当前播放器不会受影响。');
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
