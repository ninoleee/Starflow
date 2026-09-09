import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/search/data/search_preferences_repository.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/data/webdav_sync_service.dart';
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
  bool _loading = true;
  bool _busy = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final config = await ref.read(webDavSyncPreferencesProvider).load();
      if (!mounted) return;
      _url.text = config.url;
      _directory.text = config.directory;
      _username.text = config.username;
      _password.text = config.password;
      _settings = config.settings;
      _favorites = config.favorites;
    } catch (_) {
      _status = '读取同步设置失败，请重新填写';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    for (final controller in [_url, _directory, _username, _password]) {
      controller.dispose();
    }
    super.dispose();
  }

  WebDavSyncConfig get _draft => WebDavSyncConfig(
        url: _url.text.trim(),
        directory: _directory.text.trim(),
        username: _username.text.trim(),
        password: _password.text,
        settings: _settings,
        favorites: _favorites,
      );

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
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final config = _draft;
      config.fileUri;
      if (!config.settings && !config.favorites) {
        throw const FormatException('请至少选择一项同步内容');
      }
      if ((action == 'upload' || action == 'download') &&
          !await _confirm(action == 'upload')) {
        return;
      }
      if (!mounted) return;
      final preferences = ref.read(webDavSyncPreferencesProvider);
      final service = ref.read(webDavSyncServiceProvider);
      final favorites = ref.read(searchPreferencesRepositoryProvider);
      final controller = ref.read(settingsControllerProvider.notifier);
      await preferences.save(config);
      if (!mounted) return;
      switch (action) {
        case 'test':
          await service.testConnection(config);
          if (mounted) _status = '连接成功';
        case 'upload':
          final settings = await ref.read(settingsControllerProvider.future);
          await service.upload(
            config,
            WebDavSyncSnapshot(
              settings: config.settings ? settings : null,
              favorites: config.favorites
                  ? await favorites.loadFavoriteResults()
                  : null,
            ),
          );
          if (mounted) _status = '上传成功 · ${DateTime.now().toLocal()}';
        case 'download':
          final snapshot = await service.download(config);
          // Both sections have been validated before any local writes begin.
          if (config.settings) {
            await controller.replaceAllSettings(snapshot.settings!);
          }
          if (config.favorites) {
            await favorites.saveFavoriteResults(snapshot.favorites!);
          }
          if (mounted) _status = '下载成功 · ${DateTime.now().toLocal()}';
        default:
          _status = '同步设置已保存';
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
    return PopScope(
      canPop: !_busy,
      child: SettingsPageScaffold(
        onBack: _busy ? null : () => Navigator.of(context).pop(),
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
                      onChanged: (value) => setState(() => _settings = value),
                      focusId: 'sync:settings',
                    ),
                    SettingsToggleTile(
                      title: '同步收藏',
                      subtitle: '收藏列表',
                      value: _favorites,
                      onChanged: (value) => setState(() => _favorites = value),
                      focusId: 'sync:favorites',
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
                  ('save', '保存同步设置', Icons.save_rounded),
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
          ],
        ],
      ),
    );
  }
}
