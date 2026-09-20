import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_text_input_field.dart';
import '../data/live_repository.dart';
import '../data/live_playlist_parser.dart';
import '../data/live_playlist_transfer_service.dart';
import '../domain/live_models.dart';
import 'live_playlist_transfer_dialog.dart';
import 'live_widgets.dart';
import 'live_backup_dialog.dart';

class LiveSourcesPage extends ConsumerStatefulWidget {
  const LiveSourcesPage({super.key});
  @override
  ConsumerState<LiveSourcesPage> createState() => _LiveSourcesPageState();
}

class _LiveSourcesPageState extends ConsumerState<LiveSourcesPage> {
  final _busy = <String>{};
  final _toggling = <String>{};

  Future<void> _setEnabled(LiveSource source, bool enabled) async {
    if (_toggling.contains(source.id)) return;
    setState(() => _toggling.add(source.id));
    try {
      await ref.read(liveRepositoryProvider).setSourceEnabled(source.id, enabled);
    } catch (_) {
      if (mounted) liveMessage(context, '订阅状态保存失败，请重试');
    } finally {
      if (mounted) setState(() => _toggling.remove(source.id));
    }
  }

  Future<void> _refresh(LiveSource source) async {
    if (_busy.contains(source.id)) return;
    setState(() => _busy.add(source.id));
    try {
      await ref.read(liveRepositoryProvider).refresh(source.id);
      if (mounted) liveMessage(context, '已更新 ${source.name}');
    } catch (_) {
      if (mounted) liveMessage(context, '更新未完成，已保留可用频道和节目单');
    } finally {
      if (mounted) setState(() => _busy.remove(source.id));
    }
  }

  Future<void> _edit([LiveSource? source]) async {
    final saved = await Navigator.of(context).push<LiveSource>(
        MaterialPageRoute(builder: (_) => _SourceEditor(source: source)));
    if (mounted &&
        saved != null &&
        saved.enabled &&
        (saved.url.isNotEmpty || saved.effectiveEpgUrl.isNotEmpty)) {
      await _refresh(saved);
    }
  }

  Future<void> _remove(LiveSource source) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: Text('删除 ${source.name}？'),
                content: const Text('将移除此订阅的频道、收藏和节目单。'),
                actions: [
                  StarflowButton(
                      label: '取消',
                      autofocus: true,
                      onPressed: () => Navigator.pop(c, false)),
                  StarflowButton(
                      label: '删除', onPressed: () => Navigator.pop(c, true)),
                ]));
    if (confirmed == true && mounted) {
      try {
        await ref.read(liveRepositoryProvider).removeSource(source.id);
      } catch (_) {
        if (mounted) liveMessage(context, '删除失败');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('直播订阅'), actions: [
        LiveIconButton(
            icon: Icons.settings_backup_restore,
            label: '直播备份与恢复',
            onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => LiveBackupDialog(
                    repository: ref.read(liveRepositoryProvider),
                    isTelevision:
                        ref.read(isTelevisionProvider).value ?? false))),
        LiveIconButton(
            icon: Icons.add,
            label: '添加订阅',
            autofocus: true,
            onPressed: () => _edit())
      ]),
      body: ref.watch(liveSnapshotProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => Center(
                child: StarflowButton(
                    label: '重新读取直播数据',
                    onPressed: () => ref.invalidate(liveSnapshotProvider))),
            data: (s) => s.sources.isEmpty
                ? Center(
                    child:
                        StarflowButton(label: '添加订阅', onPressed: () => _edit()))
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                        16,
                        16,
                        16,
                        kBottomReservedSpacing +
                            MediaQuery.viewPaddingOf(context).bottom),
                    itemCount: s.sources.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, i) {
                      final source = s.sources[i];
                      return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                  child: Text(source.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium)),
                              const SizedBox(width: 12),
                              Semantics(
                                  label: '启用订阅 ${source.name}',
                                  toggled: source.enabled,
                                  child: Tooltip(
                                      message: source.enabled ? '停用订阅' : '启用订阅',
                                      child: TvFocusableAction(
                                          key: ValueKey(
                                              'source-enabled-${source.id}'),
                                          focusableWhenDisabled: true,
                                          onPressed: _toggling.contains(source.id)
                                              ? null
                                              : () => _setEnabled(
                                                  source, !source.enabled),
                                          child: ExcludeFocus(
                                              child: ExcludeSemantics(
                                                  child: IgnorePointer(
                                                      child: Switch(
                                                          value: source.enabled,
                                                          onChanged: _toggling
                                                                  .contains(source.id)
                                                              ? null
                                                              : (value) =>
                                                                  _setEnabled(source, value)))))))),
                            ]),
                            Text(
                                '${s.channels.where((c) => c.sourceId == source.id).length} 个频道 · ${source.url.isEmpty ? "本地导入" : "订阅"} · ${source.enabled ? "已启用" : "已停用"}'),
                            Text(source.updatedAt == 0
                                ? '尚未更新'
                                : '频道更新：${DateTime.fromMillisecondsSinceEpoch(source.updatedAt).toLocal().toString().split(".").first}'),
                            if (source.effectiveEpgUrl.isNotEmpty)
                              Text(source.epgUpdatedAt == 0
                                  ? '节目单尚未更新'
                                  : '节目单更新：${DateTime.fromMillisecondsSinceEpoch(source.epgUpdatedAt).toLocal().toString().split(".").first}'),
                            Wrap(children: [
                              LiveIconButton(
                                  icon: Icons.edit_outlined,
                                  label: '编辑订阅',
                                  onPressed: _toggling.contains(source.id)
                                      ? null
                                      : () => _edit(source)),
                              LiveIconButton(
                                  icon: _busy.contains(source.id)
                                      ? Icons.hourglass_top
                                      : Icons.refresh,
                                  label: '更新频道与节目单',
                                  onPressed: _busy.contains(source.id) ||
                                          _toggling.contains(source.id) ||
                                          !source.enabled ||
                                          (source.url.isEmpty &&
                                              source.effectiveEpgUrl.isEmpty)
                                      ? null
                                      : () => _refresh(source)),
                              LiveIconButton(
                                  icon: Icons.delete_outline,
                                  label: '删除订阅',
                                  onPressed: () => _remove(source)),
                            ]),
                          ]);
                    }),
          ));
}

class _SourceEditor extends ConsumerStatefulWidget {
  const _SourceEditor({this.source});
  final LiveSource? source;
  @override
  ConsumerState<_SourceEditor> createState() => _SourceEditorState();
}

class _SourceEditorState extends ConsumerState<_SourceEditor> {
  late final _name = TextEditingController(text: widget.source?.name);
  late final _url = TextEditingController(text: widget.source?.url);
  late final _epg = TextEditingController(text: widget.source?.epgUrl);
  late int _hours = widget.source?.refreshHours ?? 24;
  Uint8List? _bytes;
  String _fileName = '', _error = '';
  bool _saving = false;
  bool _picking = false;
  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _epg.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    if (_picking || _saving) return;
    setState(() => _picking = true);
    try {
      final isTelevision = await ref.read(isTelevisionProvider.future);
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      if (isTelevision) {
        final service = ref.read(livePlaylistTransferServiceProvider);
        final upload = await showDialog<LivePlaylistTransferResult>(
            context: context,
            builder: (_) => LivePlaylistTransferDialog(start: service.start));
        if (upload is LivePlaylistUpload && mounted) {
          _acceptFile(upload.name, upload.bytes);
        }
        return;
      }
      final file = await openFile(acceptedTypeGroups: [
        const XTypeGroup(
            label: 'M3U / TXT',
            extensions: ['m3u', 'm3u8', 'txt'],
            uniformTypeIdentifiers: ['public.text'])
      ]);
      if (file == null || !mounted) return;
      if (await file.length() > livePlaylistMaxBytes) {
        throw const FormatException('文件超过 8 MiB');
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > livePlaylistMaxBytes) {
        throw const FormatException('文件超过 8 MiB');
      }
      if (!mounted) return;
      _acceptFile(file.name, bytes);
    } catch (_) {
      if (mounted) setState(() => _error = '文件读取失败或超过 8 MiB');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _acceptFile(String name, Uint8List bytes) => setState(() {
        _bytes = bytes;
        _fileName = name;
        _error = '';
        _url.clear();
        if (_name.text.isEmpty) _name.text = name;
      });

  Future<void> _save() async {
    if (_saving || _picking) return;
    if (_bytes != null && _url.text.trim().isNotEmpty) {
      setState(() => _error = '请选择文件导入或订阅地址其中一种');
      return;
    }
    if (_name.text.trim().isEmpty ||
        (_bytes == null && widget.source == null && _url.text.trim().isEmpty)) {
      setState(() => _error = '请填写名称，并填写订阅地址或选择文件');
      return;
    }
    setState(() {
      _saving = true;
      _error = '';
    });
    final source = LiveSource(
        id: widget.source?.id ??
            liveId(DateTime.now().microsecondsSinceEpoch.toString()),
        name: _name.text.trim(),
        url: _url.text.trim(),
        epgUrl: _epg.text.trim(),
        discoveredEpgUrl: widget.source?.discoveredEpgUrl ?? '',
        enabled: widget.source?.enabled ?? true,
        refreshHours: _hours,
        updatedAt: widget.source?.updatedAt ?? 0,
        epgUpdatedAt: widget.source?.epgUpdatedAt ?? 0);
    try {
      await ref
          .read(liveRepositoryProvider)
          .saveSource(source, imported: _bytes);
      if (!mounted) return;
      // Imports can supply their own EPG URL in the playlist header.
      final saved = (await ref.read(liveRepositoryProvider).load())
          .sources
          .where((s) => s.id == source.id)
          .firstOrNull;
      if (mounted) Navigator.pop(context, saved ?? source);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is FormatException ? e.message : '保存失败');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    return Scaffold(
        appBar:
            AppBar(title: Text(widget.source == null ? '添加直播订阅' : '编辑直播订阅')),
        body: AbsorbPointer(
            absorbing: _saving,
            child: ListView(padding: EdgeInsets.fromLTRB(
                24,
                24,
                24,
                kBottomReservedSpacing +
                    MediaQuery.viewPaddingOf(context).bottom), children: [
              SettingsTextInputField(
                  controller: _name, labelText: '名称', autofocus: true),
              const SizedBox(height: 16),
              SettingsTextInputField(
                  controller: _url,
                  labelText: 'M3U / TXT 订阅地址',
                  autocorrect: false,
                  onChanged: (value) {
                    if (value.trim().isNotEmpty && _bytes != null) {
                      setState(() {
                        _bytes = null;
                        _fileName = '';
                        _error = '';
                      });
                    }
                  }),
              const SizedBox(height: 16),
              SettingsTextInputField(
                  controller: _epg,
                  labelText: 'XMLTV / XMLTV.gz 节目单地址',
                  autocorrect: false),
              const SizedBox(height: 16),
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                LiveIconButton(
                    icon: isTelevision
                        ? Icons.qr_code_scanner
                        : Icons.file_open_outlined,
                    label:
                        isTelevision ? '手机导入 M3U / TXT 文件' : '导入 M3U / TXT 文件',
                    onPressed: _saving || _picking ? null : _pick),
                if (_fileName.isNotEmpty) Text(_fileName),
                if (_bytes != null)
                  LiveIconButton(
                      icon: Icons.close,
                      label: '取消文件导入',
                      onPressed: () => setState(() {
                            _bytes = null;
                            _fileName = '';
                          })),
              ]),
              DropdownButtonFormField<int>(
                  initialValue: _hours,
                  decoration: const InputDecoration(labelText: '更新间隔'),
                  items: [
                    for (final h
                        in {6, 12, 24, 48, 168, _hours}.toList()..sort())
                      DropdownMenuItem(value: h, child: LiveSelectionLabel(
                          label: '$h 小时', selected: _hours == h, enabled: !_saving))
                  ],
                  onChanged: (v) => setState(() => _hours = v ?? 24)),
              const SizedBox(height: 24),
              if (_error.isNotEmpty)
                Text(_error,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              StarflowButton(
                  label: _saving ? '保存中' : '保存',
                  variant: isTelevision
                      ? StarflowButtonVariant.secondary
                      : StarflowButtonVariant.primary,
                  onPressed: _saving || _picking ? null : _save,
                  focusableWhenDisabled: true),
            ])));
  }
}
