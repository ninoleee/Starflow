import 'package:flutter/material.dart';
import 'package:starflow/core/utils/detail_resource_switch_trace.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/application/detail_library_match_service.dart';
import 'package:starflow/features/details/application/detail_page_controller.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/widgets/detail_shared_widgets.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

const DetailLibraryMatchService _detailLibraryMatchService =
    DetailLibraryMatchService();

bool shouldAutoMatchDetailLocalResource(MediaDetailTarget target) {
  final availability = target.availabilityLabel.trim();
  final itemType = target.itemType.trim().toLowerCase();
  if (itemType == 'episode') {
    return false;
  }
  return !target.isPlayable &&
      target.needsLibraryMatch &&
      (availability.isEmpty || availability == '无');
}

bool canManageDetailMetadataIndex(MediaDetailTarget target) {
  return (target.sourceKind == MediaSourceKind.nas ||
          target.sourceKind == MediaSourceKind.quark) &&
      target.sourceId.trim().isNotEmpty &&
      target.itemId.trim().isNotEmpty;
}

bool shouldShowDetailMetadataManagerEntry(MediaDetailTarget target) {
  return canManageDetailMetadataIndex(target) ||
      target.title.trim().isNotEmpty ||
      target.searchQuery.trim().isNotEmpty;
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
  final fileLabel = resolveDetailPathTail(
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
    required this.onSearchOnline,
    required this.onOpenTelevisionPlayableVariantPicker,
    required this.onLibraryMatchSelected,
    required this.onOpenTelevisionLibraryMatchPicker,
    required this.onMatchLocalResource,
    required this.onCheckOnlineResourceUpdate,
    required this.isCheckingOnlineResourceUpdate,
    required this.onOpenPlaybackEnginePicker,
    required this.onPlaybackEngineSelected,
    required this.onOpenMetadataIndexManager,
  });

  final MediaDetailTarget target;
  final bool isTelevision;
  final PlaybackEngine playbackEngine;
  final DetailLibraryMatchViewState libraryView;
  final VoidCallback onSearchOnline;
  final VoidCallback onOpenTelevisionPlayableVariantPicker;
  final ValueChanged<int> onLibraryMatchSelected;
  final VoidCallback onOpenTelevisionLibraryMatchPicker;
  final VoidCallback? onMatchLocalResource;
  final VoidCallback? onCheckOnlineResourceUpdate;
  final bool isCheckingOnlineResourceUpdate;
  final VoidCallback onOpenPlaybackEnginePicker;
  final ValueChanged<PlaybackEngine> onPlaybackEngineSelected;
  final VoidCallback onOpenMetadataIndexManager;

  @override
  Widget build(BuildContext context) {
    final resourceFacts = _buildDetailResourceFacts(target);
    final showPlayableVariantSwitcher = _shouldShowPlayableVariantSwitcher(
      target,
      libraryView,
    );
    final playableChoiceCount =
        libraryView.choices.where((choice) => choice.isPlayable).length;
    final episodeLikeChoiceCount = libraryView.choices.where((choice) {
      final itemType = choice.itemType.trim().toLowerCase();
      final playbackItemType =
          choice.playbackTarget?.normalizedItemType.trim().toLowerCase() ?? '';
      return itemType == 'episode' || playbackItemType == 'episode';
    }).length;
    final showLibrarySwitcher =
        libraryView.choices.length > 1 && !showPlayableVariantSwitcher;
    detailResourceSwitchTrace(
      'resource.ui.visibility',
      dedupeKey: _detailResourceTraceKey(target),
      fields: {
        'title': target.title,
        'itemType': target.itemType,
        'isPlayable': target.isPlayable,
        'availability': target.availabilityLabel,
        'choices': libraryView.choices.length,
        'playableChoices': playableChoiceCount,
        'episodeLikeChoices': episodeLikeChoiceCount,
        'selectedIndex': libraryView.selectedIndex,
        'effectiveIndex': libraryView.effectiveSelectedIndex,
        'showPlayable': showPlayableVariantSwitcher,
        'showLibrary': showLibrarySwitcher,
        'selectedChoice': _detailResourceSelectedChoiceLabel(libraryView),
        'choiceSample': _detailResourceChoiceSample(libraryView.choices),
      },
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
        if (onCheckOnlineResourceUpdate != null) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: isTelevision
                ? TvAdaptiveButton(
                    label: isCheckingOnlineResourceUpdate ? '检查中...' : '检查更新',
                    icon: Icons.update_rounded,
                    focusId: 'detail:resource:check-online-update',
                    onPressed: isCheckingOnlineResourceUpdate
                        ? null
                        : onCheckOnlineResourceUpdate,
                    variant: TvButtonVariant.text,
                  )
                : TextButton.icon(
                    onPressed: isCheckingOnlineResourceUpdate
                        ? null
                        : onCheckOnlineResourceUpdate,
                    icon: isCheckingOnlineResourceUpdate
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons.update_rounded,
                            size: 16,
                          ),
                    label: Text(
                      isCheckingOnlineResourceUpdate ? '检查中...' : '检查更新',
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
        if (_canShowManualResourceMatchButton(target)) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: isTelevision
                ? TvAdaptiveButton(
                    label: libraryView.isMatching ? '匹配中...' : '匹配资源库',
                    icon: Icons.link_rounded,
                    focusId: 'detail:resource:match-library',
                    onPressed:
                        libraryView.isMatching ? null : onMatchLocalResource,
                    variant: TvButtonVariant.text,
                  )
                : TextButton.icon(
                    onPressed:
                        libraryView.isMatching ? null : onMatchLocalResource,
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
        if (shouldShowDetailMetadataManagerEntry(target)) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: isTelevision
                ? TvAdaptiveButton(
                    label: '信息管理',
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
                    label: const Text('信息管理'),
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

String _detailResourceTraceKey(MediaDetailTarget target) {
  final parts = [
    target.sourceKind?.name ?? '',
    target.sourceId.trim(),
    target.itemId.trim(),
    target.title.trim().toLowerCase(),
    target.searchQuery.trim().toLowerCase(),
  ].where((item) => item.isNotEmpty).toList(growable: false);
  return parts.isEmpty ? 'detail-resource-ui' : parts.join('|');
}

String _detailResourceSelectedChoiceLabel(
    DetailLibraryMatchViewState viewData) {
  if (viewData.choices.isEmpty) {
    return '';
  }
  final selected = viewData.choices[viewData.effectiveSelectedIndex];
  return detailPlayableVariantOptionLabel(selected);
}

String _detailResourceChoiceSample(List<MediaDetailTarget> choices) {
  if (choices.isEmpty) {
    return '';
  }
  return choices.take(4).map(detailPlayableVariantOptionLabel).join(' || ');
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
      return _DetailTelevisionSelectionTile(
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
  final hasPlayableChoices = viewData.choices.length > 1 &&
      viewData.choices.any((choice) => choice.isPlayable);
  final hasEpisodeLikeChoices = viewData.choices.any((choice) {
    final choiceItemType = choice.itemType.trim().toLowerCase();
    final playbackItemType =
        choice.playbackTarget?.normalizedItemType.trim().toLowerCase() ?? '';
    return choiceItemType == 'episode' || playbackItemType == 'episode';
  });
  return target.isPlayable &&
      itemType != 'season' &&
      hasPlayableChoices &&
      (itemType != 'series' || hasEpisodeLikeChoices);
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

class _DetailTelevisionSelectionTile extends StatelessWidget {
  const _DetailTelevisionSelectionTile({
    required this.title,
    required this.value,
    required this.onPressed,
    this.focusId,
  });

  final String title;
  final String value;
  final VoidCallback? onPressed;
  final String? focusId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TvFocusableAction(
      onPressed: onPressed,
      focusId: focusId,
      borderRadius: BorderRadius.circular(18),
      visualStyle: TvFocusVisualStyle.subtle,
      focusScale: 1.03,
      child: Opacity(
        opacity: onPressed == null ? 0.5 : 1,
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title),
                    if (value.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          value.trim(),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
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
