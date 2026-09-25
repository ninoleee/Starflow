import 'package:flutter/material.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/playback/application/playback_variant_resolver.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

class PlayerVariantPickerDialog extends StatefulWidget {
  const PlayerVariantPickerDialog({
    super.key,
    required this.target,
    required this.isTelevision,
    required this.load,
  });

  final PlaybackTarget target;
  final bool isTelevision;
  final Future<List<PlaybackTarget>> Function() load;

  @override
  State<PlayerVariantPickerDialog> createState() => _PlayerVariantPickerState();
}

class _PlayerVariantPickerState extends State<PlayerVariantPickerDialog> {
  late Future<List<PlaybackTarget>> _choices = widget.load();

  @override
  Widget build(BuildContext context) => wrapTelevisionDialogFieldTraversal(
        enabled: widget.isTelevision,
        child: AlertDialog(
          title: const Text('播放版本'),
          content: SizedBox(
            width: 440,
            child: FutureBuilder<List<PlaybackTarget>>(
              future: _choices,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox(
                      height: 80,
                      child: Center(child: CircularProgressIndicator()));
                }
                if (snapshot.hasError) {
                  return TvDialogOption(
                    isTelevision: widget.isTelevision,
                    autofocus: true,
                    onPressed: () => setState(() {
                      _choices = widget.load();
                    }),
                    child: const Text('版本加载失败，重试'),
                  );
                }
                final choices = snapshot.data ?? [widget.target];
                return ListView(
                  shrinkWrap: true,
                  children: [
                    if (choices.length <= 1)
                      const Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('当前仅有一个播放版本')),
                    for (final choice in choices)
                      TvDialogOption(
                        isTelevision: widget.isTelevision,
                        autofocus: isSamePlaybackVariant(choice, widget.target),
                        onPressed: () => Navigator.of(context).pop(choice),
                        child: Text(
                          '${playbackVariantLabel(choice)}${isSamePlaybackVariant(choice, widget.target) ? '  当前' : ''}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          actions: [
            if (widget.isTelevision)
              StarflowButton(
                  label: '取消',
                  compact: true,
                  variant: StarflowButtonVariant.ghost,
                  onPressed: () => Navigator.of(context).pop())
            else
              TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消')),
          ],
        ),
      );
}
