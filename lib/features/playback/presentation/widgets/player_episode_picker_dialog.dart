import 'package:flutter/material.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/playback/domain/playback_episode_queue.dart';

const double _kPlaybackEpisodePickerItemExtent = 68;

String formatPlaybackEpisodePickerLabel(
  PlaybackEpisodeQueueEntry entry,
  int index,
) {
  final target = entry.target;
  final title = target.title.trim();
  final seasonNumber = target.seasonNumber ?? 0;
  final episodeNumber = target.episodeNumber ?? 0;
  final prefix = switch ((seasonNumber, episodeNumber)) {
    (> 0, > 0) => 'S${seasonNumber.toString().padLeft(2, '0')}'
        'E${episodeNumber.toString().padLeft(2, '0')}',
    (_, > 0) => '第 $episodeNumber 集',
    _ => '第 ${index + 1} 集',
  };
  return title.isEmpty ? prefix : '$prefix · $title';
}

Future<int?> showPlaybackEpisodePickerDialog({
  required BuildContext context,
  required PlaybackEpisodeQueue queue,
  required bool isTelevision,
}) {
  if (queue.entries.isEmpty || !queue.hasCurrent) {
    return Future<int?>.value(null);
  }
  return showDialog<int>(
    context: context,
    builder: (dialogContext) => _PlaybackEpisodePickerDialog(
      queue: queue,
      isTelevision: isTelevision,
    ),
  );
}

class _PlaybackEpisodePickerDialog extends StatefulWidget {
  const _PlaybackEpisodePickerDialog({
    required this.queue,
    required this.isTelevision,
  });

  final PlaybackEpisodeQueue queue;
  final bool isTelevision;

  @override
  State<_PlaybackEpisodePickerDialog> createState() =>
      _PlaybackEpisodePickerDialogState();
}

class _PlaybackEpisodePickerDialogState
    extends State<_PlaybackEpisodePickerDialog> {
  late final List<FocusNode> _episodeFocusNodes;
  late final FocusNode _closeFocusNode;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _episodeFocusNodes = List<FocusNode>.generate(
      widget.queue.entries.length,
      (index) => FocusNode(debugLabel: 'player-episode-picker-$index'),
    );
    _closeFocusNode = FocusNode(debugLabel: 'player-episode-picker-close');
    final initialIndex = widget.queue.currentIndex.clamp(
      0,
      widget.queue.entries.length - 1,
    );
    _scrollController = ScrollController(
      initialScrollOffset:
          ((initialIndex - 2).clamp(0, widget.queue.entries.length) *
                  _kPlaybackEpisodePickerItemExtent)
              .toDouble(),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (final focusNode in _episodeFocusNodes) {
      focusNode.dispose();
    }
    _closeFocusNode.dispose();
    super.dispose();
  }

  void _ensureFocusedEpisodeVisible(int index) {
    final itemContext = _episodeFocusNodes[index].context;
    if (itemContext == null) {
      return;
    }
    Scrollable.ensureVisible(
      itemContext,
      alignment: 0.5,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final queue = widget.queue;
    final dialog = AlertDialog(
      title: const Text('选择剧集'),
      content: SizedBox(
        width: 520,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.68,
          ),
          child: ListView.builder(
            controller: _scrollController,
            itemExtent: _kPlaybackEpisodePickerItemExtent,
            itemCount: queue.entries.length,
            itemBuilder: (context, index) {
              final entry = queue.entries[index];
              final selected = index == queue.currentIndex;
              final tile = DecoratedBox(
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.14)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.40)
                        : Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: selected
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.58),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          formatPlaybackEpisodePickerLabel(entry, index),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
              if (!widget.isTelevision) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.of(context).pop(index),
                    child: tile,
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: TvFocusableAction(
                  focusNode: _episodeFocusNodes[index],
                  focusId: 'player:episode-picker:$index',
                  autofocus: selected,
                  onFocused: () => _ensureFocusedEpisodeVisible(index),
                  onPressed: () => Navigator.of(context).pop(index),
                  borderRadius: BorderRadius.circular(16),
                  focusScale: kTvButtonFocusScale,
                  child: tile,
                ),
              );
            },
          ),
        ),
      ),
      actions: [
        StarflowButton(
          label: '关闭',
          icon: Icons.close_rounded,
          onPressed: () => Navigator.of(context).pop(),
          focusNode: _closeFocusNode,
          variant: StarflowButtonVariant.secondary,
          compact: true,
        ),
      ],
    );
    return wrapTelevisionDialogBackHandling(
      enabled: widget.isTelevision,
      dialogContext: context,
      inputFocusNodes: const <FocusNode>[],
      contentFocusNodes: _episodeFocusNodes,
      actionFocusNodes: [_closeFocusNode],
      child: dialog,
    );
  }
}
