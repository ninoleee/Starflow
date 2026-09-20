import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

class NavigationDestinationDialog extends ConsumerStatefulWidget {
  const NavigationDestinationDialog({
    super.key,
    required this.initialSelection,
  });

  final List<String> initialSelection;

  @override
  ConsumerState<NavigationDestinationDialog> createState() =>
      _NavigationDestinationDialogState();
}

class _NavigationDestinationDialogState
    extends ConsumerState<NavigationDestinationDialog> {
  static const _labels = {
    kNavigationDestinationHome: '首页',
    kNavigationDestinationSearch: '搜索',
    kNavigationDestinationFavorites: '收藏',
    kNavigationDestinationLibrary: '媒体库',
    kNavigationDestinationLiveTv: '直播',
    kNavigationDestinationSettings: '设置',
  };

  late final _selected =
      normalizeNavigationDestinationIds(widget.initialSelection).toSet();
  late final _order = [
    ..._selected,
    ...kAllNavigationDestinationIds.where((id) => !_selected.contains(id)),
  ];

  void _move(int from, int to) {
    setState(() => _order.insert(to, _order.removeAt(from)));
  }

  @override
  Widget build(BuildContext context) {
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    final rows = [
      for (final (index, id) in _order.indexed)
        Padding(
          key: ValueKey(id),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: StarflowCheckboxTile(
                  title: _labels[id]!,
                  value: _selected.contains(id),
                  autofocus: index == 0 && id != kNavigationDestinationSettings,
                  focusId: 'navigation-editor:$id:toggle',
                  onChanged: id == kNavigationDestinationSettings
                      ? null
                      : (checked) => setState(() {
                            if (checked) {
                              _selected.add(id);
                            } else {
                              _selected.remove(id);
                            }
                          }),
                ),
              ),
              StarflowIconButton(
                icon: Icons.arrow_upward_rounded,
                tooltip: '上移${_labels[id]}',
                size: 36,
                focusId: 'navigation-editor:$id:up',
                focusableWhenDisabled: isTelevision,
                onPressed: index == 0 ? null : () => _move(index, index - 1),
              ),
              StarflowIconButton(
                icon: Icons.arrow_downward_rounded,
                tooltip: '下移${_labels[id]}',
                size: 36,
                autofocus: index == 0 && id == kNavigationDestinationSettings,
                focusId: 'navigation-editor:$id:down',
                focusableWhenDisabled: isTelevision,
                onPressed: index == _order.length - 1
                    ? null
                    : () => _move(index, index + 1),
              ),
              if (!isTelevision)
                ReorderableDragStartListener(
                  index: index,
                  child: const Tooltip(
                    message: '拖动排序',
                    child: SizedBox(
                      width: 28,
                      height: 48,
                      child: Icon(Icons.drag_handle_rounded, size: 20),
                    ),
                  ),
                ),
            ],
          ),
        ),
    ];
    return AlertDialog(
      title: const Text('菜单栏按钮'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 440,
        height: 480,
        child: isTelevision
            ? ListView(children: rows)
            : ReorderableListView(
                buildDefaultDragHandles: false,
                onReorder: (from, to) => _move(from, to > from ? to - 1 : to),
                children: rows,
              ),
      ),
      actions: [
        StarflowButton(
          label: '取消',
          variant: StarflowButtonVariant.ghost,
          compact: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
        StarflowButton(
          label: '保存',
          compact: true,
          onPressed: () => Navigator.of(context).pop(
            _order.where(_selected.contains).toList(),
          ),
        ),
      ],
    );
  }
}
