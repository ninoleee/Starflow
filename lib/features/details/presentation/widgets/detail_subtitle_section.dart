import 'package:flutter/material.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/application/detail_subtitle_controller.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/widgets/detail_shared_widgets.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';

class DetailSubtitleSection extends StatelessWidget {
  const DetailSubtitleSection({
    super.key,
    required this.target,
    required this.isTelevision,
    required this.subtitleView,
    required this.selectedSubtitleIndex,
    required this.subtitleChoiceLabelBuilder,
    required this.onSearchSubtitles,
    required this.onOpenTelevisionSubtitlePicker,
    required this.onSubtitleSelected,
  });

  final MediaDetailTarget target;
  final bool isTelevision;
  final DetailSubtitleSearchViewState subtitleView;
  final int selectedSubtitleIndex;
  final String Function(CachedSubtitleSearchOption choice)
      subtitleChoiceLabelBuilder;
  final VoidCallback? onSearchSubtitles;
  final VoidCallback onOpenTelevisionSubtitlePicker;
  final ValueChanged<int> onSubtitleSelected;

  @override
  Widget build(BuildContext context) {
    if (!target.isPlayable) {
      return const SizedBox.shrink();
    }

    final subtitleActionLabel = subtitleView.isSearching
        ? '搜索字幕中...'
        : (subtitleView.choices.isEmpty ? '搜索字幕' : '刷新字幕');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: isTelevision
              ? TvAdaptiveButton(
                  label: subtitleActionLabel,
                  icon: Icons.subtitles_rounded,
                  focusId: 'detail:resource:search-subtitle',
                  onPressed:
                      subtitleView.isSearching ? null : onSearchSubtitles,
                  variant: TvButtonVariant.text,
                )
              : TextButton.icon(
                  onPressed:
                      subtitleView.isSearching ? null : onSearchSubtitles,
                  icon: subtitleView.isSearching
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.subtitles_rounded,
                          size: 16,
                        ),
                  label: Text(subtitleActionLabel),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 0,
                      vertical: 0,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
        ),
        if (subtitleView.choices.isNotEmpty) ...[
          const SizedBox(height: 8),
          const InfoLabel('外挂字幕'),
          const SizedBox(height: 8),
          if (isTelevision)
            TvSelectionTile(
              title: '外挂字幕',
              value: selectedSubtitleIndex < 0
                  ? '不加载外挂字幕'
                  : subtitleChoiceLabelBuilder(
                      subtitleView.choices[selectedSubtitleIndex],
                    ),
              onPressed: subtitleView.busyResultId != null
                  ? null
                  : onOpenTelevisionSubtitlePicker,
              focusId: 'detail:resource:subtitle-selector',
            )
          else
            DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: selectedSubtitleIndex,
                isExpanded: true,
                dropdownColor: const Color(0xFF142235),
                iconEnabledColor: Colors.white70,
                style: const TextStyle(
                  color: Color(0xFFDCE6F8),
                  fontSize: 14,
                  height: 1.35,
                ),
                items: [
                  const DropdownMenuItem<int>(
                    value: -1,
                    child: Text('不加载外挂字幕'),
                  ),
                  ...List.generate(
                    subtitleView.choices.length,
                    (i) => DropdownMenuItem<int>(
                      value: i,
                      child: Text(
                        subtitleChoiceLabelBuilder(subtitleView.choices[i]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (subtitleView.busyResultId != null ||
                        subtitleView.isSearching)
                    ? null
                    : (i) {
                        if (i == null) {
                          return;
                        }
                        onSubtitleSelected(i);
                      },
              ),
            ),
        ],
        if (subtitleView.statusMessage?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 8),
          Text(
            subtitleView.statusMessage!,
            style: const TextStyle(
              color: Color(0xFF9DB0CF),
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ],
    );
  }
}
