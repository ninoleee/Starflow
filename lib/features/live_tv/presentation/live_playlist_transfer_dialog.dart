import 'dart:async';

import 'package:flutter/material.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/settings/presentation/widgets/lan_transfer_qr_address_card.dart';
import '../data/live_playlist_transfer_service.dart';

class LivePlaylistTransferDialog extends StatefulWidget {
  const LivePlaylistTransferDialog({
    super.key,
    required this.start,
    this.mode = LivePlaylistTransferMode.file,
  });

  final Future<LivePlaylistTransferSession> Function() start;
  final LivePlaylistTransferMode mode;

  @override
  State<LivePlaylistTransferDialog> createState() =>
      _LivePlaylistTransferDialogState();
}

class _LivePlaylistTransferDialogState extends State<LivePlaylistTransferDialog>
    with WidgetsBindingObserver {
  final _closeFocus = FocusNode(debugLabel: 'live-transfer-close');
  final _urlsFocus = <FocusNode>[];
  LivePlaylistTransferSession? _session;
  StreamSubscription<String>? _errors;
  String _status = '正在启动手机传输';
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final session = await widget.start();
      if (!mounted || _finished) {
        await session.close();
        return;
      }
      _session = session;
      _urlsFocus.addAll(List.generate(session.urls.length,
          (i) => FocusNode(debugLabel: 'live-transfer-url-$i')));
      _errors = session.errors.listen((message) {
        if (mounted && !_finished) setState(() => _status = message);
      });
      setState(() => _status = switch (widget.mode) {
            LivePlaylistTransferMode.backupExport => '等待手机下载直播备份',
            _ => '等待手机上传',
          });
      final uploaded = await session.received;
      if (mounted && !_finished) _finish(uploaded);
    } catch (_) {
      if (mounted && !_finished) {
        setState(() => _status = '无法启动手机传输，请检查局域网连接后重试');
      }
    }
  }

  void _stop() {
    if (_finished) return;
    _finished = true;
    unawaited(_session?.close());
  }

  void _finish([LivePlaylistTransferResult? uploaded]) {
    _stop();
    Navigator.of(context).pop(uploaded);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (!_finished) _finish();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    unawaited(_errors?.cancel());
    for (final node in _urlsFocus) {
      node.dispose();
    }
    _closeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<LivePlaylistTransferResult>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _stop();
      },
      child: wrapTelevisionDialogBackHandling(
        enabled: true,
        dialogContext: context,
        inputFocusNodes: const [],
        contentFocusNodes: _urlsFocus,
        actionFocusNodes: [_closeFocus],
        child: AlertDialog(
          title: Text(switch (widget.mode) {
            LivePlaylistTransferMode.backupImport => '手机上传直播备份',
            LivePlaylistTransferMode.backupExport => '手机下载直播备份',
            _ => '手机导入直播文件',
          }),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < (_session?.urls.length ?? 0); i++) ...[
                      LanTransferQrAddressCard(
                          url: _session!.urls[i],
                          focusNode: _urlsFocus[i],
                          focusId: 'live:import:lan-url:$i'),
                      const SizedBox(height: 12),
                    ],
                    Text(_status),
                  ]),
            ),
          ),
          actions: [
            StarflowButton(
                label: '关闭服务',
                icon: Icons.close,
                autofocus: true,
                focusNode: _closeFocus,
                onPressed: _finish,
                compact: true)
          ],
        ),
      ));
}
