import 'package:flutter/material.dart';
import 'package:starflow/core/widgets/tv_focus.dart';

class StarflowOptionDialogOption<T> {
  const StarflowOptionDialogOption({
    required this.value,
    required this.title,
    this.subtitle = '',
    this.focusId,
  });

  final T value;
  final String title;
  final String subtitle;
  final String? focusId;
}

Future<T?> showStarflowOptionDialog<T>({
  required BuildContext context,
  required String title,
  required List<StarflowOptionDialogOption<T>> options,
  required T? selectedValue,
  double width = 460,
  double maxHeightFactor = 0.58,
}) {
  return showDialog<T>(
    context: context,
    builder: (dialogContext) {
      return wrapTelevisionDialogFieldTraversal(
        enabled: true,
        child: SimpleDialog(
          title: Text(title),
          constraints: BoxConstraints(
            maxWidth: width,
            maxHeight:
                MediaQuery.sizeOf(dialogContext).height * maxHeightFactor,
          ),
          children: [
            if (options.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Text('暂无可选项'),
              ),
            for (var index = 0; index < options.length; index++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TvFocusableAction(
                  onPressed: () => Navigator.of(dialogContext).pop(
                    options[index].value,
                  ),
                  focusId: options[index].focusId,
                  autofocus: index == 0,
                  borderRadius: BorderRadius.circular(14),
                  visualStyle: TvFocusVisualStyle.subtle,
                  focusScale: kTvButtonFocusScale,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          options[index].value == selectedValue
                              ? '${options[index].title}  当前'
                              : options[index].title,
                        ),
                        if (options[index].subtitle.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              options[index].subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
