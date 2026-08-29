import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/playback/application/subtitle_language_preferences.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/application/settings_slice_providers.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/settings_auto_save_coordinator.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_text_input_field.dart';

/// 字幕设置一级页。
///
/// 只通过 [savePlaybackSubtitlePreferences] 更新字幕字段，不会覆盖播放页的其它偏好。
class SubtitleSettingsPage extends ConsumerStatefulWidget {
  const SubtitleSettingsPage({super.key});

  @override
  ConsumerState<SubtitleSettingsPage> createState() =>
      _SubtitleSettingsPageState();
}

class _SubtitleSettingsPageState extends ConsumerState<SubtitleSettingsPage> {
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
  final SettingsAutoSaveCoordinator _autoSave = SettingsAutoSaveCoordinator();

  @override
  void initState() {
    super.initState();
    final slice = ref.read(settingsPlaybackSliceProvider);
    _draftSubtitlePreference = slice.playbackSubtitlePreference;
    _draftSubtitleScale = slice.playbackSubtitleScale;
    _draftOnlineSubtitleSources =
        slice.onlineSubtitleSources.toList(growable: false);
    _assrtTokenController = TextEditingController(text: slice.assrtToken);
    _assrtTokenController.addListener(_handleAssrtTokenChanged);
    _opensubtitlesUsernameController =
        TextEditingController(text: slice.opensubtitlesUsername);
    _opensubtitlesUsernameController.addListener(_scheduleAutoSave);
    _opensubtitlesPasswordController =
        TextEditingController(text: slice.opensubtitlesPassword);
    _opensubtitlesPasswordController.addListener(_scheduleAutoSave);
    _subdlApiKeyController = TextEditingController(text: slice.subdlApiKey);
    _subdlApiKeyController.addListener(_scheduleAutoSave);
    _draftSubtitlePreferredLanguageValues =
        slice.subtitlePreferredLanguages.toList(growable: false);
    _subtitleSearchMaxValidatedCandidatesController = TextEditingController(
      text: '${slice.subtitleSearchMaxValidatedCandidates}',
    );
    _subtitleSearchMaxValidatedCandidatesController.addListener(
      _scheduleAutoSave,
    );
    _draftOpensubtitlesEnabled = slice.opensubtitlesEnabled;
    _draftSubdlEnabled = slice.subdlEnabled;
    _autoSave.markCurrentAsSaved(_draftFingerprint());
  }

  @override
  void dispose() {
    _autoSave.dispose();
    _assrtTokenController.removeListener(_handleAssrtTokenChanged);
    _opensubtitlesUsernameController.removeListener(_scheduleAutoSave);
    _opensubtitlesPasswordController.removeListener(_scheduleAutoSave);
    _subdlApiKeyController.removeListener(_scheduleAutoSave);
    _subtitleSearchMaxValidatedCandidatesController.removeListener(
      _scheduleAutoSave,
    );
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
    _scheduleAutoSave();
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

  String _draftFingerprint() => jsonEncode({
        'subtitlePreference': _draftSubtitlePreference.name,
        'subtitleScale': _draftSubtitleScale,
        'onlineSubtitleSources': [
          for (final source in _draftOnlineSubtitleSources) source.name,
        ],
        'assrtToken': _assrtTokenController.text.trim(),
        'opensubtitlesEnabled': _draftOpensubtitlesEnabled,
        'opensubtitlesUsername': _opensubtitlesUsernameController.text.trim(),
        'opensubtitlesPassword': _opensubtitlesPasswordController.text,
        'subdlEnabled': _draftSubdlEnabled,
        'subdlApiKey': _subdlApiKeyController.text.trim(),
        'subtitlePreferredLanguages': _draftSubtitlePreferredLanguages(),
        'subtitleSearchMaxValidatedCandidates':
            _draftSubtitleSearchMaxValidatedCandidates(),
      });

  void _scheduleAutoSave() {
    _submitAutoSave(flush: false);
  }

  void _flushAutoSave() {
    _submitAutoSave(flush: true);
  }

  void _submitAutoSave({required bool flush}) {
    if (!mounted) {
      return;
    }
    final controller = ref.read(settingsControllerProvider.notifier);
    final subtitlePreference = _draftSubtitlePreference;
    final subtitleScale = _draftSubtitleScale;
    final onlineSubtitleSources = [..._draftOnlineSubtitleSources];
    final assrtToken = _assrtTokenController.text.trim();
    final opensubtitlesEnabled = _draftOpensubtitlesEnabled;
    final opensubtitlesUsername = _opensubtitlesUsernameController.text.trim();
    final opensubtitlesPassword = _opensubtitlesPasswordController.text;
    final subdlEnabled = _draftSubdlEnabled;
    final subdlApiKey = _subdlApiKeyController.text.trim();
    final subtitlePreferredLanguages = _draftSubtitlePreferredLanguages();
    final subtitleSearchMaxValidatedCandidates =
        _draftSubtitleSearchMaxValidatedCandidates();
    Future<void> save() => controller.savePlaybackSubtitlePreferences(
          subtitlePreference: subtitlePreference,
          subtitleScale: subtitleScale,
          onlineSubtitleSources: onlineSubtitleSources,
          assrtToken: assrtToken,
          opensubtitlesEnabled: opensubtitlesEnabled,
          opensubtitlesUsername: opensubtitlesUsername,
          opensubtitlesPassword: opensubtitlesPassword,
          subdlEnabled: subdlEnabled,
          subdlApiKey: subdlApiKey,
          subtitlePreferredLanguages: subtitlePreferredLanguages,
          subtitleSearchMaxValidatedCandidates:
              subtitleSearchMaxValidatedCandidates,
        );
    if (flush) {
      _autoSave.flush(
        fingerprint: _draftFingerprint(),
        save: save,
      );
    } else {
      _autoSave.schedule(
        fingerprint: _draftFingerprint(),
        save: save,
      );
    }
  }

  void _closePage() {
    _flushAutoSave();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope<void>(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _flushAutoSave();
        }
      },
      child: SettingsPageScaffold(
        onBack: _closePage,
        children: [
          Text(
            '字幕',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          SettingsSelectionTile(
            title: '默认字幕策略',
            value: _draftSubtitlePreference.label,
            autofocus: true,
            focusId: 'subtitle-settings:preference',
            onPressed: _openSubtitlePreferencePicker,
          ),
          const SizedBox(height: 8),
          Text(
            _draftSubtitlePreference.description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          SettingsStepperTile(
            title: '字幕大小',
            subtitle: '用于内置 MPV 和 Android 原生播放器；系统无障碍字幕启用时优先跟随系统。',
            value: formatPlaybackSubtitleScaleLabel(_draftSubtitleScale),
            onDecrease: _draftSubtitleScale > kPlaybackSubtitleScaleMin
                ? () {
                    setState(() {
                      _draftSubtitleScale = stepPlaybackSubtitleScale(
                        _draftSubtitleScale,
                        -1,
                      );
                    });
                    _scheduleAutoSave();
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
                    _scheduleAutoSave();
                  }
                : null,
          ),
          const SizedBox(height: 18),
          Text(
            '在线字幕来源',
            style: theme.textTheme.titleMedium?.copyWith(
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
              _scheduleAutoSave();
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
              _scheduleAutoSave();
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
              _scheduleAutoSave();
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
    _scheduleAutoSave();
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
    _scheduleAutoSave();
  }
}
