import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/widgets/no_animation_page_route.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/search/data/cloud115_save_client.dart';
import 'package:starflow/features/search/data/smart_strm_webhook_client.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/quark_directory_manager_page.dart';
import 'package:starflow/features/settings/presentation/quark_folder_picker_page.dart';
import 'package:starflow/features/settings/presentation/settings_auto_save_coordinator.dart';
import 'package:starflow/features/settings/presentation/webdav_directory_picker_page.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_text_input_field.dart';

enum NetworkStorageEditorSection { quark, cloud115, smartStrm, synchronization }

class NetworkStorageSettingsPage extends ConsumerWidget {
  const NetworkStorageSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(
      appSettingsProvider.select((settings) => settings.networkStorage),
    );
    final theme = Theme.of(context);
    return SettingsPageScaffold(
      onBack: () => Navigator.of(context).pop(),
      children: [
        Text('网络存储', style: theme.textTheme.headlineSmall),
        const SettingsSectionTitle(label: '分类'),
        ...buildSettingsTileGroup([
          SettingsSelectionTile(
            title: '夸克云盘',
            subtitle: config.quarkCookie.trim().isEmpty
                ? 'Cookie 与保存目录未配置'
                : '保存目录：${config.quarkSaveFolderPath}',
            value: '',
            autofocus: true,
            focusId: 'network-storage:quark',
            onPressed: () => _openEditor(
              context,
              config,
              NetworkStorageEditorSection.quark,
            ),
          ),
          SettingsSelectionTile(
            title: '115 网盘',
            subtitle: config.cloud115Cookie.trim().isEmpty
                ? 'Cookie 与保存目录未配置'
                : '保存目录：${config.cloud115SaveFolderPath}',
            value: '',
            focusId: 'network-storage:115',
            onPressed: () => _openEditor(
                context, config, NetworkStorageEditorSection.cloud115),
          ),
          SettingsSelectionTile(
            title: 'SmartStrm',
            subtitle: config.smartStrmWebhookUrl.trim().isEmpty
                ? 'Webhook 未配置'
                : '夸克：${config.smartStrmTaskName.trim().isEmpty ? '未配置' : config.smartStrmTaskName} · '
                    '115：${config.cloud115SmartStrmTaskName.trim().isEmpty ? '未配置' : config.cloud115SmartStrmTaskName}',
            value: '',
            focusId: 'network-storage:smart-strm',
            onPressed: () => _openEditor(
              context,
              config,
              NetworkStorageEditorSection.smartStrm,
            ),
          ),
          SettingsSelectionTile(
            title: '同步与索引刷新',
            subtitle: '刷新来源 ${config.refreshMediaSourceIds.length} 个',
            value: '',
            focusId: 'network-storage:synchronization',
            onPressed: () => _openEditor(
              context,
              config,
              NetworkStorageEditorSection.synchronization,
            ),
          ),
        ]),
      ],
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    NetworkStorageConfig initial,
    NetworkStorageEditorSection section,
  ) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      SettingsMaterialPageRoute<void>(
        builder: (context) => NetworkStorageEditorPage(
          initial: initial,
          section: section,
        ),
      ),
    );
  }
}

class NetworkStorageEditorPage extends ConsumerStatefulWidget {
  const NetworkStorageEditorPage({
    super.key,
    required this.initial,
    required this.section,
  });

  final NetworkStorageConfig initial;
  final NetworkStorageEditorSection section;

  @override
  ConsumerState<NetworkStorageEditorPage> createState() =>
      _NetworkStorageEditorPageState();
}

class _NetworkStorageEditorPageState
    extends ConsumerState<NetworkStorageEditorPage> {
  late final TextEditingController _quarkCookieController;
  late final TextEditingController _smartStrmWebhookController;
  late final TextEditingController _smartStrmTaskNameController;
  late final TextEditingController _cloud115SmartStrmTaskNameController;
  late final TextEditingController _smartStrmDelayController;
  late final TextEditingController _refreshDelayController;
  late String _quarkFolderId;
  late String _quarkFolderPath;
  late bool _sanitizeSavedNamesEnabled;
  late final TextEditingController _sanitizedNameCharactersController;
  late bool _syncDeleteQuarkEnabled;
  late List<NetworkStorageWebDavDirectory> _syncDeleteQuarkWebDavDirectories;
  late Set<String> _refreshSourceIds;
  final SettingsAutoSaveCoordinator _autoSave = SettingsAutoSaveCoordinator();
  bool _isTestingQuarkConnection = false;
  bool _isTestingSmartStrm = false;
  bool _isTesting115SmartStrm = false;
  bool get _is115 => widget.section == NetworkStorageEditorSection.cloud115;
  String get _driveName => _is115 ? '115' : '夸克';

  @override
  void initState() {
    super.initState();
    _quarkCookieController = TextEditingController(
      text: _is115 ? widget.initial.cloud115Cookie : widget.initial.quarkCookie,
    );
    _smartStrmWebhookController = TextEditingController(
      text: widget.initial.smartStrmWebhookUrl,
    );
    _smartStrmTaskNameController = TextEditingController(
      text: widget.initial.smartStrmTaskName,
    );
    _cloud115SmartStrmTaskNameController = TextEditingController(
      text: widget.initial.cloud115SmartStrmTaskName,
    );
    _smartStrmDelayController = TextEditingController(
      text: widget.initial.smartStrmDelaySeconds > 0
          ? '${widget.initial.smartStrmDelaySeconds}'
          : '',
    );
    _refreshDelayController = TextEditingController(
      text: widget.initial.refreshDelaySeconds > 0
          ? '${widget.initial.refreshDelaySeconds}'
          : '',
    );
    _quarkFolderId = widget.initial.quarkSaveFolderId.trim().isEmpty
        ? '0'
        : widget.initial.quarkSaveFolderId.trim();
    _quarkFolderPath = widget.initial.quarkSaveFolderPath.trim().isEmpty
        ? '/'
        : widget.initial.quarkSaveFolderPath.trim();
    if (_is115) {
      _quarkFolderId = widget.initial.cloud115SaveFolderId;
      _quarkFolderPath = widget.initial.cloud115SaveFolderPath;
    }
    _sanitizeSavedNamesEnabled = widget.initial.quarkSanitizeSavedNamesEnabled;
    _sanitizedNameCharactersController = TextEditingController(
      text: widget.initial.quarkSanitizedNameCharacters,
    );
    _syncDeleteQuarkEnabled = _is115
        ? widget.initial.syncDelete115Enabled
        : widget.initial.syncDeleteQuarkEnabled;
    _syncDeleteQuarkWebDavDirectories = [
      ...(_is115
          ? widget.initial.syncDelete115WebDavDirectories
          : widget.initial.syncDeleteQuarkWebDavDirectories),
    ];
    _refreshSourceIds = widget.initial.refreshMediaSourceIds.toSet();
    for (final controller in _draftTextControllers) {
      controller.addListener(_scheduleAutoSave);
    }
    _autoSave.markCurrentAsSaved(_draftFingerprint(widget.initial));
  }

  @override
  void dispose() {
    for (final controller in _draftTextControllers) {
      controller.removeListener(_scheduleAutoSave);
    }
    _autoSave.dispose();
    _quarkCookieController.dispose();
    _sanitizedNameCharactersController.dispose();
    _smartStrmWebhookController.dispose();
    _smartStrmTaskNameController.dispose();
    _cloud115SmartStrmTaskNameController.dispose();
    _smartStrmDelayController.dispose();
    _refreshDelayController.dispose();
    super.dispose();
  }

  List<TextEditingController> get _draftTextControllers => [
        _quarkCookieController,
        _sanitizedNameCharactersController,
        _smartStrmWebhookController,
        _smartStrmTaskNameController,
        _cloud115SmartStrmTaskNameController,
        _smartStrmDelayController,
        _refreshDelayController,
      ];

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _scheduleAutoSave();
  }

  String _draftFingerprint(NetworkStorageConfig draft) =>
      jsonEncode(draft.toJson());

  void _scheduleAutoSave() {
    if (!mounted) {
      return;
    }
    final draft = _buildDraft();
    final controller = ref.read(settingsControllerProvider.notifier);
    _autoSave.schedule(
      fingerprint: _draftFingerprint(draft),
      save: () => controller.saveNetworkStorage(draft),
    );
  }

  void _flushAutoSave() {
    if (!mounted) {
      return;
    }
    final draft = _buildDraft();
    final controller = ref.read(settingsControllerProvider.notifier);
    _autoSave.flush(
      fingerprint: _draftFingerprint(draft),
      save: () => controller.saveNetworkStorage(draft),
    );
  }

  void _closePage() {
    _flushAutoSave();
    Navigator.of(context).pop();
  }

  List<MediaSourceConfig> _refreshableMediaSources(AppSettings settings) {
    return settings.mediaSources
        .where(
          (source) =>
              source.enabled &&
              (source.kind == MediaSourceKind.emby ||
                  source.kind == MediaSourceKind.nas ||
                  (source.kind == MediaSourceKind.quark &&
                      source.hasConfiguredQuarkFolder)),
        )
        .toList(growable: false);
  }

  List<MediaSourceConfig> _syncDeleteWebDavSources(AppSettings settings) {
    return settings.mediaSources
        .where(
          (source) => source.enabled && source.kind == MediaSourceKind.nas,
        )
        .toList(growable: false);
  }

  int _refreshDelaySeconds() {
    return _parseDelaySeconds(_refreshDelayController.text);
  }

  int _smartStrmDelaySeconds() {
    return _parseDelaySeconds(_smartStrmDelayController.text);
  }

  int _parseDelaySeconds(String rawText) {
    final text = rawText.trim();
    if (text.isEmpty) {
      return 1;
    }
    final parsed = int.tryParse(text) ?? 1;
    return parsed <= 0 ? 1 : parsed;
  }

  NetworkStorageConfig _buildDraft() {
    final settings = ref.read(appSettingsProvider);
    final refreshableSourceIds =
        _refreshableMediaSources(settings).map((source) => source.id).toSet();
    return widget.initial.copyWith(
      cloud115Cookie: _is115 ? _quarkCookieController.text.trim() : null,
      cloud115SaveFolderId: _is115 ? _quarkFolderId : null,
      cloud115SaveFolderPath: _is115 ? _quarkFolderPath : null,
      quarkCookie: _is115 ? null : _quarkCookieController.text.trim(),
      quarkSaveFolderId: _is115 ? null : _quarkFolderId,
      quarkSaveFolderPath: _is115 ? null : _quarkFolderPath,
      quarkSanitizeSavedNamesEnabled: _sanitizeSavedNamesEnabled,
      quarkSanitizedNameCharacters:
          _sanitizedNameCharactersController.text.trim(),
      syncDelete115Enabled: _is115 ? _syncDeleteQuarkEnabled : null,
      syncDelete115WebDavDirectories:
          _is115 ? _normalizedSyncDeleteDirectories(settings) : null,
      syncDeleteQuarkEnabled: _is115 ? null : _syncDeleteQuarkEnabled,
      syncDeleteQuarkWebDavDirectories: _is115
          ? null
          : _normalizedSyncDeleteDirectories(
              settings,
            ),
      smartStrmWebhookUrl: _smartStrmWebhookController.text.trim(),
      smartStrmTaskName: _smartStrmTaskNameController.text.trim(),
      cloud115SmartStrmTaskName:
          _cloud115SmartStrmTaskNameController.text.trim(),
      smartStrmDelaySeconds: _smartStrmDelaySeconds(),
      refreshMediaSourceIds: _refreshSourceIds
          .where(refreshableSourceIds.contains)
          .toList(growable: false),
      refreshDelaySeconds: _refreshDelaySeconds(),
    );
  }

  List<NetworkStorageWebDavDirectory> _normalizedSyncDeleteDirectories(
    AppSettings settings,
  ) {
    final sourceNameById = {
      for (final source in settings.mediaSources)
        source.id.trim(): source.name.trim(),
    };
    final seen = <String>{};
    final normalized = <NetworkStorageWebDavDirectory>[];
    for (final item in _syncDeleteQuarkWebDavDirectories) {
      final sourceId = item.sourceId.trim();
      final directoryId = item.directoryId.trim();
      if (sourceId.isEmpty || directoryId.isEmpty) {
        continue;
      }
      final dedupeKey = '$sourceId::$directoryId';
      if (!seen.add(dedupeKey)) {
        continue;
      }
      final resolvedSourceName =
          sourceNameById[sourceId]?.trim().isNotEmpty == true
              ? sourceNameById[sourceId]!.trim()
              : item.sourceName.trim();
      final resolvedDirectoryLabel = item.directoryLabel.trim().isNotEmpty
          ? item.directoryLabel.trim()
          : _pathLabel(directoryId);
      normalized.add(
        NetworkStorageWebDavDirectory(
          sourceId: sourceId,
          sourceName: resolvedSourceName,
          directoryId: directoryId,
          directoryLabel: resolvedDirectoryLabel,
        ),
      );
    }
    return normalized;
  }

  String _pathLabel(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) {
      return raw.trim();
    }
    final path = uri.path.isEmpty ? '/' : uri.path;
    return '${uri.host}$path';
  }

  Future<void> _testQuarkConnection() async {
    FocusScope.of(context).unfocus();
    final cookie = _quarkCookieController.text.trim();
    if (cookie.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请先填写 $_driveName Cookie')),
      );
      return;
    }

    setState(() => _isTestingQuarkConnection = true);
    try {
      String summary;
      if (_is115) {
        await ref
            .read(cloud115SaveClientProvider)
            .listDirectories(cookie: cookie);
        summary = '目录访问正常';
      } else {
        final status = await ref.read(quarkSaveClientProvider).testConnection(
              cookie: cookie,
            );
        summary = status.summary;
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$_driveName 连接成功 · $summary')),
      );
    } on QuarkSaveException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } finally {
      if (mounted) {
        setState(() => _isTestingQuarkConnection = false);
      }
    }
  }

  Future<void> _pickQuarkFolder() async {
    FocusScope.of(context).unfocus();
    final cookie = _quarkCookieController.text.trim();
    if (cookie.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请先填写 $_driveName Cookie')),
      );
      return;
    }

    final picked = await Navigator.of(context).push<QuarkDirectoryEntry>(
      SettingsMaterialPageRoute(
        builder: (context) => QuarkFolderPickerPage(
          cookie: cookie,
          initialFid: _is115 ? '0' : _quarkFolderId,
          initialPath: _is115 ? '/' : _quarkFolderPath,
          directoryLoader: _is115
              ? (id, path) => ref
                  .read(cloud115SaveClientProvider)
                  .listDirectories(
                      cookie: cookie, parentFid: id, parentPath: path)
              : null,
        ),
      ),
    );
    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      _quarkFolderId = picked.fid;
      _quarkFolderPath = picked.path;
    });
  }

  Future<void> _openQuarkDirectoryManager() async {
    FocusScope.of(context).unfocus();
    final cookie = _quarkCookieController.text.trim();
    if (cookie.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请先填写 $_driveName Cookie')),
      );
      return;
    }

    await Navigator.of(context).push<void>(
      SettingsMaterialPageRoute(
        builder: (context) => QuarkDirectoryManagerPage(
          cloud115: _is115,
          cookie: cookie,
          initialFid: _quarkFolderId,
          initialPath: _quarkFolderPath,
        ),
      ),
    );
  }

  Future<void> _pickSyncDeleteWebDavDirectory(MediaSourceConfig source) async {
    FocusScope.of(context).unfocus();
    final initialPath = _syncDeleteQuarkWebDavDirectories
            .lastWhere(
              (item) => item.sourceId == source.id,
              orElse: () => NetworkStorageWebDavDirectory(
                sourceId: source.id,
                directoryId: source.libraryPath.trim(),
              ),
            )
            .directoryId
            .trim()
            .isNotEmpty
        ? _syncDeleteQuarkWebDavDirectories
            .lastWhere(
              (item) => item.sourceId == source.id,
              orElse: () => NetworkStorageWebDavDirectory(
                sourceId: source.id,
                directoryId: source.libraryPath.trim(),
              ),
            )
            .directoryId
            .trim()
        : source.libraryPath.trim();
    final picked = await Navigator.of(context).push<String>(
      SettingsMaterialPageRoute<String>(
        builder: (context) => WebDavDirectoryPickerPage(
          source: source,
          initialPath: initialPath,
        ),
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    final trimmed = picked.trim();
    if (trimmed.isEmpty) {
      return;
    }
    setState(() {
      _syncDeleteQuarkWebDavDirectories = [
        ..._syncDeleteQuarkWebDavDirectories,
        NetworkStorageWebDavDirectory(
          sourceId: source.id,
          sourceName: source.name,
          directoryId: trimmed,
          directoryLabel: _pathLabel(trimmed),
        ),
      ];
    });
  }

  void _removeSyncDeleteWebDavDirectory(NetworkStorageWebDavDirectory target) {
    setState(() {
      _syncDeleteQuarkWebDavDirectories = _syncDeleteQuarkWebDavDirectories
          .where(
            (item) =>
                item.sourceId != target.sourceId ||
                item.directoryId != target.directoryId,
          )
          .toList(growable: false);
    });
  }

  Future<void> _testSmartStrmTask({bool cloud115 = false}) async {
    FocusScope.of(context).unfocus();
    void setTesting(bool value) => setState(() {
          if (cloud115) {
            _isTesting115SmartStrm = value;
          } else {
            _isTestingSmartStrm = value;
          }
        });
    setTesting(true);
    final driveName = cloud115 ? '115' : '夸克';
    final storagePath = _quarkFolderPath.trim();
    try {
      final result = await ref.read(smartStrmWebhookClientProvider).triggerTask(
            webhookUrl: _smartStrmWebhookController.text.trim(),
            taskName: (cloud115
                    ? _cloud115SmartStrmTaskNameController
                    : _smartStrmTaskNameController)
                .text
                .trim(),
            storagePath: storagePath == '/' ? '' : storagePath,
            delay: _smartStrmDelaySeconds(),
          );
      if (!mounted) {
        return;
      }
      final message = result.addedCount != null
          ? 'SmartStrm 任务触发成功 · 新增 ${result.addedCount} 条'
          : result.message.trim().isNotEmpty
              ? 'SmartStrm ${result.message.trim()}'
              : 'SmartStrm 任务触发成功';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$driveName $message')),
      );
    } on SmartStrmWebhookException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$driveName ${error.message}')),
      );
    } finally {
      if (mounted) {
        setTesting(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final refreshableSources = _refreshableMediaSources(settings);
    final syncDeleteWebDavSources = _syncDeleteWebDavSources(settings);
    final selectedSyncDeleteDirectories =
        _normalizedSyncDeleteDirectories(settings);
    final refreshableSourceIds =
        refreshableSources.map((source) => source.id).toSet();
    final selectedRefreshSourceIds =
        _refreshSourceIds.intersection(refreshableSourceIds);

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
            switch (widget.section) {
              NetworkStorageEditorSection.quark => '夸克云盘',
              NetworkStorageEditorSection.cloud115 => '115 网盘',
              NetworkStorageEditorSection.smartStrm => 'SmartStrm',
              NetworkStorageEditorSection.synchronization => '同步与索引刷新',
            },
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (widget.section == NetworkStorageEditorSection.quark ||
              _is115) ...[
            SettingsSectionTitle(label: '$_driveName 保存'),
            SettingsTextInputField(
              controller: _quarkCookieController,
              labelText: '$_driveName Cookie',
              minLines: 2,
              maxLines: 4,
              autocorrect: false,
              hintText:
                  _is115 ? 'UID=...; CID=...; SEID=...' : '用于搜索结果一键保存到夸克网盘',
              summaryBuilder: (value) => value.isEmpty ? '未填写' : '已填写',
              autofocus: true,
              focusId: 'network-storage-quark:cookie',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SettingsActionButton(
                  label: _isTestingQuarkConnection
                      ? '测试中...'
                      : '测试 $_driveName 连接',
                  icon: Icons.cloud_done_outlined,
                  onPressed:
                      _isTestingQuarkConnection ? null : _testQuarkConnection,
                ),
                SettingsActionButton(
                  label: '选择默认保存文件夹',
                  icon: Icons.folder_open_rounded,
                  onPressed: _pickQuarkFolder,
                ),
                SettingsActionButton(
                  label: '管理当前保存目录',
                  icon: Icons.delete_outline_rounded,
                  onPressed: _openQuarkDirectoryManager,
                  variant: StarflowButtonVariant.ghost,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('默认保存到：$_quarkFolderPath'),
            const SizedBox(height: 12),
            const SettingsSectionTitle(label: 'SmartStrm 任务'),
            SettingsTextInputField(
              controller: _is115
                  ? _cloud115SmartStrmTaskNameController
                  : _smartStrmTaskNameController,
              labelText: '$_driveName SmartStrm 任务名',
              focusId: 'network-storage-$_driveName:strm-task',
            ),
            const SizedBox(height: 12),
            SettingsActionButton(
              label: (_is115 ? _isTesting115SmartStrm : _isTestingSmartStrm)
                  ? '测试中...'
                  : '测试 $_driveName STRM 任务',
              icon: Icons.bolt_rounded,
              onPressed: (_is115 ? _isTesting115SmartStrm : _isTestingSmartStrm)
                  ? null
                  : () => _testSmartStrmTask(cloud115: _is115),
            ),
          ],
          if (widget.section == NetworkStorageEditorSection.quark) ...[
            const SizedBox(height: 12),
            const SettingsSectionTitle(label: '保存后修正名称'),
            StarflowToggleTile(
              title: '转存后自动修正名称',
              subtitle: '转存完成、触发 SmartStrm 之前，把新存入的目录名和文件名里的特殊字符去掉。'
                  '路径里的 # 会截断直链并导致签名校验失败，是这类播放失败最常见的原因。'
                  '这会直接重命名夸克网盘里的真实文件，只作用于本次新存入的内容。',
              value: _sanitizeSavedNamesEnabled,
              focusId: 'network-storage-quark:sanitize',
              onChanged: (value) {
                setState(() {
                  _sanitizeSavedNamesEnabled = value;
                });
              },
            ),
            if (_sanitizeSavedNamesEnabled) ...[
              const SizedBox(height: 12),
              SettingsTextInputField(
                controller: _sanitizedNameCharactersController,
                labelText: '要去掉的字符',
                autocorrect: false,
                hintText: kDefaultQuarkSanitizedNameCharacters,
                summaryBuilder: (value) => value.isEmpty ? '未填写（不会改名）' : value,
                focusId: 'network-storage-quark:sanitize-characters',
              ),
              const SizedBox(height: 8),
              Text(
                '逐个字符匹配，不是正则。留空则不改名。'
                '只处理本次转存新存入的内容，已经在网盘里的旧文件不会被碰；'
                '开启后转存去重也改按净化后的名字比对，不会重复保存；'
                '同名冲突会跳过并在结果里提示。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ],
          if (widget.section == NetworkStorageEditorSection.quark ||
              _is115) ...[
            const SettingsSectionTitle(label: '同步删除'),
            StarflowToggleTile(
              title: '同步删除$_driveName目录',
              subtitle: _is115
                  ? '删除监听范围内的 WebDAV 资源时，按相对路径同步删除 115 保存目录中的对应资源。'
                  : '开启后，删除命中下方监听目录中的 WebDAV 文件或文件夹时，也会到当前夸克保存目录里删除匹配到的影片或剧集目录。',
              value: _syncDeleteQuarkEnabled,
              autofocus: true,
              focusId: 'network-storage-sync:delete',
              onChanged: (value) {
                setState(() {
                  _syncDeleteQuarkEnabled = value;
                });
              },
            ),
            const SizedBox(height: 12),
            const SettingsSectionTitle(label: 'WebDAV 删除监听目录'),
            Text(
              '只会在这里选中的 WebDAV 目录范围内触发$_driveName同步删除。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            if (syncDeleteWebDavSources.isNotEmpty)
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final source in syncDeleteWebDavSources)
                    SettingsActionButton(
                      label: '添加 ${source.name}',
                      icon: Icons.folder_open_rounded,
                      onPressed: () => _pickSyncDeleteWebDavDirectory(source),
                      variant: StarflowButtonVariant.ghost,
                    ),
                ],
              )
            else
              const Text('无已启用的 WebDAV 来源'),
            const SizedBox(height: 12),
            if (selectedSyncDeleteDirectories.isNotEmpty)
              ...selectedSyncDeleteDirectories.map(
                (directory) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SettingsSelectionTile(
                    title: directory.sourceName.isEmpty
                        ? directory.sourceId
                        : directory.sourceName,
                    subtitle: directory.directoryLabel.isEmpty
                        ? _pathLabel(directory.directoryId)
                        : directory.directoryLabel,
                    value: '监听中',
                    onPressed: null,
                    leading: const Icon(Icons.folder_copy_outlined),
                    trailing: IconButton(
                      tooltip: '移除',
                      onPressed: () =>
                          _removeSyncDeleteWebDavDirectory(directory),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ),
                ),
              )
            else
              const Text('未选择目录'),
          ],
          if (widget.section == NetworkStorageEditorSection.smartStrm) ...[
            const SettingsSectionTitle(label: '公共配置'),
            SettingsTextInputField(
              controller: _smartStrmWebhookController,
              labelText: 'Webhook 地址',
              keyboardType: TextInputType.url,
              autocorrect: false,
              hintText: 'http://yourip:8024/webhook/abcdef123456',
              autofocus: true,
              focusId: 'network-storage-smart-strm:webhook',
            ),
            const SizedBox(height: 12),
            SettingsSelectionTile(
              title: 'STRM 触发等待时间',
              subtitle: '保存到夸克或 115 后，等待多久再触发 Smart STRM 任务。',
              value: '${_smartStrmDelaySeconds()} 秒',
              onPressed: _openSmartStrmDelayPicker,
            ),
          ],
          if (widget.section ==
              NetworkStorageEditorSection.synchronization) ...[
            const SettingsSectionTitle(label: '自动增量刷新索引'),
            SettingsSelectionTile(
              title: '索引刷新等待时间',
              subtitle: '任务结束后，等待多久再自动执行媒体库增量刷新。',
              value: '${_refreshDelaySeconds()} 秒',
              onPressed: _openRefreshDelayPicker,
            ),
            const SizedBox(height: 12),
            if (refreshableSources.isNotEmpty) ...[
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SettingsActionButton(
                    label: '全选',
                    icon: Icons.select_all_rounded,
                    onPressed: () {
                      setState(() {
                        _refreshSourceIds = refreshableSourceIds;
                      });
                    },
                    variant: StarflowButtonVariant.ghost,
                  ),
                  SettingsActionButton(
                    label: '清空',
                    icon: Icons.clear_all_rounded,
                    onPressed: () {
                      setState(() {
                        _refreshSourceIds.clear();
                      });
                    },
                    variant: StarflowButtonVariant.ghost,
                  ),
                ],
              ),
              ...refreshableSources.map(
                (source) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: StarflowCheckboxTile(
                    title: source.name,
                    value: selectedRefreshSourceIds.contains(source.id),
                    onChanged: (value) {
                      setState(() {
                        final next = {..._refreshSourceIds};
                        if (value) {
                          next.add(source.id);
                        } else {
                          next.remove(source.id);
                        }
                        _refreshSourceIds = next;
                      });
                    },
                  ),
                ),
              ),
            ] else
              const Text('无'),
          ],
        ],
      ),
    );
  }

  Future<void> _openRefreshDelayPicker() async {
    const options = [1, 3, 5, 10, 15, 30, 60];
    final selected = await showSettingsOptionDialog<int>(
      context: context,
      title: '选择索引刷新等待时间',
      options: options,
      currentValue: _refreshDelaySeconds(),
      labelBuilder: (seconds) => '$seconds 秒',
    );
    if (selected == null) return;
    setState(() {
      _refreshDelayController.text = '$selected';
    });
  }

  Future<void> _openSmartStrmDelayPicker() async {
    const options = [1, 3, 5, 10, 15, 30, 60];
    final selected = await showSettingsOptionDialog<int>(
      context: context,
      title: '选择 STRM 触发等待时间',
      options: options,
      currentValue: _smartStrmDelaySeconds(),
      labelBuilder: (seconds) => '$seconds 秒',
    );
    if (selected == null) return;
    setState(() {
      _smartStrmDelayController.text = '$selected';
    });
  }
}
