import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTelevision = ref.watch(isTelevisionProvider).valueOrNull ?? false;
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
        return TvSelectionTile(
          title: labelText,
          value: _resolveTelevisionSummary(value.text),
          onPressed: () => _openTelevisionEditor(context),
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
              TextButton(
                focusNode: cancelFocusNode,
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                focusNode: confirmFocusNode,
                onPressed: () =>
                    Navigator.of(dialogContext).pop(dialogController.text),
                child: const Text('保存'),
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
