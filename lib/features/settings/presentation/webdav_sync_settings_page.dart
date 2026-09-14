import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/search/data/search_preferences_repository.dart';
import 'package:starflow/features/search/application/favorite_auto_sync.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/data/webdav_sync_service.dart';
import 'package:starflow/features/settings/presentation/settings_auto_save_coordinator.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_text_input_field.dart';

class WebDavSyncSettingsPage extends ConsumerStatefulWidget {
  const WebDavSyncSettingsPage({super.key});

  @override
  ConsumerState<WebDavSyncSettingsPage> createState() =>
      _WebDavSyncSettingsPageState();
}

class _WebDavSyncSettingsPageState
    extends ConsumerState<WebDavSyncSettingsPage> {
  final _url = TextEditingController();
  final _directory = TextEditingController(text: 'Starflow');
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _settings = true;
  bool _favorites = true;
  bool _autoFavorites = false;
  bool _loading = true;
  bool _busy = false;
  String _status = '';
  final _autoSave = SettingsAutoSaveCoordinator();
  late final WebDavSyncPreferences _preferences;
  Object? _saveError;
  bool _applyingConfig = false;
  bool _hasEdits = false;

  List<TextEditingController> get _textControllers =>
      [_url, _directory, _username, _password];

  @override
  void initState() {
    super.initState();
    _preferences = ref.read(webDavSyncPreferencesProvider);
    for (final controller in _textControllers) {
      controller.addListener(_scheduleAutoSave);
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final config = await _preferences.load();
      if (!mounted) return;
      _applyingConfig = true;
      _url.text = config.url;
      _directory.text = config.directory;
      _username.text = config.username;
      _password.text = config.password;
      _settings = config.settings;
      _favorites = config.favorites;
      _autoFavorites = config.autoFavorites;
      _autoSave.markCurrentAsSaved(jsonEncode(_draft.toJson()));
      _hasEdits = false;
    } catch (_) {
      _status = '读取同步设置失败，请重新填写';
    } finally {
      _applyingConfig = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _flushAutoSave();
    for (final controller in _textControllers) {
      controller.removeListener(_scheduleAutoSave);
      controller.dispose();
    }
    _autoSave.dispose();
    super.dispose();
  }

  Future<void> _save(WebDavSyncConfig config) async {
    try {
      await _preferences.save(config);
      _saveError = null;
      if (mounted && _status == '同步设置自动保存失败，请重试修改或检查本地存储') {
        setState(() => _status = '');
      }
    } catch (error) {
      _saveError = error;
      if (mounted) {
        setState(() => _status = '同步设置自动保存失败，请重试修改或检查本地存储');
      }
      rethrow;
    }
  }

  void _scheduleAutoSave() {
    if (_loading || _applyingConfig) return;
    _hasEdits = true;
    final config = _draft;
    _autoSave.schedule(
      fingerprint: jsonEncode(config.toJson()),
      save: () => _save(config),
    );
  }

  void _flushAutoSave() {
    if (_loading || _applyingConfig || !_hasEdits) return;
    final config = _draft;
    _autoSave.flush(
      fingerprint: jsonEncode(config.toJson()),
      save: () => _save(config),
    );
  }

  void _closePage() {
    _flushAutoSave();
    Navigator.of(context).pop();
  }

  WebDavSyncConfig get _draft => WebDavSyncConfig(
        url: _url.text.trim(),
        directory: _directory.text.trim(),
        username: _username.text.trim(),
        password: _password.text,
        settings: _settings,
        favorites: _favorites,
        autoFavorites: _autoFavorites,
      );

  Future<void> _setAutoFavorites(bool enabled) async {
    if (enabled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('开启收藏自动同步'),
          content: const Text(
              '开启后将自动合并各设备的收藏与删除记录。收藏可能包含鉴权链接，远端文件未加密，请仅使用可信的 WebDAV 服务器。应用配置不会自动同步。'),
          actions: [
            StarflowButton(
                label: '取消',
                autofocus: true,
                compact: true,
                variant: StarflowButtonVariant.ghost,
                onPressed: () => Navigator.of(context).pop(false)),
            StarflowButton(
                label: '开启',
                compact: true,
                onPressed: () => Navigator.of(context).pop(true)),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _autoFavorites = enabled);
    _scheduleAutoSave();
  }

  Future<bool> _confirm(bool upload) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(upload ? '上传并覆盖远端' : '下载并覆盖本机'),
            content: Text(upload
                ? '将覆盖远端已勾选的内容。配置可能包含媒体源密码、Cookie 和令牌，远端文件未加密，仅上传到可信服务器。'
                : '将覆盖本机已勾选的内容，收藏不会合并。是否继续？'),
            actions: [
              StarflowButton(
                label: '取消',
                autofocus: true,
                compact: true,
                variant: StarflowButtonVariant.ghost,
                onPressed: () => Navigator.of(context).pop(false),
              ),
              StarflowButton(
                label: '确认',
                compact: true,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _run(String action) async {
    if (_busy || _loading) return;
    setState(() => _busy = true);
    try {
      final config = _draft;
      _flushAutoSave();
      await _autoSave.drain();
      if (!mounted) return;
      if (_saveError != null) {
        throw StateError('同步设置尚未保存成功，已停止网络操作');
      }
      config.fileUri;
      final manualConfig = WebDavSyncConfig(
        url: config.url,
        directory: config.directory,
        username: config.username,
        password: config.password,
        settings: config.settings,
        favorites: config.favorites && !config.autoFavorites,
      );
      if ((action == 'upload' || action == 'download') &&
          !manualConfig.settings &&
          !manualConfig.favorites) {
        throw const FormatException('请先选择手动同步内容；收藏自动同步使用独立操作');
      }
      if ((action == 'upload' || action == 'download') &&
          !await _confirm(action == 'upload')) {
        return;
      }
      if (!mounted) return;
      final service = ref.read(webDavSyncServiceProvider);
      final favorites = ref.read(searchPreferencesRepositoryProvider);
      final controller = ref.read(settingsControllerProvider.notifier);
      switch (action) {
        case 'test':
          final result = await service.testConnection(config);
          if (mounted) _status = result.message;
        case 'upload':
          final settings = await ref.read(settingsControllerProvider.future);
          await service.upload(
            manualConfig,
            WebDavSyncSnapshot(
              settings: manualConfig.settings ? settings : null,
              favorites: manualConfig.favorites
                  ? await favorites.loadFavoriteResults()
                  : null,
            ),
          );
          if (mounted) _status = '上传成功 · ${DateTime.now().toLocal()}';
        case 'download':
          final snapshot = await service.download(manualConfig);
          // Both sections have been validated before any local writes begin.
          if (manualConfig.settings) {
            await controller.replaceAllSettings(snapshot.settings!);
            await _load();
          }
          if (manualConfig.favorites) {
            await favorites.saveFavoriteResults(snapshot.favorites!);
          }
          if (mounted) _status = '下载成功 · ${DateTime.now().toLocal()}';
        case 'favorites':
          await ref.read(favoriteAutoSyncProvider).synchronize(manual: true);
      }
    } catch (error) {
      if (mounted) {
        _status = switch (error) {
          FormatException(source: null, :final message) => '操作失败：$message',
          FormatException() => '操作失败：同步文件格式无效',
          StateError(:final message) => '操作失败：$message',
          _ => '操作失败：请检查网络、服务器地址及同步文件，稍后重试',
        };
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final autoSync = ref.watch(favoriteAutoSyncProvider);
    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _flushAutoSave();
      },
      child: SettingsPageScaffold(
        onBack: _busy ? null : _closePage,
        children: [
          Text('网络同步', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 18),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else ...[
            AbsorbPointer(
              absorbing: _busy,
              child: ExcludeFocus(
                excluding: _busy,
                child: Column(
                  children: [
                    SettingsTextInputField(
                      controller: _url,
                      labelText: 'WebDAV 地址',
                      hintText: 'https://dav.example.com/dav/',
                      autocorrect: false,
                      autofocus: true,
                      focusId: 'sync:url',
                    ),
                    const SizedBox(height: 12),
                    SettingsTextInputField(
                      controller: _directory,
                      labelText: '同步目录',
                      hintText: 'Starflow',
                      autocorrect: false,
                      focusId: 'sync:directory',
                    ),
                    const SizedBox(height: 12),
                    SettingsTextInputField(
                      controller: _username,
                      labelText: '用户名',
                      autocorrect: false,
                      focusId: 'sync:username',
                    ),
                    const SizedBox(height: 12),
                    SettingsTextInputField(
                      controller: _password,
                      labelText: '密码 / 应用密码',
                      obscureText: true,
                      autocorrect: false,
                      focusId: 'sync:password',
                    ),
                    const SizedBox(height: 18),
                    SettingsToggleTile(
                      title: '同步配置',
                      subtitle: '应用设置',
                      value: _settings,
                      onChanged: (value) {
                        setState(() => _settings = value);
                        _scheduleAutoSave();
                      },
                      focusId: 'sync:settings',
                    ),
                    SettingsToggleTile(
                      title: '同步收藏',
                      subtitle: '手动覆盖',
                      value: _favorites && !_autoFavorites,
                      onChanged: _autoFavorites
                          ? null
                          : (value) {
                              setState(() => _favorites = value);
                              _scheduleAutoSave();
                            },
                      focusId: 'sync:favorites',
                    ),
                    SettingsToggleTile(
                      title: '收藏自动同步',
                      subtitle: '双向合并',
                      value: _autoFavorites,
                      onChanged: _setAutoFavorites,
                      focusId: 'sync:auto-favorites',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final action in [
                  ('test', '测试连接', Icons.network_check_rounded),
                  ('upload', '上传到云端', Icons.cloud_upload_rounded),
                  ('download', '从云端下载', Icons.cloud_download_rounded),
                ])
                  SettingsActionButton(
                    label: action.$2,
                    icon: action.$3,
                    onPressed: _busy ? null : () => _run(action.$1),
                    focusId: 'sync:${action.$1}',
                  ),
              ],
            ),
            if (_busy) ...[
              const SizedBox(height: 18),
              const LinearProgressIndicator(),
            ],
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(_status),
            ],
            const SizedBox(height: 18),
            ListenableBuilder(
              listenable: autoSync,
              builder: (context, child) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(autoSync.status),
                  if (autoSync.lastSuccess != null)
                    Text('上次成功：${autoSync.lastSuccess!.toLocal()}'),
                  if (autoSync.enabled) ...[
                    const SizedBox(height: 12),
                    SettingsActionButton(
                      label: '立即同步收藏',
                      icon: Icons.sync_rounded,
                      onPressed: autoSync.running || _busy
                          ? null
                          : () => _run('favorites'),
                      focusId: 'sync:now',
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
