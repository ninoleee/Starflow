import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/search/application/aliyun_to115_workflow.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/settings/presentation/webdav_directory_picker_page.dart';
import 'package:starflow/features/settings/data/aliyun_open_login_client.dart';
import 'package:starflow/features/settings/presentation/aliyun_login_page.dart';
import 'package:starflow/features/settings/presentation/aliyun_open_login_page.dart';
import 'package:starflow/features/settings/presentation/aliyun_transfer_tasks_page.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/domain/cloud_account.dart';
import 'package:starflow/features/search/domain/cloud_account_auth_exception.dart';
import 'package:starflow/features/settings/presentation/quark_folder_picker_page.dart';
import 'package:starflow/features/settings/presentation/quark_directory_manager_page.dart';
import 'package:starflow/features/settings/presentation/network_storage_settings_page.dart';
import 'package:starflow/features/search/domain/cloud_save_rules.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_text_input_field.dart';

class AliyunTransferSettingsPage extends ConsumerStatefulWidget {
  const AliyunTransferSettingsPage({super.key});

  @override
  ConsumerState<AliyunTransferSettingsPage> createState() =>
      _AliyunTransferSettingsPageState();
}

class _AliyunTransferSettingsPageState
    extends ConsumerState<AliyunTransferSettingsPage> {
  late final TextEditingController _token;
  late final TextEditingController _task;
  bool _busy = false;
  String _status = '';

  Future<void> _scanLogin() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '';
    });
    final previous =
        ref.read(appSettingsProvider).networkStorage.activeAliyunRefreshToken;
    try {
      final mode = ref.read(appSettingsProvider).networkStorage.aliyunAuthMode;
      final navigator = Navigator.of(context);
      final Object? token = mode == AliyunAuthMode.open
          ? await navigator.push<AliyunOpenToken>(
              MaterialPageRoute(builder: (_) => const AliyunOpenLoginPage()))
          : await navigator.push<String>(
              MaterialPageRoute(builder: (_) => const AliyunLoginPage()));
      if (!mounted || token == null) return;
      setState(() => _status = '正在验证阿里账号');
      final workflow = ref.read(aliyunTo115WorkflowProvider);
      var latest = token is AliyunOpenToken ? token.refreshToken : '$token';
      final session =
          await workflow.aliyun.login(latest, persistToken: (next) async {
        latest = next;
      }, open: mode == AliyunAuthMode.open);
      if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
      if (session.refreshToken.isNotEmpty) latest = session.refreshToken;
      await ref.read(settingsControllerProvider.notifier).acceptCloudAccount(
          CloudAccountDrive.aliyun, previous, latest, session.userId,
          aliyunAuthMode: mode);
      if (!mounted) return;
      _token.text = latest;
      setState(() => _status = '阿里账号连接成功');
    } catch (error) {
      if (mounted) {
        setState(() => _status =
            error is QuarkSaveException ? error.message : '扫码登录验证失败，原账号未更改');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setTransferEnabled(bool enabled) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final config = ref.read(appSettingsProvider).networkStorage;
      await ref
          .read(settingsControllerProvider.notifier)
          .saveNetworkStorage(config.copyWith(aliyunTo115Enabled: enabled));
    } catch (_) {
      if (mounted) setState(() => _status = '转存选项保存失败');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _token = TextEditingController(
        text: ref
            .read(appSettingsProvider)
            .networkStorage
            .activeAliyunRefreshToken);
    final config = ref.read(appSettingsProvider).networkStorage;
    _task = TextEditingController(text: config.aliyunSmartStrmTaskName);
  }

  @override
  void dispose() {
    _token.dispose();
    _task.dispose();
    super.dispose();
  }

  Future<bool> _save({bool test = false}) async {
    if (_busy) return false;
    setState(() {
      _busy = true;
      _status = '';
    });
    final input = _token.text.trim();
    try {
      final current = ref.read(appSettingsProvider).networkStorage;
      final mode = current.aliyunAuthMode;
      var accepted = input;
      if (test || input != current.activeAliyunRefreshToken) {
        final session = await ref
            .read(aliyunTo115WorkflowProvider)
            .aliyun
            .login(input, persistToken: (next) async {
          accepted = next;
        }, open: mode == AliyunAuthMode.open);
        if (!mounted) return false;
        if (session.refreshToken.isNotEmpty) accepted = session.refreshToken;
        await ref.read(settingsControllerProvider.notifier).acceptCloudAccount(
            CloudAccountDrive.aliyun,
            current.activeAliyunRefreshToken,
            accepted,
            session.userId,
            aliyunAuthMode: mode);
        if (!mounted) return false;
        _token.text = accepted;
      }
      final latest = ref.read(appSettingsProvider).networkStorage;
      await ref.read(settingsControllerProvider.notifier).saveNetworkStorage(
          latest.copyWith(
              aliyunRefreshToken: mode == AliyunAuthMode.consumer
                  ? accepted
                  : latest.aliyunRefreshToken,
              aliyunOpenRefreshToken: mode == AliyunAuthMode.open
                  ? accepted
                  : latest.aliyunOpenRefreshToken,
              aliyunAuthMode: mode,
              aliyunSmartStrmTaskName: _task.text.trim()));
      if (mounted) setState(() => _status = test ? '阿里账号连接成功' : '已保存');
      return true;
    } catch (error) {
      if (error is CloudAccountAuthException && mounted) {
        await ref
            .read(settingsControllerProvider.notifier)
            .markCloudAccountInvalid(CloudAccountDrive.aliyun, input);
      }
      if (mounted) {
        setState(() =>
            _status = error is QuarkSaveException ? error.message : '保存或连接失败');
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _browse({bool manage = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final workflow = ref.read(aliyunTo115WorkflowProvider);
      final config = ref.read(appSettingsProvider).networkStorage;
      final session = await workflow.aliyun
          .login(config.activeAliyunRefreshToken, persistToken: (next) async {
        await workflow.persistToken(config.activeAliyunRefreshToken, next);
        if (mounted && _token.text == config.activeAliyunRefreshToken) {
          _token.text = next;
        }
      }, open: config.aliyunAuthMode == AliyunAuthMode.open);
      if (!mounted) return;
      if (manage) {
        await Navigator.of(context).push<void>(MaterialPageRoute(
            builder: (_) => QuarkDirectoryManagerPage(
                cookie: '',
                driveName: '阿里',
                initialFid: config.aliyunSaveFolderId,
                initialPath: config.aliyunSaveFolderPath,
                entryLoader: (id, path) async => (await workflow.aliyun
                        .listOwned(session, id))
                    .map((e) => QuarkFileEntry(
                        fid: e.id,
                        name: e.name,
                        path: cloudChildPath(path, e.name),
                        isDirectory: e.isDirectory,
                        extension:
                            e.name.contains('.') ? e.name.split('.').last : ''))
                    .toList(),
                deleteEntries: (id, entries) =>
                    workflow.aliyun.recycleOwned(session, id, entries))));
      } else {
        final selected = await Navigator.of(context).push<QuarkDirectoryEntry>(
            MaterialPageRoute(
                builder: (_) => QuarkFolderPickerPage(
                    cookie: '',
                    initialFid: 'root',
                    directoryLoader: (id, path) async =>
                        (await workflow.aliyun.listOwned(session, id))
                            .where((e) => e.isDirectory)
                            .map((e) => QuarkDirectoryEntry(
                                fid: e.id,
                                name: e.name,
                                path: cloudChildPath(path, e.name)))
                            .toList())));
        if (selected != null && mounted) {
          await ref
              .read(settingsControllerProvider.notifier)
              .confirmCloudDirectory(CloudAccountDrive.aliyun,
                  id: selected.fid,
                  path: selected.path,
                  credential: session.refreshToken.isNotEmpty
                      ? session.refreshToken
                      : _token.text.trim());
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() =>
            _status = error is QuarkSaveException ? error.message : '阿里目录访问失败');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _testStrm() async {
    if (!await _save() || !mounted) return;
    setState(() => _busy = true);
    try {
      final config = ref.read(appSettingsProvider).networkStorage;
      await ref
          .read(aliyunTo115WorkflowProvider)
          .postprocessing
          .smartStrm
          .triggerTask(
              webhookUrl: config.smartStrmWebhookUrl,
              taskName: config.aliyunSmartStrmTaskName,
              storagePath: config.aliyunSaveFolderPath == '/'
                  ? ''
                  : config.aliyunSaveFolderPath,
              delay: config.smartStrmDelaySeconds);
      if (mounted) setState(() => _status = '阿里 STRM 任务已触发');
    } catch (_) {
      if (mounted) setState(() => _status = 'STRM 触发失败，请检查任务与 Webhook');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openSettings(NetworkStorageEditorSection section) {
    Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => NetworkStorageEditorPage(
            initial: ref.read(appSettingsProvider).networkStorage,
            section: section)));
  }

  Future<void> _updateConfig(
      NetworkStorageConfig Function(NetworkStorageConfig) update) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(settingsControllerProvider.notifier).saveNetworkStorage(
          update(ref.read(appSettingsProvider).networkStorage));
    } catch (_) {
      if (mounted) setState(() => _status = '设置保存失败');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addScope(MediaSourceConfig source) async {
    final picked = await Navigator.of(context).push<String>(MaterialPageRoute(
        builder: (_) => WebDavDirectoryPickerPage(
            source: source, initialPath: source.libraryPath)));
    if (!mounted || picked == null || picked.trim().isEmpty) return;
    await _updateConfig((c) => c.copyWith(syncDeleteAliyunWebDavDirectories: [
          ...c.syncDeleteAliyunWebDavDirectories
              .where((s) => s.sourceId != source.id || s.directoryId != picked),
          NetworkStorageWebDavDirectory(
              sourceId: source.id,
              sourceName: source.name,
              directoryId: picked,
              directoryLabel: picked),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(
        appSettingsProvider
            .select((s) => s.networkStorage.activeAliyunRefreshToken),
        (previous, next) {
      if (_token.text.trim() == previous) _token.text = next;
    });
    final config = ref.watch(appSettingsProvider).networkStorage;
    return SettingsPageScaffold(
        onBack: () => Navigator.of(context).pop(),
        children: [
          Text('阿里云盘', style: Theme.of(context).textTheme.headlineSmall),
          SettingsSelectionTile(
              title: '转存任务与暂存清理',
              value: '',
              onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                      builder: (_) => const AliyunTransferTasksPage()))),
          Text(
              '账号：${config.account(CloudAccountDrive.aliyun).status(config.activeAliyunRefreshToken)}'),
          SettingsToggleTile(
              title: '使用阿里开放平台 OAuth',
              subtitle: '通过 OpenList 官方授权服务扫码，Token 仅保存在本机',
              value: config.aliyunAuthMode == AliyunAuthMode.open,
              focusId: 'aliyun:open-oauth',
              onChanged: _busy
                  ? null
                  : (value) => _updateConfig((c) => c.copyWith(
                      aliyunAuthMode: value
                          ? AliyunAuthMode.open
                          : AliyunAuthMode.consumer))),
          SettingsActionButton(
              label: '清除本机登录',
              icon: Icons.logout_rounded,
              onPressed: _busy || !config.hasAliyunCredential
                  ? null
                  : () async {
                      await _updateConfig((c) =>
                          c.withCredential(CloudAccountDrive.aliyun, ''));
                      if (mounted) _token.clear();
                    }),
          SettingsActionButton(
              label: '扫码登录',
              icon: Icons.qr_code_scanner_rounded,
              autofocus: true,
              focusId: 'aliyun:scan-login',
              onPressed: _busy ? null : _scanLogin),
          const SizedBox(height: 16),
          SettingsTextInputField(
              controller: _token,
              labelText: config.aliyunAuthMode == AliyunAuthMode.open
                  ? '阿里 Open Refresh Token'
                  : '阿里 Refresh Token',
              obscureText: true,
              autocorrect: false,
              focusId: 'aliyun:token'),
          const SizedBox(height: 16),
          SettingsToggleTile(
              title: '保存时转到 115 并删除阿里副本',
              subtitle: '全部校验成功后移入阿里回收站；失败时保留副本',
              value: config.aliyunTo115Enabled,
              focusId: 'aliyun:transfer-enabled',
              onChanged: _busy ? null : _setTransferEnabled),
          if (config.aliyunTo115Enabled) ...[
            Text('115 保存目录：${config.cloud115SaveFolderPath}'),
            if (config.cloud115Cookie.trim().isEmpty) const Text('115 账号未配置'),
            SettingsSelectionTile(
                title: '115 保存与后处理设置',
                value: '',
                onPressed: () =>
                    _openSettings(NetworkStorageEditorSection.cloud115)),
          ] else ...[
            SettingsSelectionTile(
                title: '阿里保存目录',
                value: config.aliyunSaveFolderPath,
                onPressed: _busy ? null : () => _browse()),
            SettingsSelectionTile(
                title: '阿里目录管理',
                value: '',
                onPressed: _busy ? null : () => _browse(manage: true)),
            SettingsTextInputField(
                controller: _task, labelText: '阿里 SmartStrm 任务名称'),
            StarflowButton(
                label: '测试阿里 STRM',
                icon: Icons.play_arrow_outlined,
                onPressed: _busy ? null : _testStrm),
            SettingsToggleTile(
                title: '同步删除阿里目录',
                value: config.syncDeleteAliyunEnabled,
                onChanged: _busy
                    ? null
                    : (value) => _updateConfig(
                        (c) => c.copyWith(syncDeleteAliyunEnabled: value))),
            if (config.syncDeleteAliyunEnabled &&
                config.syncDeleteAliyunWebDavDirectories.isEmpty)
              const Text('阿里同步删除未就绪：未选择 WebDAV 删除监听目录'),
            for (final source in ref
                .watch(appSettingsProvider)
                .mediaSources
                .where((s) => s.enabled && s.kind == MediaSourceKind.nas))
              SettingsSelectionTile(
                  title: '添加 WebDAV 监听目录',
                  value: source.name,
                  onPressed: _busy ? null : () => _addScope(source)),
            for (final scope in config.syncDeleteAliyunWebDavDirectories)
              ListTile(
                  title: Text(scope.sourceName),
                  subtitle: Text(scope.directoryLabel),
                  trailing: IconButton(
                      tooltip: '移除监听目录',
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: _busy
                          ? null
                          : () => _updateConfig((c) => c.copyWith(
                              syncDeleteAliyunWebDavDirectories: c
                                  .syncDeleteAliyunWebDavDirectories
                                  .where((s) =>
                                      s.sourceId != scope.sourceId ||
                                      s.directoryId != scope.directoryId)
                                  .toList())))),
          ],
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 12, children: [
            StarflowButton(
                label: '保存',
                icon: Icons.save_outlined,
                focusId: 'aliyun:save',
                onPressed: _busy ? null : () => _save()),
            StarflowButton(
                label: '保存并验证',
                icon: Icons.verified_user_outlined,
                focusId: 'aliyun:test',
                loading: _busy,
                onPressed: _busy ? null : () => _save(test: true)),
          ]),
          if (_status.isNotEmpty) Text(_status),
        ]);
  }
}
