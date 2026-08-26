part of 'playback_settings_page.dart';

class PlaybackSubtitleSettingsPage extends ConsumerStatefulWidget {
  const PlaybackSubtitleSettingsPage({
    super.key,
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
  });

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

  @override
  ConsumerState<PlaybackSubtitleSettingsPage> createState() =>
      _PlaybackSubtitleSettingsPageState();
}

class _PlaybackSubtitleSettingsPageState
    extends ConsumerState<PlaybackSubtitleSettingsPage> {
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
  bool _closingWithResult = false;

  @override
  void initState() {
    super.initState();
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
  }

  @override
  void dispose() {
    _assrtTokenController.removeListener(_handleAssrtTokenChanged);
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

  List<String> _draftSubtitlePreferredLanguages() {
    return _draftSubtitlePreferredLanguageValues.toList(growable: false);
  }

  int _draftSubtitleSearchMaxValidatedCandidates() {
    final parsed = int.tryParse(
          _subtitleSearchMaxValidatedCandidatesController.text.trim(),
        ) ??
        kSubtitleSearchMaxValidatedCandidatesDefault;
    return clampSubtitleSearchMaxValidatedCandidates(parsed);
  }

  _PlaybackSubtitleDraft _buildDraft() {
    return _PlaybackSubtitleDraft(
      preference: _draftSubtitlePreference,
      scale: _draftSubtitleScale,
      onlineSubtitleSources: _draftOnlineSubtitleSources,
      assrtToken: _assrtTokenController.text.trim(),
      opensubtitlesEnabled: _draftOpensubtitlesEnabled,
      opensubtitlesUsername: _opensubtitlesUsernameController.text.trim(),
      opensubtitlesPassword: _opensubtitlesPasswordController.text,
      subdlEnabled: _draftSubdlEnabled,
      subdlApiKey: _subdlApiKeyController.text.trim(),
      subtitlePreferredLanguages: _draftSubtitlePreferredLanguages(),
      subtitleSearchMaxValidatedCandidates:
          _draftSubtitleSearchMaxValidatedCandidates(),
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
          const SizedBox(height: 18),
          SettingsSelectionTile(
            title: '默认字幕策略',
            value: _draftSubtitlePreference.label,
            autofocus: true,
            focusId: 'playback-subtitle:preference',
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
          SettingsStepperTile(
            title: '字幕大小',
            subtitle: '按数字微调字号，播放器里会直接按这个字号渲染。',
            value: formatPlaybackSubtitleScaleLabel(_draftSubtitleScale),
            onDecrease: _draftSubtitleScale > kPlaybackSubtitleScaleMin
                ? () {
                    setState(() {
                      _draftSubtitleScale = stepPlaybackSubtitleScale(
                        _draftSubtitleScale,
                        -1,
                      );
                    });
                  }
                : null,
            onIncrease: _draftSubtitleScale < kPlaybackSubtitleScaleMax
                ? () {
                    setState(() {
                      _draftSubtitleScale = stepPlaybackSubtitleScale(
                        _draftSubtitleScale,
                        1,
                      );
                    });
                  }
                : null,
          ),
          const SizedBox(height: 18),
          Text(
            '在线字幕来源',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          SettingsToggleTile(
            title: OnlineSubtitleSource.assrt.label,
            subtitle: 'ASSRT 官方 API 字幕源。',
            value: _draftOnlineSubtitleSources.contains(
              OnlineSubtitleSource.assrt,
            ),
            onChanged: (value) {
              setState(() {
                final next = _draftOnlineSubtitleSources.toSet();
                if (value) {
                  next.add(OnlineSubtitleSource.assrt);
                } else {
                  next.remove(OnlineSubtitleSource.assrt);
                }
                _draftOnlineSubtitleSources = next.toList(growable: false);
              });
            },
          ),
          if (_draftOnlineSubtitleSources
              .contains(OnlineSubtitleSource.assrt)) ...[
            const SizedBox(height: 12),
            SettingsTextInputField(
              controller: _assrtTokenController,
              labelText: 'ASSRT Token',
              hintText: '必填，填写后才会启用 ASSRT 官方 API',
              obscureText: true,
              autocorrect: false,
            ),
          ],
          const SizedBox(height: 18),
          SettingsToggleTile(
            title: OnlineSubtitleSource.opensubtitles.label,
            subtitle: 'OpenSubtitles.com 官方 API 字幕源。',
            value: _draftOpensubtitlesEnabled,
            onChanged: (value) {
              setState(() {
                _draftOpensubtitlesEnabled = value;
              });
            },
          ),
          if (_draftOpensubtitlesEnabled) ...[
            const SizedBox(height: 12),
            SettingsTextInputField(
              controller: _opensubtitlesUsernameController,
              labelText: 'OpenSubtitles 用户名',
              hintText: '可留空',
              autocorrect: false,
            ),
            const SizedBox(height: 12),
            SettingsTextInputField(
              controller: _opensubtitlesPasswordController,
              labelText: 'OpenSubtitles 密码',
              hintText: '可留空',
              obscureText: true,
              autocorrect: false,
            ),
          ],
          const SizedBox(height: 18),
          SettingsToggleTile(
            title: OnlineSubtitleSource.subdl.label,
            subtitle: 'SubDL 官方 API 字幕源。',
            value: _draftSubdlEnabled,
            onChanged: (value) {
              setState(() {
                _draftSubdlEnabled = value;
              });
            },
          ),
          if (_draftSubdlEnabled) ...[
            const SizedBox(height: 12),
            SettingsTextInputField(
              controller: _subdlApiKeyController,
              labelText: 'SubDL API Key',
              hintText: '可留空',
              obscureText: true,
              autocorrect: false,
            ),
          ],
          const SizedBox(height: 12),
          SettingsSelectionTile(
            title: '优先语言',
            subtitle: '可多选；不选时按字幕结果和系统语言自动处理。',
            value: formatSubtitlePreferredLanguageSummary(
              _draftSubtitlePreferredLanguages(),
            ),
            onPressed: _openSubtitlePreferredLanguagePicker,
          ),
          const SizedBox(height: 12),
          SettingsTextInputField(
            controller: _subtitleSearchMaxValidatedCandidatesController,
            labelText: '单次最多验证条数',
            hintText: '$kSubtitleSearchMaxValidatedCandidatesDefault',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            summaryBuilder: (value) => value.isEmpty
                ? '$kSubtitleSearchMaxValidatedCandidatesDefault'
                : value,
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

  Future<void> _openSubtitlePreferredLanguagePicker() async {
    final initialSelection = orderCommonSubtitlePreferredLanguages(
            _draftSubtitlePreferredLanguages())
        .toSet();
    final selected = await showSettingsCheckboxSelectionDialog<String>(
      context: context,
      title: '选择优先语言',
      initialSelection: initialSelection,
      allLabel: '未限制',
      allSubtitle: '清空单独选择后，按字幕结果和系统语言自动处理。',
      sections: [
        SettingsCheckboxDialogSection<String>(
          options: commonSubtitlePreferredLanguageOptions
              .map(
                (option) => SettingsCheckboxDialogOption<String>(
                  value: option.value,
                  title: option.label,
                  subtitle: option.subtitle,
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
    if (selected == null) {
      return;
    }
    setState(() {
      _draftSubtitlePreferredLanguageValues =
          orderCommonSubtitlePreferredLanguages(selected);
    });
  }
}

class _PlaybackSubtitleDraft {
  const _PlaybackSubtitleDraft({
    required this.preference,
    required this.scale,
    required this.onlineSubtitleSources,
    required this.assrtToken,
    required this.opensubtitlesEnabled,
    required this.opensubtitlesUsername,
    required this.opensubtitlesPassword,
    required this.subdlEnabled,
    required this.subdlApiKey,
    required this.subtitlePreferredLanguages,
    required this.subtitleSearchMaxValidatedCandidates,
  });

  final PlaybackSubtitlePreference preference;
  final double scale;
  final List<OnlineSubtitleSource> onlineSubtitleSources;
  final String assrtToken;
  final bool opensubtitlesEnabled;
  final String opensubtitlesUsername;
  final String opensubtitlesPassword;
  final bool subdlEnabled;
  final String subdlApiKey;
  final List<String> subtitlePreferredLanguages;
  final int subtitleSearchMaxValidatedCandidates;
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

bool _sameStringSet(List<String> left, List<String> right) {
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
