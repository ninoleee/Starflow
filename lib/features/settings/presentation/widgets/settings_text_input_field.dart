import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/core/widgets/tv_text_input_launcher.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';
import '../../data/text_input_transfer_service.dart';
import 'text_input_transfer_dialog.dart';

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
    this.onChanged,
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
  final ValueChanged<String>? onChanged;

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
        onChanged: onChanged,
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
        return TvTextInputLauncher(
          onOpen: () => _openTelevisionEditor(context, ref),
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

  Future<void> _openTelevisionEditor(
      BuildContext context, WidgetRef ref) async {
    final dialogController = TextEditingController(text: controller.text);
    final inputFocusNode = FocusNode(debugLabel: 'settings-text-input');
    final cancelFocusNode = FocusNode(debugLabel: 'settings-text-cancel');
    final confirmFocusNode = FocusNode(debugLabel: 'settings-text-confirm');
    final scanFocusNode = FocusNode(debugLabel: 'settings-text-scan');
    var scanning = false;
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<String>(
      context: context,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      builder: (dialogContext) {
        final dialog = AlertDialog(
          title: Text(labelText),
          content: wrapTelevisionDialogFieldTraversal(
            enabled: true,
            child: SizedBox(
                width: 560,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
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
                      onSubmitted: (value) =>
                          Navigator.of(dialogContext).pop(value),
                    )),
                    const SizedBox(width: 8),
                    Tooltip(
                        message: '手机扫码输入',
                        child: TvFocusableAction(
                          focusNode: scanFocusNode,
                          onPressed: () async {
                            if (scanning) return;
                            scanning = true;
                            inputFocusNode.unfocus();
                            try {
                              final service =
                                  ref.read(textInputTransferServiceProvider);
                              final text = await showDialog<String>(
                                context: dialogContext,
                                builder: (_) => TextInputTransferDialog(
                                  start: () => service.start(
                                      label: labelText,
                                      multiline: maxLines > 1,
                                      obscureText: obscureText),
                                ),
                              );
                              if (!dialogContext.mounted ||
                                  ModalRoute.of(dialogContext)?.isCurrent !=
                                      true) {
                                return;
                              }
                              if (text != null) {
                                final oldValue = dialogController.value;
                                var value = TextEditingValue(
                                    text: text,
                                    selection: TextSelection.collapsed(
                                        offset: text.length));
                                for (final formatter in [
                                  if (maxLines == 1)
                                    FilteringTextInputFormatter
                                        .singleLineFormatter,
                                  ...?inputFormatters,
                                ]) {
                                  value = formatter.formatEditUpdate(
                                      oldValue, value);
                                }
                                dialogController.value = value;
                              }
                              scanFocusNode.requestFocus();
                            } finally {
                              scanning = false;
                            }
                          },
                          child: Semantics(
                              label: '手机扫码输入',
                              button: true,
                              child: const SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: Icon(Icons.qr_code_scanner))),
                        )),
                  ],
                )),
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
          contentFocusNodes: [inputFocusNode, scanFocusNode],
          actionFocusNodes: [confirmFocusNode, cancelFocusNode],
          child: dialog,
        );
      },
    );
    try {
      final result = await navigator.push(route);
      if (!context.mounted || result == null) {
        return;
      }
      controller.text = result;
      onChanged?.call(result);
    } finally {
      // The pop result precedes removal of the animated dialog's widgets.
      await route.completed;
      dialogController.dispose();
      inputFocusNode.dispose();
      cancelFocusNode.dispose();
      confirmFocusNode.dispose();
      scanFocusNode.dispose();
    }
  }
}
