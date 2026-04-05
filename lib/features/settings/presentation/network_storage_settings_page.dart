import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/search/data/smart_strm_webhook_client.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/quark_folder_picker_page.dart';
import 'package:starflow/features/settings/presentation/smart_strm_logs_page.dart';

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
  late final TextEditingController _refreshDelayController;
  late String _quarkFolderId;
  late String _quarkFolderPath;
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
    _refreshSourceIds = widget.initial.refreshMediaSourceIds.toSet();
  }

  @override
  void dispose() {
    _quarkCookieController.dispose();
    _smartStrmWebhookController.dispose();
    _smartStrmTaskNameController.dispose();
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
    final text = _refreshDelayController.text.trim();
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
      smartStrmWebhookUrl: _smartStrmWebhookController.text.trim(),
      smartStrmTaskName: _smartStrmTaskNameController.text.trim(),
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

  Future<void> _testSmartStrmTask() async {
    FocusScope.of(context).unfocus();
    setState(() => _isTestingSmartStrm = true);
    try {
      final result = await ref.read(smartStrmWebhookClientProvider).triggerTask(
            webhookUrl: _smartStrmWebhookController.text.trim(),
            taskName: _smartStrmTaskNameController.text.trim(),
            storagePath: _quarkFolderPath == '/' ? '' : _quarkFolderPath,
            delay: _refreshDelaySeconds(),
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
    final theme = Theme.of(context);
    final settings = ref.watch(appSettingsProvider);
    final refreshableSources = _refreshableMediaSources(settings);
    final refreshableSourceIds =
        refreshableSources.map((source) => source.id).toSet();
    final selectedRefreshSourceIds =
        _refreshSourceIds.intersection(refreshableSourceIds);

    return PopScope<void>(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop || _skipAutoSaveOnPop) {
          return;
        }
        _saveDraft(popAfterSave: false);
      },
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            ListView(
              padding: overlayToolbarPagePadding(context),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                _SectionTitle(theme: theme, label: '夸克保存'),
                TextField(
                  controller: _quarkCookieController,
                  minLines: 2,
                  maxLines: 4,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: '夸克 Cookie',
                    hintText: '用于搜索结果一键保存到夸克网盘',
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _isTestingQuarkConnection
                          ? null
                          : _testQuarkConnection,
                      icon: _isTestingQuarkConnection
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_done_outlined),
                      label: Text(
                        _isTestingQuarkConnection ? '测试中...' : '测试夸克连接',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pickQuarkFolder,
                      icon: const Icon(Icons.folder_open_rounded),
                      label: const Text('选择默认保存文件夹'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('默认保存到：$_quarkFolderPath'),
                _SectionTitle(theme: theme, label: 'SmartStrm'),
                TextField(
                  controller: _smartStrmWebhookController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Webhook 地址',
                    hintText: 'http://yourip:8024/webhook/abcdef123456',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _smartStrmTaskNameController,
                  decoration: const InputDecoration(
                    labelText: '任务名',
                    hintText: 'movie_task',
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed:
                          _isTestingSmartStrm ? null : _testSmartStrmTask,
                      icon: _isTestingSmartStrm
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.bolt_rounded),
                      label: Text(
                        _isTestingSmartStrm ? '测试中...' : '测试 STRM 任务',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const SmartStrmLogsPage(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.receipt_long_rounded),
                      label: const Text('查看日志'),
                    ),
                  ],
                ),
                _SectionTitle(theme: theme, label: '刷新媒体源'),
                TextField(
                  controller: _refreshDelayController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '延迟刷新秒数',
                    hintText: '1',
                  ),
                ),
                const SizedBox(height: 12),
                if (refreshableSources.isNotEmpty) ...[
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _refreshSourceIds = refreshableSourceIds;
                          });
                        },
                        child: const Text('全选'),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _refreshSourceIds.clear();
                          });
                        },
                        child: const Text('清空'),
                      ),
                    ],
                  ),
                  ...refreshableSources.map(
                    (source) => CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: selectedRefreshSourceIds.contains(source.id),
                      title: Text(source.name),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (value) {
                        setState(() {
                          final next = {..._refreshSourceIds};
                          if (value == true) {
                            next.add(source.id);
                          } else {
                            next.remove(source.id);
                          }
                          _refreshSourceIds = next;
                        });
                      },
                    ),
                  ),
                ] else
                  const Text('无'),
              ],
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: OverlayToolbar(
                trailing: TextButton(
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
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.theme, required this.label});

  final ThemeData theme;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
