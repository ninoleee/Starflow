import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/no_animation_page_route.dart';
import 'package:starflow/features/playback/application/playback_engine_support.dart';
import 'package:starflow/features/playback/application/subtitle_language_preferences.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_text_input_field.dart';

part 'playback_subtitle_settings_page.part.dart';

class PlaybackSettingsPage extends ConsumerStatefulWidget {
  const PlaybackSettingsPage({
    super.key,
    required this.initialTimeoutSeconds,
    required this.initialDefaultSpeed,
    required this.initialSubtitlePreference,
    required this.initialSubtitleScale,
    required this.initialOnlineSubtitleSources,
    required this.initialAssrtToken,
    required this.initialOpensubtitlesEnabled,
    required this.initialOpensubtitlesUsername,
    required this.initialOpensubtitlesPassword,
    required this.initialSubdlEnabled,
    required this.initialSubdlApiKey,
    required this.initialSubtitlePreferredLanguages,
    required this.initialSubtitleSearchMaxValidatedCandidates,
    required this.initialBackgroundPlaybackEnabled,
    required this.initialPlaybackEngine,
    required this.initialPlaybackDecodeMode,
    required this.initialPlaybackMpvDoubleTapToSeekEnabled,
    required this.initialPlaybackMpvSwipeToSeekEnabled,
    required this.initialPlaybackMpvLongPressSpeedBoostEnabled,
    required this.initialPlaybackMpvStallAutoRecoveryEnabled,
  });

  final int initialTimeoutSeconds;
  final double initialDefaultSpeed;
  final PlaybackSubtitlePreference initialSubtitlePreference;
  final double initialSubtitleScale;
  final List<OnlineSubtitleSource> initialOnlineSubtitleSources;
  final String initialAssrtToken;
  final bool initialOpensubtitlesEnabled;
  final String initialOpensubtitlesUsername;
  final String initialOpensubtitlesPassword;
  final bool initialSubdlEnabled;
  final String initialSubdlApiKey;
  final List<String> initialSubtitlePreferredLanguages;
  final int initialSubtitleSearchMaxValidatedCandidates;
  final bool initialBackgroundPlaybackEnabled;
  final PlaybackEngine initialPlaybackEngine;
  final PlaybackDecodeMode initialPlaybackDecodeMode;
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
  late double _draftSubtitleScale;
  late List<OnlineSubtitleSource> _draftOnlineSubtitleSources;
  late final TextEditingController _assrtTokenController;
  late final TextEditingController _opensubtitlesUsernameController;
  late final TextEditingController _opensubtitlesPasswordController;
  late final TextEditingController _subdlApiKeyController;
  late List<String> _draftSubtitlePreferredLanguageValues;
  late final TextEditingController
      _subtitleSearchMaxValidatedCandidatesController;
  late bool _draftOpensubtitlesEnabled;
  late bool _draftSubdlEnabled;
  late bool _draftBackgroundPlaybackEnabled;
  late PlaybackEngine _draftPlaybackEngine;
  late PlaybackDecodeMode _draftPlaybackDecodeMode;
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
    _assrtTokenController = TextEditingController(
      text: widget.initialAssrtToken,
    );
    _assrtTokenController.addListener(_handleAssrtTokenChanged);
    _opensubtitlesUsernameController = TextEditingController(
      text: widget.initialOpensubtitlesUsername,
    );
    _opensubtitlesPasswordController = TextEditingController(
      text: widget.initialOpensubtitlesPassword,
    );
    _subdlApiKeyController = TextEditingController(
      text: widget.initialSubdlApiKey,
    );
    _draftSubtitlePreferredLanguageValues =
        widget.initialSubtitlePreferredLanguages.toList(growable: false);
    _subtitleSearchMaxValidatedCandidatesController = TextEditingController(
      text: '${widget.initialSubtitleSearchMaxValidatedCandidates}',
    );
    _draftOpensubtitlesEnabled = widget.initialOpensubtitlesEnabled;
    _draftSubdlEnabled = widget.initialSubdlEnabled;
    _draftBackgroundPlaybackEnabled = widget.initialBackgroundPlaybackEnabled;
    _draftPlaybackEngine = effectivePlaybackEngine(
      selected: widget.initialPlaybackEngine,
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    );
    _draftPlaybackDecodeMode = widget.initialPlaybackDecodeMode;
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
    _assrtTokenController.removeListener(_handleAssrtTokenChanged);
    _timeoutController.dispose();
    _assrtTokenController.dispose();
    _opensubtitlesUsernameController.dispose();
    _opensubtitlesPasswordController.dispose();
    _subdlApiKeyController.dispose();
    _subtitleSearchMaxValidatedCandidatesController.dispose();
    super.dispose();
  }

  void _handleAssrtTokenChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  int _draftSeconds() {
    final parsed = int.tryParse(_timeoutController.text.trim()) ?? 20;
    return parsed.clamp(1, 600);
  }

  int _draftSubtitleSearchMaxValidatedCandidates() {
    final parsed = int.tryParse(
          _subtitleSearchMaxValidatedCandidatesController.text.trim(),
        ) ??
        kSubtitleSearchMaxValidatedCandidatesDefault;
    return clampSubtitleSearchMaxValidatedCandidates(parsed);
  }

  List<String> _draftSubtitlePreferredLanguages() {
    return _draftSubtitlePreferredLanguageValues.toList(growable: false);
  }

  Future<void> _saveDraft({bool popAfterSave = true}) async {
    await ref.read(settingsControllerProvider.notifier).savePlaybackPreferences(
          openTimeoutSeconds: _draftSeconds(),
          defaultSpeed: _draftPlaybackSpeed,
          subtitlePreference: _draftSubtitlePreference,
          subtitleScale: _draftSubtitleScale,
          onlineSubtitleSources: _draftOnlineSubtitleSources,
          assrtToken: _assrtTokenController.text,
          opensubtitlesEnabled: _draftOpensubtitlesEnabled,
          opensubtitlesUsername: _opensubtitlesUsernameController.text,
          opensubtitlesPassword: _opensubtitlesPasswordController.text,
          subdlEnabled: _draftSubdlEnabled,
          subdlApiKey: _subdlApiKeyController.text,
          subtitlePreferredLanguages: _draftSubtitlePreferredLanguages(),
          subtitleSearchMaxValidatedCandidates:
              _draftSubtitleSearchMaxValidatedCandidates(),
          backgroundPlaybackEnabled: _draftBackgroundPlaybackEnabled,
          playbackEngine: _draftPlaybackEngine,
          playbackDecodeMode: _draftPlaybackDecodeMode,
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
        _assrtTokenController.text != widget.initialAssrtToken ||
        _draftOpensubtitlesEnabled != widget.initialOpensubtitlesEnabled ||
        _opensubtitlesUsernameController.text !=
            widget.initialOpensubtitlesUsername ||
        _opensubtitlesPasswordController.text !=
            widget.initialOpensubtitlesPassword ||
        _draftSubdlEnabled != widget.initialSubdlEnabled ||
        _subdlApiKeyController.text != widget.initialSubdlApiKey ||
        !_sameStringSet(
          _draftSubtitlePreferredLanguages(),
          widget.initialSubtitlePreferredLanguages,
        ) ||
        _draftSubtitleSearchMaxValidatedCandidates() !=
            widget.initialSubtitleSearchMaxValidatedCandidates ||
        _draftBackgroundPlaybackEnabled !=
            widget.initialBackgroundPlaybackEnabled ||
        _draftPlaybackEngine != widget.initialPlaybackEngine ||
        _draftPlaybackDecodeMode != widget.initialPlaybackDecodeMode ||
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
              subtitle: 'Android 切后台进入小窗；iOS 继续后台音频，并在锁屏 / 控制中心显示封面。',
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
          initialAssrtToken: _assrtTokenController.text,
          initialOpensubtitlesEnabled: _draftOpensubtitlesEnabled,
          initialOpensubtitlesUsername: _opensubtitlesUsernameController.text,
          initialOpensubtitlesPassword: _opensubtitlesPasswordController.text,
          initialSubdlEnabled: _draftSubdlEnabled,
          initialSubdlApiKey: _subdlApiKeyController.text,
          initialSubtitlePreferredLanguages: _draftSubtitlePreferredLanguages(),
          initialSubtitleSearchMaxValidatedCandidates:
              _draftSubtitleSearchMaxValidatedCandidates(),
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
      _assrtTokenController.text = result.assrtToken;
      _draftOpensubtitlesEnabled = result.opensubtitlesEnabled;
      _opensubtitlesUsernameController.text = result.opensubtitlesUsername;
      _opensubtitlesPasswordController.text = result.opensubtitlesPassword;
      _draftSubdlEnabled = result.subdlEnabled;
      _subdlApiKeyController.text = result.subdlApiKey;
      _draftSubtitlePreferredLanguageValues =
          result.subtitlePreferredLanguages.toList(growable: false);
      _subtitleSearchMaxValidatedCandidatesController.text =
          '${result.subtitleSearchMaxValidatedCandidates}';
    });
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

  static String _formatSpeedLabel(double speed) {
    if (speed == speed.roundToDouble()) {
      return '${speed.toStringAsFixed(0)}x';
    }
    return '${speed.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')}x';
  }

  String _subtitleSettingsSummary() {
    final providerSummary = [
      if (_draftOnlineSubtitleSources.contains(OnlineSubtitleSource.assrt) &&
          _assrtTokenController.text.trim().isNotEmpty)
        'ASSRT API',
      if (_draftOpensubtitlesEnabled) 'OpenSubtitles',
      if (_draftSubdlEnabled) 'SubDL',
    ].join(' / ');
    final sourceLabel = _draftOnlineSubtitleSources.isEmpty
        ? '未启用在线字幕源'
        : _draftOnlineSubtitleSources.map((item) => item.label).join(' / ');
    final languageLabel = formatSubtitlePreferredLanguageSummary(
      _draftSubtitlePreferredLanguages(),
      emptyLabel: '语言未限制',
      separator: '/',
    );
    return [
      _draftSubtitlePreference.label,
      formatPlaybackSubtitleScaleLabel(_draftSubtitleScale),
      if (providerSummary.isNotEmpty) providerSummary,
      sourceLabel,
      languageLabel,
    ].join(' · ');
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
