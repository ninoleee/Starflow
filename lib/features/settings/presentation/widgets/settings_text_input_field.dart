import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';

class SettingsTextInputField extends ConsumerWidget {
  const SettingsTextInputField({
    super.key,
    required this.controller,
    required this.labelText,
    this.hintText = '',
    this.keyboardType,
    this.textInputAction,
    this.minLines = 1,
    this.maxLines = 1,
    this.obscureText = false,
    this.autocorrect = true,
    this.inputFormatters,
    this.autofillHints,
    this.alignLabelWithHint = false,
    this.summaryBuilder,
    this.autofocus = false,
    this.focusId,
  });

  final TextEditingController controller;
  final String labelText;
  final String hintText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int minLines;
  final int maxLines;
  final bool obscureText;
  final bool autocorrect;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final bool alignLabelWithHint;
  final String Function(String value)? summaryBuilder;
  final bool autofocus;
  final String? focusId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    if (!isTelevision) {
      return TextField(
        controller: controller,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        minLines: minLines,
        maxLines: maxLines,
        obscureText: obscureText,
        autocorrect: autocorrect,
        inputFormatters: inputFormatters,
        autofillHints: autofillHints,
        autofocus: autofocus,
        decoration: InputDecoration(
          labelText: labelText,
          hintText: hintText.isEmpty ? null : hintText,
          alignLabelWithHint: alignLabelWithHint,
        ),
      );
    }

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        return _TelevisionInputLauncher(
          onOpen: () => _openTelevisionEditor(context),
          builder: (onPressed) => SettingsSelectionTile(
            title: labelText,
            value: _resolveTelevisionSummary(value.text),
            autofocus: autofocus,
            focusId: focusId,
            onPressed: onPressed,
          ),
        );
      },
    );
  }

  String _resolveTelevisionSummary(String raw) {
    final trimmed = raw.trim();
    if (summaryBuilder != null) {
      return summaryBuilder!(trimmed);
    }
    if (trimmed.isEmpty) {
      return '未填写';
    }
    if (obscureText) {
      return '已填写';
    }
    return trimmed.replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<void> _openTelevisionEditor(BuildContext context) async {
    final dialogController = TextEditingController(text: controller.text);
    final inputFocusNode = FocusNode(debugLabel: 'settings-text-input');
    final cancelFocusNode = FocusNode(debugLabel: 'settings-text-cancel');
    final confirmFocusNode = FocusNode(debugLabel: 'settings-text-confirm');
    try {
      final result = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          final dialog = AlertDialog(
            title: Text(labelText),
            content: wrapTelevisionDialogFieldTraversal(
              enabled: true,
              child: TextField(
                controller: dialogController,
                focusNode: inputFocusNode,
                autofocus: true,
                keyboardType: keyboardType,
                textInputAction: textInputAction,
                minLines: minLines,
                maxLines: maxLines,
                obscureText: obscureText,
                autocorrect: autocorrect,
                inputFormatters: inputFormatters,
                autofillHints: autofillHints,
                decoration: InputDecoration(
                  hintText: hintText.isEmpty ? null : hintText,
                  alignLabelWithHint: alignLabelWithHint,
                ),
                onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
              ),
            ),
            actions: [
              StarflowButton(
                label: '取消',
                focusNode: cancelFocusNode,
                onPressed: () => Navigator.of(dialogContext).pop(),
                variant: StarflowButtonVariant.ghost,
                compact: true,
              ),
              StarflowButton(
                label: '保存',
                focusNode: confirmFocusNode,
                onPressed: () =>
                    Navigator.of(dialogContext).pop(dialogController.text),
                compact: true,
              ),
            ],
          );
          return wrapTelevisionDialogBackHandling(
            enabled: true,
            dialogContext: dialogContext,
            inputFocusNodes: [inputFocusNode],
            contentFocusNodes: [inputFocusNode],
            actionFocusNodes: [confirmFocusNode, cancelFocusNode],
            child: dialog,
          );
        },
      );
      if (result == null) {
        return;
      }
      controller.text = result;
    } finally {
      dialogController.dispose();
      inputFocusNode.dispose();
      cancelFocusNode.dispose();
      confirmFocusNode.dispose();
    }
  }
}

/// Do not attach an IME while the remote key that opened it is still held.
class _TelevisionInputLauncher extends StatefulWidget {
  const _TelevisionInputLauncher({required this.onOpen, required this.builder});

  final Future<void> Function() onOpen;
  final Widget Function(VoidCallback) builder;

  @override
  State<_TelevisionInputLauncher> createState() =>
      _TelevisionInputLauncherState();
}

class _TelevisionInputLauncherState extends State<_TelevisionInputLauncher> {
  static final _activationKeys = {
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.gameButtonA,
  };

  bool _opening = false;
  Completer<void>? _release;
  bool Function(KeyEvent)? _keyHandler;

  void _stopWaiting() {
    final handler = _keyHandler;
    if (handler != null) {
      HardwareKeyboard.instance.removeHandler(handler);
      _keyHandler = null;
    }
    final release = _release;
    _release = null;
    if (release != null && !release.isCompleted) release.complete();
  }

  Future<void> _open() async {
    if (_opening) return;
    _opening = true;
    try {
      final held = HardwareKeyboard.instance.logicalKeysPressed
          .intersection(_activationKeys);
      if (held.isNotEmpty) {
        final release = Completer<void>();
        _release = release;
        _keyHandler = (event) {
          if (!held.contains(event.logicalKey)) return false;
          if (event is KeyUpEvent) {
            held.remove(event.logicalKey);
            if (held.isEmpty) _stopWaiting();
          }
          return true;
        };
        HardwareKeyboard.instance.addHandler(_keyHandler!);
        await release.future;
        // Finish dispatching the release before requesting text input.
        await Future<void>.delayed(Duration.zero);
      }
      if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
      await widget.onOpen();
    } finally {
      _stopWaiting();
      _opening = false;
    }
  }

  @override
  void dispose() {
    _stopWaiting();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_open);
}
