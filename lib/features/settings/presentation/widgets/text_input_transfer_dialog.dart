import 'dart:async';
import 'package:flutter/material.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import '../../data/text_input_transfer_service.dart';
import 'lan_transfer_qr_address_card.dart';

class TextInputTransferDialog extends StatefulWidget {
  const TextInputTransferDialog({super.key, required this.start});
  final Future<TextInputTransferSession> Function() start;
  @override
  State<TextInputTransferDialog> createState() =>
      _TextInputTransferDialogState();
}

class _TextInputTransferDialogState extends State<TextInputTransferDialog>
    with WidgetsBindingObserver {
  final _closeFocus = FocusNode(debugLabel: 'text-transfer-close');
  final _urlFocus = <FocusNode>[];
  TextInputTransferSession? _session;
  StreamSubscription<String>? _errors;
  String _status = '正在启动手机输入';
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
      _urlFocus.addAll(List.generate(session.urls.length,
          (i) => FocusNode(debugLabel: 'text-transfer-url-$i')));
      _errors = session.errors.listen((message) {
        if (mounted && !_finished) setState(() => _status = message);
      });
      setState(() => _status = '等待手机输入');
      final text = await session.received;
      if (mounted && !_finished) _finish(text);
    } catch (_) {
      if (mounted && !_finished) {
        setState(() => _status = '无法启动手机输入，请检查局域网连接后重试');
      }
    }
  }

  void _stop() {
    if (_finished) return;
    _finished = true;
    unawaited(_session?.close());
  }

  void _finish([String? text]) {
    _stop();
    Navigator.of(context).pop(text);
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
    for (final focus in _urlFocus) {
      focus.dispose();
    }
    _closeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<String>(
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) _stop();
        },
        child: wrapTelevisionDialogBackHandling(
            enabled: true,
            dialogContext: context,
            inputFocusNodes: const [],
            contentFocusNodes: _urlFocus,
            actionFocusNodes: [_closeFocus],
            child: AlertDialog(
              title: const Text('手机扫码输入'),
              content: SizedBox(
                  width: 620,
                  child: SingleChildScrollView(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        for (var i = 0;
                            i < (_session?.urls.length ?? 0);
                            i++) ...[
                          LanTransferQrAddressCard(
                              url: _session!.urls[i],
                              focusNode: _urlFocus[i],
                              focusId: 'text:lan-url:$i'),
                          const SizedBox(height: 12),
                        ],
                        Text(_status),
                      ]))),
              actions: [
                StarflowButton(
                    label: '关闭服务',
                    icon: Icons.close,
                    autofocus: true,
                    focusNode: _closeFocus,
                    onPressed: _finish,
                    compact: true)
              ],
            )),
      );
}
