import 'package:flutter/material.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/application/detail_library_match_service.dart';
import 'package:starflow/features/details/application/detail_page_controller.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/widgets/detail_shared_widgets.dart';
import 'package:starflow/features/details/presentation/widgets/detail_subtitle_section.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

const DetailLibraryMatchService _detailLibraryMatchService =
    DetailLibraryMatchService();

bool shouldAutoMatchDetailLocalResource(MediaDetailTarget target) {
  final availability = target.availabilityLabel.trim();
  return !target.isPlayable &&
      target.needsLibraryMatch &&
      (availability.isEmpty || availability == '无');
}

bool canManageDetailMetadataIndex(MediaDetailTarget target) {
  return target.sourceKind == MediaSourceKind.nas &&
      target.sourceId.trim().isNotEmpty &&
      target.itemId.trim().isNotEmpty;
}

bool shouldShowDetailResourceInfo(MediaDetailTarget target) {
  return target.sourceName.trim().isNotEmpty ||
      target.availabilityLabel.trim().isNotEmpty ||
      _buildDetailResourceFacts(target).isNotEmpty;
}

String detailLibraryMatchOptionLabel(MediaDetailTarget target) {
  return _detailLibraryMatchService.libraryMatchOptionLabel(target);
}

String detailPlayableVariantOptionLabel(MediaDetailTarget target) {
  final source = target.sourceName.trim();
  final fileLabel = _detailPathTail(
    target.playbackTarget?.actualAddress ?? target.resourcePath,
  );
  if (fileLabel.isNotEmpty) {
    if (source.isNotEmpty) {
      return '$source · $fileLabel';
    }
    return fileLabel;
  }
  return detailLibraryMatchOptionLabel(target);
}

String detailMovieVariantOptionSubtitle(MediaDetailTarget target) {
  return _detailLibraryMatchService.movieVariantOptionSubtitle(target);
}

class DetailResourceInfoSection extends StatelessWidget {
  const DetailResourceInfoSection({
    super.key,
    required this.target,
    required this.isTelevision,
    required this.playbackEngine,
    required this.libraryView,
    required this.subtitleView,
    required this.selectedSubtitleIndex,
    required this.isRefreshingMetadata,
    required this.subtitleChoiceLabelBuilder,
    required this.onSearchOnline,
    required this.onOpenTelevisionPlayableVariantPicker,
    required this.onLibraryMatchSelected,
    required this.onOpenTelevisionLibraryMatchPicker,
    required this.onMatchLocalResource,
    required this.onOpenPlaybackEnginePicker,
    required this.onPlaybackEngineSelected,
    required this.onSearchSubtitles,
    required this.onOpenTelevisionSubtitlePicker,
    required this.onSubtitleSelected,
    required this.onOpenMetadataIndexManager,
    required this.onRefreshMetadata,
  });

  final MediaDetailTarget target;
  final bool isTelevision;
  final PlaybackEngine playbackEngine;
  final DetailLibraryMatchViewState libraryView;
  final DetailSubtitleSearchViewState subtitleView;
  final int selectedSubtitleIndex;
  final bool isRefreshingMetadata;
  final String Function(CachedSubtitleSearchOption choice)
      subtitleChoiceLabelBuilder;
  final VoidCallback onSearchOnline;
  final VoidCallback onOpenTelevisionPlayableVariantPicker;
  final ValueChanged<int> onLibraryMatchSelected;
  final VoidCallback onOpenTelevisionLibraryMatchPicker;
  final VoidCallback? onMatchLocalResource;
  final VoidCallback onOpenPlaybackEnginePicker;
  final ValueChanged<PlaybackEngine> onPlaybackEngineSelected;
  final VoidCallback? onSearchSubtitles;
  final VoidCallback onOpenTelevisionSubtitlePicker;
  final ValueChanged<int> onSubtitleSelected;
  final VoidCallback onOpenMetadataIndexManager;
  final VoidCallback? onRefreshMetadata;

  @override
  Widget build(BuildContext context) {
    final resourceFacts = _buildDetailResourceFacts(target);
    final showPlayableVariantSwitcher = _shouldShowPlayableVariantSwitcher(
      target,
      libraryView,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (target.availabilityLabel.trim().isNotEmpty)
          FactRow(
            label: '状态',
            value: target.availabilityLabel,
          ),
        if (showPlayableVariantSwitcher) ...[
          const SizedBox(height: 12),
          const InfoLabel('播放版本'),
          const SizedBox(height: 8),
          _DetailLibraryMatchSelectionControl(
            isTelevision: isTelevision,
            title: '播放版本',
            focusId: 'detail:resource:playable-selector',
            televisionOnPressed: onOpenTelevisionPlayableVariantPicker,
            viewData: libraryView,
            onSelected: onLibraryMatchSelected,
            labelBuilder: detailPlayableVariantOptionLabel,
          ),
          if (detailMovieVariantOptionSubtitle(
            libraryView.choices[libraryView.effectiveSelectedIndex],
          ).trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              detailMovieVariantOptionSubtitle(
                libraryView.choices[libraryView.effectiveSelectedIndex],
              ).trim(),
              style: const TextStyle(
                color: Color(0xFF9DB0CF),
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
        ],
        if (libraryView.choices.length > 1 && !showPlayableVariantSwitcher) ...[
          const SizedBox(height: 12),
          const InfoLabel('本地资源'),
          const SizedBox(height: 8),
          _DetailLibraryMatchSelectionControl(
            isTelevision: isTelevision,
            title: '本地资源',
            focusId: 'detail:resource:library-selector',
            televisionOnPressed: onOpenTelevisionLibraryMatchPicker,
            viewData: libraryView,
            onSelected: onLibraryMatchSelected,
          ),
        ],
        if (target.searchQuery.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: isTelevision
                ? TvAdaptiveButton(
                    label: '搜索在线资源',
                    icon: Icons.search_rounded,
                    focusId: 'detail:resource:search-online',
                    onPressed: onSearchOnline,
                    variant: TvButtonVariant.text,
                  )
                : TextButton.icon(
                    onPressed: onSearchOnline,
                    icon: const Icon(
                      Icons.search_rounded,
                      size: 16,
                    ),
                    label: const Text('搜索在线资源'),
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
        ],
        if (_canShowManualResourceMatchButton(target)) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: isTelevision
                ? TvAdaptiveButton(
                    label: libraryView.isMatching ? '匹配中...' : '匹配资源库',
                    icon: Icons.link_rounded,
                    focusId: 'detail:resource:match-library',
                    onPressed: libraryView.isMatching ? null : onMatchLocalResource,
                    variant: TvButtonVariant.text,
                  )
                : TextButton.icon(
                    onPressed: libraryView.isMatching ? null : onMatchLocalResource,
                    icon: libraryView.isMatching
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons.link_rounded,
                            size: 16,
                          ),
                    label: Text(
                      libraryView.isMatching ? '匹配中...' : '匹配资源库',
                    ),
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
        ],
        if (target.isPlayable) ...[
          const SizedBox(height: 12),
          const InfoLabel('播放器'),
          const SizedBox(height: 8),
          if (isTelevision)
            TvSelectionTile(
              title: '播放器',
              value: playbackEngine.label,
              onPressed: onOpenPlaybackEnginePicker,
              focusId: 'detail:resource:playback-engine',
            )
          else
            DropdownButtonHideUnderline(
              child: DropdownButton<PlaybackEngine>(
                value: playbackEngine,
                isExpanded: true,
                dropdownColor: const Color(0xFF142235),
                iconEnabledColor: Colors.white70,
                style: const TextStyle(
                  color: Color(0xFFDCE6F8),
                  fontSize: 14,
                  height: 1.35,
                ),
                items: PlaybackEngine.values
                    .map(
                      (engine) => DropdownMenuItem<PlaybackEngine>(
                        value: engine,
                        child: Text(
                          engine.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (selection) {
                  if (selection == null) {
                    return;
                  }
                  onPlaybackEngineSelected(selection);
                },
              ),
            ),
        ],
        DetailSubtitleSection(
          target: target,
          isTelevision: isTelevision,
          subtitleView: subtitleView,
          selectedSubtitleIndex: selectedSubtitleIndex,
          subtitleChoiceLabelBuilder: subtitleChoiceLabelBuilder,
          onSearchSubtitles: onSearchSubtitles,
          onOpenTelevisionSubtitlePicker: onOpenTelevisionSubtitlePicker,
          onSubtitleSelected: onSubtitleSelected,
        ),
        if (canManageDetailMetadataIndex(target)) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: isTelevision
                ? TvAdaptiveButton(
                    label: '建立/管理索引',
                    icon: Icons.manage_search_rounded,
                    focusId: 'detail:resource:metadata-index',
                    onPressed: onOpenMetadataIndexManager,
                    variant: TvButtonVariant.text,
                  )
                : TextButton.icon(
                    onPressed: onOpenMetadataIndexManager,
                    icon: const Icon(
                      Icons.manage_search_rounded,
                      size: 16,
                    ),
                    label: const Text('建立/管理索引'),
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
        ],
        if (_canManuallyRefreshMetadata(target)) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: isTelevision
                ? TvAdaptiveButton(
                    label: isRefreshingMetadata ? '更新中...' : '手动更新信息',
                    icon: Icons.refresh_rounded,
                    focusId: 'detail:resource:refresh-metadata',
                    onPressed: isRefreshingMetadata ? null : onRefreshMetadata,
                    variant: TvButtonVariant.text,
                  )
                : TextButton.icon(
                    onPressed: isRefreshingMetadata ? null : onRefreshMetadata,
                    icon: isRefreshingMetadata
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons.refresh_rounded,
                            size: 16,
                          ),
                    label: Text(
                      isRefreshingMetadata ? '更新中...' : '手动更新信息',
                    ),
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
        ],
        if (target.sourceName.trim().isNotEmpty) ...[
          if (target.availabilityLabel.trim().isNotEmpty)
            const SizedBox(height: 12),
          FactRow(
            label: '来源',
            value: target.sourceKind == null
                ? target.sourceName
                : '${target.sourceKind!.label} · ${target.sourceName}',
          ),
        ],
        for (final fact in resourceFacts) ...[
          const SizedBox(height: 12),
          FactRow(
            label: fact.label,
            value: fact.value,
            selectable: fact.selectable,
          ),
        ],
      ],
    );
  }
}

class _DetailLibraryMatchSelectionControl extends StatelessWidget {
  const _DetailLibraryMatchSelectionControl({
    required this.isTelevision,
    required this.title,
    required this.focusId,
    required this.televisionOnPressed,
    required this.viewData,
    required this.onSelected,
    this.labelBuilder = detailLibraryMatchOptionLabel,
  });

  final bool isTelevision;
  final String title;
  final String focusId;
  final VoidCallback televisionOnPressed;
  final DetailLibraryMatchViewState viewData;
  final ValueChanged<int> onSelected;
  final String Function(MediaDetailTarget target) labelBuilder;

  @override
  Widget build(BuildContext context) {
    if (viewData.choices.isEmpty) {
      return const SizedBox.shrink();
    }

    final selectedIndex = viewData.effectiveSelectedIndex;
    if (isTelevision) {
      return TvSelectionTile(
        title: title,
        value: labelBuilder(viewData.choices[selectedIndex]),
        onPressed: viewData.isMatching ? null : televisionOnPressed,
        focusId: focusId,
      );
    }

    return DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        value: selectedIndex,
        isExpanded: true,
        dropdownColor: const Color(0xFF142235),
        iconEnabledColor: Colors.white70,
        style: const TextStyle(
          color: Color(0xFFDCE6F8),
          fontSize: 14,
          height: 1.35,
        ),
        items: List.generate(viewData.choices.length, (i) {
          return DropdownMenuItem<int>(
            value: i,
            child: Text(
              labelBuilder(viewData.choices[i]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }),
        onChanged: viewData.isMatching
            ? null
            : (i) {
                if (i == null) {
                  return;
                }
                onSelected(i);
              },
      ),
    );
  }
}

class _DetailResourceFact {
  const _DetailResourceFact({
    required this.label,
    required this.value,
    this.selectable = false,
  });

  final String label;
  final String value;
  final bool selectable;
}

bool _shouldShowPlayableVariantSwitcher(
  MediaDetailTarget target,
  DetailLibraryMatchViewState viewData,
) {
  final itemType = target.itemType.trim().toLowerCase();
  return target.isPlayable &&
      itemType != 'series' &&
      itemType != 'season' &&
      viewData.choices.length > 1 &&
      viewData.choices.any((choice) => choice.isPlayable);
}

bool _shouldShowLocalResourceMatcher(MediaDetailTarget target) {
  return target.canManuallyMatchLibraryResource;
}

bool _canShowManualResourceMatchButton(MediaDetailTarget target) {
  if (_shouldShowLocalResourceMatcher(target)) {
    return true;
  }
  if (_detailLibraryMatchService.isUnavailableAvailabilityLabel(
    target.availabilityLabel,
  )) {
    return true;
  }
  if (target.sourceId.trim().isNotEmpty || target.itemId.trim().isNotEmpty) {
    return true;
  }
  return target.title.trim().isNotEmpty || target.searchQuery.trim().isNotEmpty;
}

bool _canManuallyRefreshMetadata(MediaDetailTarget target) {
  if (target.sourceKind == MediaSourceKind.nas &&
      target.sourceId.trim().isNotEmpty) {
    return false;
  }
  return target.title.trim().isNotEmpty || target.searchQuery.trim().isNotEmpty;
}

List<_DetailResourceFact> _buildDetailResourceFacts(MediaDetailTarget target) {
  final playback = target.playbackTarget;
  final facts = <_DetailResourceFact>[];
  final streamUrl = playback?.streamUrl.trim() ?? '';
  final actualAddress = playback?.actualAddress.trim() ?? '';
  final resourcePath = target.resourcePath.trim();
  final displayAddress = actualAddress.isNotEmpty
      ? actualAddress
      : resourcePath.isNotEmpty
          ? resourcePath
          : streamUrl;
  final format = playback?.formatLabel.trim() ?? '';
  final fileSize = playback?.fileSizeLabel.trim() ?? '';
  final resolution = playback?.resolutionLabel.trim() ?? '';
  final bitrate = playback?.bitrateLabel.trim() ?? '';
  final duration = target.durationLabel.trim();
  final sectionName = target.sectionName.trim();

  if (displayAddress.isNotEmpty) {
    facts.add(
      _DetailResourceFact(
        label: '地址',
        value: displayAddress,
        selectable: true,
      ),
    );
  }
  if (format.isNotEmpty) {
    facts.add(_DetailResourceFact(label: '格式', value: format));
  }
  if (fileSize.isNotEmpty) {
    facts.add(_DetailResourceFact(label: '大小', value: fileSize));
  }
  if (_isMeaningfulDurationLabel(duration)) {
    facts.add(_DetailResourceFact(label: '时长', value: duration));
  }
  if (resolution.isNotEmpty) {
    facts.add(_DetailResourceFact(label: '清晰度', value: resolution));
  }
  if (bitrate.isNotEmpty) {
    facts.add(_DetailResourceFact(label: '码率', value: bitrate));
  }
  if (sectionName.isNotEmpty) {
    facts.add(_DetailResourceFact(label: '分区', value: sectionName));
  }

  return facts;
}

bool _isMeaningfulDurationLabel(String label) {
  final trimmed = label.trim();
  return trimmed.isNotEmpty && trimmed != '时长未知' && trimmed != '文件';
}

String _detailPathTail(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final uri = Uri.tryParse(trimmed);
  final rawPath = uri != null && uri.hasScheme ? uri.path : trimmed;
  final normalized = rawPath.replaceAll('\\', '/').trim();
  if (normalized.isEmpty) {
    return '';
  }
  final tail = normalized.split('/').last.trim();
  if (tail.isEmpty) {
    return '';
  }
  try {
    return Uri.decodeComponent(tail);
  } on ArgumentError {
    return tail;
  }
}
