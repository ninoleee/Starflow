import 'package:flutter/material.dart';
import 'package:starflow/core/widgets/starflow_option_dialog.dart';

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
  required String title,
  required List<DetailTelevisionPickerOption<T>> options,
  required T? selectedValue,
  double width = 460,
  double maxHeightFactor = 0.58,
}) {
  return showStarflowOptionDialog<T>(
    context: context,
    title: title,
    selectedValue: selectedValue,
    width: width,
    maxHeightFactor: maxHeightFactor,
    options: [
      for (final option in options)
        StarflowOptionDialogOption<T>(
          value: option.value,
          title: option.title,
          subtitle: option.subtitle,
          focusId: option.focusId,
        ),
    ],
  );
}
