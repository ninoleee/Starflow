import 'package:flutter/material.dart';
import 'package:starflow/core/widgets/tv_focus.dart';

class DetailTelevisionPickerOption<T> {
  const DetailTelevisionPickerOption({
    required this.value,
    required this.title,
    required this.focusId,
    this.subtitle = '',
  });

  final T value;
  final String title;
  final String focusId;
  final String subtitle;
}

Future<T?> showDetailTelevisionPickerDialog<T>({
  required BuildContext context,
  required bool enabled,
  required String title,
  required List<DetailTelevisionPickerOption<T>> options,
  required T? selectedValue,
  required String optionDebugLabelPrefix,
  required String closeFocusDebugLabel,
  required String closeFocusId,
  double width = 460,
  double maxHeightFactor = 0.58,
  int titleMaxLines = 2,
}) async {
  final optionFocusNodes = List<FocusNode>.generate(
    options.length,
    (index) => FocusNode(debugLabel: '$optionDebugLabelPrefix-$index'),
  );
  final closeFocusNode = FocusNode(debugLabel: closeFocusDebugLabel);
  try {
    final selectedIndex = options.indexWhere(
      (option) => option.value == selectedValue,
    );
    final autofocusIndex = optionFocusNodes.isEmpty
        ? -1
        : selectedIndex.clamp(0, optionFocusNodes.length - 1);
    return showDialog<T>(
      context: context,
      builder: (dialogContext) {
        final dialog = AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: width,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight:
                    MediaQuery.sizeOf(dialogContext).height * maxHeightFactor,
              ),
              child: FocusTraversalGroup(
                policy: OrderedTraversalPolicy(),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: options.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final option = options[index];
                    final isSelected = option.value == selectedValue;
                    return TvFocusableAction(
                      focusNode: optionFocusNodes[index],
                      focusId: option.focusId,
                      autofocus: index == autofocusIndex,
                      onPressed: () =>
                          Navigator.of(dialogContext).pop(option.value),
                      borderRadius: BorderRadius.circular(18),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white.withValues(alpha: 0.14)
                              : Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.4)
                                : Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                isSelected
                                    ? Icons.check_circle_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      option.title,
                                      maxLines: titleMaxLines,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (option.subtitle.trim().isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          option.subtitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFF9DB0CF),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          actions: [
            TvAdaptiveButton(
              label: '关闭',
              icon: Icons.close_rounded,
              onPressed: () => Navigator.of(dialogContext).pop(),
              focusNode: closeFocusNode,
              autofocus: optionFocusNodes.isEmpty,
              variant: TvButtonVariant.outlined,
              focusId: closeFocusId,
            ),
          ],
        );
        return wrapTelevisionDialogBackHandling(
          enabled: enabled,
          dialogContext: dialogContext,
          inputFocusNodes: const <FocusNode>[],
          contentFocusNodes: optionFocusNodes,
          actionFocusNodes: [closeFocusNode],
          child: dialog,
        );
      },
    );
  } finally {
    for (final focusNode in optionFocusNodes) {
      focusNode.dispose();
    }
    closeFocusNode.dispose();
  }
}
