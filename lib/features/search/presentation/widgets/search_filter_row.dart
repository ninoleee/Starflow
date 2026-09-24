import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:starflow/core/widgets/tv_focus.dart';

class SearchFilterRow extends StatelessWidget {
  const SearchFilterRow({
    super.key,
    required this.label,
    required this.storageId,
    required this.isTelevision,
    required this.children,
  });

  final String label;
  final String storageId;
  final bool isTelevision;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;
    final scaler = MediaQuery.textScalerOf(context);
    final painter = TextPainter(
      text: TextSpan(text: '搜索来源', style: style),
      textDirection: Directionality.of(context),
      textScaler: scaler,
    )..layout();
    final labelWidth = painter.width + 16;
    painter.dispose();

    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 600;
      final stacked = narrow && scaler.scale(14) > 21;
      final optionsWidth = constraints.maxWidth - (stacked ? 0 : labelWidth);
      final options = [
        for (final child in children)
          ConstrainedBox(
            key: child.key == null
                ? null
                : ValueKey(('filter-option', child.key)),
            constraints: BoxConstraints(maxWidth: optionsWidth - 12),
            child: child,
          ),
      ];
      final Widget choices;
      if (narrow && !isTelevision) {
        choices = SizedBox(
          height: StarflowChipButton.minimumHeight(context) + 12,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {
              ...ScrollConfiguration.of(context).dragDevices,
              PointerDeviceKind.mouse,
            }),
            child: SingleChildScrollView(
              key: PageStorageKey('search-filter:$storageId'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(6),
              child: Row(children: [
                for (var index = 0; index < options.length; index++) ...[
                  if (index > 0) const SizedBox(width: 8),
                  options[index],
                ],
              ]),
            ),
          ),
        );
      } else {
        choices = Padding(
          padding: const EdgeInsets.all(6),
          child: Wrap(spacing: 8, runSpacing: 8, children: options),
        );
      }

      final heading = Text(label,
          style: style?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant));
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [heading, const SizedBox(height: 4), choices],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: labelWidth,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 22),
                      child: heading,
                    ),
                  ),
                  Expanded(child: choices),
                ],
              ),
      );
    });
  }
}
