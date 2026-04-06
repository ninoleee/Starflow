import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/search/data/smart_strm_webhook_client.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/quark_directory_manager_page.dart';
import 'package:starflow/features/settings/presentation/quark_folder_picker_page.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_text_input_field.dart';

class NetworkStorageSettingsPage extends ConsumerStatefulWidget {
  const NetworkStorageSettingsPage({super.key, required this.initial});

  final NetworkStorageConfig initial;

  @override
  ConsumerState<NetworkStorageSettingsPage> createState() =>
      _NetworkStorageSettingsPageState();
}

class _NetworkStorageSettingsPageState
    extends ConsumerState<NetworkStorageSettingsPage> {
  late final TextEditingController _quarkCookieController;
  late final TextEditingController _smartStrmWebhookController;
  late final TextEditingController _smartStrmTaskNameController;
  late final TextEditingController _smartStrmDelayController;
  late final TextEditingController _refreshDelayController;
  late String _quarkFolderId;
  late String _quarkFolderPath;
  late bool _syncDeleteQuarkEnabled;
  late Set<String> _refreshSourceIds;
  bool _skipAutoSaveOnPop = false;
  bool _isTestingQuarkConnection = false;
  bool _isTestingSmartStrm = false;

  @override
  void initState() {
    super.initState();
    _quarkCookieController = TextEditingController(
      text: widget.initial.quarkCookie,
    );
    _smartStrmWebhookController = TextEditingController(
      text: widget.initial.smartStrmWebhookUrl,
    );
    _smartStrmTaskNameController = TextEditingController(
      text: widget.initial.smartStrmTaskName,
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
    _syncDeleteQuarkEnabled = widget.initial.syncDeleteQuarkEnabled;
    _refreshSourceIds = widget.initial.refreshMediaSourceIds.toSet();
  }

  @override
  void dispose() {
    _quarkCookieController.dispose();
    _smartStrmWebhookController.dispose();
    _smartStrmTaskNameController.dispose();
    _smartStrmDelayController.dispose();
    _refreshDelayController.dispose();
    super.dispose();
  }

  List<MediaSourceConfig> _refreshableMediaSources(AppSettings settings) {
    return settings.mediaSources
        .where(
          (source) =>
              source.enabled &&
              (source.kind == MediaSourceKind.emby ||
                  source.kind == MediaSourceKind.nas),
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
    final refreshableSourceIds = _refreshableMediaSources(
      ref.read(appSettingsProvider),
    ).map((source) => source.id).toSet();
    return NetworkStorageConfig(
      quarkCookie: _quarkCookieController.text.trim(),
      quarkSaveFolderId: _quarkFolderId,
      quarkSaveFolderPath: _quarkFolderPath,
      syncDeleteQuarkEnabled: _syncDeleteQuarkEnabled,
      smartStrmWebhookUrl: _smartStrmWebhookController.text.trim(),
      smartStrmTaskName: _smartStrmTaskNameController.text.trim(),
      smartStrmDelaySeconds: _smartStrmDelaySeconds(),
      refreshMediaSourceIds: _refreshSourceIds
          .where(refreshableSourceIds.contains)
          .toList(growable: false),
      refreshDelaySeconds: _refreshDelaySeconds(),
    );
  }

  Future<void> _saveDraft({bool popAfterSave = true}) async {
    await ref
        .read(settingsControllerProvider.notifier)
        .saveNetworkStorage(_buildDraft());
    if (popAfterSave && mounted) {
      _skipAutoSaveOnPop = true;
      Navigator.of(context).pop();
    }
  }

  bool _hasUnsavedChanges() {
    return jsonEncode(_buildDraft().toJson()) !=
        jsonEncode(widget.initial.toJson());
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

  Future<void> _testQuarkConnection() async {
    FocusScope.of(context).unfocus();
    final cookie = _quarkCookieController.text.trim();
    if (cookie.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写夸克 Cookie')),
      );
      return;
    }

    setState(() => _isTestingQuarkConnection = true);
    try {
      final status = await ref.read(quarkSaveClientProvider).testConnection(
            cookie: cookie,
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('夸克连接成功 · ${status.summary}')),
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
        const SnackBar(content: Text('请先填写夸克 Cookie')),
      );
      return;
    }

    final picked = await Navigator.of(context).push<QuarkDirectoryEntry>(
      MaterialPageRoute(
        builder: (context) => QuarkFolderPickerPage(
          cookie: cookie,
          initialFid: _quarkFolderId,
          initialPath: _quarkFolderPath,
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
        const SnackBar(content: Text('请先填写夸克 Cookie')),
      );
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => QuarkDirectoryManagerPage(
          cookie: cookie,
          initialFid: _quarkFolderId,
          initialPath: _quarkFolderPath,
        ),
      ),
    );
  }

  Future<void> _testSmartStrmTask() async {
    FocusScope.of(context).unfocus();
    setState(() => _isTestingSmartStrm = true);
    try {
      final result = await ref.read(smartStrmWebhookClientProvider).triggerTask(
            webhookUrl: _smartStrmWebhookController.text.trim(),
            taskName: _smartStrmTaskNameController.text.trim(),
            storagePath: _quarkFolderPath == '/' ? '' : _quarkFolderPath,
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
        SnackBar(content: Text(message)),
      );
    } on SmartStrmWebhookException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } finally {
      if (mounted) {
        setState(() => _isTestingSmartStrm = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final refreshableSources = _refreshableMediaSources(settings);
    final refreshableSourceIds =
        refreshableSources.map((source) => source.id).toSet();
    final selectedRefreshSourceIds =
        _refreshSourceIds.intersection(refreshableSourceIds);

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
          const SettingsSectionTitle(label: '夸克保存'),
          SettingsTextInputField(
            controller: _quarkCookieController,
            labelText: '夸克 Cookie',
            minLines: 2,
            maxLines: 4,
            autocorrect: false,
            hintText: '用于搜索结果一键保存到夸克网盘',
            summaryBuilder: (value) => value.isEmpty ? '未填写' : '已填写',
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SettingsActionButton(
                label: _isTestingQuarkConnection ? '测试中...' : '测试夸克连接',
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
          StarflowToggleTile(
            title: '同步删除夸克目录',
            subtitle:
                '开启后，删除已匹配到夸克直链的 WebDAV .strm 文件时，也会到当前夸克保存目录里删除对应影片或剧集目录。',
            value: _syncDeleteQuarkEnabled,
            onChanged: (value) {
              setState(() {
                _syncDeleteQuarkEnabled = value;
              });
            },
          ),
          const SettingsSectionTitle(label: 'SmartStrm'),
          SettingsTextInputField(
            controller: _smartStrmWebhookController,
            labelText: 'Webhook 地址',
            keyboardType: TextInputType.url,
            autocorrect: false,
            hintText: 'http://yourip:8024/webhook/abcdef123456',
          ),
          const SizedBox(height: 12),
          SettingsTextInputField(
            controller: _smartStrmTaskNameController,
            labelText: '任务名',
            hintText: 'movie_task',
          ),
          const SizedBox(height: 12),
          SettingsSelectionTile(
            title: 'STRM 触发等待时间',
            subtitle: '保存到夸克后，等待多久再触发 Smart STRM 任务。',
            value: '${_smartStrmDelaySeconds()} 秒',
            onPressed: _openSmartStrmDelayPicker,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SettingsActionButton(
                label: _isTestingSmartStrm ? '测试中...' : '测试 STRM 任务',
                icon: Icons.bolt_rounded,
                onPressed: _isTestingSmartStrm ? null : _testSmartStrmTask,
              ),
            ],
          ),
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
