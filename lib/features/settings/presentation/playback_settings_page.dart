import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

class PlaybackSettingsPage extends ConsumerStatefulWidget {
  const PlaybackSettingsPage({
    super.key,
    required this.initialTimeoutSeconds,
  });

  final int initialTimeoutSeconds;

  @override
  ConsumerState<PlaybackSettingsPage> createState() =>
      _PlaybackSettingsPageState();
}

class _PlaybackSettingsPageState extends ConsumerState<PlaybackSettingsPage> {
  late final TextEditingController _timeoutController;
  bool _skipAutoSaveOnPop = false;

  @override
  void initState() {
    super.initState();
    _timeoutController = TextEditingController(
      text: '${widget.initialTimeoutSeconds.clamp(1, 600)}',
    );
  }

  @override
  void dispose() {
    _timeoutController.dispose();
    super.dispose();
  }

  int _draftSeconds() {
    final parsed = int.tryParse(_timeoutController.text.trim()) ?? 20;
    return parsed.clamp(1, 600);
  }

  Future<void> _saveDraft({bool popAfterSave = true}) async {
    await ref
        .read(settingsControllerProvider.notifier)
        .setPlaybackOpenTimeoutSeconds(_draftSeconds());
    if (popAfterSave && mounted) {
      _skipAutoSaveOnPop = true;
      Navigator.of(context).pop();
    }
  }

  bool _hasUnsavedChanges() {
    return _draftSeconds() != widget.initialTimeoutSeconds.clamp(1, 600);
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
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('保存修改？'),
        content: const Text('当前页面有未保存的修改，返回前要怎么处理？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('cancel'),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('discard'),
            child: const Text('不保存'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('save'),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (action == 'discard') {
      await _discardAndClose();
    } else if (action == 'save') {
      await _saveDraft();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTelevision = ref.watch(isTelevisionProvider).valueOrNull ?? false;
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _skipAutoSaveOnPop) {
          return;
        }
        _handleCloseRequest();
      },
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            ListView(
              padding: overlayToolbarPagePadding(context),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                if (isTelevision)
                  TvSelectionTile(
                    title: '最大超时时间（秒）',
                    value: '${_draftSeconds()} 秒',
                    onPressed: _openTimeoutPicker,
                  )
                else
                  TextField(
                    controller: _timeoutController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: '最大超时时间（秒）',
                      hintText: '20',
                    ),
                  ),
                const SizedBox(height: kBottomReservedSpacing),
              ],
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: OverlayToolbar(
                onBack: _handleCloseRequest,
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

  Future<void> _openTimeoutPicker() async {
    final options = <int>[5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 300, 600];
    final selection = await showDialog<int>(
      context: context,
      builder: (context) {
        final current = _draftSeconds();
        return SimpleDialog(
          title: const Text('选择最大超时时间'),
          children: [
            for (final seconds in options)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(seconds),
                child: Text(
                  seconds == current ? '$seconds 秒  当前' : '$seconds 秒',
                ),
              ),
          ],
        );
      },
    );
    if (selection == null) {
      return;
    }
    setState(() {
      _timeoutController.text = '$selection';
    });
  }
}
